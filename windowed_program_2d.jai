/*

usage:

#import "Basic"()(MEMORY_DEBUGGER = true);

#import "tbx/geometry";
#import "tbx/engine";
#import "tbx/opengl";
#import "tbx/math";

main :: () {
    wp2 : Windowed_Program_2D;
    init(*wp2, "tbx_graph_2d");

    renderable := array_add(*wp2.renderables);
    assign_geometry(renderable, create_itpc_with_color_variation(create_torus(ZERO3, Z3, 2, 1, 8, 8)));
    buffer_object(*wp2.camera_per_object_transform_color_renderer, renderable);

    while !wp2.end_program {
        mark_frame_start(*wp2);

        per_frame_update(*wp2);
    
        render_scene(*wp2);

        sleep_to_maintain_max_fps(*wp2);
        mark_frame_end(*wp2);
    }

    deinit(*wp2);
    report_memory_leaks(.{});
}


*/

#scope_file
Window_Creation :: #import "Window_Creation";
Input          :: #import "Input";
Simp           :: #import "Simp";
#scope_export

Windowed_Program_2D :: struct {
    using #as wmp : Windowed_Menu_Program;

    camera_per_object_transform_color_renderer : Camera_Per_Object_Transform_Color_Renderer;
    renderables : [..] Camera_Per_Object_Transform_Color_Renderable;

    // orthographic camera state
    ortho_center  : Vector2;
    ortho_height  := 10.0;

    // left-mouse pan drag state
    is_dragging       := false;
    drag_start_mouse  : Vector2;
    drag_start_center : Vector2;
}

init :: (using,except(window_name) wp2 : *Windowed_Program_2D, window_name : string) {
    wp2.window_name = window_name;
    init(*wmp);
    init(*camera_per_object_transform_color_renderer);
    init(*section_timer);

    performance_graph.graph_min_ms = min_frame_time * 1000 - 1;
    performance_graph.graph_max_ms = min_frame_time * 1000 + 5;

    enumerate_resolutions(*wp2.wmp);
    load_menu_settings(*wp2.wmp);
}

deinit :: (wp2 : *Windowed_Program_2D) {
    log("windowed program 2d deinit called");
    deinit(*wp2.wmp);
    deinit(*wp2.camera_per_object_transform_color_renderer);

    for * wp2.renderables deinit(it); 
    array_free(wp2.renderables);
}

// must be called per frame.
per_frame_update :: (using wp2 : *Windowed_Program_2D) {
    per_frame_update(*wp2.wmp);

    // ESC toggles the in-game menu
    for Input.events_this_frame {
        if it.type == .KEYBOARD && it.key_pressed {
            if it.key_code == .ESCAPE {
                toggle_menu(wp2);
            }
        }
    }

    // cursor is always visible in 2D (no look-capture)
    show_cursor(*wmp);

    vx, vy, vw, vh := Window_Creation.get_dimensions(window, right_handed_mouse_position);

    // pan and zoom (only when no menu is open)
    if current_menu == .NONE {
        update_2d_camera(wp2, vw, vh);
    }

    // set orthographic projection uniforms on the renderer
    glUseProgram(camera_per_object_transform_color_renderer.shader_program_gl_handle);

    world_to_camera := Matrix4_Identity;
    set_world_to_camera_uniform(*camera_per_object_transform_color_renderer, world_to_camera);
    set_camera_to_clip_uniform(*camera_per_object_transform_color_renderer, get_ortho_matrix(wp2, vw, vh));
}

// Computes and returns the orthographic projection matrix for the current
// ortho_center / ortho_height / window dimensions.
get_ortho_matrix :: (using wp2 : *Windowed_Program_2D, vw: s32, vh: s32) -> Matrix4 {
    aspect      := cast(float) vw / cast(float) vh;
    ortho_width := ortho_height * aspect;
    half_w      := ortho_width  * 0.5;
    half_h      := ortho_height * 0.5;

    return orthographic_projection_matrix(
        left   = ortho_center.x - half_w,
        right  = ortho_center.x + half_w,
        bottom = ortho_center.y - half_h,
        top    = ortho_center.y + half_h,
        near   = -100.0,
        far    =  100.0,
        depth_range_01 = false
    );
}

