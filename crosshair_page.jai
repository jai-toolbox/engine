// A full settings page, independent of Windowed_Menu_Program and its menu enum.
// Hosts supply their crosshair state and handle Back / configuration persistence.
Engine_Crosshair_Page_Action :: enum { NONE; NEW; OPEN; DUPLICATE; REFRESH; BACK; }

Engine_Crosshair_Page :: struct {
    crosshair_editor: Engine_Crosshair_Editor;
    initialized: bool;
    clean_fingerprint: u64;
    pending_action: Engine_Crosshair_Page_Action;
    pending_path: string;
    confirmation_error: string;
}

Engine_Crosshair_Page_Result :: struct {
    back: bool;
    settings_changed: bool;
}

deinit_engine_crosshair_page :: (page: *Engine_Crosshair_Page) {
    deinit_engine_crosshair_editor(*page.crosshair_editor);
    if page.pending_path.count > 0 free(page.pending_path);
    page.* = .{};
}

crosshair_fingerprint_member :: (value: $T, seed: u64) -> u64 {
    bytes: string;
    bytes.data = cast(*u8) *value;
    bytes.count = size_of(T);
    return ui_hash_fnv1a(bytes, seed);
}

engine_crosshair_editor_fingerprint :: (editor: *Engine_Crosshair_Editor) -> u64 {
    hash := ui_hash_fnv1a(engine_crosshair_editor_name(editor));
    hash = crosshair_fingerprint_member(editor.model.side, hash);
    hash = crosshair_fingerprint_member(editor.color, hash);
    for polygon: editor.model.polygons {
        hash = crosshair_fingerprint_member(polygon.count, hash);
        hash = crosshair_fingerprint_member(polygon.mirror_x, hash);
        hash = crosshair_fingerprint_member(polygon.mirror_y, hash);
        for i: 0..polygon.count - 1 hash = crosshair_fingerprint_member(polygon.vertices[i], hash);
    }
    return hash;
}

engine_crosshair_page_read_only :: (page: *Engine_Crosshair_Page) -> bool {
    return crosshair_is_default_path(page.crosshair_editor.current_path);
}

engine_crosshair_page_disabled_button :: (label: string) {
    style := ui_ctx.style;
    width := msdf_measure_text_pixels(ui_ctx.font, label, style.font_size) + style.padding * 2;
    rect := ui_allocate_rect(width, style.button_height);
    ui_cmd_rect(rect, .{0.12, 0.14, 0.16, 1});
    ui_cmd_rect_outline(rect, style.color_border);
    ui_cmd_text(label, ui_text_centered_x(rect, label, style.font_size),
                ui_text_baseline_y(rect, style.font_size), style.font_size, style.color_text_disabled);
}

engine_crosshair_page_has_changes :: (page: *Engine_Crosshair_Page) -> bool {
    return page.initialized && engine_crosshair_editor_fingerprint(*page.crosshair_editor) != page.clean_fingerprint;
}

engine_crosshair_page_mark_clean :: (page: *Engine_Crosshair_Page) {
    page.initialized = true;
    page.clean_fingerprint = engine_crosshair_editor_fingerprint(*page.crosshair_editor);
    if ui_ctx != null ui_ctx.focused = UI_ID_NONE;
}

queue_engine_crosshair_page_action :: (page: *Engine_Crosshair_Page,
                                       action: Engine_Crosshair_Page_Action, path: string = "") {
    if page.pending_action != .NONE return;
    page.pending_action = action;
    page.pending_path = copy_string(path);
    page.confirmation_error = "";
}

clear_engine_crosshair_page_action :: (page: *Engine_Crosshair_Page) {
    if page.pending_path.count > 0 free(page.pending_path);
    page.pending_path = "";
    page.pending_action = .NONE;
    page.confirmation_error = "";
}

open_engine_crosshair_page_file :: (page: *Engine_Crosshair_Page, file: *Crosshair_File_State,
                                    settings: *Crosshair_Settings, path: string) -> bool {
    if !begin_edit_engine_crosshair_editor(*page.crosshair_editor, path, settings.color) return false;
    load_crosshair_file(file, path);
    file.selection = -1;
    for entry, index: file.library.paths {
        if entry == file.path {
            file.selection = cast(s32) index;
            break;
        }
    }
    settings.color = page.crosshair_editor.color;
    engine_crosshair_page_mark_clean(page);
    return true;
}

