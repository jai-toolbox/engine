// usage of this engine is at the bottom of the file

#import "Math";
#import "Basic";
#import "GL";

#scope_file
Window_Creation :: #import "Window_Creation";
Sound_Player :: #import "Sound_Player";
Simp :: #import "Simp";
Input :: #import "Input";
#scope_export

#load "sound.jai";

#import "tbx/opengl";
#import "tbx/camera";
#import "tbx/movement";
#import "tbx/rectangle";
#import "tbx/configuration";
#import "tbx/time";
#import "tbx/math";
#import "tbx/geometry";
#import "tbx/ui";

Current_Menu :: enum {
    MAIN;
    GRAPHICS_SETTINGS;
    USER_SETTINGS;
    SOUND_SETTINGS;
    IN_GAME;
    NONE;
}

Looping_Program :: struct {
    end_program := false; // loop on this condition

    max_fps : u32 = 144;
    min_frame_time :float;

    tick_timer : Periodic_Timer;

    current_time_sec : float = 0;

    section_timer : Section_Timer;

    current_frame_start : Apollo_Time;
    delta_time :float;

    iteration := 0;
}


set_max_fps :: (using lp: *Looping_Program, new_max_fps : u32) {
    max_fps = new_max_fps;
    min_frame_time = 1.0 / max_fps;
}

init :: (using lp: *Looping_Program) {
    min_frame_time = 1.0 / max_fps;
    delta_time = min_frame_time;
}

// must be called at start of frame for delta_time to be correct
mark_frame_start :: (using lp: *Looping_Program) {
    current_frame_start = current_time_monotonic();
}

// must be called to maintain target frame rate
sleep_to_maintain_max_fps :: (using lp: *Looping_Program) {
    while true {
        current_time := current_time_monotonic();
        if to_float64_seconds(current_time - current_frame_start) >= min_frame_time break;
    }
}

// must be called at end of frame for delta_time to be correct
mark_frame_end :: (using lp: *Looping_Program) {
    reset_temporary_storage();
    frame_end := current_time_monotonic();
    delta_time = cast (float) to_float64_seconds(frame_end - current_frame_start);
    current_time_sec += delta_time;
    iteration += 1;
}

// not required to function
per_frame_update :: (using lp: *Looping_Program) {
    mark_cycle(*tick_timer);
}


Windowed_Program :: struct {
    using # as lp : Looping_Program;

    window : Window_Creation.Window_Type;
    saved_window_info : Window_Creation.Saved_Window_Info;

    absolute_position_color_renderer : Absolute_Position_Color_Renderer;
    performance_graph: Performance_Graph;

    window_name : string = "";

    window_width : s32 = 1280;
    window_height : s32 = 720;

    vsync := false;
    fullscreen := false;
    window_has_focus := true;

    cursor_visible := true;

    right_handed_mouse_position := false;

    configuration: Configuration;

    // custom UI system replaces GetRect
    ui_context: UI_Context;
    ui_font: MSDF_Font;
    ui_msdf_renderer: Multi_Channel_Signed_Distance_Field_Text_Renderer;
    ui_rect_renderer: Absolute_Position_Color_Alpha_Renderer;
    ui_initialized := false;

    sound_catalog : Table(u8, Sound_Player.Sound_Data);

    // mouse/keyboard state gathered per frame for the UI
    ui_mouse_left_down:  bool;
    ui_mouse_right_down: bool;
    ui_scroll_y:         float32;
    ui_ctrl_held:        bool;
    ui_shift_held:       bool;
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



init :: (using wp: *Windowed_Program) {
    init(*lp);
    window = Window_Creation.create_window(window_width, window_height, window_name);
    Simp.set_render_target(window);

    init(*absolute_position_color_renderer);

    // initialize custom UI system
    #import "stb_image";
    stbi_set_flip_vertically_on_load(1);
    ui_font = msdf_font_load("data/fonts/pt_serif/atlas.json", "data/fonts/pt_serif/atlas.png");
    init(*ui_msdf_renderer);
    init(*ui_rect_renderer);
    ui_init(*ui_context, *ui_font, *ui_msdf_renderer, *ui_rect_renderer);
    ui_initialized = true;

    set_vsync(vsync);

    if !Sound_Player.sound_player_init(.{}) {
        print("Failed to initialize sound player!\n");
    }

    configuration.config_path = "data/engine.cfg";
    init(*configuration);
}

deinit :: (using wp: *Windowed_Program) {
    Sound_Player.sound_player_shutdown();
    deinit(*configuration);
    if ui_initialized {
        ui_destroy(*ui_context);
        msdf_font_destroy(*ui_font);
    }
}


sleep_to_maintain_max_fps :: (using wp: *Windowed_Program) {
    if vsync return;
    sleep_to_maintain_max_fps(*lp);
}



get_window_dimensions_vector :: (using wp : *Windowed_Program) -> Vector2 {
    return .{xx window_width, xx window_height};
}

set_aspect_ratio_uniform :: (using wp : *Windowed_Program) {
    set_active_program(absolute_position_color_renderer);
    set_aspect_ratio_uniform(*absolute_position_color_renderer, get_window_dimensions_vector(wp));
    clear_active_program();
}

per_frame_update :: (using wp: *Windowed_Program) {
    per_frame_update(*lp);

    // reset per-frame UI input accumulators
    ui_scroll_y = 0;
    ui_ctrl_held = false;
    ui_shift_held = false;

    Input.update_window_events();
    for Input.events_this_frame {
        if it.type == .QUIT then end_program = true;

        // feed keyboard events to custom UI
        if it.type == .KEYBOARD {
            if it.key_pressed {
                if it.key_code == {
                    case .BACKSPACE;    ui_push_key(.BACKSPACE);
                    case .DELETE;       ui_push_key(.DELETE);
                    case .ARROW_LEFT;   ui_push_key(.LEFT);
                    case .ARROW_RIGHT;  ui_push_key(.RIGHT);
                    case .HOME;         ui_push_key(.HOME);
                    case .END;          ui_push_key(.END);
                    case .ENTER;        ui_push_key(.ENTER);
                    case .ESCAPE;       ui_push_key(.ESCAPE);
                    case .TAB;          ui_push_key(.TAB);
                }
            }
            ui_ctrl_held  = it.ctrl_pressed;
            ui_shift_held = it.shift_pressed;
        }

        if it.type == .TEXT_INPUT {
            if it.utf32 >= 32 && it.utf32 < 127 {
                ui_push_char(cast(u8) it.utf32);
            }
        }

        if it.type == .MOUSE_WHEEL {
            if it.wheel_delta > 0      ui_scroll_y += 1.0;
            else if it.wheel_delta < 0 ui_scroll_y -= 1.0;
        }
    }

    // gather mouse button state
    ui_mouse_left_down  = (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_LEFT]  & .DOWN) != 0;
    ui_mouse_right_down = (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT] & .DOWN) != 0;

    ui_set_modifiers(ui_ctrl_held, ui_shift_held);

    // detect focus transitions
    old_focus := window_has_focus;
    window_has_focus = Input.input_application_has_focus;

    if old_focus && !window_has_focus {
        show_cursor(wp);
        if fullscreen {
            ChangeDisplaySettingsW(null, 0);
            ShowWindow(window, SW_MINIMIZE);
        }
    }

    if !old_focus && window_has_focus {
        if fullscreen {
            set_fullscreen(wp, true);
        }
    }

    for Input.get_window_resizes() {
        Simp.update_window(it.window);
        if it.window == window {
            resolution_has_changed := (it.width != window_width) || (it.height != window_height);
            if (resolution_has_changed) {
                window_width  = it.width;
                window_height = it.height;
            }
        }
    }

    set_aspect_ratio_uniform(wp);
}

