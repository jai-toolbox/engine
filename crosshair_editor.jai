// In-engine editor for the same polygon model and OBJ library used by the
// standalone editor. UI geometry keeps the canvas in the ordinary menu pass.

#scope_file
Input :: #import "Input";
#scope_export

Engine_Crosshair_Drag_Kind :: enum { NONE; BODY; VERTEX; }

Engine_Crosshair_Drag :: struct {
    kind: Engine_Crosshair_Drag_Kind;
    polygon: s32;
    vertex: s32;
    start_x, start_y: float32;
    original: [MAX_POLYGON_SIDES] Grid_Point;
}

Engine_Crosshair_Editor :: struct {
    model: Polygon_Model;
    color: Vector4 = .{0.22, 0.91, 1, 1};
    name: [256] u8;
    name_length: s32;
    current_path: string;
    sides: s32 = 3;
    clipboard: Polygon_Clipboard;
    zoom: float32 = 1;
    center_x: float32 = 50;
    center_y: float32 = 50;
    drag: Engine_Crosshair_Drag;
    pan_active: bool;
    status: string;
}

Engine_Crosshair_Layout :: struct {
    grid: UI_Rect;
    panel: UI_Rect;
    preview: UI_Rect;
    controls_height: float32;
    origin_x, origin_y: float32;
    scale: float32;
}

deinit_engine_crosshair_editor :: (editor: *Engine_Crosshair_Editor) {
    free_polygon_model(*editor.model);
    if editor.current_path.count > 0 free(editor.current_path);
    editor.current_path = "";
}

engine_crosshair_editor_set_name :: (editor: *Engine_Crosshair_Editor, name: string) {
    editor.name_length = cast(s32) min(name.count, 255);
    for i: 0..editor.name_length - 1 editor.name[i] = name[i];
}

engine_crosshair_editor_name :: (editor: *Engine_Crosshair_Editor) -> string {
    result: string;
    result.data = editor.name.data;
    result.count = editor.name_length;
    return result;
}

begin_new_engine_crosshair_editor :: (editor: *Engine_Crosshair_Editor, color: Vector4) {
    deinit_engine_crosshair_editor(editor);
    editor.model = make_polygon_model(DEFAULT_GRID_SIDE);
    editor.color = color;
    editor.sides = 3;
    editor.zoom = 1;
    editor.center_x = cast(float32) editor.model.side * 0.5;
    editor.center_y = cast(float32) editor.model.side * 0.5;
    editor.drag = .{};
    editor.pan_active = false;
    editor.status = "";
    engine_crosshair_editor_set_name(editor, "New crosshair");
}

begin_edit_engine_crosshair_editor :: (editor: *Engine_Crosshair_Editor, path: string,
                                      fallback_color: Vector4) -> bool {
    model, color, loaded, reason := load_crosshair_obj_for_editing(path, fallback_color);
    if !loaded {
        free_polygon_model(*model);
        editor.status = reason;
        return false;
    }
    deinit_engine_crosshair_editor(editor);
    editor.model = model;
    editor.color = color;
    editor.current_path = copy_string(path);
    editor.sides = ifx model.selected >= 0 then model.polygons[model.selected].count else 3;
    editor.zoom = 1;
    editor.center_x = cast(float32) editor.model.side * 0.5;
    editor.center_y = cast(float32) editor.model.side * 0.5;
    editor.drag = .{};
    editor.pan_active = false;
    editor.status = "";
    engine_crosshair_editor_set_name(editor, crosshair_obj_display_name(path));
    return true;
}

save_engine_crosshair_editor :: (wp: *Windowed_Menu_Program) -> bool {
    editor := *wp.crosshair_editor;
    name := engine_crosshair_editor_name(editor);
    if !crosshair_valid_name(name) {
        editor.status = "Use 1-100 letters, numbers, spaces, dashes, or underscores for the name.";
        return false;
    }
    path := crosshair_obj_path(name);
    if file_exists(path) && path != editor.current_path {
        editor.status = "That name already exists. Choose another name or edit the existing crosshair.";
        return false;
    }
    saved, reason := save_crosshair_obj(path, editor.model, editor.color);
    if !saved {
        editor.status = reason;
        return false;
    }
    if editor.current_path.count > 0 free(editor.current_path);
    editor.current_path = copy_string(path);
    refresh_crosshair_library(*wp.crosshair_file, wp.configuration.config_path,
                                     crosshair_obj_filename(path));
    wp.crosshair_settings.enabled = true;
    wp.crosshair_settings.color = editor.color;
    editor.status = "Saved and selected. Changes now appear as the custom crosshair.";
    return true;
}

