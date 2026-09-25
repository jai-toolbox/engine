Windowed_Program_3D_Transform_Operation_Type :: enum {
    NONE;
    MOVE;
    ROTATE;
    SCALE;
}

Windowed_Program_3D_Transform_Operation :: struct {
    type: Windowed_Program_3D_Transform_Operation_Type;
    object_id: u32;
    axis_constraint: s32 = -1; // -1 = free, 0 = X, 1 = Y, 2 = Z
    start_mouse: Vector2;
    pivot: Vector3;
    original_transform: Matrix4 = Matrix4_Identity;
    preview_transform: Matrix4 = Matrix4_Identity;
}

windowed_program_3d_transform_pivot :: (transform: Matrix4) -> Vector3 {
    return .{transform._14, transform._24, transform._34};
}

windowed_program_3d_transform_axis :: (axis_constraint: s32) -> Vector3 {
    if axis_constraint == 0 return .{1, 0, 0};
    if axis_constraint == 1 return .{0, 1, 0};
    if axis_constraint == 2 return .{0, 0, 1};
    return .{};
}

windowed_program_3d_ray_from_screen :: (
    mouse: Vector2,
    viewport_width: s32,
    viewport_height: s32,
    world_to_camera: Matrix4,
    camera_to_clip: Matrix4,
) -> (origin: Vector3, direction: Vector3, ok: bool) {
    if viewport_width <= 0 || viewport_height <= 0 return .{}, .{}, false;

    projection_ok, clip_to_camera := inverse(camera_to_clip);
    view_ok, camera_to_world := inverse(world_to_camera);
    if !projection_ok || !view_ok return .{}, .{}, false;

    ndc_x := cast(float) mouse.x / cast(float) viewport_width * 2.0 - 1.0;
    ndc_y := cast(float) mouse.y / cast(float) viewport_height * 2.0 - 1.0;
    camera_near := clip_to_camera * Vector4.{ndc_x, ndc_y, -1, 1};
    camera_far := clip_to_camera * Vector4.{ndc_x, ndc_y, 1, 1};
    if abs(camera_near.w) <= 0.000001 || abs(camera_far.w) <= 0.000001 {
        return .{}, .{}, false;
    }
    camera_near /= camera_near.w;
    camera_far /= camera_far.w;

    world_near_4 := camera_to_world * camera_near;
    world_far_4 := camera_to_world * camera_far;
    world_near := Vector3.{world_near_4.x, world_near_4.y, world_near_4.z};
    world_far := Vector3.{world_far_4.x, world_far_4.y, world_far_4.z};
    ray := world_far - world_near;
    if length_squared(ray) <= 0.000001 return .{}, .{}, false;
    return world_near, normalize(ray), true;
}

windowed_program_3d_ray_plane_intersection :: (
    ray_origin: Vector3,
    ray_direction: Vector3,
    plane_point: Vector3,
    plane_normal: Vector3,
) -> (point: Vector3, ok: bool) {
    denominator := dot(plane_normal, ray_direction);
    if abs(denominator) <= 0.00001 return .{}, false;
    distance := dot(plane_point - ray_origin, plane_normal) / denominator;
    return ray_origin + ray_direction * distance, true;
}

windowed_program_3d_publish_editor_transform :: (
    using base3d: *Windowed_Program_3D_Base,
    object_id: u32,
    transform: Matrix4,
) {
    if !set_pickable_transform(*picker, object_id, transform) return;
    editor_transform_object_id = object_id;
    editor_transform_matrix = transform;
    editor_transform_changed = true;
}

begin_windowed_program_3d_transform_operation :: (
    using base3d: *Windowed_Program_3D_Base,
    operation_type: Windowed_Program_3D_Transform_Operation_Type,
    mouse: Vector2,
) -> bool {
    if operation_type == .NONE || selected_object_id == WINDOWED_PROGRAM_3D_NO_OBJECT_ID return false;
    if !pickable_is_transformable(*picker, selected_object_id) return false;
    transform, found := get_pickable_transform(*picker, selected_object_id);
    if !found return false;

    transform_operation.type = operation_type;
    transform_operation.object_id = selected_object_id;
    transform_operation.axis_constraint = -1;
    transform_operation.start_mouse = mouse;
    transform_operation.pivot = windowed_program_3d_transform_pivot(transform);
    transform_operation.original_transform = transform;
    transform_operation.preview_transform = transform;
    return true;
}

cancel_windowed_program_3d_transform_operation :: (using base3d: *Windowed_Program_3D_Base) {
    if transform_operation.type == .NONE return;
    windowed_program_3d_publish_editor_transform(
        base3d,
        transform_operation.object_id,
        transform_operation.original_transform,
    );
    transform_operation = .{};
    transform_operation.axis_constraint = -1;
}

confirm_windowed_program_3d_transform_operation :: (using base3d: *Windowed_Program_3D_Base) {
    if transform_operation.type == .NONE return;
    transform_operation = .{};
    transform_operation.axis_constraint = -1;
}

