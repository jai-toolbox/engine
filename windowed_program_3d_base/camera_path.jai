#scope_file
Input :: #import "Input";
#scope_export

Windowed_Program_3D_Camera_Keyframe :: struct {
    position: Vector3;
    yaw: float32;
    pitch: float32;
}

Windowed_Program_3D_Camera_Path :: struct {
    keyframes: [..] Windowed_Program_3D_Camera_Keyframe;
    selected_index: s64 = -1;

    visible: bool = true;
    playing: bool;
    loop_playback: bool;
    playback_time_s: float32;
    seconds_per_segment: float32 = 1.5;
    preview_samples_per_segment: s32 = 24;

    curve_color: Vector4 = .{0.22, 0.72, 1.0, 0.88};
    keyframe_color: Vector4 = .{0.20, 0.82, 1.0, 0.95};
    selected_keyframe_color: Vector4 = .{1.0, 0.72, 0.08, 1.0};
    orientation_color: Vector4 = .{0.96, 0.42, 0.18, 0.95};
    curve_thickness_px: float32 = 2.0;
    keyframe_radius_px: float32 = 6.0;
    selected_keyframe_radius_px: float32 = 9.0;
    keyframe_hit_radius_px: float32 = 13.0;
    orientation_marker_length: float32 = 0.5;

    changed_this_frame: bool;
}

windowed_program_3d_camera_keyframe_from_camera :: (
    camera: *Camera,
) -> Windowed_Program_3D_Camera_Keyframe {
    return .{
        position = camera.position,
        yaw = camera.yaw,
        pitch = camera.pitch,
    };
}

windowed_program_3d_camera_path_shortest_turn_delta :: (
    start: float32,
    end: float32,
) -> float32 {
    delta := end - start;
    return delta - floor(delta + 0.5);
}

windowed_program_3d_camera_path_catmull_rom_position :: (
    p0: Vector3,
    p1: Vector3,
    p2: Vector3,
    p3: Vector3,
    amount: float32,
) -> Vector3 {
    chord := length(p2 - p1);
    if chord <= 0.000001 return p1;

    interval_01 := sqrt(max(length(p1 - p0), cast(float32) 0.000001));
    interval_12 := sqrt(max(chord, cast(float32) 0.000001));
    interval_23 := sqrt(max(length(p3 - p2), cast(float32) 0.000001));
    t0: float32 = 0;
    t1 := t0 + interval_01;
    t2 := t1 + interval_12;
    t3 := t2 + interval_23;
    t := t1 + (t2 - t1) * clamp(amount, cast(float32) 0, cast(float32) 1);

    a1 := p0 * ((t1 - t) / (t1 - t0))
        + p1 * ((t - t0) / (t1 - t0));
    a2 := p1 * ((t2 - t) / (t2 - t1))
        + p2 * ((t - t1) / (t2 - t1));
    a3 := p2 * ((t3 - t) / (t3 - t2))
        + p3 * ((t - t2) / (t3 - t2));
    b1 := a1 * ((t2 - t) / (t2 - t0))
        + a2 * ((t - t0) / (t2 - t0));
    b2 := a2 * ((t3 - t) / (t3 - t1))
        + a3 * ((t - t1) / (t3 - t1));
    return b1 * ((t2 - t) / (t2 - t1))
        + b2 * ((t - t1) / (t2 - t1));
}

windowed_program_3d_camera_path_catmull_rom_scalar :: (
    v0: float32,
    v1: float32,
    v2: float32,
    v3: float32,
    p0: Vector3,
    p1: Vector3,
    p2: Vector3,
    p3: Vector3,
    amount: float32,
) -> float32 {
    interval_01 := sqrt(max(length(p1 - p0), cast(float32) 0.000001));
    interval_12 := sqrt(max(length(p2 - p1), cast(float32) 0.000001));
    interval_23 := sqrt(max(length(p3 - p2), cast(float32) 0.000001));
    t0: float32 = 0;
    t1 := t0 + interval_01;
    t2 := t1 + interval_12;
    t3 := t2 + interval_23;
    t := t1 + (t2 - t1) * clamp(amount, cast(float32) 0, cast(float32) 1);

    a1 := v0 * ((t1 - t) / (t1 - t0))
        + v1 * ((t - t0) / (t1 - t0));
    a2 := v1 * ((t2 - t) / (t2 - t1))
        + v2 * ((t - t1) / (t2 - t1));
    a3 := v2 * ((t3 - t) / (t3 - t2))
        + v3 * ((t - t2) / (t3 - t2));
    b1 := a1 * ((t2 - t) / (t2 - t0))
        + a2 * ((t - t0) / (t2 - t0));
    b2 := a2 * ((t3 - t) / (t3 - t1))
        + a3 * ((t - t1) / (t3 - t1));
    return b1 * ((t2 - t) / (t2 - t1))
        + b2 * ((t - t1) / (t2 - t1));
}