engine_crosshair_editor_clamp_view :: (editor: *Engine_Crosshair_Editor) {
    editor.zoom = clamp(editor.zoom, 1.0, 16.0);
    side := cast(float32) editor.model.side;
    half_visible := side * 0.5 / editor.zoom;
    editor.center_x = clamp(editor.center_x, half_visible, side - half_visible);
    editor.center_y = clamp(editor.center_y, half_visible, side - half_visible);
}

engine_crosshair_editor_layout :: (editor: Engine_Crosshair_Editor,
                                   window_w: float32, window_h: float32) -> Engine_Crosshair_Layout {
    result: Engine_Crosshair_Layout;
    panel_w := clamp(window_w * 0.27, 280.0, 400.0);
    gap: float32 = 32;
    side := max(2.0, min(window_h - 166.0, window_w - panel_w - gap - 64.0));
    side = cast(float32) (cast(s32) side - (cast(s32) side % 2));
    x := (window_w - side - gap - panel_w) * 0.5;
    result.grid = .{x, 112, side, side};
    result.panel = .{x + side + gap, 96, panel_w, window_h - 142};
    preview_h := clamp(window_h * 0.18, 120.0, 185.0);
    result.preview = .{result.panel.x + 16, window_h - preview_h - 56,
                      panel_w - 32, preview_h};
    result.controls_height = result.preview.y - result.panel.y - 28;
    result.scale = side * editor.zoom / cast(float32) editor.model.side;
    result.origin_x = result.grid.x + side * 0.5 - editor.center_x * result.scale;
    result.origin_y = result.grid.y + side * 0.5 - editor.center_y * result.scale;
    return result;
}

engine_crosshair_editor_rect_contains :: (rect: UI_Rect, x: float32, y: float32) -> bool {
    return x >= rect.x && y >= rect.y && x < rect.x + rect.w && y < rect.y + rect.h;
}

engine_crosshair_editor_grid_x :: (layout: Engine_Crosshair_Layout, x: float32) -> float32 {
    return (x - layout.origin_x) / layout.scale;
}

engine_crosshair_editor_grid_y :: (layout: Engine_Crosshair_Layout, y: float32) -> float32 {
    return (y - layout.origin_y) / layout.scale;
}

engine_crosshair_editor_screen_x :: (layout: Engine_Crosshair_Layout, x: float32) -> float32 {
    return layout.origin_x + cast(float32) x * layout.scale;
}

engine_crosshair_editor_screen_y :: (layout: Engine_Crosshair_Layout, y: float32) -> float32 {
    return layout.origin_y + cast(float32) y * layout.scale;
}

