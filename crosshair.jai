Crosshair_Type :: enum {
    DOT;
    CROSS;
    X;
    CROSS_MISSING_TOP;
    CROSS_WITH_HOLE;
    X_WITH_HOLE;
    UPWARD_CARET;
    CROSS_MISSING_TOP_BOTTOM_WITH_HOLE;
    RING;
    CUSTOM;
}

Crosshair_Settings :: struct {
    enabled := true;
    kind := Crosshair_Type.CROSS_WITH_HOLE;
    color: Vector4 = .{0.95, 0.95, 0.95, 0.9};
    size: float32 = 1.0;
}

Crosshair_Custom_State :: struct {
    path: string;
    geometry: Indexed_Triangle_Positions;
    loaded: bool;
    warned_missing: bool;
}

Crosshair_Preview_State :: struct {
    visible: bool;
    rect: UI_Rect;
}

CROSSHAIR_BASE_NDC_SIZE :: 0.1;

crosshair_type_labels :: () -> [] string {
    return string.[
        "Dot",
        "Cross",
        "X",
        "Cross missing top",
        "Cross with hole",
        "X with hole",
        "Upward caret",
        "Cross missing top/bottom with hole",
        "Ring",
        "Custom OBJ",
    ];
}

create_crosshair_geometry :: (kind: Crosshair_Type) -> Indexed_Triangle_Positions {
    result: Indexed_Triangle_Positions;

    if kind == {
        case .DOT;
            result = create_circle(.{0, 0, 0}, .{0, 0, 1}, 0.065, 24);

        case .CROSS;
            append_crosshair_cross_solid(*result, 0.39, 0.11, 0.0);

        case .X;
            append_crosshair_cross_solid(*result, 0.39, 0.11, PI * 0.25);

        case .CROSS_MISSING_TOP;
            append_crosshair_cross_with_gap(*result, 0.055, 0.39, 0.11, true, false, false, false, 0.0);
            append_crosshair_center_cap(*result, 0.11, 0.0);

        case .CROSS_WITH_HOLE;
            append_crosshair_cross_with_gap(*result, 0.17, 0.43, 0.10, false, false, false, false, 0.0);

        case .X_WITH_HOLE;
            append_crosshair_cross_with_gap(*result, 0.17, 0.43, 0.10, false, false, false, false, PI * 0.25);

        case .UPWARD_CARET;
            append_crosshair_segment(*result, .{-0.055, -0.055}, .{-0.34, -0.34}, 0.10);
            append_crosshair_segment(*result, .{ 0.055, -0.055}, .{ 0.34, -0.34}, 0.10);

        case .CROSS_MISSING_TOP_BOTTOM_WITH_HOLE;
            append_crosshair_cross_with_gap(*result, 0.17, 0.43, 0.10, true, true, false, false, 0.0);

        case .RING;
            result = create_annulus(.{0, 0, 0}, .{0, 0, 1}, 0.30, 0.42, 48);

        case .CUSTOM;
            // Custom geometry is loaded and validated separately.
    }

    return result;
}

append_crosshair_cross_solid :: (result: *Indexed_Triangle_Positions, outer: float, thickness: float, rotation: float) {
    inner := thickness * 0.5;
    append_crosshair_cross_with_gap(result, inner, outer, thickness, false, false, false, false, rotation);
    append_crosshair_center_cap(result, thickness, rotation);
}

append_crosshair_center_cap :: (result: *Indexed_Triangle_Positions, size: float, rotation: float) {
    h := size * 0.5;
    append_crosshair_polygon(result, Vector2.[
        rotate2(.{-h, -h}, rotation),
        rotate2(.{ h, -h}, rotation),
        rotate2(.{ h,  h}, rotation),
        rotate2(.{-h,  h}, rotation),
    ]);
}

append_crosshair_polygon :: (result: *Indexed_Triangle_Positions, points: [] Vector2) {
    if points.count < 3 return;

    base := cast(u32) result.positions.count;
    for p: points array_add(*result.positions, .{p.x, p.y, 0});

    for i: 1..points.count - 2 {
        array_add(*result.indices, base);
        array_add(*result.indices, base + cast(u32) i);
        array_add(*result.indices, base + cast(u32)(i + 1));
    }
}

append_crosshair_cross_with_gap :: (
    result: *Indexed_Triangle_Positions,
    inner: float,
    outer: float,
    thickness: float,
    skip_up: bool,
    skip_down: bool,
    skip_left: bool,
    skip_right: bool,
    rotation: float
) {
    if !skip_right append_crosshair_segment(result, rotate2(.{inner, 0}, rotation), rotate2(.{outer, 0}, rotation), thickness);
    if !skip_left  append_crosshair_segment(result, rotate2(.{-inner, 0}, rotation), rotate2(.{-outer, 0}, rotation), thickness);
    if !skip_up    append_crosshair_segment(result, rotate2(.{0, inner}, rotation), rotate2(.{0, outer}, rotation), thickness);
    if !skip_down  append_crosshair_segment(result, rotate2(.{0, -inner}, rotation), rotate2(.{0, -outer}, rotation), thickness);
}