apply_engine_crosshair_page_action :: (page: *Engine_Crosshair_Page, file: *Crosshair_File_State,
                                       settings: *Crosshair_Settings, config_path: string) -> Engine_Crosshair_Page_Result {
    result: Engine_Crosshair_Page_Result;
    if page.pending_action == {
        case .NEW;
            begin_new_engine_crosshair_editor(*page.crosshair_editor, settings.color);
            engine_crosshair_page_mark_clean(page);
        case .OPEN;
            result.settings_changed = open_engine_crosshair_page_file(page, file, settings, page.pending_path);
        case .DUPLICATE;
            path, duplicated, reason := duplicate_crosshair_obj(page.crosshair_editor.current_path);
            if duplicated {
                refresh_crosshair_library(file, config_path, crosshair_obj_filename(path));
                result.settings_changed = open_engine_crosshair_page_file(page, file, settings, path);
                free(path);
            } else page.crosshair_editor.status = reason;
        case .REFRESH;
            refresh_crosshair_library(file, config_path);
            if file.loaded result.settings_changed = open_engine_crosshair_page_file(page, file, settings, file.path);
        case .BACK;
            result.back = true;
            deinit_engine_crosshair_editor(*page.crosshair_editor);
            page.initialized = false;
    }
    clear_engine_crosshair_page_action(page);
    return result;
}

save_engine_crosshair_page :: (page: *Engine_Crosshair_Page, file: *Crosshair_File_State,
                               settings: *Crosshair_Settings, config_path: string) -> bool {
    // Reloading the current file after Save must follow a custom-file rename.
    reloading_current := page.pending_action == .OPEN && page.pending_path == page.crosshair_editor.current_path;
    if !save_engine_crosshair_editor(*page.crosshair_editor, file, settings, config_path) return false;
    if reloading_current {
        if page.pending_path.count > 0 free(page.pending_path);
        page.pending_path = copy_string(page.crosshair_editor.current_path);
    }
    engine_crosshair_page_mark_clean(page);
    return true;
}

render_engine_crosshair_page_confirmation :: (page: *Engine_Crosshair_Page, file: *Crosshair_File_State,
                                              settings: *Crosshair_Settings, config_path: string) -> Engine_Crosshair_Page_Result {
    result: Engine_Crosshair_Page_Result;
    draw_overlay_background(0.65);
    width := min(460.0, ui_ctx.window_w - 48);
    rect := UI_Rect.{(ui_ctx.window_w - width) * 0.5, (ui_ctx.window_h - 215) * 0.5, width, 215};
    ui_cmd_rect(rect, .{0.08, 0.12, 0.18, 1});
    ui_cmd_rect_outline(rect, .{0.28, 0.43, 0.53, 1});
    ui_push_layout(.{mode = .VERTICAL, cursor_x = rect.x + 20, cursor_y = rect.y + 20,
                    origin_x = rect.x + 20, origin_y = rect.y + 20,
                    max_w = rect.w - 40, max_h = rect.h - 40, visible_h = rect.h - 40});
    ui_label("Unsaved crosshair");
    ui_label_disabled_wrapped("Save your changes before continuing, or discard them?");
    if ui_button("Save and continue") {
        if save_engine_crosshair_page(page, file, settings, config_path) {
            result = apply_engine_crosshair_page_action(page, file, settings, config_path);
            result.settings_changed = true;
        } else {
            page.confirmation_error = page.crosshair_editor.status;
        }
    }
    ui_begin_row();
    if ui_button("Discard changes") {
        result = apply_engine_crosshair_page_action(page, file, settings, config_path);
    }
    if ui_button("Cancel") clear_engine_crosshair_page_action(page);
    ui_end_row();
    if page.confirmation_error.count > 0 ui_label_disabled_wrapped(page.confirmation_error);
    ui_pop_layout();
    return result;
}