sample_windowed_program_3d_camera_path_segment :: (
    path: *Windowed_Program_3D_Camera_Path,
    segment_index: s64,
    amount: float32,
) -> Windowed_Program_3D_Camera_Keyframe {
    count := path.keyframes.count;
    if count == 0 return .{};
    if count == 1 return path.keyframes[0];

    segment_index = clamp(segment_index, cast(s64) 0, count - 2);
    key1 := path.keyframes[segment_index];
    key2 := path.keyframes[segment_index + 1];
    p1 := key1.position;
    p2 := key2.position;
    p0 := ifx segment_index > 0
        then path.keyframes[segment_index - 1].position
        else p1 + (p1 - p2);
    p3 := ifx segment_index + 2 < count
        then path.keyframes[segment_index + 2].position
        else p2 + (p2 - p1);

    yaw1 := key1.yaw;
    yaw2 := yaw1 + windowed_program_3d_camera_path_shortest_turn_delta(yaw1, key2.yaw);
    yaw0 := ifx segment_index > 0
        then yaw1 + windowed_program_3d_camera_path_shortest_turn_delta(
            yaw1,
            path.keyframes[segment_index - 1].yaw,
        )
        else yaw1 - windowed_program_3d_camera_path_shortest_turn_delta(yaw1, yaw2);
    yaw3 := ifx segment_index + 2 < count
        then yaw2 + windowed_program_3d_camera_path_shortest_turn_delta(
            yaw2,
            path.keyframes[segment_index + 2].yaw,
        )
        else yaw2 + windowed_program_3d_camera_path_shortest_turn_delta(yaw1, yaw2);

    pitch0 := ifx segment_index > 0
        then path.keyframes[segment_index - 1].pitch
        else key1.pitch + (key1.pitch - key2.pitch);
    pitch3 := ifx segment_index + 2 < count
        then path.keyframes[segment_index + 2].pitch
        else key2.pitch + (key2.pitch - key1.pitch);

    sample: Windowed_Program_3D_Camera_Keyframe;
    sample.position = windowed_program_3d_camera_path_catmull_rom_position(
        p0, p1, p2, p3, amount,
    );
    sample.yaw = windowed_program_3d_camera_path_catmull_rom_scalar(
        yaw0, yaw1, yaw2, yaw3, p0, p1, p2, p3, amount,
    );
    sample.pitch = windowed_program_3d_camera_path_catmull_rom_scalar(
        pitch0, key1.pitch, key2.pitch, pitch3,
        p0, p1, p2, p3, amount,
    );
    sample.pitch = clamp(
        sample.pitch,
        cast(float32)(-ONE_QUARTER_TURN + PITCH_EPSILON),
        cast(float32)(ONE_QUARTER_TURN - PITCH_EPSILON),
    );
    return sample;
}

sample_windowed_program_3d_camera_path :: (
    path: *Windowed_Program_3D_Camera_Path,
    time_s: float32,
) -> Windowed_Program_3D_Camera_Keyframe {
    count := path.keyframes.count;
    if count == 0 return .{};
    if count == 1 return path.keyframes[0];

    seconds_per_segment := max(path.seconds_per_segment, cast(float32) 0.0001);
    duration := cast(float32)(count - 1) * seconds_per_segment;
    clamped_time := clamp(time_s, cast(float32) 0, duration);
    segment_position := clamped_time / seconds_per_segment;
    segment_index := min(cast(s64) floor(segment_position), count - 2);
    amount := segment_position - cast(float32) segment_index;
    if clamped_time >= duration amount = 1;
    return sample_windowed_program_3d_camera_path_segment(path, segment_index, amount);
}

