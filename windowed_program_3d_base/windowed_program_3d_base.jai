#scope_file
Window_Creation :: #import "Window_Creation";
Input :: #import "Input";
#if OS == .LINUX {
    X11 :: #import "X11";
}
#scope_export

#if OS == .LINUX {
    libXi :: #library,system "libXi";

    XIAllDevices : s32 : 0;
    XI_RawMotion : s32 : 17;
    XI_LASTEVENT : s32 : 32;

    XIEventMask :: struct {
        deviceid: s32;
        mask_len: s32;
        mask: *u8;
    }

    XIValuatorState :: struct {
        mask_len: s32;
        mask: *u8;
        values: *float64;
    }

    XIRawEvent :: struct {
        type: s32;
        serial: u64;
        send_event: X11.Bool;
        display: *X11.Display;
        extension: s32;
        evtype: s32;
        time: X11.Time;
        deviceid: s32;
        sourceid: s32;
        detail: s32;
        flags: s32;
        valuators: XIValuatorState;
        raw_values: *float64;
    }

    XIQueryVersion :: (display: *X11.Display, major_version_inout: *s32, minor_version_inout: *s32) -> X11.Status #foreign libXi;
    XISelectEvents :: (dpy: *X11.Display, win: X11.Window, masks: *XIEventMask, num_masks: s32) -> s32 #foreign libXi;

    xi_set_mask :: (mask: *u8, event_type: s32) {
        mask[event_type >> 3] |= cast(u8)(1 << (event_type & 7));
    }

    xi_mask_is_set :: (mask: *u8, index: s32) -> bool {
        return (mask[index >> 3] & cast(u8)(1 << (index & 7))) != 0;
    }

    xi_count_valuator_values :: (using state: XIValuatorState) -> int {
        count := 0;
        for i: 0..mask_len * 8 - 1 {
            if xi_mask_is_set(mask, i) count += 1;
        }
        return count;
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

Windowed_Program_3D_View_Preset :: enum {
    PERSPECTIVE;
    TOP;
    SIDE;
    FRONT;
}

Orientation :: struct {
    forward: Vector3;
    right: Vector3;
    up: Vector3;
}

STANDARD_ORIENTATION :: #run Orientation.{X3, -Y3, Z3};
GL_ORIENTATION :: Orientation.{Z3, X3, Y3};
NEGATIVE_Z_GL_ORIENTATION :: #run Orientation.{-Z3, X3, Y3};

Windowed_Program_3D_Base :: struct {
    using #as wp: Windowed_Menu_Program;

    orientation := STANDARD_ORIENTATION;

    camera: Camera;
    camera_mode := Camera_Mode.FIRST_PERSON;
    camera_look_active := true;
    camera_velocity: Vector3;
    movement_mode: Movement_Mode;

    picker: Windowed_Program_3D_Picker;
    selected_object_id: u32;
    selection_changed: bool;
    selection_outline_color: Vector4 = .{1.0, 0.7, 0.0, 1.0};
    selection_outline_thickness_px: u32 = 3;
    grid: Camera_Infinite_Grid;
    axis_alignment_threshold: float32 = 0.999;
    orthographic_view_height: float32 = 10.0;
    orthographic_projection_active: bool;
    show_view_axis_gizmo := true;
    view_preset_shortcuts_enabled := true;
    view_preset_focus: Vector3;
    view_preset_distance: float32 = 8.0;

    axis_view_active: bool;
    saved_perspective_camera_valid: bool;
    saved_perspective_camera_position: Vector3;
    saved_perspective_camera_yaw: float;
    saved_perspective_camera_pitch: float;

    transform_operation: Windowed_Program_3D_Transform_Operation;
    editor_transform_changed: bool;
    editor_transform_object_id: u32;
    editor_transform_matrix: Matrix4 = Matrix4_Identity;

    raw_mouse_supported := false;
    raw_mouse_extension_opcode: s32;
    raw_mouse_dx, raw_mouse_dy: float64;
    raw_mouse_events: int;

    // 2D camera mode supports pan and zoom with the same window/menu shell.
    ortho_center: Vector2;
    ortho_height := 10.0;
    is_dragging := false;
    drag_start_mouse: Vector2;
    drag_start_center: Vector2;

    // Updated by per_frame_update. Applications upload these to their own shaders.
    world_to_camera: Matrix4 = Matrix4_Identity;
    camera_to_clip: Matrix4 = Matrix4_Identity;
}

init :: (using wp3b: *Windowed_Program_3D_Base) {
    init(*wp);
    wp.show_open_model_menu = false;
    wp.show_scene_graphics_settings = false;
    wp.show_3d_graphics_settings = true;
    init(*section_timer);
    init(*grid);
    if !init(*picker, cast(u32) window_width, cast(u32) window_height) {
        log_error("Windowed Program 3D picking is unavailable");
    }

    #if OS == .LINUX {
        init_raw_mouse_input(wp3b);
    }

    performance_graph.graph_min_ms = min_frame_time * 1000 - 1;
    performance_graph.graph_max_ms = min_frame_time * 1000 + 5;

    // Enumerate fullscreen display modes before loading settings. Windowed
    // dimensions continue to follow ordinary user-driven window resizing.
    enumerate_fullscreen_resolutions(*wp);

    // menu_fullscreen_checkbox = fullscreen;
    // menu_vsync_checkbox = vsync;

    conf_sens, ok_s := get_float(*configuration, "input", "sensitivity");
    if ok_s camera.sensitivity = conf_sens;

    load_menu_settings(*wp);
}