render_engine_crosshair_page :: (page: *Engine_Crosshair_Page, file: *Crosshair_File_State,
                                settings: *Crosshair_Settings, monitor: Crosshair_Monitor_Scale,
                                config_path: string) -> Engine_Crosshair_Page_Result {
    result: Engine_Crosshair_Page_Result;
    editor := *page.crosshair_editor;
    if !page.initialized {
        if !file.loaded || !open_engine_crosshair_page_file(page, file, settings, file.path) {
            begin_new_engine_crosshair_editor(editor, settings.color);
            engine_crosshair_page_mark_clean(page);
        }
    }
    ctx := ui_ctx;
    layout := engine_crosshair_editor_layout(editor.*, ctx.window_w, ctx.window_h);
    ui_cmd_rect(.{0, 0, ctx.window_w, ctx.window_h}, .{0.035, 0.055, 0.08, 1});

    // No editor widgets or canvas input run while the confirmation is visible.
    if page.pending_action != .NONE {
        if engine_crosshair_page_has_changes(page) {
            for i: 0..ctx.keyboard.key_count - 1 {
                if ctx.keyboard.keys_pressed[i] == .ESCAPE {
                    clear_engine_crosshair_page_action(page);
                    ctx.keyboard.keys_pressed[i] = .NONE;
                }
            }
            if page.pending_action != .NONE {
                engine_crosshair_editor_draw_grid(editor.*, layout);
                engine_crosshair_editor_draw_preview(editor.*, layout, monitor);
                return render_engine_crosshair_page_confirmation(page, file, settings, config_path);
            }
        } else {
            result = apply_engine_crosshair_page_action(page, file, settings, config_path);
            if result.back return result;
            layout = engine_crosshair_editor_layout(editor.*, ctx.window_w, ctx.window_h);
        }
    }

    for i: 0..ctx.keyboard.key_count - 1 {
        if ctx.keyboard.keys_pressed[i] == .ESCAPE && ctx.open_popup_id == UI_ID_NONE {
            queue_engine_crosshair_page_action(page, .BACK);
        }
    }
    read_only := engine_crosshair_page_read_only(page);
    if read_only editor.model.selected = -1;
    engine_crosshair_editor_input(editor, layout, read_only);
    layout = engine_crosshair_editor_layout(editor.*, ctx.window_w, ctx.window_h);
    ui_cmd_rect(.{0, 0, ctx.window_w, 78}, .{0.08, 0.12, 0.18, 1});
    ui_cmd_text("CROSSHAIR SETTINGS", layout.grid.x, 33, 22, .{0.92, 0.96, 1, 1});
    subtitle := ifx read_only then "Default preset (read-only). Duplicate it to create an editable copy."
                else ifx engine_crosshair_page_has_changes(page) then "Unsaved changes"
                else "Select a saved crosshair, edit it here, or create a new one.";
    ui_cmd_text(subtitle, layout.grid.x, 58, 15, .{0.65, 0.75, 0.81, 1});
    ui_cmd_text("The grid represents 1 x 1 inch on your monitor.",
                layout.grid.x, 100, 16, .{0.65, 0.75, 0.81, 1});
    engine_crosshair_editor_draw_grid(editor.*, layout);

    ui_push_layout(.{mode = .VERTICAL, cursor_x = layout.panel.x + 16, cursor_y = 20,
                    origin_x = layout.panel.x + 16, origin_y = 20,
                    max_w = layout.panel.w - 32, max_h = 44, visible_h = 44});
    ui_begin_row();
    if ui_button("New") queue_engine_crosshair_page_action(page, .NEW);
    if read_only {
        engine_crosshair_page_disabled_button("Save");
    } else if ui_button_colored("Save", GOLD_NORMAL, GOLD_HOVER, GOLD_ACTIVE) {
        result.settings_changed = save_engine_crosshair_page(page, file, settings, config_path);
    }
    if ui_button("Back") queue_engine_crosshair_page_action(page, .BACK);
    ui_end_row();
    ui_pop_layout();

    ui_push_layout(.{mode = .VERTICAL, cursor_x = layout.panel.x, cursor_y = layout.panel.y,
                    origin_x = layout.panel.x, origin_y = layout.panel.y,
                    max_w = layout.panel.w, max_h = layout.controls_height,
                    visible_h = layout.controls_height});
    ui_begin_scroll_region_ex("crosshair editor controls", layout.controls_height, 16);
    ui_spacing(12);
    if ui_checkbox("Show crosshair", *settings.enabled) result.settings_changed = true;
    if file.library.paths.count > 0 {
        labels := NewArray(file.library.paths.count, string,, allocator = temp);
        for file.library.paths labels[it_index] = crosshair_obj_display_name(it);
        selection := file.selection;
        if ui_dropdown("Saved crosshairs", labels, *selection) {
            queue_engine_crosshair_page_action(page, .OPEN, file.library.paths[selection]);
        }
    } else ui_label_disabled("No saved crosshairs yet.");
    ui_begin_row();
    if !read_only && file.loaded && ui_button("Edit selected") queue_engine_crosshair_page_action(page, .OPEN, file.path);
    if editor.current_path.count > 0 && ui_button("Duplicate") queue_engine_crosshair_page_action(page, .DUPLICATE);
    if read_only && ui_button("Refresh files") queue_engine_crosshair_page_action(page, .REFRESH);
    ui_end_row();
    if !read_only && ui_button("Refresh files") queue_engine_crosshair_page_action(page, .REFRESH);
    ui_separator();
    if read_only {
        ui_label(tprint("% (preset)", engine_crosshair_editor_name(editor)));
        ui_label_disabled_wrapped("Default crosshairs cannot be edited. Duplicate this preset to change its shape, color, or name.");
        ui_label_disabled("Zoom and pan remain available.");
    } else {
        ui_text_input("Name", *editor.name, *editor.name_length);
        ui_label_disabled_wrapped("Save updates this file. Changing its name renames it; use Duplicate for a separate copy.");
        ui_separator();
        snap_grid: s32 = cast(s32) (ifx editor.model.side == FINE_GRID_SIDE then 1 else 0);
        if ui_dropdown("Snap grid", string.["100 x 100", "1000 x 1000"], *snap_grid) {
            old_side := editor.model.side;
            new_side: s32 = cast(s32) (ifx snap_grid == 1 then FINE_GRID_SIDE else DEFAULT_GRID_SIDE);
            if set_grid_resolution(*editor.model, new_side) {
                ratio := cast(float32) new_side / cast(float32) old_side;
                editor.center_x *= ratio;
                editor.center_y *= ratio;
                editor.drag = .{};
                engine_crosshair_editor_clamp_view(editor);
            }
        }
        ui_slider_int("Number of sides", *editor.sides, MIN_POLYGON_SIDES, MAX_POLYGON_SIDES);
        if ui_button("Add shape") add_crosshair_polygon(*editor.model, editor.sides, editor.color);
        ui_separator();
        if ui_color_edit3("Crosshair color", *editor.color) {
            for *polygon: editor.model.polygons polygon.color = editor.color;
        }
        if ui_slider_float("Opacity", *editor.color.w, 0.0, 1.0) {
            for *polygon: editor.model.polygons polygon.color.w = editor.color.w;
        }
        ui_separator();
        ui_begin_row();
        if ui_button("Copy") copy_selected_polygon(editor.model, *editor.clipboard);
        if ui_button("Paste") paste_polygon(*editor.model, *editor.clipboard);
        if ui_button("Delete") delete_selected_polygon(*editor.model);
        ui_end_row();
        ui_label("Mirror / linked copies");
        mirror_x := false;
        mirror_y := false;
        if editor.model.selected >= 0 && editor.model.selected < editor.model.polygons.count {
            mirror_x = editor.model.polygons[editor.model.selected].mirror_x;
            mirror_y = editor.model.polygons[editor.model.selected].mirror_y;
        }
        ui_begin_row();
        if ui_checkbox("X", *mirror_x) toggle_selected_mirror(*editor.model, true, false);
        if ui_checkbox("Y", *mirror_y) toggle_selected_mirror(*editor.model, false, true);
        if ui_button("X+Y") toggle_selected_mirror(*editor.model, true, true);
        ui_end_row();
    }
    ui_label(tprint("% shapes / % shown", editor.model.polygons.count,
                    rendered_polygon_count(editor.model)));
    if editor.status.count > 0 ui_label_disabled(editor.status);
    ui_spacing(12);
    ui_end_scroll_region();
    ui_pop_layout();

    ui_cmd_text("ACTUAL SIZE", layout.preview.x, layout.preview.y - 11, 16,
                .{0.92, 0.96, 1, 1});
    engine_crosshair_editor_draw_preview(editor.*, layout, monitor);
    if editor.status.count > 0 {
        ui_cmd_text(editor.status, layout.grid.x, ctx.window_h - 43, 14,
                    .{0.78, 0.88, 0.75, 1});
    }
    help := ifx read_only then "Wheel: zoom. Right/middle drag: pan. Duplicate this preset to edit it."
            else "Wheel: zoom. Right/middle drag: pan. 0: reset. Ctrl+C/V: copy/paste. N: add. Del: remove.";
    ui_cmd_text(help,
                layout.grid.x, ctx.window_h - 22, 15, .{0.65, 0.75, 0.81, 1});
    return result;
}

// Only the default-menu adapter knows about navigation or the host's config.
render_crosshair_settings :: (wp: *Windowed_Menu_Program) {
    result := render_engine_crosshair_page(*wp.crosshair_page, *wp.crosshair_file,
                                           *wp.crosshair_settings, wp.crosshair_monitor,
                                           wp.configuration.config_path);
    if result.settings_changed save_settings(*wp.wmpb);
    if result.back wp.current_menu = wp.menu_return_to;
}