engine_crosshair_editor_input :: (editor: *Engine_Crosshair_Editor, layout: Engine_Crosshair_Layout) {
    mouse := ui_ctx.mouse;
    over_grid := engine_crosshair_editor_rect_contains(layout.grid, mouse.x, mouse.y);

    if over_grid && mouse.scroll_y != 0 {
        world_x := engine_crosshair_editor_grid_x(layout, mouse.x);
        world_y := engine_crosshair_editor_grid_y(layout, mouse.y);
        factor: float32 = ifx mouse.scroll_y > 0 then 1.25 else 0.8;
        new_zoom := clamp(editor.zoom * factor, 1.0, 16.0);
        new_scale := layout.grid.w * new_zoom / cast(float32) editor.model.side;
        editor.center_x = world_x - (mouse.x - layout.grid.x - layout.grid.w * 0.5) / new_scale;
        editor.center_y = world_y - (mouse.y - layout.grid.y - layout.grid.h * 0.5) / new_scale;
        editor.zoom = new_zoom;
        engine_crosshair_editor_clamp_view(editor);
    }

    middle_down := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_MIDDLE] & .DOWN) != 0;
    if over_grid && (mouse.right_pressed || (middle_down && !editor.pan_active)) {
        editor.pan_active = true;
    }
    if editor.pan_active {
        if mouse.right_down || middle_down {
            editor.center_x -= mouse.dx / layout.scale;
            editor.center_y -= mouse.dy / layout.scale;
            engine_crosshair_editor_clamp_view(editor);
        } else editor.pan_active = false;
    }

    if over_grid && mouse.left_pressed {
        editor.drag = .{};
        if editor.model.selected >= 0 && editor.model.selected < editor.model.polygons.count {
            polygon := editor.model.polygons[editor.model.selected];
            for i: 0..polygon.count - 1 {
                x := engine_crosshair_editor_screen_x(layout, polygon.vertices[i].x);
                y := engine_crosshair_editor_screen_y(layout, polygon.vertices[i].y);
                dx := mouse.x - x;
                dy := mouse.y - y;
                if dx * dx + dy * dy <= 100 {
                    editor.drag.kind = .VERTEX;
                    editor.drag.polygon = editor.model.selected;
                    editor.drag.vertex = cast(s32) i;
                    editor.drag.start_x = engine_crosshair_editor_grid_x(layout, mouse.x);
                    editor.drag.start_y = engine_crosshair_editor_grid_y(layout, mouse.y);
                    editor.drag.original = polygon.vertices;
                    break;
                }
            }
        }
        if editor.drag.kind == .NONE {
            gx := engine_crosshair_editor_grid_x(layout, mouse.x);
            gy := engine_crosshair_editor_grid_y(layout, mouse.y);
            hit := polygon_at(editor.model, gx, gy);
            editor.model.selected = hit;
            if hit >= 0 {
                editor.drag.kind = .BODY;
                editor.drag.polygon = hit;
                editor.drag.start_x = gx;
                editor.drag.start_y = gy;
                editor.drag.original = editor.model.polygons[hit].vertices;
            }
        }
    }
    if !mouse.left_down editor.drag = .{};
    if editor.drag.kind != .NONE && mouse.left_down {
        gx := engine_crosshair_editor_grid_x(layout, mouse.x);
        gy := engine_crosshair_editor_grid_y(layout, mouse.y);
        if editor.drag.kind == .VERTEX {
            dx := gx - editor.drag.start_x;
            dy := gy - editor.drag.start_y;
            if abs(dx) < 0.000001 && abs(dy) < 0.000001 {
                editor.model.polygons[editor.drag.polygon].vertices[editor.drag.vertex] =
                    editor.drag.original[editor.drag.vertex];
            } else {
                source := editor.drag.original[editor.drag.vertex];
                move_polygon_vertex(*editor.model, editor.drag.polygon, editor.drag.vertex,
                                    source.x + dx, source.y + dy);
            }
        } else {
            dx := cast(s32) floor(gx - editor.drag.start_x + 0.5);
            dy := cast(s32) floor(gy - editor.drag.start_y + 0.5);
            move_polygon_from(*editor.model, editor.drag.polygon, editor.drag.original, dx, dy);
        }
    }

    if ui_ctx.focused == UI_ID_NONE {
        for event: Input.events_this_frame {
            if event.type != .KEYBOARD || !event.key_pressed || event.repeat continue;
            if event.ctrl_pressed {
                if event.key_code == cast(Input.Key_Code) #char "C" {
                    copy_selected_polygon(editor.model, *editor.clipboard);
                }
                if event.key_code == cast(Input.Key_Code) #char "V" {
                    paste_polygon(*editor.model, *editor.clipboard);
                }
            } else {
                if event.key_code == cast(Input.Key_Code) #char "N" {
                    add_crosshair_polygon(*editor.model, editor.sides, editor.color);
                }
                if event.key_code == .DELETE delete_selected_polygon(*editor.model);
                if event.key_code == cast(Input.Key_Code) #char "0" {
                    editor.zoom = 1;
                    editor.center_x = cast(float32) editor.model.side * 0.5;
                    editor.center_y = cast(float32) editor.model.side * 0.5;
                }
            }
        }
    }
}

engine_crosshair_editor_triangle :: (x0: float32, y0: float32, x1: float32, y1: float32,
                                     x2: float32, y2: float32, color: Vector4) {
    w := ui_ctx.window_w;
    h := ui_ctx.window_h;
    positions := Vector3.[
        .{2*x0/w - 1, 1 - 2*y0/h, 0},
        .{2*x1/w - 1, 1 - 2*y1/h, 0},
        .{2*x2/w - 1, 1 - 2*y2/h, 0},
    ];
    colors := Vector4.[color, color, color];
    winding := (x1 - x0) * (y2 - y0) - (y1 - y0) * (x2 - x0);
    indices := ifx winding > 0 then u32.[0, 2, 1] else u32.[0, 1, 2];
    ui_cmd_geometry(positions, colors, indices);
}

