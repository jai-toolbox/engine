#scope_file
Window_Creation :: #import "Window_Creation";
Sound_Player :: #import "Sound_Player";
Input :: #import "Input";
Simp :: #import "Simp";
#scope_export

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

Orientation :: struct {
    forward: Vector3;
    right: Vector3;
    up: Vector3;
}

STANDARD_ORIENTATION :: #run Orientation.{X3, -Y3, Z3};
GL_ORIENTATION :: Orientation.{Z3, X3, Y3};
NEGATIVE_Z_GL_ORIENTATION :: #run Orientation.{-Z3, X3, Y3};

// it might be nice to make a dedicated 2d program.

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

init :: (using wp3 : *Windowed_Program_3D) {
    init(*wp);
    init(*camera_per_object_transform_color_renderer);
    init(*section_timer);

    performance_graph.graph_min_ms = min_frame_time * 1000 - 1;
    performance_graph.graph_max_ms = min_frame_time * 1000 + 5;

    // enumerate available resolutions before loading settings
    enumerate_resolutions(*wp3.wp);

    // menu_fullscreen_checkbox = fullscreen;
    // menu_vsync_checkbox = vsync;

    conf_sens, ok_s := get_float(*configuration, "input", "sensitivity");
    if ok_s camera.sensitivity = conf_sens;

    load_menu_settings(*wp3.wp);
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

per_frame_update :: (using wp3 : *Windowed_Program_3D) {
    per_frame_update(*wp3.wp);

    // sync sensitivity from menu to camera
    // camera.sensitivity = menu_sensitivity;

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

    if camera_mode != .TWO_DIMENSIONS && want_cursor_captured {
        if movement_mode == {
            case .GOD;
                gmi := God_Mode_Input.{
                    key_pressed(xx #char "E"),
                    key_pressed(xx #char "Q"),
                    key_pressed(xx #char "W"),
                    key_pressed(xx #char "S"),
                    key_pressed(xx #char "D"),
                    key_pressed(xx #char "A"),
                    key_pressed(xx #char " "),
                    key_pressed(Input.Key_Code.SHIFT),
                };
                camera_velocity = get_new_god_mode_velocity(camera_velocity, get_forward(*camera), gmi, delta_time);
        }
    }

    if movement_mode != .MANUAL camera.position += camera_velocity * delta_time;

    update_listener_orientation(camera.position, camera.yaw);
    // Sound_Player.update(delta_time);

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

        mouse_left_down := key_pressed(xx Input.Key_Code.MOUSE_BUTTON_LEFT);
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

    glUseProgram(absolute_position_color_alpha_renderer.shader_program_gl_handle);

    glUseProgram(camera_per_object_transform_color_renderer.shader_program_gl_handle);

    if camera_mode != .TWO_DIMENSIONS {
        set_world_to_camera_uniform(*camera_per_object_transform_color_renderer, get_world_to_camera_matrix(*camera));
        set_camera_to_clip_uniform(*camera_per_object_transform_color_renderer, get_projection_matrix(*camera, window_width, window_height));
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

        update_graph_visual(*wp3.performance_graph);
        render_performance_graph(wp3);
        render_section_bar_graph(wp3);
    } else if wp3.current_menu == .MAIN {
        // initial menu, no 3D scene visible (or you could show it, up to you)
        render_menus(*wp3.wp);
    } else {
        // in-game menu or settings, render over the 3D scene
        render_menus(*wp3.wp);
    }

    // end the UI frame, flushes all draw commands
    ui_end(*wp3.wp);

    // play UI sounds from audio events emitted during the frame
    drain_ui_audio_events(*wp3.wp);

    Simp.swap_buffers(wp3.window, false);
}


sample_first_person_movement_input :: (forward := #char "W", backward := #char "S", right := #char "D", left := #char "A", jump := #char " ") -> First_Person_Movement_Input {
    return .{
        key_pressed(xx forward),
        key_pressed(xx backward),
        key_pressed(xx right),
        key_pressed(xx left),
        key_pressed(xx jump),
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
