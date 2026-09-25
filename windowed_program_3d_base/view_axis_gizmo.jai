Windowed_Program_3D_View_Axis :: struct {
    label: string;
    world_direction: Vector3;
    screen_direction: Vector2;
    view_depth: float32;
    color: Vector4;
}

Windowed_Program_3D_View_Axis_Arm :: struct {
    label: string;
    screen_direction: Vector2;
    view_depth: float32;
    color: Vector4;
    line_thickness: float32;
    endpoint_radius: float32;
    show_label: bool;
}

windowed_program_3d_draw_screen_line :: (
    start_pixels: Vector2,
    end_pixels: Vector2,
    thickness_pixels: float32,
    color: Vector4,
) {
    direction := end_pixels - start_pixels;
    segment_length := length(direction);
    if segment_length <= 0.0001 return;

    perpendicular := Vector2.{-direction.y, direction.x}
        * (thickness_pixels * 0.5 / segment_length);
    pixel_corners := Vector2.[
        start_pixels + perpendicular,
        start_pixels - perpendicular,
        end_pixels - perpendicular,
        end_pixels + perpendicular,
    ];
    positions := ui_pixels_to_ndc(pixel_corners);
    colors := ui_solid_colors(4, color);
    indices := u32.[0, 1, 2, 0, 2, 3];
    ui_cmd_geometry(positions, colors, indices);
}

windowed_program_3d_draw_screen_circle :: (
    center_pixels: Vector2,
    radius_pixels: float32,
    color: Vector4,
    segment_count: s32 = 20,
) {
    pixel_positions := NewArray(segment_count + 1, Vector2,, allocator = temp);
    pixel_positions[0] = center_pixels;
    for segment: 0..segment_count - 1 {
        angle := 2.0 * PI * cast(float32) segment / cast(float32) segment_count;
        pixel_positions[segment + 1] = center_pixels + Vector2.{cos(angle), sin(angle)} * radius_pixels;
    }

    positions := ui_pixels_to_ndc(pixel_positions);
    colors := ui_solid_colors(positions.count, color);
    indices := NewArray(segment_count * 3, u32,, allocator = temp);
    for segment: 0..segment_count - 1 {
        next_segment := (segment + 1) % segment_count;
        indices[segment * 3 + 0] = 0;
        indices[segment * 3 + 1] = cast(u32) segment + 1;
        indices[segment * 3 + 2] = cast(u32) next_segment + 1;
    }
    ui_cmd_geometry(positions, colors, indices);
}

windowed_program_3d_draw_view_axis_arm :: (
    center: Vector2,
    axis_radius: float32,
    arm: Windowed_Program_3D_View_Axis_Arm,
) {
    endpoint := center + arm.screen_direction * axis_radius;
    windowed_program_3d_draw_screen_line(
        center,
        endpoint,
        arm.line_thickness,
        arm.color,
    );
    windowed_program_3d_draw_screen_circle(
        endpoint,
        arm.endpoint_radius,
        arm.color,
        cast(s32) ifx arm.show_label then 18 else 14,
    );

    if arm.show_label {
        ui_cmd_text(
            arm.label,
            endpoint.x - 4.0,
            endpoint.y + 4.5,
            12.0,
            .{1, 1, 1, 1},
        );
    }
}

render_windowed_program_3d_view_axis_gizmo :: (
    world_to_camera: Matrix4,
    orthographic_projection: bool,
) {
    if ui_ctx == null return;

    center := Vector2.{ui_ctx.window_w - 72.0, 72.0};
    axis_radius: float32 = 39.0;

    windowed_program_3d_draw_screen_circle(
        center,
        axis_radius + 14.0,
        .{0.035, 0.045, 0.065, 0.72},
        28,
    );

    axes := Windowed_Program_3D_View_Axis.[
        .{label = "X", world_direction = .{1, 0, 0}, color = .{0.94, 0.23, 0.20, 1}},
        .{label = "Y", world_direction = .{0, 1, 0}, color = .{0.32, 0.78, 0.24, 1}},
        .{label = "Z", world_direction = .{0, 0, 1}, color = .{0.24, 0.48, 0.96, 1}},
    ];

    for *axis: axes {
        view_direction_4 := world_to_camera * Vector4.{
            axis.world_direction.x,
            axis.world_direction.y,
            axis.world_direction.z,
            0,
        };
        axis.screen_direction = .{view_direction_4.x, -view_direction_4.y};
        axis.view_depth = view_direction_4.z;
    }

    // UI rendering has no depth buffer, so represent the three axes as six
    // independently sortable half-arms. An axis's positive and negative arms
    // always have opposite camera-space depths and cannot be drawn as a bundle.
    arms: [6] Windowed_Program_3D_View_Axis_Arm;
    arm_index := 0;
    for axis: axes {
        negative_color := axis.color;
        negative_color.x *= 0.42;
        negative_color.y *= 0.42;
        negative_color.z *= 0.42;
        negative_color.w = 0.72;

        arms[arm_index] = .{
            label = axis.label,
            screen_direction = -axis.screen_direction,
            view_depth = -axis.view_depth,
            color = negative_color,
            line_thickness = 2.0,
            endpoint_radius = 4.0,
            show_label = false,
        };
        arm_index += 1;

        arms[arm_index] = .{
            label = axis.label,
            screen_direction = axis.screen_direction,
            view_depth = axis.view_depth,
            color = axis.color,
            line_thickness = 3.0,
            endpoint_radius = 9.0,
            show_label = true,
        };
        arm_index += 1;
    }

    // Camera-space Z increases toward the viewer. Painter-sort the half-arms
    // from far to near and insert the origin hub at camera-space depth zero.
    for i: 0..arms.count - 2 {
        for j: i + 1..arms.count - 1 {
            if arms[j].view_depth < arms[i].view_depth swap(*arms[i], *arms[j]);
        }
    }

    hub_drawn := false;
    for arm: arms {
        if !hub_drawn && arm.view_depth >= 0 {
            windowed_program_3d_draw_screen_circle(
                center,
                3.0,
                .{0.82, 0.85, 0.90, 1},
                14,
            );
            hub_drawn = true;
        }
        windowed_program_3d_draw_view_axis_arm(center, axis_radius, arm);
    }
    if !hub_drawn {
        windowed_program_3d_draw_screen_circle(
            center,
            3.0,
            .{0.82, 0.85, 0.90, 1},
            14,
        );
    }

    if orthographic_projection {
        ui_cmd_text(
            "ORTHO",
            center.x - 21.0,
            center.y + axis_radius + 25.0,
            11.0,
            .{0.78, 0.83, 0.90, 1},
        );
    }
}