engine_crosshair_editor_draw_polygon :: (polygon: Crosshair_Polygon,
                                        origin_x: float32, origin_y: float32,
                                        scale_x: float32, scale_y: float32, color: Vector4) {
    mesh := triangulate_polygon(polygon);
    if !mesh.valid return;
    for i: 0..mesh.count - 1 {
        tri := mesh.triangles[i];
        a := polygon.vertices[tri.indices[0]];
        b := polygon.vertices[tri.indices[1]];
        c := polygon.vertices[tri.indices[2]];
        engine_crosshair_editor_triangle(origin_x + cast(float32) a.x * scale_x,
                                         origin_y + cast(float32) a.y * scale_y,
                                         origin_x + cast(float32) b.x * scale_x,
                                         origin_y + cast(float32) b.y * scale_y,
                                         origin_x + cast(float32) c.x * scale_x,
                                         origin_y + cast(float32) c.y * scale_y, color);
    }
}

engine_crosshair_editor_draw_shapes :: (editor: Engine_Crosshair_Editor,
                                        origin_x: float32, origin_y: float32,
                                        scale_x: float32, scale_y: float32) {
    for polygon: editor.model.polygons {
        engine_crosshair_editor_draw_polygon(polygon, origin_x, origin_y, scale_x, scale_y, editor.color);
        if polygon.mirror_x {
            mirrored := derived_mirror_polygon(polygon, editor.model.side, true, false);
            engine_crosshair_editor_draw_polygon(mirrored, origin_x, origin_y, scale_x, scale_y, editor.color);
        }
        if polygon.mirror_y {
            mirrored := derived_mirror_polygon(polygon, editor.model.side, false, true);
            engine_crosshair_editor_draw_polygon(mirrored, origin_x, origin_y, scale_x, scale_y, editor.color);
        }
        if polygon.mirror_x && polygon.mirror_y {
            mirrored := derived_mirror_polygon(polygon, editor.model.side, true, true);
            engine_crosshair_editor_draw_polygon(mirrored, origin_x, origin_y, scale_x, scale_y, editor.color);
        }
    }
}

engine_crosshair_editor_draw_grid :: (editor: Engine_Crosshair_Editor,
                                      layout: Engine_Crosshair_Layout) {
    ui_cmd_rect(layout.grid, .{0.055, 0.08, 0.115, 1});
    ui_cmd_scissor_push(layout.grid);
    grid_stride: s32 = 1;
    while layout.scale * cast(float32) grid_stride < 5 && grid_stride < editor.model.side grid_stride *= 10;
    for i: 0..editor.model.side {
        if i % grid_stride != 0 && i != editor.model.side / 2 continue;
        x := layout.origin_x + cast(float32) i * layout.scale;
        y := layout.origin_y + cast(float32) i * layout.scale;
        line_color := ifx i == editor.model.side / 2 then Vector4.{0.21, 0.65, 0.70, 1}
                      else ifx i % (editor.model.side / 10) == 0 then Vector4.{0.16, 0.25, 0.33, 1}
                      else Vector4.{0.11, 0.17, 0.23, 1};
        ui_cmd_rect(.{x, layout.grid.y, 1, layout.grid.h}, line_color);
        ui_cmd_rect(.{layout.grid.x, y, layout.grid.w, 1}, line_color);
    }
    engine_crosshair_editor_draw_shapes(editor, layout.origin_x, layout.origin_y,
                                        layout.scale, layout.scale);
    if editor.model.selected >= 0 && editor.model.selected < editor.model.polygons.count {
        polygon := editor.model.polygons[editor.model.selected];
        for i: 0..polygon.count - 1 {
            x := engine_crosshair_editor_screen_x(layout, polygon.vertices[i].x);
            y := engine_crosshair_editor_screen_y(layout, polygon.vertices[i].y);
            ui_cmd_rect(.{x - 5, y - 5, 10, 10}, .{1, 1, 1, 1});
            ui_cmd_rect_outline(.{x - 5, y - 5, 10, 10}, .{0.02, 0.04, 0.06, 1});
        }
    }
    ui_cmd_scissor_pop();
    ui_cmd_rect_outline(layout.grid, .{0.22, 0.31, 0.39, 1});
}

