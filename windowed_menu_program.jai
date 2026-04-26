#scope_file
Input :: #import "Input";
Simp :: #import "Simp";
Sound_Player :: #import "Sound_Player";

// this is just a sample thing, you'll make your own probably.
Current_Menu :: enum {
    MAIN;
    GRAPHICS_SETTINGS;
    USER_SETTINGS;
    SOUND_SETTINGS;
    IN_GAME;
    NONE;
}

#scope_export


Resolution_Entry :: struct {
    width:  s32;
    height: s32;
    label:  string;
}

#if OS == .WINDOWS {
    _user32_enum :: #system_library "user32";
    ENUM_CURRENT_SETTINGS : u32 : 0xFFFFFFFF;
    EnumDisplaySettingsW :: (lpszDeviceName: *u16, iModeNum: u32, lpDevMode: *DEVMODEW) -> s32 #foreign _user32_enum;
}

enumerate_resolutions :: (using wp: *Windowed_Menu_Program) {
    array_reset(*available_resolutions);
    array_reset(*resolution_labels);

    #if OS == .WINDOWS {
        native_w : s32 = 0;
        native_h : s32 = 0;

        dm_current: DEVMODEW;
        dm_current.dmSize = size_of(type_of(dm_current));
        if EnumDisplaySettingsW(null, ENUM_CURRENT_SETTINGS, *dm_current) != 0 {
            native_w = cast(s32) dm_current.dmPelsWidth;
            native_h = cast(s32) dm_current.dmPelsHeight;
        }

        if native_w == 0 || native_h == 0 {
            native_w = 1920;
            native_h = 1080;
        }

        mode_index : u32 = 0;
        dm: DEVMODEW;
        dm.dmSize = size_of(type_of(dm));

        Seen_Res :: struct { w: s32; h: s32; }
        seen: [..] Seen_Res;
        defer array_free(seen);

        while EnumDisplaySettingsW(null, mode_index, *dm) != 0 {
            w := cast(s32) dm.dmPelsWidth;
            h := cast(s32) dm.dmPelsHeight;

            if w >= 640 && h >= 480 && w <= native_w && h <= native_h && dm.dmBitsPerPel == 32 {
                already_seen := false;
                for s : seen {
                    if s.w == w && s.h == h { already_seen = true; break; }
                }
                if !already_seen {
                    array_add(*seen, .{w, h});
                }
            }

            mode_index += 1;
            dm.dmSize = size_of(type_of(dm));
        }

        // sort descending by pixel count
        for i : 0..seen.count-2 {
            for j : i+1..seen.count-1 {
                a_pixels := seen[i].w * seen[i].h;
                b_pixels := seen[j].w * seen[j].h;
                if b_pixels > a_pixels {
                    tmp := seen[i];
                    seen[i] = seen[j];
                    seen[j] = tmp;
                }
            }
        }

        for s : seen {
            label := sprint("%x%", s.w, s.h);
            array_add(*available_resolutions, .{s.w, s.h, label});
            array_add(*resolution_labels, label);
        }

        // find current resolution in the list
        resolution_selection = 0;
        for i : 0..available_resolutions.count-1 {
            if available_resolutions[i].width == window_width && available_resolutions[i].height == window_height {
                resolution_selection = cast(s32) i;
                break;
            }
        }
    }

    if available_resolutions.count == 0 {
        array_add(*available_resolutions, .{1920, 1080, "1920x1080"});
        array_add(*available_resolutions, .{1280, 720,  "1280x720"});
        array_add(*available_resolutions, .{640,  480,  "640x480"});
        array_add(*resolution_labels, "1920x1080");
        array_add(*resolution_labels, "1280x720");
        array_add(*resolution_labels, "640x480");
    }
}