// begin the UI frame - call this after per_frame_update, before any ui_ widget calls
ui_begin :: (using wp: *Windowed_Program) {
    mx, my, mouse_ok := Window_Creation.get_mouse_pointer_position(window, false);
    mouse_x := cast(float32) mx;
    mouse_y := cast(float32) my;

    w := cast(float32) window_width;
    h := cast(float32) window_height;

    ui_begin_frame(mouse_x, mouse_y, ui_mouse_left_down, ui_mouse_right_down, ui_scroll_y, w, h, cast(float64) delta_time);
}

// end the UI frame - call this after all widget calls, before swap_buffers
ui_end :: (using wp: *Windowed_Program) {
    ui_end_frame();
}

set_fullscreen :: (using wp: *Windowed_Program, enabled : bool) {
    if fullscreen == enabled return;

    #if OS == .WINDOWS {
        saved_window_info.rect.left = 0;
        saved_window_info.rect.top = 0;
        saved_window_info.rect.bottom = window_width;
        saved_window_info.rect.right = window_height;

        success, new_width, new_height := toggle_fullscreen_exclusive(window, enabled, *saved_window_info);
        fullscreen = enabled;
        set_vsync(vsync);
    }
}

DEVMODEW :: struct {
    dmDeviceName        : [32] u16;
    dmSpecVersion       : u16;
    dmDriverVersion     : u16;
    dmSize              : u16;
    dmDriverExtra       : u16;
    dmFields            : u32;
    dmPositionX         : s32;
    dmPositionY         : s32;
    dmDisplayOrientation: u32;
    dmDisplayFixedOutput: u32;
    dmColor             : s16;
    dmDuplex            : s16;
    dmYResolution       : s16;
    dmTTOption          : s16;
    dmCollate           : s16;
    dmFormName          : [32] u16;
    dmLogPixels         : u16;
    dmBitsPerPel        : u32;
    dmPelsWidth         : u32;
    dmPelsHeight        : u32;
    dmDisplayFlags      : u32;
    dmDisplayFrequency  : u32;
}

DM_BITSPERPEL : u32 : 0x00040000;
DM_PELSWIDTH  : u32 : 0x00080000;
DM_PELSHEIGHT : u32 : 0x00100000;
CDS_FULLSCREEN : u32 : 0x00000004;
DISP_CHANGE_SUCCESSFUL : s32 : 0;

#if OS == .WINDOWS {

_user32 :: #system_library "user32";
ChangeDisplaySettingsW :: (lpDevMode: *DEVMODEW, dwflags: u32) -> s32 #foreign _user32;

#import "Windows";
toggle_fullscreen_exclusive :: (hwnd: HWND, desire_fullscreen: bool, saved: *Window_Creation.Saved_Window_Info) -> (success: bool, width: s32, height: s32) {
    assert(saved != null);

    if desire_fullscreen {
        monitor := MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
        info: MONITORINFO;
        info.cbSize = size_of(type_of(info));
        if !GetMonitorInfoW(monitor, *info) return false, 0, 0;

        width  := info.rcMonitor.right  - info.rcMonitor.left;
        height := info.rcMonitor.bottom - info.rcMonitor.top;

        GetWindowRect(hwnd, *saved.rect);
        saved.style    = GetWindowLongW(hwnd, GWL_STYLE);
        saved.ex_style = GetWindowLongW(hwnd, GWL_EXSTYLE);

        dm: DEVMODEW;
        dm.dmSize       = size_of(type_of(dm));
        dm.dmPelsWidth  = xx width;
        dm.dmPelsHeight = xx height;
        dm.dmBitsPerPel = 32;
        dm.dmFields     = DM_PELSWIDTH | DM_PELSHEIGHT | DM_BITSPERPEL;

        if ChangeDisplaySettingsW(*dm, CDS_FULLSCREEN) != DISP_CHANGE_SUCCESSFUL {
            log("ChangeDisplaySettingsW failed");
            return false, 0, 0;
        }

        SetWindowLongW(hwnd, GWL_STYLE,   saved.style    & ~cast(s32)(WS_CAPTION | WS_THICKFRAME));
        SetWindowLongW(hwnd, GWL_EXSTYLE, saved.ex_style & ~cast(s32)(WS_EX_DLGMODALFRAME | WS_EX_WINDOWEDGE | WS_EX_CLIENTEDGE | WS_EX_STATICEDGE));
        SetWindowPos(hwnd, HWND_TOP, 0, 0, width, height, SWP_FRAMECHANGED);

        return true, width, height;
    } else {
        ChangeDisplaySettingsW(null, 0);

        x := saved.rect.left;
        y := saved.rect.top;
        SetWindowLongW(hwnd, GWL_STYLE,   saved.style);
        SetWindowLongW(hwnd, GWL_EXSTYLE, saved.ex_style);
        SetWindowPos(hwnd, HWND_TOP, x, y, saved.rect.right - x, saved.rect.bottom - y, SWP_FRAMECHANGED);

        return true, saved.rect.right - x, saved.rect.bottom - y;
    }
}

}