engine_crosshair_editor_draw_preview :: (editor: Engine_Crosshair_Editor,
                                         layout: Engine_Crosshair_Layout,
                                         monitor: Crosshair_Monitor_Scale) {
    ui_cmd_rect(layout.preview, .{0, 0, 0, 1});
    if !monitor.valid {
        ui_cmd_text("Monitor dimensions unavailable", layout.preview.x + 12,
                    layout.preview.y + layout.preview.h * 0.5, 16, .{0.7, 0.7, 0.7, 1});
        return;
    }
    px_x := monitor.pixels_per_inch_x;
    px_y := monitor.pixels_per_inch_y;
    origin_x := layout.preview.x + layout.preview.w * 0.5 - px_x * 0.5;
    origin_y := layout.preview.y + layout.preview.h * 0.5 - px_y * 0.5;
    ui_cmd_scissor_push(layout.preview);
    ui_cmd_rect_outline(.{origin_x, origin_y, px_x, px_y}, .{0.16, 0.21, 0.25, 1});
    engine_crosshair_editor_draw_shapes(editor, origin_x, origin_y,
                                        px_x / cast(float32) editor.model.side,
                                        px_y / cast(float32) editor.model.side);
    ui_cmd_scissor_pop();
}

render_engine_crosshair_editor :: (wp: *Windowed_Menu_Program) {
    editor := *wp.crosshair_editor;
    if editor.model.side == 0 begin_new_engine_crosshair_editor(editor, wp.crosshair_settings.color);
    ctx := ui_ctx;
    layout := engine_crosshair_editor_layout(editor.*, ctx.window_w, ctx.window_h);
    engine_crosshair_editor_input(editor, layout);
    layout = engine_crosshair_editor_layout(editor.*, ctx.window_w, ctx.window_h);

    ui_cmd_rect(.{0, 0, ctx.window_w, ctx.window_h}, .{0.035, 0.055, 0.08, 1});
    ui_cmd_rect(.{0, 0, ctx.window_w, 78}, .{0.08, 0.12, 0.18, 1});
    ui_cmd_text("CROSSHAIR EDITOR", layout.grid.x, 40, 18, .{0.92, 0.96, 1, 1});
    ui_cmd_text("The grid below represents 1 x 1 inch on your monitor.",
                layout.grid.x, 100, 16, .{0.65, 0.75, 0.81, 1});
    engine_crosshair_editor_draw_grid(editor.*, layout);

    ui_push_layout(.{
        mode = .VERTICAL, cursor_x = layout.panel.x + 16, cursor_y = 20,
        origin_x = layout.panel.x + 16, origin_y = 20,
        max_w = layout.panel.w - 32, max_h = 44, visible_h = 44,
    });
    ui_begin_row();
    if ui_button("Save crosshair") save_engine_crosshair_editor(wp);
    if ui_button("Back") wp.current_menu = .USER_SETTINGS;
    ui_end_row();
    ui_pop_layout();

    ui_push_layout(.{
        mode = .VERTICAL,
        cursor_x = layout.panel.x, cursor_y = layout.panel.y,
        origin_x = layout.panel.x, origin_y = layout.panel.y,
        max_w = layout.panel.w, max_h = layout.controls_height,
        visible_h = layout.controls_height,
    });
    ui_begin_scroll_region_ex("crosshair editor controls", layout.controls_height, 16);
    ui_spacing(12);
    ui_text_input("Name", *editor.name, *editor.name_length);
    ui_label_disabled("OBJ files are saved in data/crosshairs.");
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
    ui_label(tprint("% shapes / % shown", editor.model.polygons.count,
                    rendered_polygon_count(editor.model)));
    if editor.status.count > 0 ui_label_disabled(editor.status);
    ui_spacing(12);
    ui_end_scroll_region();
    ui_pop_layout();

    ui_cmd_text("ACTUAL SIZE", layout.preview.x, layout.preview.y - 11, 16,
                .{0.92, 0.96, 1, 1});
    engine_crosshair_editor_draw_preview(editor.*, layout, wp.crosshair_monitor);
    if editor.status.count > 0 {
        ui_cmd_text(editor.status, layout.grid.x, ctx.window_h - 43, 14,
                    .{0.78, 0.88, 0.75, 1});
    }
    ui_cmd_text("Wheel: zoom. Right/middle drag: pan. 0: reset. Ctrl+C/V: copy/paste. N: add. Del: remove.",
                layout.grid.x, ctx.window_h - 22, 15, .{0.65, 0.75, 0.81, 1});
}
