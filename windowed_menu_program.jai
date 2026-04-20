#scope_file
Input :: #import "Input";
Simp :: #import "Simp";
Sound_Player :: #import "Sound_Player";
#scope_export

Current_Menu :: enum {
    MAIN;
    GRAPHICS_SETTINGS;
    USER_SETTINGS;
    SOUND_SETTINGS;
    IN_GAME;
    NONE;
}


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
        menu_resolution_selection = 0;
        for i : 0..available_resolutions.count-1 {
            if available_resolutions[i].width == window_width && available_resolutions[i].height == window_height {
                menu_resolution_selection = cast(s32) i;
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

apply_resolution :: (using wp: *Windowed_Menu_Program) {
    #if OS == .WINDOWS {
        win32 :: #import "Windows";

        if menu_resolution_selection >= 0 && menu_resolution_selection < cast(s32) available_resolutions.count {
            new_w := available_resolutions[menu_resolution_selection].width;
            new_h := available_resolutions[menu_resolution_selection].height;

            if new_w != window_width || new_h != window_height {
                if !fullscreen {
                    style   := win32.GetWindowLongW(window, win32.GWL_STYLE);
                    ex_style := win32.GetWindowLongW(window, win32.GWL_EXSTYLE);

                    rect: win32.RECT;
                    rect.left   = 0;
                    rect.top    = 0;
                    rect.right  = new_w;
                    rect.bottom = new_h;
                    win32.AdjustWindowRectEx(*rect, cast(u32) style, 0, ex_style);

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


Windowed_Menu_Program :: struct {
    using #as base : Windowed_Program;

    current_menu := Current_Menu.MAIN;
    menu_return_to := Current_Menu.MAIN;  // where "Back" should go

    // menu state
    volume: float32 = 50.0;
    menu_fullscreen_checkbox: bool = false;
    menu_vsync_checkbox: bool = false;
    menu_resolution_selection: s32 = 0;
    menu_max_fps_float: float32 = 144.0;

    menu_sensitivity: float32 = 0.3;

    available_resolutions: [..] Resolution_Entry;
    resolution_labels: [..] string;
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

// potentially move this into the other thing

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
    w := msdf_measure_text(ctx.font, text, size);
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


// menu rendering useing a centered layout and colored buttons

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
        ui_dropdown("Resolution", resolution_labels, *menu_resolution_selection);
    }

    ui_spacing(4);
    ui_checkbox("Fullscreen", *menu_fullscreen_checkbox);

    ui_spacing(4);
    ui_checkbox("VSync", *menu_vsync_checkbox);

    ui_spacing(4);
    ui_slider_float("Max FPS", *menu_max_fps_float, 30.0, 512.0);

    ui_spacing(20);

    ui_begin_row();

    if ui_button_colored("Apply", GREEN_NORMAL, GREEN_HOVER, GREEN_ACTIVE) {
        if menu_fullscreen_checkbox != fullscreen {
            set_fullscreen(wp, menu_fullscreen_checkbox);
        }

        if menu_vsync_checkbox != vsync {
            vsync = menu_vsync_checkbox;
            set_vsync(vsync);
        }

        max_fps = cast(u32)(menu_max_fps_float + 0.5);
        set_max_fps(wp, max_fps);

        apply_resolution(wp);
    }

    if ui_button_colored("Save", GOLD_NORMAL, GOLD_HOVER, GOLD_ACTIVE) {
        if menu_fullscreen_checkbox != fullscreen {
            set_fullscreen(wp, menu_fullscreen_checkbox);
        }

        if menu_vsync_checkbox != vsync {
            vsync = menu_vsync_checkbox;
            set_vsync(vsync);
        }

        max_fps = cast(u32)(menu_max_fps_float + 0.5);
        set_max_fps(wp, max_fps);

        apply_resolution(wp);
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

    ui_label_disabled("No user settings available yet.");

    ui_spacing(20);

    if ui_button_colored("Back", GREY_NORMAL, GREY_HOVER, GREY_ACTIVE) {
        current_menu = menu_return_to;
    }

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
    // if we came from the in-game menu, always draw the dark overlay behind everything
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


toggle_menu :: (using wp: *Windowed_Menu_Program) {
    if current_menu == .NONE {
        current_menu = .IN_GAME;
        show_cursor(wp);
    } else {
        current_menu = .NONE;
        hide_cursor(wp);
    }
}


apply_sfx_volume :: (using wp: *Windowed_Menu_Program) {
    Sound_Player.mix_levels[Sound_Player.Sound_Category.GENERAL_SFX] = volume / 100.0;
    Sound_Player.mix_levels[Sound_Player.Sound_Category.UI]          = volume / 100.0;
}

save_settings :: (using wp: *Windowed_Menu_Program) {
    set_float(*configuration, "audio", "volume", volume);
    set_int(*configuration, "graphics", "resolution", menu_resolution_selection);
    set_bool(*configuration, "graphics", "fullscreen", menu_fullscreen_checkbox);
    set_bool(*configuration, "graphics", "vsync", menu_vsync_checkbox);
    set_float(*configuration, "graphics", "max_fps", menu_max_fps_float);
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
        menu_resolution_selection = cast(s32) res_idx;
    }

    fs, ok_fs := get_bool(*configuration, "graphics", "fullscreen");
    if ok_fs {
        menu_fullscreen_checkbox = fs;
        if fs != fullscreen {
            set_fullscreen(wp, fs);
        }
    }

    vs, ok_vs := get_bool(*configuration, "graphics", "vsync");
    if ok_vs {
        menu_vsync_checkbox = vs;
        if vs != vsync {
            vsync = vs;
            set_vsync(vsync);
        }
    }

    fps, ok_fps := get_float(*configuration, "graphics", "max_fps");
    if ok_fps && fps >= 30.0 && fps <= 512.0 {
        menu_max_fps_float = fps;
        max_fps = cast(u32)(fps + 0.5);
        set_max_fps(wp, max_fps);
    }

    apply_resolution(wp);
}