deinit :: (using wp3b: *Windowed_Program_3D_Base) {
    deinit(*picker);
    deinit(*grid);
    deinit(*wp);
}

windowed_program_3d_selected_renderable_index :: (using wp3b: *Windowed_Program_3D_Base) -> s64 {
    if selected_object_id == WINDOWED_PROGRAM_3D_NO_OBJECT_ID return -1;
    return cast(s64) selected_object_id - 1;
}

set_windowed_program_3d_editor_permissions :: (
    using wp3b: *Windowed_Program_3D_Base,
    object_id: u32,
    editor_permissions: Windowed_Program_3D_Editor_Permissions,
) -> bool {
    _, found := get_pickable_editor_permissions(*picker, object_id);
    if !found return false;

    selectable := windowed_program_3d_has_editor_permission(editor_permissions, .SELECTABLE);
    transformable := windowed_program_3d_has_editor_permission(editor_permissions, .TRANSFORMABLE);
    loses_active_interaction := !selectable || !transformable;
    if loses_active_interaction && transform_operation.object_id == object_id {
        cancel_windowed_program_3d_transform_operation(wp3b);
    }

    if !set_pickable_editor_permissions(*picker, object_id, editor_permissions) {
        return false;
    }

    if !selectable && selected_object_id == object_id {
        selected_object_id = WINDOWED_PROGRAM_3D_NO_OBJECT_ID;
        selection_changed = true;
    }
    return true;
}

get_windowed_program_3d_editor_permissions :: (
    using wp3b: *Windowed_Program_3D_Base,
    object_id: u32,
) -> (permissions: Windowed_Program_3D_Editor_Permissions, found: bool) {
    permissions, found := get_pickable_editor_permissions(*picker, object_id);
    return permissions, found;
}

windowed_program_3d_dominant_axis :: (
    using wp3b: *Windowed_Program_3D_Base,
) -> (plane: Grid_Plane, alignment: float32) {
    forward := normalize(get_forward(*camera));
    absolute_forward := Vector3.{abs(forward.x), abs(forward.y), abs(forward.z)};

    if absolute_forward.x >= absolute_forward.y && absolute_forward.x >= absolute_forward.z {
        return .YZ, absolute_forward.x;
    }
    if absolute_forward.y >= absolute_forward.z return .XZ, absolute_forward.y;
    return .XY, absolute_forward.z;
}

set_windowed_program_3d_orthographic :: (
    using wp3b: *Windowed_Program_3D_Base,
    enabled: bool,
) {
    orthographic_projection_active = enabled && camera_mode != .TWO_DIMENSIONS;
    if orthographic_projection_active camera_velocity = .{};
    else {
        axis_view_active = false;
        saved_perspective_camera_valid = false;
    }
}

set_windowed_program_3d_view_preset :: (
    using wp3b: *Windowed_Program_3D_Base,
    preset: Windowed_Program_3D_View_Preset,
) {
    if camera_mode == .TWO_DIMENSIONS return;

    if preset == .PERSPECTIVE {
        restore_saved_camera := axis_view_active && saved_perspective_camera_valid;
        restored_position := saved_perspective_camera_position;
        restored_yaw := saved_perspective_camera_yaw;
        restored_pitch := saved_perspective_camera_pitch;

        set_windowed_program_3d_orthographic(wp3b, false);
        if restore_saved_camera {
            camera.position = restored_position;
            camera.yaw = restored_yaw;
            camera.pitch = restored_pitch;
        }
        camera_velocity = .{};
        return;
    }

    if !axis_view_active {
        saved_perspective_camera_valid = true;
        saved_perspective_camera_position = camera.position;
        saved_perspective_camera_yaw = camera.yaw;
        saved_perspective_camera_pitch = camera.pitch;
    }

    axis_view_active = true;
    distance := max(view_preset_distance, 0.001);
    if preset == {
        case .TOP;
            camera.position = view_preset_focus + Vector3.{0, distance, 0};
            camera.yaw = 0;
            camera.pitch = 0.249;
        case .SIDE;
            camera.position = view_preset_focus + Vector3.{distance, 0, 0};
            camera.yaw = -0.25;
            camera.pitch = 0;
        case .FRONT;
            camera.position = view_preset_focus + Vector3.{0, 0, distance};
            camera.yaw = 0;
            camera.pitch = 0;
    }
    camera_velocity = .{};
    set_windowed_program_3d_orthographic(wp3b, true);
}

