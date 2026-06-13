#scope_file
Window_Creation :: #import "Window_Creation";
Sound_Player :: #import "Sound_Player";
Input :: #import "Input";
Simp :: #import "Simp";
#scope_export

Engine_Sound_Type :: enum u8 {
    // ordering matches that in the ui sound types
    BUTTON_CLICK;
    BUTTON_HOVER;
    SLIDER_CHANGE;
}

Build_Type :: enum {
    DEVELOPMENT;
    DISTRIBUTION;
}

Windowed_Program :: struct {
    using # as lp : Looping_Program;

    build_type :: Build_Type.DEVELOPMENT;
    // build_type :: Build_Type.DISTRIBUTION;

    window : Window_Creation.Window_Type;
    saved_window_info : Window_Creation.Saved_Window_Info;

    // this is included because it's almost always useful to render things with this
    absolute_position_color_alpha_renderer : Absolute_Position_Color_Alpha_Renderer;
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

init :: (using wp: *Windowed_Program) {
    init(*lp);
    init_assets_for_build_type(wp);

    window = Window_Creation.create_window(window_width, window_height, window_name);
    Simp.set_render_target(window);

    init(*absolute_position_color_alpha_renderer);

    // initialize custom UI system
    #import "stb_image";
    stbi_set_flip_vertically_on_load(1);
    ui_font = msdf_font_load("data/fonts/pt_serif/atlas.json", "data/fonts/pt_serif/atlas.png");
    stbi_set_flip_vertically_on_load(0);
    init(*ui_msdf_renderer);
    init(*ui_rect_renderer);
    ui_init(*ui_context, *ui_font, *ui_msdf_renderer, *ui_rect_renderer);
    ui_initialized = true;

    set_vsync(vsync);

    if !Sound_Player.sound_player_init(.{}) {
        print("Failed to initialize sound player!\n");
    }

    configuration.config_path = "data/cfg.ini";
    init(*configuration);
}

deinit :: (using wp: *Windowed_Program) {

    Sound_Player.sound_player_shutdown();

    for * entry, key : sound_catalog {
        if entry.name.count > 0  free(entry.name.data);
        if entry.buffer.count > 0  free(entry.buffer.data);
    }
    deinit(*sound_catalog);

    deinit(*configuration);

    if ui_initialized {
        ui_destroy(*ui_context);
        deinit(*ui_font);
    }

    deinit_assets();
}

init_assets_for_build_type :: (using wp: *Windowed_Program) {
    if assets_initialized return;

    DATA_DIRECTORY :: "data";
    DATA_PACKAGE   :: "data.package";

    #if build_type == .DEVELOPMENT {
        init_from_loose_files(DATA_DIRECTORY);
    } else #if build_type == .DISTRIBUTION {
        package_loaded := init_from_package(DATA_PACKAGE);
        assert(package_loaded, "Distribution build could not load data.package.");
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
    set_active_program(absolute_position_color_alpha_renderer);
    set_aspect_ratio_uniform(*absolute_position_color_alpha_renderer, get_window_dimensions_vector(wp));
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

            #if OS == .WINDOWS {
                ChangeDisplaySettingsW(null, 0);
                ShowWindow(window, SW_MINIMIZE);
            }
        }
    }

    if !old_focus && window_has_focus {
        if fullscreen {
            set_fullscreen(wp, true);
        }
    }

    for Input.get_window_resizes() {
        // this resizes the viewport and does other stuff, I'm keeping this because 
        // im not sure about the other stuff and if I need to keep doing it
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

    Sound_Player.update(delta_time);
}

// begin the UI frame, call this after per_frame_update, before any ui_ widget calls
ui_begin :: (using wp: *Windowed_Program) {
    mx, my, mouse_ok := Window_Creation.get_mouse_pointer_position(window, false);
    mouse_x := cast(float32) mx;
    mouse_y := cast(float32) my;

    w := cast(float32) window_width;
    h := cast(float32) window_height;

    ui_begin_frame(mouse_x, mouse_y, ui_mouse_left_down, ui_mouse_right_down, ui_scroll_y, w, h, cast(float64) delta_time);
}

// end the UI frame, call this after all widget calls, before swap_buffers
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

keep_mouse_in_center_of_screen :: (using wp: *Windowed_Program) {
    x, y, w, h := Window_Creation.get_dimensions(window, right_handed_mouse_position);
    #if OS == .WINDOWS {
        set_mouse_pointer_position (w / 2, h / 2);
    } else #if OS == .LINUX {
        X11 :: #import "X11";
        X11.XWarpPointer(X11.x_global_display, X11.None, window, 0, 0, 0, 0, w / 2, h / 2);
        X11.XFlush(X11.x_global_display);
    }
}

show_cursor :: (using wp: *Windowed_Program) {
    if !cursor_visible {
        cursor_visible = true;
        #if OS == .WINDOWS {
            win32 :: #import "Windows";
            win32.ShowCursor(1);
        } else #if OS == .LINUX {
            X11 :: #import "X11";
            X11.XUngrabPointer(X11.x_global_display, X11.CurrentTime);
            X11.XUndefineCursor(X11.x_global_display, window);
            X11.XFlush(X11.x_global_display);
        }
    }
}

hide_cursor :: (using wp: *Windowed_Program) {
    if cursor_visible {
        cursor_visible = false;
        #if OS == .WINDOWS {
            win32 :: #import "Windows";
            win32.ShowCursor(0);
        } else #if OS == .LINUX {
            X11 :: #import "X11";
            X11.XDefineCursor(X11.x_global_display, window, X11.x_global_invisible_cursor);
            X11.XGrabPointer(
                X11.x_global_display,
                window,
                X11.True,
                X11.ButtonPressMask | X11.ButtonReleaseMask | X11.PointerMotionMask,
                X11.GrabModeAsync,
                X11.GrabModeAsync,
                window,
                X11.x_global_invisible_cursor,
                X11.CurrentTime
            );
            X11.XFlush(X11.x_global_display);
        }
    }
}

// graph rendering

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
    immediate_render(*wp.absolute_position_color_alpha_renderer, graph_renderable);
}



render_section_bar_graph :: (using wp: *Windowed_Program) {
    push_allocator(temp);

    should_print := key_just_pressed(xx #char "P");

    bar_renderable := create_section_bar_graph(
        *section_timer,
        graph_origin = .{0.95 , -0.95 + 0.2 + 0.02},
        graph_size = .{0.4, 0.15},
        min_ms = performance_graph.bar_graph_min_ms,
        max_ms = performance_graph.bar_graph_max_ms,
        target_ms = min_frame_time * 1000,
        print_legend = should_print
    );
    immediate_render(*wp.absolute_position_color_alpha_renderer, bar_renderable);
}


// drains UI audio events and plays sounds from the sound catalog. expects the catalog to have entries keyed by Engine_Sound_Type, though we can change this later
// rename to drain ui audio events
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

    // flush newly started streams to the mixer immediately, the main Sound_Player.update
    // already ran earlier this frame, so without this, sounds started during UI drain
    // would sit unprocessed until next frame and may be dropped.
    Sound_Player.update(0);
}
