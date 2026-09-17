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


Windowed_Program :: struct {
    using # as lp : Looping_Program;


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

    crosshair_settings: Crosshair_Settings;
    crosshair_custom: Crosshair_Custom_State;
    crosshair_preview: Crosshair_Preview_State;

    // custom UI system replaces GetRect
    ui_context: UI_Context;
    ui_font: MSDF_Font;
    ui_renderer: OpenGL_UI_Renderer;
    ui_initialized := false;

    sound_catalog : Table(u8, Sound_Player.Sound_Data);

    // Applications that need to drive audio themselves can disable the
    // background mixer before initialization.
    sound_mixer_updates_on_background_thread := true;

    // mouse/keyboard state gathered per frame for the UI
    ui_mouse_left_down:  bool;
    ui_mouse_right_down: bool;
    ui_scroll_y:         float32;
    ui_ctrl_held:        bool;
    ui_shift_held:       bool;
    ui_alt_held:         bool;
    ui_shift_chord_down: bool;
    ui_shift_chord_clean: bool;
}

init :: (using wp: *Windowed_Program) {
    init(*lp);
    init_assets_for_build_type(wp);

    window = Window_Creation.create_window(window_width, window_height, window_name);
    Simp.set_render_target(window);

    init(*absolute_position_color_alpha_renderer);

    // The widget/layout core produces draw data. This program selects the
    // OpenGL renderer backend to consume it.
    ui_font = load_msdf_font_metrics("data/fonts/pt_serif/atlas.json");
    if !init(*ui_renderer, *ui_font, "data/fonts/pt_serif/atlas.png") return;
    ui_init(*ui_context, *ui_font);
    attach_opengl_render_target_backend_to_ui_context(*ui_renderer);
    ui_initialized = true;

    set_vsync(vsync);

    sound_config: Sound_Player.Sound_Player_Config;
    sound_config.update_from_a_thread = sound_mixer_updates_on_background_thread;
    #if OS == .LINUX {
        // The engine supplies a synchronized Linux mixer thread below.
        sound_config.update_from_a_thread = false;
    }
    sound_config.seconds_to_fill_ahead = 0.10;
    sound_player_initialized := Sound_Player.sound_player_init(sound_config);
    if !sound_player_initialized {
        print("Failed to initialize sound player!\n");
    }
    #if OS == .LINUX {
        if sound_player_initialized && sound_mixer_updates_on_background_thread {
            if !start_linux_sound_mixer() {
                print("Failed to initialize synchronized Linux sound mixer!\n");
                sound_mixer_updates_on_background_thread = false;
            }
        }
    }

    configuration.config_path = "data/cfg.ini";
    init(*configuration);
    crosshair_custom.path = crosshair_path_next_to_config(configuration.config_path);
}

deinit :: (using wp: *Windowed_Program) {

    #if OS == .LINUX stop_linux_sound_mixer();
    Sound_Player.sound_player_shutdown();

    for * entry, key : sound_catalog {
        if entry.name.count > 0  free(entry.name.data);
        if entry.buffer.count > 0  free(entry.buffer.data);
    }
    deinit(*sound_catalog);

    deinit(*configuration);
    deinit(*crosshair_custom.geometry);

    if ui_initialized {
        ui_destroy(*ui_context);
        deinit(*ui_renderer);
        deinit(*ui_font);
    }

    deinit_assets();
}

init_assets_for_build_type :: (using wp: *Windowed_Program) {
    if assets_initialized return;

    DATA_DIRECTORY :: "data";
    DATA_PACKAGE   :: "data.package";

    #if BUILD_TYPE == .DEVELOPMENT {
        init_from_loose_files(DATA_DIRECTORY);
    } else #if BUILD_TYPE == .DISTRIBUTION {
        package_loaded := init_from_package(DATA_PACKAGE);
        assert(package_loaded, "Distribution build could not load data.package.");
    }
}


sleep_to_maintain_max_fps :: (using wp: *Windowed_Program) {
    if vsync return;
    sleep_to_maintain_max_fps(*lp);
}