set_windowed_program_3d_camera_look_active :: (
    using wp3b: *Windowed_Program_3D_Base,
    enabled: bool,
) {
    if camera_look_active == enabled return;

    camera_look_active = enabled;
    camera_velocity = .{};
    if enabled set_windowed_program_3d_view_preset(wp3b, .PERSPECTIVE);
}

windowed_program_3d_grid_plane :: (using wp3b: *Windowed_Program_3D_Base) -> Grid_Plane {
    if !orthographic_projection_active return .XZ;

    plane, alignment := windowed_program_3d_dominant_axis(wp3b);
    if alignment >= axis_alignment_threshold return plane;
    return .XZ;
}

render_windowed_program_3d_editor_overlays :: (using wp3b: *Windowed_Program_3D_Base) {
    if current_menu != .NONE || camera_mode == .TWO_DIMENSIONS return;

    if show_grid {
        glDepthMask(GL_FALSE);
        render(
            *grid,
            camera_to_clip,
            world_to_camera,
            camera.position,
            windowed_program_3d_grid_plane(wp3b),
        );
        glDepthMask(GL_TRUE);
    }

    draw_selection_outline(
        *picker,
        selected_object_id,
        selection_outline_color,
        selection_outline_thickness_px,
    );

    if show_view_axis_gizmo {
        render_windowed_program_3d_view_axis_gizmo(
            world_to_camera,
            orthographic_projection_active,
        );
    }

    render_windowed_program_3d_transform_operation_status(wp3b);
}

begin_windowed_program_3d_geometry_render :: (using wp3b: *Windowed_Program_3D_Base) {
    if wireframe enable_wireframe_mode();
}

end_windowed_program_3d_geometry_render :: (using wp3b: *Windowed_Program_3D_Base) {
    if wireframe disable_wireframe_mode();
}

#if OS == .LINUX {
    init_raw_mouse_input :: (using wp3b: *Windowed_Program_3D_Base) {
        display := X11.x_global_display;
        if !display {
            return;
        }

        opcode, event, error: s32;
        if !X11.XQueryExtension(display, "XInputExtension", *opcode, *event, *error) {
            return;
        }

        major := cast(s32) 2;
        minor := cast(s32) 0;
        if XIQueryVersion(display, *major, *minor) == X11.BadRequest {
            return;
        }

        mask: [(XI_LASTEVENT + 7) / 8] u8;
        xi_set_mask(mask.data, XI_RawMotion);

        event_mask: XIEventMask;
        event_mask.deviceid = XIAllDevices;
        event_mask.mask_len = size_of(type_of(mask));
        event_mask.mask = mask.data;

        root := X11.DefaultRootWindow(display);
        result := XISelectEvents(display, root, *event_mask, 1);
        X11.XFlush(display);

        raw_mouse_supported = result == 0;
        raw_mouse_extension_opcode = opcode;
    }

    read_raw_mouse_events :: (using wp3b: *Windowed_Program_3D_Base) {
        raw_mouse_dx = 0;
        raw_mouse_dy = 0;
        raw_mouse_events = 0;

        if !raw_mouse_supported return;

        display := X11.x_global_display;
        events_to_put_back: [..] X11.XEvent;
        defer array_free(events_to_put_back);

        while X11.XPending(display) {
            event: X11.XEvent;
            X11.XNextEvent(display, *event);

            is_raw_mouse_event := false;
            if event.type == X11.GenericEvent && event.xcookie.extension == raw_mouse_extension_opcode {
                if X11.XGetEventData(display, *event.xcookie) != 0 {
                    if event.xcookie.evtype == XI_RawMotion {
                        raw := cast(*XIRawEvent) event.xcookie.data;
                        value_count := xi_count_valuator_values(raw.valuators);
                        if value_count >= 1 raw_mouse_dx += raw.raw_values[0];
                        if value_count >= 2 raw_mouse_dy += raw.raw_values[1];
                        raw_mouse_events += 1;
                        is_raw_mouse_event = true;
                    }
                    X11.XFreeEventData(display, *event.xcookie);
                }
            }

            if !is_raw_mouse_event {
                array_add(*events_to_put_back, event);
            }
        }

        for i: 0..events_to_put_back.count - 1 {
            index := events_to_put_back.count - 1 - i;
            X11.XPutBackEvent(display, *events_to_put_back[index]);
        }
    }
}