// Handles scroll-to-zoom and left-mouse-button pan drag.
// Called once per frame when no menu is open.
update_2d_camera :: (using wp2 : *Windowed_Program_2D, vw: s32, vh: s32) {
    aspect      := cast(float) vw / cast(float) vh;
    ortho_width := ortho_height * aspect;

    // query mouse position once, used by both zoom and pan
    mx, my, mouse_success := Window_Creation.get_mouse_pointer_position(window, true);

    // scroll to zoom toward cursor
    for Input.events_this_frame {
        if it.type == .MOUSE_WHEEL && mouse_success {
            // normalized offset of cursor from center (-0.5 .. 0.5)
            nrm_x := cast(float) mx / cast(float) vw - 0.5;
            nrm_y := cast(float) my / cast(float) vh - 0.5;

            // world position under cursor before zoom
            world_x := ortho_center.x + nrm_x * ortho_width;
            world_y := ortho_center.y + nrm_y * ortho_height;

            if it.wheel_delta > 0 {
                ortho_height *= 0.9;
                if ortho_height < 0.1  ortho_height = 0.1;
            } else if it.wheel_delta < 0 {
                ortho_height *= 1.1;
            }

            // recompute width after zoom
            ortho_width = ortho_height * aspect;

            // shift center so the world point stays under the cursor
            ortho_center.x = world_x - nrm_x * ortho_width;
            ortho_center.y = world_y - nrm_y * ortho_height;
        }
    }

    // middle-mouse pan drag
    mouse_middle_down := key_pressed(xx Input.Key_Code.MOUSE_BUTTON_MIDDLE);

    if mouse_success {
        mouse_world_x := (cast(float) mx / cast(float) vw - 0.5) * ortho_width  + ortho_center.x;
        mouse_world_y := (cast(float) my / cast(float) vh - 0.5) * ortho_height + ortho_center.y;

        if mouse_middle_down {
            if !is_dragging {
                is_dragging       = true;
                drag_start_mouse  = .{mouse_world_x, mouse_world_y};
                drag_start_center = ortho_center;
            } else {
                current_mouse_world_x := (cast(float) mx / cast(float) vw - 0.5) * ortho_width  + drag_start_center.x;
                current_mouse_world_y := (cast(float) my / cast(float) vh - 0.5) * ortho_height + drag_start_center.y;

                ortho_center.x = drag_start_center.x - (current_mouse_world_x - drag_start_mouse.x);
                ortho_center.y = drag_start_center.y - (current_mouse_world_y - drag_start_mouse.y);
            }
        } else {
            is_dragging = false;
        }
    }
}

render_scene :: (using wp2 : *Windowed_Program_2D) {
    for renderables queue_render(*wp2.camera_per_object_transform_color_renderer, it.object_index);

    Simp.update_window(wp2.window);
    Simp.clear_render_target(.15, .08, .08, 1);

    ui_begin(*wp2.wmp);

    glDepthMask(GL_TRUE);
    glEnable(GL_DEPTH_TEST);
    glClear(GL_DEPTH_BUFFER_BIT);
    render(*wp2.camera_per_object_transform_color_renderer);

    if wp2.current_menu == .NONE {
        // update_graph_visual(*wp2.performance_graph);
        // render_performance_graph(wp2);
        // render_section_bar_graph(wp2);
    } else {
        render_menus(*wp2.wmp);
    }

    ui_end(*wp2.wmp);
    drain_ui_audio_events(*wp2.wmp);

    Simp.swap_buffers(wp2.window, false);
}