apply_resolution :: (using wp: *Windowed_Menu_Program_Base) {
    #if OS == .WINDOWS {
        win32 :: #import "Windows";

        if resolution_selection >= 0 && resolution_selection < cast(s32) available_resolutions.count {
            new_w := available_resolutions[resolution_selection].width;
            new_h := available_resolutions[resolution_selection].height;

            if new_w != window_width || new_h != window_height {
                if !fullscreen {
                    style   := win32.GetWindowLongW(window, win32.GWL_STYLE);
                    ex_style := win32.GetWindowLongW(window, win32.GWL_EXSTYLE);

                    rect: win32.RECT;
                    rect.left   = 0;
                    rect.top    = 0;
                    rect.right  = new_w;
                    rect.bottom = new_h;
                    win32.AdjustWindowRectEx(*rect, cast(u32) style, 0, xx ex_style);

                    adjusted_w := rect.right - rect.left;
                    adjusted_h := rect.bottom - rect.top;

                    win32.SetWindowPos(window, null, 0, 0, adjusted_w, adjusted_h, win32.SWP_NOMOVE | win32.SWP_NOZORDER | win32.SWP_FRAMECHANGED);
                }

                window_width  = new_w;
                window_height = new_h;
            }
        }
    }
}

apply_graphics_settings :: (using wp: *Windowed_Menu_Program_Base) {
    set_fullscreen(wp, desired_fullscreen);
    set_vsync(desired_vsync);
    vsync = desired_vsync;
    set_max_fps(wp, desired_max_fps);
    max_fps = desired_max_fps;
    apply_resolution(wp);
}

// you can just "using" this in your own game if you want a basic thing that helps you 
// build a menu for setting that most games are going to need anways
Windowed_Menu_Program_Base :: struct {
    using #as base : Windowed_Program;

    // pending settings (what the UI edits, applied on "Apply")
    desired_fullscreen := false;
    desired_vsync := false;
    desired_max_fps : u32 = 144;

    volume: float32 = 50.0;
    sensitivity: float32 = 0.3;
    resolution_selection: s32 = 0;
    available_resolutions: [..] Resolution_Entry;
    resolution_labels: [..] string;
}



init_default_ui_sounds :: (wmpb : *Windowed_Menu_Program_Base) {
    table_add(*sound_catalog, cast(u8) Engine_Sound_Type.BUTTON_CLICK, load_sound("data/sounds/ui/button_click.wav"));
    table_add(*sound_catalog, cast(u8) Engine_Sound_Type.BUTTON_HOVER, load_sound("data/sounds/ui/button_hover.wav"));
    table_add(*sound_catalog, cast(u8) Engine_Sound_Type.SLIDER_CHANGE, load_sound("data/sounds/ui/handle_tick.wav"));
}


// this is a specific implementation that we're providing to you to let you have one for free and see how we do stuff
Windowed_Menu_Program :: struct {
    using #as wmpg : Windowed_Menu_Program_Base;

    current_menu := Current_Menu.MAIN;
    menu_return_to := Current_Menu.MAIN;
}


init :: (using wmp : *Windowed_Menu_Program) {
}

init_menu_defaults :: (using wp: *Windowed_Menu_Program_Base) {
    desired_fullscreen = fullscreen;
    desired_vsync = vsync;
    desired_max_fps = max_fps;
}

// common ui widgets, move to the ui submodule later.

GREY_NORMAL  :: Vector4.{0.30, 0.30, 0.33, 0.9};
GREY_HOVER   :: Vector4.{0.42, 0.42, 0.45, 1.0};
GREY_ACTIVE  :: Vector4.{0.22, 0.22, 0.25, 1.0};

GREEN_NORMAL :: Vector4.{0.15, 0.50, 0.18, 0.9};
GREEN_HOVER  :: Vector4.{0.20, 0.65, 0.25, 1.0};
GREEN_ACTIVE :: Vector4.{0.12, 0.40, 0.14, 1.0};

BLUE_NORMAL  :: Vector4.{0.18, 0.40, 0.65, 0.9};
BLUE_HOVER   :: Vector4.{0.25, 0.50, 0.80, 1.0};
BLUE_ACTIVE  :: Vector4.{0.14, 0.32, 0.55, 1.0};

RED_NORMAL   :: Vector4.{0.55, 0.14, 0.14, 0.9};
RED_HOVER    :: Vector4.{0.72, 0.20, 0.20, 1.0};
RED_ACTIVE   :: Vector4.{0.42, 0.10, 0.10, 1.0};

GOLD_NORMAL  :: Vector4.{0.60, 0.50, 0.10, 0.9};
GOLD_HOVER   :: Vector4.{0.75, 0.63, 0.15, 1.0};
GOLD_ACTIVE  :: Vector4.{0.48, 0.40, 0.08, 1.0};