per_frame_update :: (using wp3b: *Windowed_Program_3D_Base) {
    selection_changed = false;
    editor_transform_changed = false;
    linux_motion_dx := 0;
    linux_motion_dy := 0;
    linux_nonzero_motion_events := 0;

    #if OS == .LINUX {
        if camera_look_active && current_menu == .NONE && camera_mode != .TWO_DIMENSIONS && window_has_focus {
            read_raw_mouse_events(wp3b);
            _, _, w, h := Window_Creation.get_dimensions(window, right_handed_mouse_position);

            motion_event: X11.XEvent;
            while X11.XCheckTypedWindowEvent(X11.x_global_display, window, X11.MotionNotify, *motion_event) {
                event_dx := motion_event.xmotion.x - w / 2;
                event_dy := motion_event.xmotion.y - h / 2;
                if event_dx != 0 || event_dy != 0 {
                    linux_motion_dx += event_dx;
                    linux_motion_dy += event_dy;
                    linux_nonzero_motion_events += 1;
                }
            }
        }
    }

    per_frame_update(*wp);

    camera.sensitivity = sensitivity;

    // handle ESC to toggle in-game menu
    // handle M to toggle mouse cursor without opening menu
    for Input.events_this_frame {
        if it.type == .KEYBOARD && it.key_pressed {
            if it.key_code == .ESCAPE {
                if transform_operation.type != .NONE {
                    cancel_windowed_program_3d_transform_operation(wp3b);
                } else if current_menu == .CROSSHAIR_EDITOR {
                    current_menu = .USER_SETTINGS;
                } else if !camera_look_active {
                    // if mouse mode is active, pressing ESC should re-lock the camera first
                    set_windowed_program_3d_camera_look_active(wp3b, true);
                } else {
                    toggle_menu(*wp);
                }
            }

            if it.key_code == xx #char "M" && current_menu == .NONE &&
               transform_operation.type == .NONE {
                set_windowed_program_3d_camera_look_active(wp3b, !camera_look_active);
            }

            if it.key_code == xx #char "O" && current_menu == .NONE &&
               transform_operation.type == .NONE {
                set_windowed_program_3d_orthographic(
                    wp3b,
                    !orthographic_projection_active,
                );
            }

            if view_preset_shortcuts_enabled && !camera_look_active &&
               camera_mode != .TWO_DIMENSIONS && current_menu == .NONE &&
               transform_operation.type == .NONE {
                if it.key_code == xx #char "1" {
                    set_windowed_program_3d_view_preset(wp3b, .PERSPECTIVE);
                } else if it.key_code == xx #char "2" {
                    set_windowed_program_3d_view_preset(wp3b, .TOP);
                } else if it.key_code == xx #char "3" {
                    set_windowed_program_3d_view_preset(wp3b, .SIDE);
                } else if it.key_code == xx #char "4" {
                    set_windowed_program_3d_view_preset(wp3b, .FRONT);
                }
            }

        }
    }

    if right_mouse_just_pressed() && current_menu == .NONE {
        if transform_operation.type != .NONE {
            cancel_windowed_program_3d_transform_operation(wp3b);
        } else {
            set_windowed_program_3d_camera_look_active(wp3b, !camera_look_active);
        }
    }

    want_cursor_captured := camera_look_active
                         && current_menu == .NONE
                         && camera_mode != .TWO_DIMENSIONS
                         && window_has_focus;

    if want_cursor_captured {
        hide_cursor(*wp);
        #if OS == .WINDOWS {
            keep_mouse_in_center_of_screen(*wp);
            update_angles_with_deltas(*camera, Input.mouse_delta_x, Input.mouse_delta_y);
        } else #if OS == .LINUX {
            dx := 0;
            dy := 0;

            if raw_mouse_events > 0 {
                dx = cast(int) raw_mouse_dx;
                dy = cast(int) raw_mouse_dy;
            } else if linux_nonzero_motion_events > 0 {
                dx = linux_motion_dx;
                dy = linux_motion_dy;
            } else {
                x, y, success := Window_Creation.get_mouse_pointer_position(window, right_handed_mouse_position);
                _, _, w, h := Window_Creation.get_dimensions(window, right_handed_mouse_position);
                if success {
                    dx = x - w / 2;
                    dy = y - h / 2;
                }
            }

            update_angles_with_deltas(*camera, dx, dy);
            keep_mouse_in_center_of_screen(*wp);
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

    if movement_mode != .MANUAL && want_cursor_captured camera.position += camera_velocity * delta_time;

    update_listener_orientation(camera.position, camera.yaw);

    if orthographic_projection_active && current_menu == .NONE {
        for Input.events_this_frame {
            if it.type != .MOUSE_WHEEL continue;
            if it.wheel_delta > 0 {
                orthographic_view_height *= 0.9;
            } else if it.wheel_delta < 0 {
                orthographic_view_height *= 1.1;
            }
            orthographic_view_height = clamp(orthographic_view_height, 0.1, 10000.0);
        }
    }

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

    world_to_camera = Matrix4_Identity;
    camera_to_clip = Matrix4_Identity;
    if camera_mode != .TWO_DIMENSIONS {
        world_to_camera = get_world_to_camera_matrix(*camera);
        if orthographic_projection_active {
            aspect := cast(float) vw / cast(float) vh;
            half_h := orthographic_view_height * 0.5;
            half_w := half_h * aspect;
            camera_to_clip = orthographic_projection_matrix(
                left = -half_w,
                right = half_w,
                bottom = -half_h,
                top = half_h,
                near = -1000.0,
                far = 1000.0,
                depth_range_01 = false,
            );
        } else {
            camera_to_clip = get_projection_matrix(*camera, window_width, window_height);
        }
    } else {
        aspect := cast(float) vw / cast(float) vh;
        ortho_width := ortho_height * aspect;
        half_w := ortho_width * 0.5;
        half_h := ortho_height * 0.5;

        camera_to_clip = orthographic_projection_matrix(
            left   = ortho_center.x - half_w,
            right  = ortho_center.x + half_w,
            bottom = ortho_center.y - half_h,
            top    = ortho_center.y + half_h,
            near   = -100.0,
            far    =  100.0,
            depth_range_01 = false
        );
    }


    picker_width := cast(u32) max(vw, 1);
    picker_height := cast(u32) max(vh, 1);
    if picker.width != picker_width || picker.height != picker_height {
        resize(*picker, picker_width, picker_height);
    }

    if !camera_look_active && camera_mode != .TWO_DIMENSIONS &&
       current_menu == .NONE && transform_operation.type == .NONE &&
       left_mouse_just_pressed() {
        mouse_x, mouse_y, mouse_position_available := Window_Creation.get_mouse_pointer_position(window, true);
        if mouse_position_available {
            new_selection := pick_closest(*picker, cast(s32) mouse_x, cast(s32) mouse_y);
            selection_changed = new_selection != selected_object_id;
            selected_object_id = new_selection;
        }
    }

    if !camera_look_active && camera_mode != .TWO_DIMENSIONS && current_menu == .NONE {
        mouse_x, mouse_y, mouse_position_available := Window_Creation.get_mouse_pointer_position(window, true);
        if mouse_position_available {
            mouse := Vector2.{cast(float) mouse_x, cast(float) mouse_y};

            if transform_operation.type == .NONE && selected_object_id != WINDOWED_PROGRAM_3D_NO_OBJECT_ID {
                if key_just_pressed(xx #char "G") {
                    begin_windowed_program_3d_transform_operation(wp3b, .MOVE, mouse);
                } else if key_just_pressed(xx #char "R") {
                    begin_windowed_program_3d_transform_operation(wp3b, .ROTATE, mouse);
                } else if key_just_pressed(xx #char "S") {
                    begin_windowed_program_3d_transform_operation(wp3b, .SCALE, mouse);
                }
            }

            if transform_operation.type != .NONE {
                if key_just_pressed(xx #char "X") {
                    transform_operation.axis_constraint = ifx transform_operation.axis_constraint == 0
                        then cast(s32) -1 else cast(s32) 0;
                }
                if key_just_pressed(xx #char "Y") {
                    transform_operation.axis_constraint = ifx transform_operation.axis_constraint == 1
                        then cast(s32) -1 else cast(s32) 1;
                }
                if key_just_pressed(xx #char "Z") {
                    transform_operation.axis_constraint = ifx transform_operation.axis_constraint == 2
                        then cast(s32) -1 else cast(s32) 2;
                }

                update_windowed_program_3d_transform_operation(wp3b, mouse, vw, vh);
                if left_mouse_just_pressed() {
                    confirm_windowed_program_3d_transform_operation(wp3b);
                }
            }
        }
    }

}