append_crosshair_beam :: (result: *Indexed_Triangle_Positions, cx: float, cy: float, length_: float, thickness: float, rotation: float) {
    a := rotate2(.{-length_ * 0.5, 0}, rotation) + .{cx, cy};
    b := rotate2(.{ length_ * 0.5, 0}, rotation) + .{cx, cy};
    append_crosshair_segment(result, a, b, thickness);
}

append_crosshair_segment :: (result: *Indexed_Triangle_Positions, a: Vector2, b: Vector2, thickness: float) {
    dir := b - a;
    len := length(dir);
    if len <= 0.0001 return;

    n := Vector2.{-dir.y / len, dir.x / len} * (thickness * 0.5);
    base := cast(u32) result.positions.count;

    array_add(*result.positions, .{a.x + n.x, a.y + n.y, 0});
    array_add(*result.positions, .{a.x - n.x, a.y - n.y, 0});
    array_add(*result.positions, .{b.x - n.x, b.y - n.y, 0});
    array_add(*result.positions, .{b.x + n.x, b.y + n.y, 0});

    array_add(*result.indices, base + 0);
    array_add(*result.indices, base + 1);
    array_add(*result.indices, base + 2);
    array_add(*result.indices, base + 0);
    array_add(*result.indices, base + 2);
    array_add(*result.indices, base + 3);
}

rotate2 :: (v: Vector2, angle: float) -> Vector2 {
    c := cos(angle);
    s := sin(angle);
    return .{v.x * c - v.y * s, v.x * s + v.y * c};
}

make_crosshair_render_geometry :: (itp: Indexed_Triangle_Positions, color: Vector4, size: float32) -> Indexed_Triangle_Positions_Color_Alphas {
    result: Indexed_Triangle_Positions_Color_Alphas;
    scale := CROSSHAIR_BASE_NDC_SIZE * size;

    array_reserve(*result.indices, itp.indices.count);
    array_reserve(*result.positions, itp.positions.count);
    array_reserve(*result.rgba_colors, itp.positions.count);

    for itp.indices array_add(*result.indices, it);
    for p: itp.positions {
        array_add(*result.positions, .{p.x * scale, p.y * scale, p.z});
        array_add(*result.rgba_colors, color);
    }

    return result;
}

make_crosshair_preview_geometry :: (itp: Indexed_Triangle_Positions, color: Vector4, size: float32, preview: UI_Rect) -> Indexed_Triangle_Positions_Color_Alphas {
    result: Indexed_Triangle_Positions_Color_Alphas;

    pixel_scale := min(ui_ctx.window_w, ui_ctx.window_h) * CROSSHAIR_BASE_NDC_SIZE * size;
    cx := preview.x + preview.w * 0.5;
    cy := preview.y + preview.h * 0.5;

    array_reserve(*result.indices, itp.indices.count);
    array_reserve(*result.positions, itp.positions.count);
    array_reserve(*result.rgba_colors, itp.positions.count);

    for itp.indices array_add(*result.indices, it);
    for p: itp.positions {
        px := cx + p.x * pixel_scale;
        py := cy - p.y * pixel_scale;
        ndc_x := (px / ui_ctx.window_w) * 2.0 - 1.0;
        ndc_y := -((py / ui_ctx.window_h) * 2.0 - 1.0);
        array_add(*result.positions, .{ndc_x, ndc_y, 0});
        array_add(*result.rgba_colors, color);
    }

    return result;
}

load_custom_crosshair :: (state: *Crosshair_Custom_State, config_path: string) {
    if state.geometry.positions.count > 0 || state.geometry.indices.count > 0 {
        deinit(*state.geometry);
    }

    state.loaded = false;
    state.warned_missing = false;
    state.path = crosshair_path_next_to_config(config_path);

    if !asset_exists(state.path) return;

    obj := load_obj(state.path);
    defer deinit(*obj);

    geom := crosshair_obj_to_itp(*obj);
    valid, reason := validate_crosshair_geometry(*geom);
    if !valid {
        print("Invalid custom crosshair '%': %\n", state.path, reason);
        deinit(*geom);
        return;
    }

    state.geometry = geom;
    state.loaded = true;
    print("Loaded custom crosshair '%'\n", state.path);
}

crosshair_path_next_to_config :: (config_path: string) -> string {
    normalized := copy_temporary_string(config_path);
    normalize_slashes(normalized);

    last_slash := -1;
    for i: 0..normalized.count - 1 {
        if normalized[i] == #char "/" last_slash = i;
    }

    if last_slash < 0 return "crosshair.obj";

    directory: string;
    directory.data = normalized.data;
    directory.count = last_slash;
    return tprint("%/crosshair.obj", directory);
}