update_centered_mouse_delta :: (using wp: *Windowed_Program) {
    #if OS == .LINUX {
        x, y, success := Window_Creation.get_mouse_pointer_position(window, false);
        _, _, w, h := Window_Creation.get_dimensions(window, false);
        if success {
            Input.mouse_delta_x = x - w / 2;
            Input.mouse_delta_y = y - h / 2;
        }

        keep_mouse_in_center_of_screen(wp);
    }
}

poll_pointer_modifiers :: (using wp: *Windowed_Program) -> (ctrl: bool, shift: bool, alt: bool, ok: bool) {
    #if OS == .LINUX {
        X11 :: #import "X11";
        root, child: X11.Window;
        root_x, root_y, window_x, window_y: s32;
        modifier_mask: u32;
        query_ok := X11.XQueryPointer(X11.x_global_display, window, *root, *child, *root_x, *root_y, *window_x, *window_y, *modifier_mask);
        if query_ok == X11.True {
            return (modifier_mask & X11.ControlMask) != 0,
                   (modifier_mask & X11.ShiftMask) != 0,
                   (modifier_mask & X11.Mod1Mask) != 0,
                   true;
        }
    }

    return false, false, false, false;
}

ui_shift_chord_handle_key_event :: (down: *bool, clean: *bool, key_code: Input.Key_Code, key_pressed: bool, shift_pressed: bool) -> bool {
    clean_shift_space := key_pressed &&
                         key_code == xx #char " " &&
                         shift_pressed &&
                         down.* &&
                         clean.*;

    if key_code == .SHIFT {
        if key_pressed {
            if !down.* clean.* = true;
            down.* = true;
        } else {
            down.* = false;
            clean.* = false;
        }
    } else if key_pressed && down.* {
        // Shift+Space is deliberate only when Space is the first key pressed
        // after Shift. Typing ':' consumes the chord before a following Space.
        clean.* = false;
    }

    return clean_shift_space;
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
    ui_alt_held = false;

    Input.update_window_events();
    for Input.events_this_frame {
        if it.type == .QUIT then end_program = true;

        // feed keyboard events to custom UI
        if it.type == .KEYBOARD {
            clean_shift_chord := ui_shift_chord_handle_key_event(
                *ui_shift_chord_down,
                *ui_shift_chord_clean,
                it.key_code,
                it.key_pressed != 0,
                it.shift_pressed);

            if it.key_pressed {
                if it.key_code == {
                    case .BACKSPACE;    ui_push_key(.BACKSPACE, it.ctrl_pressed, it.shift_pressed);
                    case .DELETE;       ui_push_key(.DELETE, it.ctrl_pressed, it.shift_pressed);
                    case .ARROW_LEFT;   ui_push_key(.LEFT, it.ctrl_pressed, it.shift_pressed);
                    case .ARROW_RIGHT;  ui_push_key(.RIGHT, it.ctrl_pressed, it.shift_pressed);
                    case .ARROW_UP;     ui_push_key(.UP, it.ctrl_pressed, it.shift_pressed);
                    case .ARROW_DOWN;   ui_push_key(.DOWN, it.ctrl_pressed, it.shift_pressed);
                    case .HOME;         ui_push_key(.HOME, it.ctrl_pressed, it.shift_pressed);
                    case .END;          ui_push_key(.END, it.ctrl_pressed, it.shift_pressed);
                    case .ENTER;        ui_push_key(.ENTER, it.ctrl_pressed, it.shift_pressed);
                    case .ESCAPE;       ui_push_key(.ESCAPE, it.ctrl_pressed, it.shift_pressed);
                    case .TAB;          ui_push_key(.TAB, it.ctrl_pressed, it.shift_pressed);
                    case xx #char " ";  ui_push_key(.SPACE, it.ctrl_pressed, it.shift_pressed, clean_shift_chord);
                    case xx #char "A";  ui_push_key(.A, it.ctrl_pressed, it.shift_pressed);
                    case xx #char "C";  ui_push_key(.C, it.ctrl_pressed, it.shift_pressed);
                    case xx #char "F";  ui_push_key(.F, it.ctrl_pressed, it.shift_pressed);
                    case xx #char "V";  ui_push_key(.V, it.ctrl_pressed, it.shift_pressed);
                    case xx #char "X";  ui_push_key(.X, it.ctrl_pressed, it.shift_pressed);
                    case xx #char "Y";  ui_push_key(.Y, it.ctrl_pressed, it.shift_pressed);
                    case xx #char "Z";  ui_push_key(.Z, it.ctrl_pressed, it.shift_pressed);
                }
            }

            ui_ctrl_held  = it.ctrl_pressed;
            ui_shift_held = it.shift_pressed;
            ui_alt_held   = it.alt_pressed;
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

    // Poll held modifiers too; mouse-only frames will not carry keyboard events.
    ui_ctrl_held  = (Input.input_button_states[Input.Key_Code.CTRL]  & .DOWN) != 0;
    ui_shift_held = (Input.input_button_states[Input.Key_Code.SHIFT] & .DOWN) != 0;
    ui_alt_held   = (Input.input_button_states[Input.Key_Code.ALT]   & .DOWN) != 0;

    // X11 can lose a modifier release when the window manager grabs an
    // Alt/Shift gesture. For wheel input, query the pointer's live modifier
    // mask so a stale cached key cannot lock scrolling to the wrong axis.
    if ui_scroll_y != 0 {
        live_ctrl, live_shift, live_alt, modifiers_ok := poll_pointer_modifiers(wp);
        if modifiers_ok {
            ui_ctrl_held = live_ctrl;
            ui_shift_held = live_shift;
            ui_alt_held = live_alt;

            if live_ctrl  Input.input_button_states[Input.Key_Code.CTRL]  |= .DOWN;
            else          Input.input_button_states[Input.Key_Code.CTRL]  &= ~Input.Key_Current_State.DOWN;
            if live_shift Input.input_button_states[Input.Key_Code.SHIFT] |= .DOWN;
            else          Input.input_button_states[Input.Key_Code.SHIFT] &= ~Input.Key_Current_State.DOWN;
            if live_alt   Input.input_button_states[Input.Key_Code.ALT]   |= .DOWN;
            else          Input.input_button_states[Input.Key_Code.ALT]   &= ~Input.Key_Current_State.DOWN;
        }
    }

    // gather mouse button state
    ui_mouse_left_down  = (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_LEFT]  & .DOWN) != 0;
    ui_mouse_right_down = (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT] & .DOWN) != 0;

    ui_set_modifiers(ui_ctrl_held, ui_shift_held, ui_alt_held);

    // detect focus transitions
    old_focus := window_has_focus;
    window_has_focus = Input.input_application_has_focus;

    if old_focus && !window_has_focus {
        Input.input_button_states[Input.Key_Code.CTRL] = .NONE;
        Input.input_button_states[Input.Key_Code.SHIFT] = .NONE;
        Input.input_button_states[Input.Key_Code.ALT] = .NONE;
        ui_ctrl_held = false;
        ui_shift_held = false;
        ui_alt_held = false;
        ui_shift_chord_down = false;
        ui_shift_chord_clean = false;
        ui_set_modifiers(false, false, false);
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
    render_ui_draw_data_with_opengl(*ui_renderer, *ui_context);
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
    } else #if OS == .LINUX {
        success, new_width, new_height := Window_Creation.toggle_fullscreen(window, enabled, *saved_window_info);
        if success {
            fullscreen = enabled;
            window_width = new_width;
            window_height = new_height;
            set_vsync(vsync);
        }
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

with_alpha :: (source: Indexed_Triangle_Positions_Colors, alpha: float = 1.0) -> Indexed_Triangle_Positions_Color_Alphas {
    result: Indexed_Triangle_Positions_Color_Alphas;
    result.indices = source.indices;
    result.positions = source.positions;
    array_reserve(*result.rgba_colors, source.rgb_colors.count);
    for color: source.rgb_colors {
        array_add(*result.rgba_colors, .{color.x, color.y, color.z, alpha});
    }
    return result;
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