// a full-width colored button suitable for menus
ui_menu_button :: (label: string, normal: Vector4, hover: Vector4, active: Vector4) -> bool {
    ctx := ui_ctx;
    style := *ctx.style;
    id := ui_get_id(label);

    w := ui_available_width();
    h := style.button_height;
    rect := ui_allocate_rect(w, h);

    ui_try_hot(id, rect);
    ui_try_active(id);
    clicked := ui_was_clicked(id);
    if clicked  ui_emit_audio(.BUTTON_CLICK, id);

    bg: Vector4;
    if ui_is_active(id)        bg = active;
    else if ui_is_hot(id)      bg = hover;
    else                       bg = normal;

    ui_cmd_rect(rect, bg);
    ui_cmd_rect_outline(rect, style.color_border);

    text_x := ui_text_centered_x(rect, label, style.font_size);
    text_y := ui_text_baseline_y(rect, style.font_size);
    ui_cmd_text(label, text_x, text_y, style.font_size, style.color_text);

    return clicked;
}

// a section header in gold at a larger font size
ui_section_header :: (label: string) {
    ui_push_style_float(.FONT_SIZE, 22.0);
    ui_label_colored(label, .{1.0, 0.85, 0.2, 0.9});
    ui_pop_style_float(.FONT_SIZE);
}

// horizontally centered text at a given y position
ui_centered_text :: (text: string, y: float32, size: float32, color: Vector4) {
    ctx := ui_ctx;
    w := msdf_measure_text_pixels(ctx.font, text, size);
    ui_cmd_text(text, (ctx.window_w - w) * 0.5, y, size, color);
}

// a page header with title, optional subtitle, and separator line; returns the y position below it
draw_page_header :: (title: string, subtitle: string = "") -> float32 {
    ctx := ui_ctx;
    W := ctx.window_w;
    H := ctx.window_h;

    title_size : float32 = 64.0;
    title_y := H * 0.12;
    ui_centered_text(title, title_y, title_size, .{1.0, 0.85, 0.2, 1.0});

    bottom_y := title_y + title_size * 0.4 + 10.0;

    if subtitle.count > 0 {
        sub_size : float32 = 20.0;
        sub_y := title_y + title_size * 0.4 + 30.0;
        ui_centered_text(subtitle, sub_y, sub_size, .{0.7, 0.7, 0.7, 0.8});
        bottom_y = sub_y + 24.0;
    }

    sep_w : float32 = 300.0;
    ui_cmd_rect(.{(W - sep_w) * 0.5, bottom_y, sep_w, 2.0}, .{1.0, 0.85, 0.2, 0.4});

    return bottom_y + 30.0;
}

// a small version footer at the bottom of the screen
draw_version_footer :: (version_text: string = "Early Access.") {
    ctx := ui_ctx;
    ver_size : float32 = 14.0;
    ui_centered_text(version_text, ctx.window_h - 28.0, ver_size, .{0.45, 0.45, 0.45, 0.6});
}

// push a vertically centered layout for menu buttons
push_centered_layout :: (width: float32, y_start: float32, btn_h: float32, btn_gap: float32, font_size: float32) {
    ctx := ui_ctx;
    W := ctx.window_w;
    start_x := (W - width) * 0.5;

    ui_push_layout(.{
        mode = .VERTICAL,
        cursor_x = start_x,
        cursor_y = y_start,
        origin_x = start_x,
        origin_y = y_start,
        max_w = width, max_h = 2000,
        row_height = 0, indent = 0, content_max_y = 0,
    });

    ui_push_style_float(.BUTTON_HEIGHT, btn_h);
    ui_push_style_float(.FONT_SIZE, font_size);
    ui_push_style_float(.ITEM_SPACING, btn_gap);
}

pop_centered_layout :: () {
    ui_pop_style_float(.ITEM_SPACING);
    ui_pop_style_float(.FONT_SIZE);
    ui_pop_style_float(.BUTTON_HEIGHT);
    ui_pop_layout();
}

// a full-screen dark overlay
draw_overlay_background :: (alpha: float32 = 0.75) {
    ctx := ui_ctx;
    ui_cmd_rect(.{0, 0, ctx.window_w, ctx.window_h}, .{0.0, 0.0, 0.0, alpha});
}


// here is some sample rendering of a menu using the ui system, if you're making your own thing
// and want to use the ui system, then you can literally just copy out these functions and then
// replace Windowed_Menu_Program with whatever your thing is and make any tweaks you need.