apply_windowed_program_3d_camera_keyframe :: (
    using base3d: *Windowed_Program_3D_Base,
    keyframe: Windowed_Program_3D_Camera_Keyframe,
) {
    set_windowed_program_3d_view_preset(base3d, .PERSPECTIVE);
    camera.position = keyframe.position;
    camera.yaw = keyframe.yaw;
    camera.pitch = keyframe.pitch;
    camera_velocity = .{};
}

add_windowed_program_3d_camera_keyframe :: (
    using base3d: *Windowed_Program_3D_Base,
) -> s64 {
    camera_path.playing = false;
    array_add(*camera_path.keyframes, windowed_program_3d_camera_keyframe_from_camera(*camera));
    camera_path.selected_index = camera_path.keyframes.count - 1;
    camera_path.visible = true;
    camera_path.changed_this_frame = true;
    return camera_path.selected_index;
}

update_selected_windowed_program_3d_camera_keyframe :: (
    using base3d: *Windowed_Program_3D_Base,
) -> bool {
    index := camera_path.selected_index;
    if index < 0 || index >= camera_path.keyframes.count return false;
    camera_path.playing = false;
    camera_path.keyframes[index] = windowed_program_3d_camera_keyframe_from_camera(*camera);
    camera_path.changed_this_frame = true;
    return true;
}

remove_selected_windowed_program_3d_camera_keyframe :: (
    using base3d: *Windowed_Program_3D_Base,
) -> bool {
    index := camera_path.selected_index;
    if index < 0 || index >= camera_path.keyframes.count return false;
    camera_path.playing = false;
    array_ordered_remove_by_index(*camera_path.keyframes, index);
    if camera_path.keyframes.count == 0 {
        camera_path.selected_index = -1;
    } else {
        camera_path.selected_index = min(index, camera_path.keyframes.count - 1);
    }
    camera_path.changed_this_frame = true;
    return true;
}

select_windowed_program_3d_camera_keyframe :: (
    using base3d: *Windowed_Program_3D_Base,
    index: s64,
    jump_to_keyframe: bool = true,
) -> bool {
    if index < 0 || index >= camera_path.keyframes.count return false;
    camera_path.playing = false;
    camera_path.selected_index = index;
    if jump_to_keyframe {
        apply_windowed_program_3d_camera_keyframe(base3d, camera_path.keyframes[index]);
    }
    return true;
}

step_windowed_program_3d_camera_keyframe :: (
    using base3d: *Windowed_Program_3D_Base,
    direction: s64,
) -> bool {
    count := camera_path.keyframes.count;
    if count == 0 return false;
    index := camera_path.selected_index;
    if index < 0 index = 0;
    else index = (index + direction + count) % count;
    return select_windowed_program_3d_camera_keyframe(base3d, index, true);
}

set_windowed_program_3d_camera_path_playing :: (
    using base3d: *Windowed_Program_3D_Base,
    playing: bool,
    restart: bool = true,
) -> bool {
    if playing && camera_path.keyframes.count < 2 return false;
    camera_path.playing = playing;
    if !playing return true;

    if restart camera_path.playback_time_s = 0;
    set_windowed_program_3d_view_preset(base3d, .PERSPECTIVE);
    set_windowed_program_3d_camera_look_active(base3d, false);
    camera_velocity = .{};
    apply_windowed_program_3d_camera_keyframe(
        base3d,
        sample_windowed_program_3d_camera_path(*camera_path, camera_path.playback_time_s),
    );
    return true;
}

update_windowed_program_3d_camera_path_playback :: (
    using base3d: *Windowed_Program_3D_Base,
    dt: float32,
) {
    if !camera_path.playing || camera_path.keyframes.count < 2 return;

    duration := cast(float32)(camera_path.keyframes.count - 1)
        * max(camera_path.seconds_per_segment, cast(float32) 0.0001);
    camera_path.playback_time_s += max(dt, cast(float32) 0);
    if camera_path.playback_time_s >= duration {
        if camera_path.loop_playback {
            camera_path.playback_time_s -=
                floor(camera_path.playback_time_s / duration) * duration;
        } else {
            camera_path.playback_time_s = duration;
            camera_path.playing = false;
            camera_path.selected_index = camera_path.keyframes.count - 1;
        }
    }

    apply_windowed_program_3d_camera_keyframe(
        base3d,
        sample_windowed_program_3d_camera_path(*camera_path, camera_path.playback_time_s),
    );
}