enable_fullscreen :: (using wp: *Windowed_Program) {
    set_fullscreen(wp, true);
}

disable_fullscreen :: (using wp: *Windowed_Program) {
    set_fullscreen(wp, false);
}


// Common UI widgets

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

render_tick_stats :: (using wp : *Windowed_Program) {
    average_tick_ms : int = xx (get_average_delta_time(*tick_timer) * 1000);
    average_fps : int = xx (1 / get_average_delta_time(*tick_timer));

    // render as a small window in the top-right
    w := cast(float32) window_width;
    if ui_begin_window("tick_stats", w - 160, 5, 150, 40) {
        ui_label(tprint("%fps / %ms", average_fps, average_tick_ms));
        ui_end_window();
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

Camera_Mode :: enum {
    FIRST_PERSON;
    THIRD_PERSON;
    TWO_DIMENSIONS;
}

Movement_Mode :: enum {
    GOD;
    MANUAL;
    FPS;
}

// we can remove the is prefix.

is_key_down :: inline (key : Input.Key_Code) -> bool #must {
    return (Input.input_button_states[cast (s64) key] & .DOWN) != 0;
}

is_key_just_pressed :: inline (key : Input.Key_Code) -> bool #must {
    return (Input.input_button_states[cast (s64) key] & .START) != 0;
}

right_mouse_just_pressed :: () -> bool #must {
    return Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT] & .START != 0;
}

left_mouse_just_pressed :: () -> bool #must {
    return Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_LEFT] & .START != 0;
}

left_mouse_pressed :: () -> bool #must {
    return Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_LEFT] & .DOWN != 0;
}

right_mouse_pressed :: () -> bool #must {
    return Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT] & .DOWN != 0;
}