crosshair_obj_to_itp :: (obj: *Obj_Data) -> Indexed_Triangle_Positions {
    result: Indexed_Triangle_Positions;
    current_index: u32 = 0;

    for *object: obj.all_objects {
        for *face: object.faces {
            if face.face_vertices.count < 3 continue;

            first_index := current_index;
            for *fv: face.face_vertices {
                if fv.position_index < 0 || fv.position_index >= obj.all_positions.count continue;
                array_add(*result.positions, obj.all_positions[fv.position_index]);
                current_index += 1;
            }

            append_triangulated_polygon_indices(*result.indices, result.positions, first_index, face.face_vertices.count);
        }
    }

    return result;
}

validate_crosshair_geometry :: (itp: *Indexed_Triangle_Positions) -> bool, string {
    if itp.positions.count == 0 return false, "no vertices were found";
    if itp.indices.count == 0 return false, "no triangles were found";

    eps := 0.001;
    for p: itp.positions {
        if abs(p.z) > eps return false, "vertices must lie on the z=0 plane";
        if p.x < -0.5 - eps || p.x > 0.5 + eps || p.y < -0.5 - eps || p.y > 0.5 + eps {
            return false, "vertices must fit inside the unit square [-0.5, 0.5] on x/y";
        }
    }

    for idx: itp.indices {
        if idx >= itp.positions.count return false, "triangle index references a missing vertex";
    }

    return true, "";
}

render_crosshair :: (wp: *Windowed_Program) {
    if !wp.crosshair_settings.enabled return;

    source: Indexed_Triangle_Positions;
    use_custom := wp.crosshair_settings.kind == .CUSTOM;
    source_is_owned := !use_custom;

    if use_custom {
        if wp.crosshair_custom.loaded {
            source = wp.crosshair_custom.geometry;
        } else {
            if !wp.crosshair_custom.warned_missing {
                print("Custom crosshair selected, but no valid '%' was loaded.\n", wp.crosshair_custom.path);
                wp.crosshair_custom.warned_missing = true;
            }
            source = create_crosshair_geometry(.CROSS_WITH_HOLE);
            source_is_owned = true;
        }
    } else {
        source = create_crosshair_geometry(wp.crosshair_settings.kind);
    }

    if source.indices.count == 0 || source.positions.count == 0 return;

    rendered := make_crosshair_render_geometry(source, wp.crosshair_settings.color, wp.crosshair_settings.size);
    defer {
        if source_is_owned deinit(*source);
        deinit(*rendered);
    }

    depth_test_was_enabled := glIsEnabled(GL_DEPTH_TEST);
    depth_write_was_enabled: GLboolean;
    glGetBooleanv(GL_DEPTH_WRITEMASK, *depth_write_was_enabled);

    glDisable(GL_DEPTH_TEST);
    glDepthMask(GL_FALSE);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    set_active_program(wp.absolute_position_color_alpha_renderer);
    set_aspect_ratio_uniform(*wp.absolute_position_color_alpha_renderer, get_window_dimensions_vector(wp));
    immediate_render(*wp.absolute_position_color_alpha_renderer, rendered);
    clear_active_program();

    if depth_test_was_enabled {
        glEnable(GL_DEPTH_TEST);
    } else {
        glDisable(GL_DEPTH_TEST);
    }
    glDepthMask(depth_write_was_enabled);
}

set_crosshair_preview_rect :: (wp: *Windowed_Program, rect: UI_Rect) {
    wp.crosshair_preview.visible = true;
    wp.crosshair_preview.rect = rect;
}

render_crosshair_preview :: (wp: *Windowed_Program) {
    if !wp.crosshair_preview.visible return;
    defer wp.crosshair_preview.visible = false;

    source: Indexed_Triangle_Positions;
    use_custom := wp.crosshair_settings.kind == .CUSTOM;
    source_is_owned := !use_custom;

    if use_custom && wp.crosshair_custom.loaded {
        source = wp.crosshair_custom.geometry;
    } else if use_custom {
        source = create_crosshair_geometry(.CROSS_WITH_HOLE);
        source_is_owned = true;
    } else {
        source = create_crosshair_geometry(wp.crosshair_settings.kind);
    }

    if source.indices.count == 0 || source.positions.count == 0 return;

    rendered := make_crosshair_preview_geometry(source, wp.crosshair_settings.color, wp.crosshair_settings.size, wp.crosshair_preview.rect);
    defer {
        if source_is_owned deinit(*source);
        deinit(*rendered);
    }

    depth_test_was_enabled := glIsEnabled(GL_DEPTH_TEST);
    depth_write_was_enabled: GLboolean;
    glGetBooleanv(GL_DEPTH_WRITEMASK, *depth_write_was_enabled);

    glDisable(GL_DEPTH_TEST);
    glDepthMask(GL_FALSE);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    set_active_program(wp.absolute_position_color_alpha_renderer);
    set_aspect_ratio_uniform(*wp.absolute_position_color_alpha_renderer, .{1.0, 1.0});
    immediate_render(*wp.absolute_position_color_alpha_renderer, rendered);
    clear_active_program();

    if depth_test_was_enabled {
        glEnable(GL_DEPTH_TEST);
    } else {
        glDisable(GL_DEPTH_TEST);
    }
    glDepthMask(depth_write_was_enabled);
}