windowed_program_3d_camera_path_project_to_ui :: (
    world_position: Vector3,
    world_to_camera: Matrix4,
    camera_to_clip: Matrix4,
    viewport_width: float32,
    viewport_height: float32,
) -> (screen: Vector2, ok: bool) {
    clip := camera_to_clip
        * world_to_camera
        * Vector4.{world_position.x, world_position.y, world_position.z, 1};
    if clip.w <= 0.000001 return .{}, false;
    ndc := clip / clip.w;
    if ndc.z < -1 || ndc.z > 1 return .{}, false;
    return .{
        (ndc.x + 1.0) * 0.5 * viewport_width,
        (1.0 - (ndc.y + 1.0) * 0.5) * viewport_height,
    }, true;
}

windowed_program_3d_camera_keyframe_forward :: (
    keyframe: Windowed_Program_3D_Camera_Keyframe,
) -> Vector3 {
    key_camera: Camera;
    key_camera.position = keyframe.position;
    key_camera.yaw = keyframe.yaw;
    key_camera.pitch = keyframe.pitch;
    return get_forward(*key_camera);
}

hit_test_windowed_program_3d_camera_path :: (
    using base3d: *Windowed_Program_3D_Base,
    mouse_bottom_left: Vector2,
    viewport_width: s32,
    viewport_height: s32,
) -> (index: s64, hit: bool) {
    if !camera_path.visible || camera_path.keyframes.count == 0 return -1, false;
    mouse := Vector2.{mouse_bottom_left.x, cast(float32) viewport_height - mouse_bottom_left.y};
    best_distance_squared := camera_path.keyframe_hit_radius_px
        * camera_path.keyframe_hit_radius_px;
    best_index: s64 = -1;
    for keyframe, keyframe_index: camera_path.keyframes {
        screen, projected := windowed_program_3d_camera_path_project_to_ui(
            keyframe.position,
            world_to_camera,
            camera_to_clip,
            cast(float32) viewport_width,
            cast(float32) viewport_height,
        );
        if !projected continue;
        distance_squared := length_squared(screen - mouse);
        if distance_squared > best_distance_squared continue;
        best_distance_squared = distance_squared;
        best_index = keyframe_index;
    }
    return best_index, best_index >= 0;
}

update_windowed_program_3d_camera_path_editor :: (
    using base3d: *Windowed_Program_3D_Base,
) {
    camera_path.changed_this_frame = false;
    if !camera_path_editor_enabled || camera_mode == .TWO_DIMENSIONS ||
       current_menu != .NONE || transform_operation.type != .NONE {
        update_windowed_program_3d_camera_path_playback(base3d, cast(float32) delta_time);
        return;
    }

    control_down := key_pressed(Input.Key_Code.CTRL);
    if control_down && key_just_pressed(xx #char "K") {
        add_windowed_program_3d_camera_keyframe(base3d);
    }
    if control_down && key_just_pressed(Input.Key_Code.ARROW_LEFT) {
        step_windowed_program_3d_camera_keyframe(base3d, -1);
    }
    if control_down && key_just_pressed(Input.Key_Code.ARROW_RIGHT) {
        step_windowed_program_3d_camera_keyframe(base3d, 1);
    }
    if control_down && key_just_pressed(Input.Key_Code.ENTER) {
        update_selected_windowed_program_3d_camera_keyframe(base3d);
    }
    if control_down && key_just_pressed(Input.Key_Code.DELETE) {
        remove_selected_windowed_program_3d_camera_keyframe(base3d);
    }
    if control_down && key_just_pressed(xx #char "H") {
        camera_path.visible = !camera_path.visible;
    }
    if control_down && key_just_pressed(xx #char " ") {
        set_windowed_program_3d_camera_path_playing(
            base3d,
            !camera_path.playing,
            restart = true,
        );
    }

    update_windowed_program_3d_camera_path_playback(base3d, cast(float32) delta_time);
}