sample_first_person_movement_input :: () -> First_Person_Movement_Input {
    return .{
            is_key_down (xx #char "W"),
            is_key_down (xx #char "S"),
            is_key_down (xx #char "D"),
            is_key_down (xx #char "A"),
            is_key_down (xx #char " "),
        };
}

get_forward_and_side_input :: (using fpmi : First_Person_Movement_Input) -> forward_input: float, side_input: float {
    forward_input : float = 0.0;
    right_input   : float = 0.0;

    if forward_pressed forward_input += 1.0;
    if back_pressed forward_input    -= 1.0;
    if right_pressed right_input     += 1.0;
    if left_pressed right_input      -= 1.0;

    return forward_input, right_input;
}

Orientation :: struct {
    forward: Vector3;
    right: Vector3;
    up: Vector3;
}

STANDARD_ORIENTATION :: #run Orientation.{X3, -Y3, Z3};
GL_ORIENTATION :: Orientation.{Z3, X3, Y3};
NEGATIVE_Z_GL_ORIENTATION :: #run Orientation.{-Z3, X3, Y3};

Windowed_Program_3D :: struct {

    using #as wp : Windowed_Menu_Program;

    orientation := STANDARD_ORIENTATION;

    camera_per_object_transform_color_renderer : Camera_Per_Object_Transform_Color_Renderer;

    camera : Camera;
    camera_mode := Camera_Mode.FIRST_PERSON;

    camera_look_active := true;

    camera_velocity : Vector3;
    movement_mode : Movement_Mode;

    renderables : [..] Camera_Per_Object_Transform_Color_Renderable;

    last_mouse_delta_x, last_mouse_delta_y: int;

    // 2D camera state
    ortho_center : Vector2;
    ortho_height := 10.0;

    // drag state
    is_dragging := false;
    drag_start_mouse : Vector2;
    drag_start_center : Vector2;
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


init :: (using wp3 : *Windowed_Program_3D) {
    init(*wp);
    init(*camera_per_object_transform_color_renderer);
    init(*absolute_position_color_renderer);
    init_section_timer(*section_timer);

    performance_graph.graph_min_ms = min_frame_time * 1000 - 1;
    performance_graph.graph_max_ms = min_frame_time * 1000 + 5;

    // enumerate available resolutions before loading settings
    enumerate_resolutions(*wp3.wp);

    menu_fullscreen_checkbox = fullscreen;
    menu_vsync_checkbox = vsync;

    conf_sens, ok_s := get_float(*configuration, "input", "sensitivity");
    if ok_s camera.sensitivity = conf_sens;

    load_menu_settings(*wp3.wp);
}

set_mouse_pointer_position :: inline (x : int, y : int) {
    #if OS == .WINDOWS {
        user32 :: #system_library "User32";
        SetCursorPos :: (x : s32, y : s32) -> s32 #foreign user32;
        SetCursorPos (xx x, xx y);
    } else {
        // @Todo!
    }
}

format_vec3 :: (v: Vector3, decimals: int = 2) -> string {
    return tprint("(%, %, %)",
        FormatFloat.{value=v.x, trailing_width=decimals, zero_removal=.NO},
        FormatFloat.{value=v.y, trailing_width=decimals, zero_removal=.NO},
        FormatFloat.{value=v.z, trailing_width=decimals, zero_removal=.NO});
}

render_movement_stats :: (using wp3 : *Windowed_Program_3D) {
    ui_label(tprint("pos: %", format_vec3(camera.position)));
    ui_label(tprint("vel: %", format_vec3(camera_velocity)));
}

render_camera_stats :: (using wp3 : *Windowed_Program_3D) {
    ui_label(tprint("fwd: %", format_vec3(get_forward(*camera))));
}

render_iteration :: (using wp3 : *Windowed_Program_3D) {
    ui_label(tprint("iter: %", iteration));
}


keep_mouse_in_center_of_screen :: (using wp: *Windowed_Program) {
    #if OS == .WINDOWS {
        x, y, w, h := Window_Creation.get_dimensions(window, right_handed_mouse_position);
        set_mouse_pointer_position (w / 2, h / 2);
    } else {
        // don't know how to do this on linux yet.
    }
}

update_listener_orientation :: (position: Vector3, yaw: float) {
    yaw_quat: Quaternion;
    set_from_axis_and_angle(*yaw_quat, 0, 0, 1, -yaw);

    rotation_y: Quaternion;
    set_from_axis_and_angle(*rotation_y, 0, 1, 0, PI/2);

    rotation_z: Quaternion;
    set_from_axis_and_angle(*rotation_z, 0, 0, 1, PI/2);

    correction_quat := rotation_z * rotation_y;
    listener_orientation := yaw_quat * correction_quat;

    Sound_Player.update_listener(position, listener_orientation);
}

per_frame_update :: (using wp3 : *Windowed_Program_3D) {
    per_frame_update(*wp3.wp);

    // sync sensitivity from menu to camera
    camera.sensitivity = menu_sensitivity;

    // handle ESC to toggle in-game menu
    // handle M to toggle mouse cursor without opening menu
    for Input.events_this_frame {
        if it.type == .KEYBOARD && it.key_pressed {
            if it.key_code == .ESCAPE {
                if !camera_look_active {
                    // if mouse mode is active, pressing ESC should re-lock the camera first
                    camera_look_active = true;
                } else {
                    toggle_menu(wp3);
                }
            }

            if it.key_code == xx #char "M" && current_menu == .NONE {
                camera_look_active = !camera_look_active;
            }
        }
    }

    want_cursor_captured := camera_look_active
                         && current_menu == .NONE
                         && camera_mode != .TWO_DIMENSIONS
                         && window_has_focus;

    if want_cursor_captured {
        hide_cursor(*wp);
        #if OS == .WINDOWS {
            keep_mouse_in_center_of_screen(*wp3.wp);
            last_mouse_delta_x = Input.mouse_delta_x;
            last_mouse_delta_y = Input.mouse_delta_y;
            update_angles_with_deltas(*camera, Input.mouse_delta_x, Input.mouse_delta_y);
        } else {
            x, y, success := Window_Creation.get_mouse_pointer_position(window, right_handed_mouse_position);
            if success update_angles(*camera, x, y);
        }
    } else {
        show_cursor(*wp);
    }

    vx, vy, vw, vh := Window_Creation.get_dimensions(window, right_handed_mouse_position);

    if camera_mode == {
        case .FIRST_PERSON;
            update_matrices(*camera, vw, vh);
        case .THIRD_PERSON;
            update_matrices_third_person(*camera, vw, vh);
    }

    if camera_mode != .TWO_DIMENSIONS && want_cursor_captured {
        if movement_mode == {
            case .GOD;
                gmi := God_Mode_Input.{
                    is_key_down(xx #char "E"),
                    is_key_down(xx #char "Q"),
                    is_key_down(xx #char "W"),
                    is_key_down(xx #char "S"),
                    is_key_down(xx #char "D"),
                    is_key_down(xx #char "A"),
                    is_key_down(xx #char " "),
                    is_key_down(Input.Key_Code.SHIFT),
                };
                camera_velocity = get_new_god_mode_velocity(camera_velocity, get_forward(*camera), gmi, delta_time);
        }
    }

    if movement_mode != .MANUAL camera.position += camera_velocity * delta_time;

    update_listener_orientation(camera.position, camera.yaw);
    Sound_Player.update(delta_time);

    // handle 2d drag and scroll
    if camera_mode == .TWO_DIMENSIONS && current_menu == .NONE {
        aspect := cast(float) vw / cast(float) vh;
        ortho_width := ortho_height * aspect;

        for Input.events_this_frame {
            if it.type == .MOUSE_WHEEL {
                if it.wheel_delta > 0 {
                    ortho_height *= 0.9;
                    if ortho_height < 0.1  ortho_height = 0.1;
                } else if it.wheel_delta < 0 {
                    ortho_height *= 1.1;
                }
            }
        }

        mouse_left_down := is_key_down(xx Input.Key_Code.MOUSE_BUTTON_LEFT);
        mx, my, mouse_success := Window_Creation.get_mouse_pointer_position(window, true);

        if mouse_success {
            mouse_world_x := (cast(float) mx / cast(float) vw - 0.5) * ortho_width + ortho_center.x;
            mouse_world_y := (cast(float) my / cast(float) vh - 0.5) * ortho_height + ortho_center.y;

            if mouse_left_down {
                if !is_dragging {
                    is_dragging = true;
                    drag_start_mouse = .{mouse_world_x, mouse_world_y};
                    drag_start_center = ortho_center;
                } else {
                    current_mouse_world_x := (cast(float) mx / cast(float) vw - 0.5) * ortho_width + drag_start_center.x;
                    current_mouse_world_y := (cast(float) my / cast(float) vh - 0.5) * ortho_height + drag_start_center.y;

                    ortho_center.x = drag_start_center.x - (current_mouse_world_x - drag_start_mouse.x);
                    ortho_center.y = drag_start_center.y - (current_mouse_world_y - drag_start_mouse.y);
                }
            } else {
                is_dragging = false;
            }
        }
    }

    glUseProgram(absolute_position_color_renderer.shader_program_gl_handle);

    glUseProgram(camera_per_object_transform_color_renderer.shader_program_gl_handle);

    if camera_mode != .TWO_DIMENSIONS {
        set_world_to_camera_uniform(*camera_per_object_transform_color_renderer, camera.world_to_camera);
        set_camera_to_clip_uniform(*camera_per_object_transform_color_renderer, camera.camera_to_clip);
    } else {
        world_to_camera := Matrix4_Identity;
        set_world_to_camera_uniform(*camera_per_object_transform_color_renderer, world_to_camera);

        aspect := cast(float) vw / cast(float) vh;
        ortho_width := ortho_height * aspect;
        half_w := ortho_width * 0.5;
        half_h := ortho_height * 0.5;

        ortho := orthographic_projection_matrix(
            left   = ortho_center.x - half_w,
            right  = ortho_center.x + half_w,
            bottom = ortho_center.y - half_h,
            top    = ortho_center.y + half_h,
            near   = -100.0,
            far    =  100.0,
            depth_range_01 = false
        );

        set_camera_to_clip_uniform(*camera_per_object_transform_color_renderer, ortho);
    }
}

render_scene :: (using wp3 : *Windowed_Program_3D) {

    for renderables queue_render(*wp3.camera_per_object_transform_color_renderer, it.object_index);

    Simp.update_window(wp3.window);
    Simp.clear_render_target(.15, .08, .08, 1);

    // begin the UI frame
    ui_begin(*wp3.wp);

    // always render the 3D scene (it shows behind the overlay when menu is open)
    glDepthMask(GL_TRUE);
    glEnable(GL_DEPTH_TEST);
    glClear(GL_DEPTH_BUFFER_BIT);
    render(*wp3.camera_per_object_transform_color_renderer);

    if wp3.current_menu == .NONE {
        // HUD elements via the custom UI as small windows
        if ui_begin_window("hud_stats", 5, 5, 300, 100) {
             if wp3.camera_look_active {
                ui_label_colored("M - toggle mouse cursor", .{0.5, 0.5, 0.5, 0.6});
            } else {
                ui_label_colored("M - lock camera (mouse free)", .{0.3, 1.0, 0.3, 0.8});
            }
            render_tick_stats(wp3);
            render_movement_stats(wp3);
            render_camera_stats(wp3);
            render_iteration(wp3);
            ui_end_window();
        }

        // performance graphs still use the absolute_position_color_renderer
        update_graph_visual(*wp3.performance_graph);
        render_performance_graph(wp3);
        render_section_bar_graph(wp3);
    } else if wp3.current_menu == .MAIN {
        // initial menu - no 3D scene visible (or you could show it, up to you)
        render_menus(*wp3.wp);
    } else {
        // in-game menu or settings - render over the 3D scene
        render_menus(*wp3.wp);
    }

    // end the UI frame - flushes all draw commands
    ui_end(*wp3.wp);

    // play UI sounds from audio events emitted during the frame
    drain_ui_audio_events(*wp3.wp);

    Simp.swap_buffers(wp3.window, false);
}



Engine_Sound_Type :: enum u8 {
    // ordering matches that in the ui sound types
    BUTTON_CLICK;
    BUTTON_HOVER;
    SLIDER_CHANGE;
}


// drains UI audio events and plays sounds from the sound catalog. expects the catalog to have entries keyed by Engine_Sound_Type, though we can change this later
drain_ui_audio_events :: (using wp: *Windowed_Program) {
    for event : ui_drain_audio_events() {
        if event.type == {
            case .BUTTON_CLICK;
                sound_data := table_find_pointer(*sound_catalog, cast(u8) Engine_Sound_Type.BUTTON_CLICK);
                if sound_data play_sound(*sound_catalog, cast(u8) Engine_Sound_Type.BUTTON_CLICK);
            case .BUTTON_HOVER;
                sound_data := table_find_pointer(*sound_catalog, cast(u8) Engine_Sound_Type.BUTTON_HOVER);
                if sound_data play_sound(*sound_catalog, cast(u8) Engine_Sound_Type.BUTTON_HOVER);
            case .SLIDER_CHANGE;
                sound_data := table_find_pointer(*sound_catalog, cast(u8) Engine_Sound_Type.SLIDER_CHANGE);
                if sound_data play_sound(*sound_catalog, cast(u8) Engine_Sound_Type.SLIDER_CHANGE);
        }
    }
}


show_cursor :: (using wp: *Windowed_Program) {
    if !cursor_visible {
        cursor_visible = true;
        #if OS == .WINDOWS {
            win32 :: #import "Windows";
            win32.ShowCursor(1);
        }
    }
}

hide_cursor :: (using wp: *Windowed_Program) {
    if cursor_visible {
        cursor_visible = false;
        #if OS == .WINDOWS {
            win32 :: #import "Windows";
            win32.ShowCursor(0);
        }
    }
}


// performance graph 

Performance_Graph :: struct {
    graph_min_ms: float = 4.0;
    graph_max_ms: float = 25.0;

    bar_graph_min_ms: float = 0.0;
    bar_graph_max_ms: float = 10.0;

    GRAPH_STEP_MS :: 0.5;
    GRAPH_MS_FLOOR :: 0.0;
    GRAPH_MS_CEILING :: 200.0;
    GRAPH_MIN_RANGE :: 0.5;
}

render_performance_graph :: (using wp: *Windowed_Program) {
    push_allocator(temp);
    graph_renderable := create_frame_time_graph_with_background(
        *section_timer,
        graph_origin = .{0.95, -0.95},
        graph_size = .{0.4, 0.2},
        min_ms = performance_graph.graph_min_ms,
        max_ms = performance_graph.graph_max_ms,
        target_ms = min_frame_time * 1000
    );
    immediate_render(*wp.absolute_position_color_renderer, graph_renderable);
}

update_graph_visual :: (using pg: *Performance_Graph) {
    shift_down := is_key_down(Input.Key_Code.SHIFT);

    if shift_down {
        if is_key_just_pressed(.ARROW_UP) {
            bar_graph_max_ms -= GRAPH_STEP_MS;
            if bar_graph_max_ms < bar_graph_min_ms + GRAPH_MIN_RANGE  bar_graph_max_ms = bar_graph_min_ms + GRAPH_MIN_RANGE;
        }
        if is_key_just_pressed(.ARROW_DOWN) {
            bar_graph_max_ms += GRAPH_STEP_MS;
            if bar_graph_max_ms > GRAPH_MS_CEILING  bar_graph_max_ms = GRAPH_MS_CEILING;
        }
        if is_key_just_pressed(.ARROW_RIGHT) {
            bar_graph_min_ms += GRAPH_STEP_MS;
            if bar_graph_min_ms > bar_graph_max_ms - GRAPH_MIN_RANGE  bar_graph_min_ms = bar_graph_max_ms - GRAPH_MIN_RANGE;
        }
        if is_key_just_pressed(.ARROW_LEFT) {
            bar_graph_min_ms -= GRAPH_STEP_MS;
            if bar_graph_min_ms < GRAPH_MS_FLOOR  bar_graph_min_ms = GRAPH_MS_FLOOR;
        }
    } else {
        if is_key_just_pressed(.ARROW_UP) {
            graph_max_ms -= GRAPH_STEP_MS;
            if graph_max_ms < graph_min_ms + GRAPH_MIN_RANGE  graph_max_ms = graph_min_ms + GRAPH_MIN_RANGE;
        }
        if is_key_just_pressed(.ARROW_DOWN) {
            graph_max_ms += GRAPH_STEP_MS;
            if graph_max_ms > GRAPH_MS_CEILING  graph_max_ms = GRAPH_MS_CEILING;
        }
        if is_key_just_pressed(.ARROW_RIGHT) {
            graph_min_ms += GRAPH_STEP_MS;
            if graph_min_ms > graph_max_ms - GRAPH_MIN_RANGE  graph_min_ms = graph_max_ms - GRAPH_MIN_RANGE;
        }
        if is_key_just_pressed(.ARROW_LEFT) {
            graph_min_ms -= GRAPH_STEP_MS;
            if graph_min_ms < GRAPH_MS_FLOOR  graph_min_ms = GRAPH_MS_FLOOR;
        }
    }
}

create_frame_time_graph :: (st: *Section_Timer, graph_origin: Vector2 = .{-0.95, -0.95}, graph_size: Vector2 = .{0.5, 0.3}, min_ms: float = 0.0, max_ms: float = 33.33) -> Indexed_Triangle_Positions_Colors {

    points: [MAX_HISTORY] Vector2;
    point_count: int = 0;

    if st.completed_tree_count == 0 {
        empty: Indexed_Triangle_Positions_Colors;
        return empty;
    }

    count := cast(int) st.completed_tree_count;

    oldest_index: int;
    if count < MAX_HISTORY {
        oldest_index = 0;
    } else {
        oldest_index = cast(int) st.completed_tree_write_index;
    }

    range_ms := max_ms - min_ms;
    if range_ms <= 0 range_ms = 1.0;

    for i: 0..count-1 {
        idx := (oldest_index + i) % MAX_HISTORY;
        root := st.completed_tree_roots[idx];
        if root == null || !root.completed continue;

        x_norm := cast(float) i / cast(float) max(count - 1, 1);
        frame_ms := root.elapsed_seconds * 1000.0;
        y_norm := clamp((frame_ms - min_ms) / range_ms, 0.0, 1.0);

        points[point_count] = .{x_norm, y_norm};
        point_count += 1;
    }

    if point_count < 2 {
        empty: Indexed_Triangle_Positions_Colors;
        return empty;
    }

    points_slice: [] Vector2;
    points_slice.data = points.data;
    points_slice.count = point_count;

    graph_itp := create_graph(points_slice, graph_origin, graph_size);

    itpc: Indexed_Triangle_Positions_Colors;
    for graph_itp.indices array_add(*itpc.indices, it);
    for graph_itp.positions array_add(*itpc.positions, it);

    color := Vector3.{0.2, 0.8, 0.3};
    array_reserve(*itpc.rgb_colors, itpc.positions.count);
    for 1..itpc.positions.count array_add(*itpc.rgb_colors, color);

    return itpc;
}


create_frame_time_graph_with_background :: (st: *Section_Timer, graph_origin: Vector2 = .{-0.95, -0.95}, graph_size: Vector2 = .{0.5, 0.3}, min_ms: float = 0.0, max_ms: float = 33.33, target_ms: float = 16.67) -> Indexed_Triangle_Positions_Colors {
    itpc: Indexed_Triangle_Positions_Colors;

    range_ms := max_ms - min_ms;
    if range_ms <= 0 range_ms = 1.0;

    merge(*itpc, create_itpc_with_color(
        create_quad(graph_origin.x, graph_origin.y, graph_origin.x + graph_size.x, graph_origin.y + graph_size.y, 0.02),
        .{0.1, 0.1, 0.1}));

    line_half_height := graph_size.y * 0.005;
    first_tick_ms := cast(float) cast(int) min_ms + 1.0;
    tick_ms := first_tick_ms;
    while tick_ms < max_ms {
        if tick_ms != target_ms {
            y_norm := (tick_ms - min_ms) / range_ms;
            if y_norm >= 0.0 && y_norm <= 1.0 {
                y := graph_origin.y + y_norm * graph_size.y;
                merge(*itpc, create_itpc_with_color(
                    create_quad(graph_origin.x, y - line_half_height, graph_origin.x + graph_size.x, y + line_half_height, 0.01),
                    .{0.35, 0.35, 0.35}));
            }
        }
        tick_ms += 1.0;
    }

    merge(*itpc, create_frame_time_graph(st, graph_origin, graph_size, min_ms, max_ms));

    target_y_norm := (target_ms - min_ms) / range_ms;
    if target_y_norm >= 0.0 && target_y_norm <= 1.0 {
        target_y := graph_origin.y + target_y_norm * graph_size.y;
        line_half_height_target := graph_size.y * 0.01;
        merge(*itpc, create_itpc_with_color(
            create_quad(graph_origin.x, target_y - line_half_height_target, graph_origin.x + graph_size.x, target_y + line_half_height_target, -0.01),
            .{1.0, 0.0, 0.0}));
    }

    return itpc;
}


Section_Color_Entry :: struct {
    name: string;
    color: Vector3;
}

seen_section_colors: [MAX_SECTIONS] Section_Color_Entry;
seen_section_color_count: int = 0;

hash_section_name_to_color :: (name: string) -> Vector3 {
    for i: 0..seen_section_color_count-1 {
        if seen_section_colors[i].name == name return seen_section_colors[i].color;
    }

    h: u32 = 5381;
    for i: 0..name.count-1 {
        h = ((h << 5) + h) + cast(u32) name[i];
    }

    r_hash := cast(float)((h * 2654435761) % 1000) / 1000.0;
    g_hash := cast(float)((h * 2246822519) % 1000) / 1000.0;
    b_hash := cast(float)((h * 3266489917) % 1000) / 1000.0;

    color := Vector3.{
        0.3 + r_hash * 0.6,
        0.3 + g_hash * 0.6,
        0.3 + b_hash * 0.6
    };

    if seen_section_color_count < MAX_SECTIONS {
        seen_section_colors[seen_section_color_count] = .{name, color};
        seen_section_color_count += 1;
    }

    return color;
}

create_section_bar_graph :: (st: *Section_Timer, graph_origin: Vector2 = .{-0.95, -0.95}, graph_size: Vector2 = .{0.3, 0.3}, min_ms: float = 0.0, max_ms: float = 33.33, target_ms: float = 16.67, print_legend: bool = false) -> Indexed_Triangle_Positions_Colors {
    itpc: Indexed_Triangle_Positions_Colors;

    range_ms := max_ms - min_ms;
    if range_ms <= 0 range_ms = 1.0;

    merge(*itpc, create_itpc_with_color(
        create_quad(graph_origin.x, graph_origin.y, graph_origin.x + graph_size.x, graph_origin.y + graph_size.y, 0.02),
        .{0.1, 0.1, 0.1}));

    line_half_height := graph_size.y * 0.005;
    tick_ms := cast(float)(cast(int) min_ms + 1);
    while tick_ms < max_ms {
        if tick_ms != target_ms {
            y_norm := (tick_ms - min_ms) / range_ms;
            if y_norm >= 0.0 && y_norm <= 1.0 {
                y := graph_origin.y + y_norm * graph_size.y;
                merge(*itpc, create_itpc_with_color(
                    create_quad(graph_origin.x, y - line_half_height, graph_origin.x + graph_size.x, y + line_half_height, 0.01),
                    .{0.35, 0.35, 0.35}));
            }
        }
        tick_ms += 1.0;
    }

    target_y_norm := (target_ms - min_ms) / range_ms;
    if target_y_norm >= 0.0 && target_y_norm <= 1.0 {
        target_y := graph_origin.y + target_y_norm * graph_size.y;
        line_half_height_target := graph_size.y * 0.01;
        merge(*itpc, create_itpc_with_color(
            create_quad(graph_origin.x, target_y - line_half_height_target, graph_origin.x + graph_size.x, target_y + line_half_height_target, -0.02),
            .{1.0, 0.0, 0.0}));
    }

    root := get_latest_completed_section(st);
    if root == null return itpc;
    if root.child_count == 0 return itpc;

    child_count := cast(int) root.child_count;

    gap_fraction := 0.1;
    bar_slot_width := graph_size.x / cast(float) child_count;
    gap_width := bar_slot_width * gap_fraction;
    bar_width := bar_slot_width - gap_width;

    if print_legend {
        print("[section_bar_graph] Legend (left to right):\n");
    }

    for i: 0..child_count-1 {
        child := root.children[i];
        if child == null continue;
        if !child.completed continue;

        child_ms := child.elapsed_seconds * 1000.0;
        bar_height_norm := clamp((child_ms - min_ms) / range_ms, 0.0, 1.0);

        bar_x0 := graph_origin.x + cast(float) i * bar_slot_width + gap_width * 0.5;
        bar_x1 := bar_x0 + bar_width;
        bar_y0 := graph_origin.y;
        bar_y1 := graph_origin.y + bar_height_norm * graph_size.y;

        color := hash_section_name_to_color(child.name);

        if print_legend {
            print("  [%] '%' -> (%, %, %)\n",
                i,
                child.name,
                FormatFloat.{value=color.x, trailing_width=2, zero_removal=.NO},
                FormatFloat.{value=color.y, trailing_width=2, zero_removal=.NO},
                FormatFloat.{value=color.z, trailing_width=2, zero_removal=.NO});
        }

        merge(*itpc, create_itpc_with_color(
            create_quad(bar_x0, bar_y0, bar_x1, bar_y1, -0.01),
            color));
    }

    if print_legend print("\n");

    return itpc;
}

render_section_bar_graph :: (using wp: *Windowed_Program) {
    push_allocator(temp);

    should_print := is_key_just_pressed(xx #char "P");

    bar_renderable := create_section_bar_graph(
        *section_timer,
        graph_origin = .{0.95 , -0.95 + 0.2 + 0.02},
        graph_size = .{0.4, 0.15},
        min_ms = performance_graph.bar_graph_min_ms,
        max_ms = performance_graph.bar_graph_max_ms,
        target_ms = min_frame_time * 1000,
        print_legend = should_print
    );
    immediate_render(*wp.absolute_position_color_renderer, bar_renderable);
}

#import "tbx/network";
#import "tbx/serialize";

// the packet is allocated on temporary storage, because packets get sent out soon.
packet_create :: (t: $T, packet_flags : Packet_Flags) -> *Packet {
    size_when_serialized := size_when_serialized_with_type_first(t);
    memory : *void = temporary_alloc(size_when_serialized);
    serialize_with_type_first(memory, t);
    packet := packet_create(memory, size_when_serialized, packet_flags);
    return packet;
}

#import "tbx/circular_array";

create_time_series_graph :: (
    history: *Circular_Array(float, $N),
    graph_origin: Vector2,
    graph_size: Vector2,
    min_val: float,
    max_val: float,
    color: Vector3 = .{0.2, 0.8, 0.3},
    reference_lines: [] float = .[]
) -> Indexed_Triangle_Positions_Colors {

    itpc: Indexed_Triangle_Positions_Colors;

    range_val := max_val - min_val;
    if range_val <= 0 range_val = 1.0;

    merge(*itpc, create_itpc_with_color(
        create_quad(graph_origin.x, graph_origin.y, graph_origin.x + graph_size.x, graph_origin.y + graph_size.y, 0.02),
        .{0.1, 0.1, 0.1}));

    count := history.count;
    if count >= 2 {
        points: [N] Vector2;
        point_count := 0;

        idx := history.tail;
        for i: 0..count-1 {
            x_norm := cast(float) i / cast(float) max(count - 1, 1);
            val := history.data[idx];
            y_norm := clamp((val - min_val) / range_val, 0.0, 1.0);

            points[point_count] = .{x_norm, y_norm};
            point_count += 1;

            idx = (idx + 1) % N;
        }

        points_slice: [] Vector2;
        points_slice.data = points.data;
        points_slice.count = point_count;

        graph_itp := create_graph(points_slice, graph_origin, graph_size);
        graph_itpc := create_itpc_with_color(graph_itp, color);
        merge(*itpc, graph_itpc);
    }

    line_half_height := graph_size.y * 0.008;
    for ref_idx: 0..reference_lines.count-1 {
        ref_val := reference_lines[ref_idx];
        y_norm := (ref_val - min_val) / range_val;
        if y_norm >= 0.0 && y_norm <= 1.0 {
            y := graph_origin.y + y_norm * graph_size.y;
            merge(*itpc, create_itpc_with_color(
                create_quad(graph_origin.x, y - line_half_height, graph_origin.x + graph_size.x, y + line_half_height, -0.01),
                .{1.0, 1.0, 1.0}));
        }
    }

    return itpc;
}

create_colored_timeline_strip :: (
    history: *Circular_Array(float, $N),
    graph_origin: Vector2,
    graph_size: Vector2,
    color_map_func: (float) -> Vector3 = null
) -> Indexed_Triangle_Positions_Colors {

    itpc: Indexed_Triangle_Positions_Colors;

    merge(*itpc, create_itpc_with_color(
        create_quad(graph_origin.x, graph_origin.y, graph_origin.x + graph_size.x, graph_origin.y + graph_size.y, 0.02),
        .{0.1, 0.1, 0.1}));

    count := history.count;
    if count == 0 return itpc;

    bar_width := graph_size.x / cast(float) count;

    idx := history.tail;
    for i: 0..count-1 {
        val := history.data[idx];

        color: Vector3;
        if color_map_func != null {
            color = color_map_func(val);
        } else {
            color = default_binary_color_map(val);
        }

        x0 := graph_origin.x + cast(float) i * bar_width;
        x1 := x0 + bar_width;

        merge(*itpc, create_itpc_with_color(
            create_quad(x0, graph_origin.y, x1, graph_origin.y + graph_size.y, -0.01),
            color));

        idx = (idx + 1) % N;
    }

    return itpc;
}

default_binary_color_map :: (val: float) -> Vector3 {
    if val > 0.5 return .{0.2, 0.8, 0.2};
    return .{0.8, 0.2, 0.2};
}

#import "tbx/networked_interpolator";

render_npsq_monitor_graphs :: (
    renderer: *Absolute_Position_Color_Renderer,
    npsq: *Networked_Periodic_Signal_Quantizer($T, $MONITOR),
    origin_x: float = -0.95,
    origin_y: float = -0.95,
    graph_width: float = 0.4,
    graph_height: float = 0.1,
    gap: float = 0.02
) {
    #if !MONITOR {
        return;
    } else {
        push_allocator(temp);

        y := origin_y;

        {
            ref_lines: [2] float;
            ref_lines[0] = cast(float) npsq.target_num_states;
            ref_lines[1] = cast(float) npsq.max_num_states;

            ref_slice: [] float;
            ref_slice.data = ref_lines.data;
            ref_slice.count = 2;

            graph := create_time_series_graph(
                *npsq.buffer_occupancy_history,
                .{origin_x, y},
                .{graph_width, graph_height},
                min_val = 0.0,
                max_val = cast(float) npsq.max_num_states + 1.0,
                color = .{0.3, 0.6, 0.9},
                reference_lines = ref_slice
            );
            immediate_render(renderer, graph);
            y += graph_height + gap;
        }

        {
            graph := create_colored_timeline_strip(
                *npsq.mode_history,
                .{origin_x, y},
                .{graph_width, graph_height}
            );
            immediate_render(renderer, graph);
            y += graph_height + gap;
        }

        {
            graph := create_colored_timeline_strip(
                *npsq.emit_result_history,
                .{origin_x, y},
                .{graph_width, graph_height}
            );
            immediate_render(renderer, graph);
            y += graph_height + gap;
        }

        {
            graph := create_time_series_graph(
                *npsq.removal_count_history,
                .{origin_x, y},
                .{graph_width, graph_height},
                min_val = 0.0,
                max_val = cast(float) npsq.max_num_states,
                color = .{0.9, 0.6, 0.2}
            );
            immediate_render(renderer, graph);
        }
    }
}







/*

The way you use this "engine" can be as modular as you want. If you want to do pretty much everything yourself then you can just grab Looping_Program so that you have a loop which
runs at a controlled rate. That can look something like this: 

On the other hand, a good reason to use this engine is that it allows you to start rendering objects immediately. If you're new to jai, then this is like getting the key to the castle.
And so you can start focusing on making a game or something immediately, which is great overtime you'll explore the rooms of the castle and understand its layout. 
Eventually you'll want to to do something that doesn't exist in the castle, and then you can start moving away from it. Either way here is the highest level of support we currently give:

#import "Basic"; // for print
#import "Math";  // for make translation matrix

#import "tbx/engine";   
#import "tbx/opengl";   // for buffer object
#import "tbx/geometry"; // for cube

main :: () {
	// This is here because on Windows, segfaults and stuff are silent.
	// If the program ends without printing this message, then something bad happened.
	defer print ("Program ended gracefully, if you stop seeing this then something bad happend.\n");

    wp3 : Windowed_Program_3D;
    wp3.vsync = false;
    wp3.movement_mode = .GOD;
    wp3.window_name = "my_program";
    init(*wp3);

    box_renderable := array_add(*wp3.renderables);

    assign_geometry(box_renderable, create_itpc_with_color_variation(create_box(), .{0.5, 0.5, 0.5}, 0.4));

    buffer_object(*wp3.camera_per_object_transform_color_renderer, box_renderable);

    start_time := current_time_monotonic();

    while !wp3.end_program {
        mark_frame_start(*wp3);
        
        per_frame_update(*wp3);

        set_local_to_world_matrix(*wp3.camera_per_object_transform_color_renderer, box_renderable.*, make_transform_matrix4(.{1, 1, 1}, .{0, 1, 0}, elapsed_seconds(start_time) * TAU * 0.25));

        render_scene(*wp3);

        sleep_to_maintain_max_fps(*wp3);
        mark_frame_end(*wp3);
    }
}

elapsed_seconds :: (start_time: Apollo_Time) -> float {
    now := current_time_monotonic();
    return cast(float) to_float64_seconds(now - start_time);
}

make_rotation_matrix4 :: (axis: Vector3, angle: float) -> Matrix4 {
    q: Quaternion;
    set_from_axis_and_angle(*q, axis, angle);
    return rotation_matrix(Matrix4, q);
}

make_transform_matrix4 :: (translation: Vector3, rotation_axis: Vector3, rotation_angle: float) -> Matrix4 {
    return make_translation_matrix4(translation) * make_rotation_matrix4(rotation_axis, rotation_angle);
}

In this system you can just create new geometry and modify the transform of objects. Very minimal but at least you don't have to write 500 lines of boilerplate to make it happen.

*/