// menu rendering using a centered layout and colored buttons


toggle_menu :: (using wp: *Windowed_Menu_Program) {
    if current_menu == .NONE {
        current_menu = .IN_GAME;
        show_cursor(wp);
    } else {
        current_menu = .NONE;
        hide_cursor(wp);
    }
}

render_main_menu :: (using wp : *Windowed_Menu_Program) {
    content_y := draw_page_header(window_name);

    push_centered_layout(280.0, content_y, 50.0, 14.0, 22.0);

    if ui_menu_button("Start", GREEN_NORMAL, GREEN_HOVER, GREEN_ACTIVE) {
        toggle_menu(wp);
    }

    if ui_menu_button("Graphics Settings", GREY_NORMAL, GREY_HOVER, GREY_ACTIVE) {
        menu_return_to = .MAIN;
        current_menu = .GRAPHICS_SETTINGS;
    }

    if ui_menu_button("User Settings", GREY_NORMAL, GREY_HOVER, GREY_ACTIVE) {
        menu_return_to = .MAIN;
        current_menu = .USER_SETTINGS;
    }

    if ui_menu_button("Sound Settings", GREY_NORMAL, GREY_HOVER, GREY_ACTIVE) {
        menu_return_to = .MAIN;
        current_menu = .SOUND_SETTINGS;
    }

    if ui_menu_button("Exit", RED_NORMAL, RED_HOVER, RED_ACTIVE) {
        end_program = true;
    }

    pop_centered_layout();

    draw_version_footer();
}

render_graphics_settings :: (using wp : *Windowed_Menu_Program) {
    content_y := draw_page_header("Graphics Settings");

    push_centered_layout(400.0, content_y, 40.0, 10.0, 18.0);

    if resolution_labels.count > 0 {
        ui_dropdown("Resolution", resolution_labels, *resolution_selection);
    }

    ui_spacing(4);
    ui_checkbox("Fullscreen", *desired_fullscreen);

    ui_spacing(4);
    ui_checkbox("VSync", *desired_vsync);

    ui_spacing(4);
    desired_max_fps_s32 := cast(s32) desired_max_fps;
    if ui_slider_int("Max FPS", *desired_max_fps_s32, 30, 512) {
        desired_max_fps = cast(u32) desired_max_fps_s32;
    }

    ui_spacing(20);

    ui_begin_row();

    if ui_button_colored("Apply", GREEN_NORMAL, GREEN_HOVER, GREEN_ACTIVE) {
        apply_graphics_settings(wp);
    }

    if ui_button_colored("Save", GOLD_NORMAL, GOLD_HOVER, GOLD_ACTIVE) {
        apply_graphics_settings(wp);
        save_settings(wp);
    }

    if ui_button_colored("Back", GREY_NORMAL, GREY_HOVER, GREY_ACTIVE) {
        current_menu = menu_return_to;
    }

    ui_end_row();

    pop_centered_layout();

    draw_version_footer();
}

render_sound_settings :: (using wp : *Windowed_Menu_Program) {
    content_y := draw_page_header("Sound Settings");

    push_centered_layout(400.0, content_y, 40.0, 10.0, 18.0);

    ui_slider_float("Volume", *volume, 0, 100);

    ui_spacing(20);

    ui_begin_row();

    if ui_button_colored("Apply", GREEN_NORMAL, GREEN_HOVER, GREEN_ACTIVE) {
        apply_sfx_volume(wp);
    }

    if ui_button_colored("Save", GOLD_NORMAL, GOLD_HOVER, GOLD_ACTIVE) {
        apply_sfx_volume(wp);
        save_settings(wp);
    }

    if ui_button_colored("Back", GREY_NORMAL, GREY_HOVER, GREY_ACTIVE) {
        current_menu = menu_return_to;
    }

    ui_end_row();

    pop_centered_layout();

    draw_version_footer();
}

render_user_settings :: (using wp : *Windowed_Menu_Program) {
    content_y := draw_page_header("User Settings");

    push_centered_layout(400.0, content_y, 40.0, 10.0, 18.0);

    ui_slider_float("Sensitivity", *sensitivity, 0.01, 2.0);

    ui_spacing(20);

    ui_begin_row();

    if ui_button_colored("Apply", GREEN_NORMAL, GREEN_HOVER, GREEN_ACTIVE) {
        // sensitivity is synced to camera in Windowed_Program_3D per_frame_update
    }

    if ui_button_colored("Save", GOLD_NORMAL, GOLD_HOVER, GOLD_ACTIVE) {
        save_settings(wp);
    }

    if ui_button_colored("Back", GREY_NORMAL, GREY_HOVER, GREY_ACTIVE) {
        current_menu = menu_return_to;
    }

    ui_end_row();

    pop_centered_layout();

    draw_version_footer();
}

