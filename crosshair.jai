// All selectable crosshairs are OBJ files. The nine defaults are generated
// when missing, so the installation need not carry preset OBJ assets.
DEFAULT_CROSSHAIR_FILENAME :: "cross_with_hole.obj";

Crosshair_Settings :: struct {
    enabled := true;
    color: Vector4 = .{0.95, 0.95, 0.95, 0.9};
}

Crosshair_File_State :: struct {
    path: string;
    library: Crosshair_Library;
    selection: s32 = -1;
    geometry: Indexed_Triangle_Positions;
    loaded: bool;
    warned_missing: bool;
}

Crosshair_Monitor_Scale :: struct {
    pixels_per_inch_x: float32;
    pixels_per_inch_y: float32;
    valid: bool;
}

measure_crosshair_monitor_scale :: () -> Crosshair_Monitor_Scale {
    profiles := find_connected_monitor_profiles();
    defer free_monitor_profiles(*profiles);
    if profiles.count == 0 return .{};
    profile := profiles[0];
    if !profile.mode_is_observed || profile.width_mm <= 0 || profile.height_mm <= 0 return .{};
    return .{
        pixels_per_inch_x = cast(float32) profile.mode_width * 25.4 / cast(float32) profile.width_mm,
        pixels_per_inch_y = cast(float32) profile.mode_height * 25.4 / cast(float32) profile.height_mm,
        valid = true,
    };
}

crosshair_monitor_scale_or_fallback :: (monitor: Crosshair_Monitor_Scale) -> Crosshair_Monitor_Scale {
    if monitor.valid return monitor;
    return .{pixels_per_inch_x = 96, pixels_per_inch_y = 96, valid = false};
}

// Older configurations stored a numeric procedural type. Map it to the
// equivalent shipped OBJ once, then persist only the selected filename.
legacy_crosshair_preset_filename :: (old_type: int) -> string {
    if old_type < 0 || old_type >= CROSSHAIR_DEFAULT_COUNT return "";
    return crosshair_default_filename(cast(s32) old_type);
}

make_crosshair_render_geometry :: (itp: Indexed_Triangle_Positions, color: Vector4,
                                   window_width: float32, window_height: float32,
                                   monitor: Crosshair_Monitor_Scale) -> Indexed_Triangle_Positions_Color_Alphas {
    result: Indexed_Triangle_Positions_Color_Alphas;
    if window_width <= 0 || window_height <= 0 return result;
    scale_x := 2.0 * monitor.pixels_per_inch_x / window_width;
    scale_y := 2.0 * monitor.pixels_per_inch_y / window_height;
    for itp.indices array_add(*result.indices, it);
    for p: itp.positions {
        array_add(*result.positions, .{p.x * scale_x, p.y * scale_y, p.z});
        array_add(*result.rgba_colors, color);
    }
    return result;
}

draw_selected_crosshair_preview :: (state: *Crosshair_File_State,
                                    settings: Crosshair_Settings,
                                    monitor_profile: Crosshair_Monitor_Scale,
                                    rect: UI_Rect) {
    ui_cmd_rect(rect, .{0.02, 0.02, 0.025, 0.92});
    ui_cmd_rect_outline(rect, .{0.7, 0.7, 0.75, 0.85});
    if !state.loaded || state.geometry.indices.count == 0 {
        ui_cmd_text("No valid crosshair selected", rect.x + 10, rect.y + rect.h * 0.5,
                    14, .{0.7, 0.7, 0.7, 1});
        return;
    }

    monitor := crosshair_monitor_scale_or_fallback(monitor_profile);
    cx := rect.x + rect.w * 0.5;
    cy := rect.y + rect.h * 0.5;
    ui_cmd_scissor_push(rect);
    ui_cmd_rect_outline(.{cx - monitor.pixels_per_inch_x * 0.5,
                          cy - monitor.pixels_per_inch_y * 0.5,
                          monitor.pixels_per_inch_x, monitor.pixels_per_inch_y},
                        .{0.16, 0.21, 0.25, 1});

    positions := NewArray(state.geometry.positions.count, Vector3,, allocator = temp);
    colors := NewArray(state.geometry.positions.count, Vector4,, allocator = temp);
    for p: state.geometry.positions {
        px := cx + p.x * monitor.pixels_per_inch_x;
        py := cy - p.y * monitor.pixels_per_inch_y;
        positions[it_index] = .{px / ui_ctx.window_w * 2.0 - 1.0,
                                1.0 - py / ui_ctx.window_h * 2.0, 0};
        colors[it_index] = settings.color;
    }
    ui_cmd_geometry(positions, colors, state.geometry.indices);
    ui_cmd_scissor_pop();
}