render_windowed_program_3d_camera_path :: (
    using base3d: *Windowed_Program_3D_Base,
    viewport_left: float32 = 0,
    viewport_top: float32 = 0,
    viewport_width: float32 = -1,
    viewport_height: float32 = -1,
) {
    if !camera_path_editor_enabled || !camera_path.visible || ui_ctx == null ||
       camera_path.keyframes.count == 0 return;

    width := ifx viewport_width > 0 then viewport_width else cast(float32) ui_ctx.window_w;
    height := ifx viewport_height > 0 then viewport_height else cast(float32) ui_ctx.window_h;
    viewport_offset := Vector2.{viewport_left, viewport_top};
    if camera_path.keyframes.count >= 2 {
        samples_per_segment := max(camera_path.preview_samples_per_segment, cast(s32) 2);
        previous_screen, previous_visible := windowed_program_3d_camera_path_project_to_ui(
            camera_path.keyframes[0].position,
            world_to_camera,
            camera_to_clip,
            width,
            height,
        );
        previous_screen += viewport_offset;
        for segment_index: 0..camera_path.keyframes.count - 2 {
            for sample_index: 1..samples_per_segment {
                amount := cast(float32) sample_index / cast(float32) samples_per_segment;
                sample := sample_windowed_program_3d_camera_path_segment(
                    *camera_path,
                    segment_index,
                    amount,
                );
                screen, visible := windowed_program_3d_camera_path_project_to_ui(
                    sample.position,
                    world_to_camera,
                    camera_to_clip,
                    width,
                    height,
                );
                screen += viewport_offset;
                if previous_visible && visible {
                    windowed_program_3d_draw_screen_line(
                        previous_screen,
                        screen,
                        camera_path.curve_thickness_px,
                        camera_path.curve_color,
                    );
                }
                previous_screen = screen;
                previous_visible = visible;
            }
        }
    }

    for keyframe, keyframe_index: camera_path.keyframes {
        screen, visible := windowed_program_3d_camera_path_project_to_ui(
            keyframe.position,
            world_to_camera,
            camera_to_clip,
            width,
            height,
        );
        screen += viewport_offset;
        if !visible continue;

        selected := keyframe_index == camera_path.selected_index;
        marker_color := ifx selected
            then camera_path.selected_keyframe_color
            else camera_path.keyframe_color;
        marker_radius := ifx selected
            then camera_path.selected_keyframe_radius_px
            else camera_path.keyframe_radius_px;
        windowed_program_3d_draw_screen_circle(screen, marker_radius, marker_color, 18);

        orientation_end := keyframe.position
            + windowed_program_3d_camera_keyframe_forward(keyframe)
            * camera_path.orientation_marker_length;
        orientation_screen, orientation_visible := windowed_program_3d_camera_path_project_to_ui(
            orientation_end,
            world_to_camera,
            camera_to_clip,
            width,
            height,
        );
        orientation_screen += viewport_offset;
        if orientation_visible {
            windowed_program_3d_draw_screen_line(
                screen,
                orientation_screen,
                2.0,
                camera_path.orientation_color,
            );
        }
        ui_cmd_text(
            tprint("%", keyframe_index + 1),
            screen.x + marker_radius + 3.0,
            screen.y + 4.0,
            11.0,
            marker_color,
        );
    }

    selected_display := ifx camera_path.selected_index >= 0
        then camera_path.selected_index + 1 else cast(s64) 0;
    state := ifx camera_path.playing then "PLAYING" else "EDIT";
    status := tprint(
        "CAMERA PATH [%]  % keys  selected %  |  Ctrl+K add  Ctrl+Left/Right jump  Ctrl+Enter update  Ctrl+Space play  Ctrl+Del remove  Ctrl+H hide",
        state,
        camera_path.keyframes.count,
        selected_display,
    );
    ui_cmd_rect(.{
        viewport_left + 12,
        viewport_top + 12,
        min(width - 24.0, 990.0),
        28,
    }, .{0.035, 0.045, 0.065, 0.88});
    ui_cmd_text(status, viewport_left + 20, viewport_top + 31, 12, .{0.92, 0.95, 1.0, 1});
}
