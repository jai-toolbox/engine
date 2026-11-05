Saved_Camera_View :: struct {
    camera: Camera;
    mode: Camera_Mode;
    focus: Vector3;
    orthographic: bool;
    view_height: float32;
}

is_plane_camera_mode :: (mode: Camera_Mode) -> bool {
    return mode == .XY || mode == .XZ || mode == .YZ;
}

get_camera_plane :: (mode: Camera_Mode) -> Grid_Plane {
    assert(is_plane_camera_mode(mode));
    if mode == .XY return .XY;
    if mode == .XZ return .XZ;
    return .YZ;
}

// Plane names refer to world coordinates, independently of camera.world_up.
// Keep the configured up convention; yaw/pitch supply the exact axial pose.
align_plane_camera :: (using wp3b: *Windowed_Program_3D_Base) {
    assert(is_plane_camera_mode(camera_mode));
    normal := Z3;
    if camera_mode == .XZ normal = Y3;
    if camera_mode == .YZ normal = X3;
    distance := max(length(camera.position + camera.offset - camera_focus), 0.05);
    set_camera_look_at(*camera, camera_focus + normal * distance - camera.offset, camera_focus);
    orthographic_projection_active = true;
    camera_velocity = .{};
}

set_camera_mode :: (
    using wp3b: *Windowed_Program_3D_Base,
    mode: Camera_Mode,
    restore_view: bool = true,
) {
    was_plane := is_plane_camera_mode(camera_mode);
    if is_plane_camera_mode(mode) {
        if !was_plane {
            saved_free_view = .{camera, camera_mode, camera_focus,
                orthographic_projection_active, orthographic_view_height};
            saved_free_view_valid = true;
        }
        camera_path.playing = false;
        set_camera_look_active(wp3b, false);
        camera_mode = mode;
        align_plane_camera(wp3b);
    } else {
        if was_plane && restore_view && saved_free_view_valid {
            camera = saved_free_view.camera;
            // Carry plane-view panning into the restored free view.
            camera.position += camera_focus - saved_free_view.focus;
            orthographic_projection_active = saved_free_view.orthographic;
            orthographic_view_height = saved_free_view.view_height;
        }
        camera_mode = mode;
        saved_free_view_valid = false;
    }
    camera_velocity = .{};
    orthographic_pan_active = false;
    selection_cycle_valid = false;
    selection_drag_active = false;
    selection_rectangle_active = false;
}

restore_free_view :: (using wp3b: *Windowed_Program_3D_Base, restore_view: bool = true) {
    if !is_plane_camera_mode(camera_mode) return;
    mode := ifx saved_free_view_valid then saved_free_view.mode else Camera_Mode.FIRST_PERSON;
    set_camera_mode(wp3b, mode, restore_view);
}

set_orthographic :: (using wp3b: *Windowed_Program_3D_Base, enabled: bool) {
    // Perspective rendering leaves a locked plane, retaining its current pose.
    if !enabled restore_free_view(wp3b, restore_view = false);
    orthographic_projection_active = enabled;
    if enabled camera_velocity = .{};
}

// Shared navigation for the locked planes and free orthographic orbit views.
pan_orthographic :: (
    using wp3b: *Windowed_Program_3D_Base,
    pixel_delta: Vector2,
    viewport_height: s32,
) {
    units_per_pixel := orthographic_view_height / cast(float32) max(viewport_height, 1);
    translation := -(get_right(*camera) * pixel_delta.x + get_up(*camera) * pixel_delta.y) * units_per_pixel;
    camera.position += translation;
    camera_focus += translation;
    camera_velocity = .{};
    selection_cycle_valid = false;
}

zoom_orthographic :: (
    using wp3b: *Windowed_Program_3D_Base,
    factor: float32,
    viewport_mouse: Vector2,
    viewport_width: s32,
    viewport_height: s32,
) {
    height := cast(float32) max(viewport_height, 1);
    cursor := viewport_mouse - Vector2.{cast(float32) max(viewport_width, 1) * 0.5, height * 0.5};
    previous_height := orthographic_view_height;
    orthographic_view_height = clamp(previous_height * factor, 0.1, 10000.0);
    // Translate the view so the world position under the cursor stays fixed.
    translation := (get_right(*camera) * cursor.x + get_up(*camera) * cursor.y)
        * ((previous_height - orthographic_view_height) / height);
    camera.position += translation;
    camera_focus += translation;
    camera_velocity = .{};
    selection_cycle_valid = false;
}

update_camera_matrices :: (using wp3b: *Windowed_Program_3D_Base, width: s32, height: s32) {
    world_to_camera = get_world_to_camera_matrix(*camera);
    if orthographic_projection_active {
        half_h := orthographic_view_height * 0.5;
        half_w := half_h * cast(float32) max(width, 1) / cast(float32) max(height, 1);
        camera_to_clip = orthographic_projection_matrix(-half_w, half_w, -half_h, half_h,
            -1000.0, 1000.0, depth_range_01 = false);
    } else camera_to_clip = get_projection_matrix(*camera, width, height);
}