update_windowed_program_3d_transform_operation :: (
    using base3d: *Windowed_Program_3D_Base,
    mouse: Vector2,
    viewport_width: s32,
    viewport_height: s32,
) {
    operation := *transform_operation;
    if operation.type == .NONE return;
    if selected_object_id != operation.object_id {
        cancel_windowed_program_3d_transform_operation(base3d);
        return;
    }

    result := operation.original_transform;
    if operation.type == .MOVE {
        camera_forward := normalize(get_forward(*camera));
        plane_normal := camera_forward;
        axis := windowed_program_3d_transform_axis(operation.axis_constraint);
        if operation.axis_constraint >= 0 {
            // Use the camera-facing plane that contains the constrained axis.
            // This remains stable for oblique views and avoids pixel-scale magic.
            plane_normal = camera_forward - axis * dot(camera_forward, axis);
            if length_squared(plane_normal) <= 0.00001 {
                camera_up := normalize(get_up(*camera));
                plane_normal = camera_up - axis * dot(camera_up, axis);
            }
            if length_squared(plane_normal) <= 0.00001 {
                camera_right := normalize(get_right(*camera));
                plane_normal = camera_right - axis * dot(camera_right, axis);
            }
            if length_squared(plane_normal) <= 0.00001 return;
            plane_normal = normalize(plane_normal);
        }

        start_origin, start_direction, start_ray_ok := windowed_program_3d_ray_from_screen(
            operation.start_mouse,
            viewport_width,
            viewport_height,
            world_to_camera,
            camera_to_clip,
        );
        current_origin, current_direction, current_ray_ok := windowed_program_3d_ray_from_screen(
            mouse,
            viewport_width,
            viewport_height,
            world_to_camera,
            camera_to_clip,
        );
        if !start_ray_ok || !current_ray_ok return;

        start_hit, start_hit_ok := windowed_program_3d_ray_plane_intersection(
            start_origin,
            start_direction,
            operation.pivot,
            plane_normal,
        );
        current_hit, current_hit_ok := windowed_program_3d_ray_plane_intersection(
            current_origin,
            current_direction,
            operation.pivot,
            plane_normal,
        );
        if !start_hit_ok || !current_hit_ok return;

        delta := current_hit - start_hit;
        if operation.axis_constraint >= 0 delta = axis * dot(delta, axis);
        result = make_translation_matrix4(delta) * operation.original_transform;
    } else if operation.type == .ROTATE {
        mouse_delta := mouse - operation.start_mouse;
        angle := (mouse_delta.x + mouse_delta.y * 0.35) * 0.01;
        axis := ifx operation.axis_constraint >= 0
            then windowed_program_3d_transform_axis(operation.axis_constraint)
            else normalize(get_forward(*camera));
        rotation: Quaternion;
        set_from_axis_and_angle(*rotation, axis, angle);
        pivot_to_origin := make_translation_matrix4(-operation.pivot);
        origin_to_pivot := make_translation_matrix4(operation.pivot);
        result = origin_to_pivot
            * rotation_matrix(Matrix4, rotation)
            * pivot_to_origin
            * operation.original_transform;
    } else if operation.type == .SCALE {
        mouse_delta := mouse - operation.start_mouse;
        scale_factor := max(0.01, 1.0 + (mouse_delta.x + mouse_delta.y * 0.35) * 0.005);
        scale := Vector3.{scale_factor, scale_factor, scale_factor};
        if operation.axis_constraint >= 0 {
            scale = .{1, 1, 1};
            scale.component[operation.axis_constraint] = scale_factor;
        }
        pivot_to_origin := make_translation_matrix4(-operation.pivot);
        origin_to_pivot := make_translation_matrix4(operation.pivot);
        result = origin_to_pivot
            * make_scale_matrix4(scale)
            * pivot_to_origin
            * operation.original_transform;
    }

    transform_operation.preview_transform = result;
    windowed_program_3d_publish_editor_transform(base3d, operation.object_id, result);
}

render_windowed_program_3d_transform_operation_status :: (
    using base3d: *Windowed_Program_3D_Base,
) {
    if transform_operation.type == .NONE || ui_ctx == null return;

    operation_name := ifx transform_operation.type == .MOVE then "MOVE"
        else ifx transform_operation.type == .ROTATE then "ROTATE"
        else "SCALE";
    axis_name := ifx transform_operation.axis_constraint == 0 then "X"
        else ifx transform_operation.axis_constraint == 1 then "Y"
        else ifx transform_operation.axis_constraint == 2 then "Z"
        else "FREE";
    status := tprint(
        "% [%]  |  X/Y/Z constrain  |  Left click confirm  |  Right click or Esc cancel",
        operation_name,
        axis_name,
    );
    ui_cmd_rect(.{12, ui_ctx.window_h - 39, 570, 28}, .{0.035, 0.045, 0.065, 0.86});
    ui_cmd_text(status, 20, ui_ctx.window_h - 20, 13, .{0.92, 0.94, 0.98, 1});
}