render_in_game_menu :: (using wp : *Windowed_Menu_Program) {
    ctx := ui_ctx;
    content_y := ctx.window_h * 0.25;

    push_centered_layout(280.0, content_y, 50.0, 14.0, 22.0);

    if ui_menu_button("Resume", GREEN_NORMAL, GREEN_HOVER, GREEN_ACTIVE) {
        toggle_menu(wp);
    }

    if ui_menu_button("Graphics Settings", GREY_NORMAL, GREY_HOVER, GREY_ACTIVE) {
        menu_return_to = .IN_GAME;
        current_menu = .GRAPHICS_SETTINGS;
    }

    if ui_menu_button("User Settings", GREY_NORMAL, GREY_HOVER, GREY_ACTIVE) {
        menu_return_to = .IN_GAME;
        current_menu = .USER_SETTINGS;
    }

    if ui_menu_button("Sound Settings", GREY_NORMAL, GREY_HOVER, GREY_ACTIVE) {
        menu_return_to = .IN_GAME;
        current_menu = .SOUND_SETTINGS;
    }

    if ui_menu_button("Exit", RED_NORMAL, RED_HOVER, RED_ACTIVE) {
        end_program = true;
    }

    pop_centered_layout();
}

render_menus :: (using wp : *Windowed_Menu_Program) {
    if menu_return_to == .IN_GAME || current_menu == .IN_GAME {
        draw_overlay_background(0.75);
    }

    if current_menu == {
        case .MAIN;
            render_main_menu(wp);
        case .IN_GAME;
            render_in_game_menu(wp);
        case .GRAPHICS_SETTINGS;
            render_graphics_settings(wp);
        case .USER_SETTINGS;
            render_user_settings(wp);
        case .SOUND_SETTINGS;
            render_sound_settings(wp);
    }
}




apply_sfx_volume :: (using wp: *Windowed_Menu_Program_Base) {
    Sound_Player.mix_levels[Sound_Player.Sound_Category.GENERAL_SFX] = volume / 100.0;
    Sound_Player.mix_levels[Sound_Player.Sound_Category.UI]          = volume / 100.0;
}

save_settings :: (using wp: *Windowed_Menu_Program_Base) {
    set_float(*configuration, "audio", "volume", volume);
    set_int(*configuration, "graphics", "resolution", resolution_selection);
    set_bool(*configuration, "graphics", "fullscreen", desired_fullscreen);
    set_bool(*configuration, "graphics", "vsync", desired_vsync);
    set_int(*configuration, "graphics", "max_fps", cast(int) desired_max_fps);
    set_float(*configuration, "input", "sensitivity", sensitivity);
    save(*configuration);
}

load_menu_settings :: (using wp: *Windowed_Menu_Program) {
    vol, ok_vol := get_float(*configuration, "audio", "volume");
    if ok_vol {
        volume = vol;
        apply_sfx_volume(wp);
    }

    res_idx, ok_res := get_int(*configuration, "graphics", "resolution");
    if ok_res && res_idx >= 0 && res_idx < cast(int) available_resolutions.count {
        resolution_selection = cast(s32) res_idx;
    }

    fs, ok_fs := get_bool(*configuration, "graphics", "fullscreen");
    if ok_fs {
        desired_fullscreen = fs;
    }

    vs, ok_vs := get_bool(*configuration, "graphics", "vsync");
    if ok_vs {
        desired_vsync = vs;
    }

    fps, ok_fps := get_int(*configuration, "graphics", "max_fps");
    if ok_fps && fps >= 30 && fps <= 512 {
        desired_max_fps = cast(u32) fps;
    }

    sens, ok_sens := get_float(*configuration, "input", "sensitivity");
    if ok_sens && sens >= 0.01 && sens <= 2.0 {
        sensitivity = sens;
    }

    // apply all loaded settings to the active state
    apply_graphics_settings(wp);
}