load_crosshair_file :: (state: *Crosshair_File_State, path: string) {
    if state.geometry.positions.count > 0 || state.geometry.indices.count > 0 {
        deinit(*state.geometry);
    }

    state.loaded = false;
    state.warned_missing = false;
    new_path := copy_string(path);
    if state.path.count > 0 free(state.path);
    state.path = new_path;

    if !file_exists(state.path) return;

    contents, opened := read_entire_file(state.path, log_errors = false);
    if !opened return;
    defer free(contents);
    obj := parse_obj(contents);
    defer deinit(*obj);

    geom := crosshair_obj_to_itp(*obj);
    valid, reason := validate_crosshair_geometry(*geom);
    if !valid {
        print("Invalid crosshair OBJ '%': %\n", state.path, reason);
        deinit(*geom);
        return;
    }

    state.geometry = geom;
    state.loaded = true;
    print("Loaded crosshair OBJ '%'\n", state.path);
}

refresh_crosshair_library :: (state: *Crosshair_File_State,
                              config_path: string, selected_filename: string = "") {
    wanted_source := ifx selected_filename.count > 0 then copy_string(selected_filename)
              else ifx state.path.count > 0 then copy_string(crosshair_obj_filename(state.path))
              else copy_string(DEFAULT_CROSSHAIR_FILENAME);
    defer free(wanted_source);
    wanted := copy_string(crosshair_obj_filename(
        crosshair_obj_path(crosshair_obj_filename(wanted_source))));
    defer free(wanted);
    free_crosshair_library(*state.library);
    state.library = scan_crosshair_library();
    legacy := crosshair_path_next_to_config(config_path);
    if file_exists(legacy) array_add(*state.library.paths, copy_string(legacy));

    state.selection = -1;
    for i: 0..state.library.paths.count - 1 {
        if crosshair_obj_filename(state.library.paths[i]) == wanted {
            state.selection = cast(s32) i;
            break;
        }
    }
    if state.selection < 0 && state.library.paths.count > 0 state.selection = 0;
    if state.selection >= 0 {
        load_crosshair_file(state, state.library.paths[state.selection]);
    } else {
        if state.path.count > 0 free(state.path);
        state.path = "";
        if state.geometry.positions.count > 0 || state.geometry.indices.count > 0 deinit(*state.geometry);
        state.loaded = false;
    }
}

crosshair_color_from_selected_file :: (state: Crosshair_File_State) -> Vector4 {
    fallback := Vector4.{0.95, 0.95, 0.95, 0.9};
    if !state.loaded return fallback;
    return read_crosshair_obj_color(state.path, fallback);
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

            valid_face := true;
            for *fv: face.face_vertices {
                if fv.position_index < 0 || fv.position_index >= obj.all_positions.count {
                    valid_face = false;
                    break;
                }
            }
            if !valid_face {
                deinit(*result);
                return .{};
            }

            first_index := current_index;
            for *fv: face.face_vertices {
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
    if !wp.crosshair_file.loaded {
        if !wp.crosshair_file.warned_missing {
            print("No valid crosshair OBJ is selected.\n");
            wp.crosshair_file.warned_missing = true;
        }
        return;
    }

    monitor := crosshair_monitor_scale_or_fallback(wp.crosshair_monitor);
    rendered := make_crosshair_render_geometry(wp.crosshair_file.geometry,
                                                wp.crosshair_settings.color,
                                                cast(float32) wp.window_width,
                                                cast(float32) wp.window_height,
                                                monitor);
    defer deinit(*rendered);

    depth_test_was_enabled := glIsEnabled(GL_DEPTH_TEST);
    cull_was_enabled := glIsEnabled(GL_CULL_FACE);
    depth_write_was_enabled: GLboolean;
    glGetBooleanv(GL_DEPTH_WRITEMASK, *depth_write_was_enabled);

    glDisable(GL_DEPTH_TEST);
    glDisable(GL_CULL_FACE);
    glDepthMask(GL_FALSE);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    set_active_program(wp.absolute_position_color_alpha_renderer);
    // OBJ positions are converted to framebuffer NDC, so no additional
    // aspect-ratio correction belongs in the shader.
    set_aspect_ratio_uniform(*wp.absolute_position_color_alpha_renderer, .{1.0, 1.0});
    immediate_render(*wp.absolute_position_color_alpha_renderer, rendered);
    clear_active_program();

    if depth_test_was_enabled glEnable(GL_DEPTH_TEST);
    else glDisable(GL_DEPTH_TEST);
    glDepthMask(depth_write_was_enabled);
    if cull_was_enabled glEnable(GL_CULL_FACE);
    else glDisable(GL_CULL_FACE);
}
