WINDOWED_PROGRAM_3D_NO_OBJECT_ID :: 0;

Windowed_Program_3D_Editor_Permissions :: enum_flags u8 {
    NONE          :: 0;
    SELECTABLE    :: 1;
    TRANSFORMABLE :: 2;
    ALL           :: SELECTABLE | TRANSFORMABLE;
}

windowed_program_3d_has_editor_permission :: (
    permissions: Windowed_Program_3D_Editor_Permissions,
    permission: Windowed_Program_3D_Editor_Permissions,
) -> bool {
    return cast(bool)(permissions & permission);
}

Windowed_Program_3D_Pickable_Geometry :: struct {
    indices: [..] u32;
    positions: [..] Vector3;
}

Windowed_Program_3D_Skeletal_Pickable_Geometry :: struct {
    indices: [..] u32;
    positions: [..] Vector3;
    bone_transform_indices: [..] [4] u32;
    bone_weights: [..] [4] float32;
}

Windowed_Program_3D_Pickable :: struct {
    object_id: u32;
    editor_permissions: Windowed_Program_3D_Editor_Permissions;
    mesh: Camera_Per_Object_Transform_Selection_Depth_Renderable;
    local_to_world: Matrix4 = Matrix4_Identity;
    local_bounds_min: Vector3;
    local_bounds_max: Vector3;
    local_bounds_valid: bool;

    /*
    we store this data because we want to allow picking on animated things
    but then the shader doesn't accept in bone things yet so we do a cpu side and rebuffer
    which is really bad but works for now I guess.
    */
    bind_positions: [..] Vector3;
    bone_transform_indices: [..] [4] u32;
    bone_weights: [..] [4] float32;
}

Windowed_Program_3D_Picker :: struct {
    scene_depth_framebuffer_gl_handle: GLuint;
    selected_depth_framebuffer_gl_handle: GLuint;
    selected_depth_texture_gl_handle: GLuint;
    scene_depth_texture_gl_handle: GLuint;
    width: u32;
    height: u32;
    scene_depth_framebuffer_complete: bool;
    selected_depth_framebuffer_complete: bool;

    selected_depth_renderer: Camera_Per_Object_Transform_Selection_Depth_Renderer;
    outline_renderer: Object_Id_Selection_Outline_Renderer;
    outline_vao_gl_handle: GLuint;

    pickables: [..] Windowed_Program_3D_Pickable;
    next_object_id: u32 = 1;
}

update_pickable_local_bounds :: (pickable: *Windowed_Program_3D_Pickable) {
    positions := pickable.mesh.positions;
    if positions.count == 0 {
        pickable.local_bounds_valid = false;
        return;
    }

    bounds_min := positions[0];
    bounds_max := positions[0];
    for position: positions {
        bounds_min.x = min(bounds_min.x, position.x);
        bounds_min.y = min(bounds_min.y, position.y);
        bounds_min.z = min(bounds_min.z, position.z);
        bounds_max.x = max(bounds_max.x, position.x);
        bounds_max.y = max(bounds_max.y, position.y);
        bounds_max.z = max(bounds_max.z, position.z);
    }
    pickable.local_bounds_min = bounds_min;
    pickable.local_bounds_max = bounds_max;
    pickable.local_bounds_valid = true;
}

resize :: (using picker: *Windowed_Program_3D_Picker, new_width: u32, new_height: u32) -> bool {
    if new_width == 0 || new_height == 0 return false;
    if scene_depth_framebuffer_complete && selected_depth_framebuffer_complete &&
       width == new_width && height == new_height return true;

    width = new_width;
    height = new_height;

    glBindTexture(GL_TEXTURE_2D, scene_depth_texture_gl_handle);
    glTexImage2D(
        GL_TEXTURE_2D,
        0,
        GL_DEPTH_COMPONENT32F,
        xx width,
        xx height,
        0,
        GL_DEPTH_COMPONENT,
        GL_FLOAT,
        null,
    );

    glBindTexture(GL_TEXTURE_2D, selected_depth_texture_gl_handle);
    glTexImage2D(
        GL_TEXTURE_2D,
        0,
        GL_DEPTH_COMPONENT32F,
        xx width,
        xx height,
        0,
        GL_DEPTH_COMPONENT,
        GL_FLOAT,
        null,
    );

    glBindFramebuffer(GL_FRAMEBUFFER, scene_depth_framebuffer_gl_handle);
    glFramebufferTexture2D(
        GL_FRAMEBUFFER,
        GL_DEPTH_ATTACHMENT,
        GL_TEXTURE_2D,
        scene_depth_texture_gl_handle,
        0,
    );
    glDrawBuffer(GL_NONE);
    glReadBuffer(GL_NONE);

    scene_status := glCheckFramebufferStatus(GL_FRAMEBUFFER);
    scene_depth_framebuffer_complete = scene_status == GL_FRAMEBUFFER_COMPLETE;
    if !scene_depth_framebuffer_complete {
        log_error("Windowed Program 3D scene-depth framebuffer incomplete, status: 0x%", formatInt(scene_status, base = 16));
    }

    glBindFramebuffer(GL_FRAMEBUFFER, selected_depth_framebuffer_gl_handle);
    glFramebufferTexture2D(
        GL_FRAMEBUFFER,
        GL_DEPTH_ATTACHMENT,
        GL_TEXTURE_2D,
        selected_depth_texture_gl_handle,
        0,
    );
    glDrawBuffer(GL_NONE);
    glReadBuffer(GL_NONE);

    status := glCheckFramebufferStatus(GL_FRAMEBUFFER);
    selected_depth_framebuffer_complete = status == GL_FRAMEBUFFER_COMPLETE;
    if !selected_depth_framebuffer_complete {
        log_error("Windowed Program 3D selection-depth framebuffer incomplete, status: 0x%", formatInt(status, base = 16));
    } else {
        glDepthMask(GL_TRUE);
        glClear(GL_DEPTH_BUFFER_BIT);
    }

    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glBindTexture(GL_TEXTURE_2D, 0);
    return scene_depth_framebuffer_complete && selected_depth_framebuffer_complete;
}

init :: (
    using picker: *Windowed_Program_3D_Picker,
    initial_width: u32,
    initial_height: u32,
) -> bool {
    init(*selected_depth_renderer);
    init(*outline_renderer);
    glGenVertexArrays(1, *outline_vao_gl_handle);

    glGenFramebuffers(1, *scene_depth_framebuffer_gl_handle);
    glGenFramebuffers(1, *selected_depth_framebuffer_gl_handle);

    glGenTextures(1, *scene_depth_texture_gl_handle);
    glBindTexture(GL_TEXTURE_2D, scene_depth_texture_gl_handle);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    glGenTextures(1, *selected_depth_texture_gl_handle);
    glBindTexture(GL_TEXTURE_2D, selected_depth_texture_gl_handle);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glBindTexture(GL_TEXTURE_2D, 0);

    return resize(picker, initial_width, initial_height);
}

deinit :: (using picker: *Windowed_Program_3D_Picker) {
    for *pickable: pickables {
        deinit(*pickable.mesh, *selected_depth_renderer);
        array_free(pickable.bind_positions);
        array_free(pickable.bone_transform_indices);
        array_free(pickable.bone_weights);
    }
    array_free(pickables);

    if outline_vao_gl_handle != 0 glDeleteVertexArrays(1, *outline_vao_gl_handle);
    deinit(*outline_renderer);
    deinit(*selected_depth_renderer);

    if selected_depth_texture_gl_handle != 0 glDeleteTextures(1, *selected_depth_texture_gl_handle);
    if scene_depth_texture_gl_handle != 0 glDeleteTextures(1, *scene_depth_texture_gl_handle);
    if selected_depth_framebuffer_gl_handle != 0 glDeleteFramebuffers(1, *selected_depth_framebuffer_gl_handle);
    if scene_depth_framebuffer_gl_handle != 0 glDeleteFramebuffers(1, *scene_depth_framebuffer_gl_handle);
    picker.* = .{};
}

add_pickable :: (
    using picker: *Windowed_Program_3D_Picker,
    geometry: $T/interface Windowed_Program_3D_Pickable_Geometry,
    local_to_world: Matrix4,
    editor_permissions: Windowed_Program_3D_Editor_Permissions = .ALL,
) -> u32 {
    object_id := next_object_id;

    pickable: Windowed_Program_3D_Pickable;
    pickable.object_id = object_id;
    pickable.editor_permissions = editor_permissions;
    pickable.local_to_world = local_to_world;
    array_copy(*pickable.mesh.indices, geometry.indices);
    array_copy(*pickable.mesh.positions, geometry.positions);
    update_pickable_local_bounds(*pickable);

    if !buffer_object(*selected_depth_renderer, *pickable.mesh) {
        deinit(*pickable.mesh);
        return WINDOWED_PROGRAM_3D_NO_OBJECT_ID;
    }

    set_local_to_world_matrix(*selected_depth_renderer, pickable.mesh, local_to_world);
    array_add(*pickables, pickable);
    next_object_id += 1;
    return object_id;
}

add_skeletal_pickable :: (
    picker: *Windowed_Program_3D_Picker,
    geometry: $T/interface Windowed_Program_3D_Skeletal_Pickable_Geometry,
    local_to_world: Matrix4,
    editor_permissions: Windowed_Program_3D_Editor_Permissions = .ALL,
) -> u32 {
    object_id := add_pickable(picker, geometry, local_to_world, editor_permissions);
    if object_id == WINDOWED_PROGRAM_3D_NO_OBJECT_ID return object_id;

    pickable := *picker.pickables[picker.pickables.count - 1];
    array_copy(*pickable.bind_positions, geometry.positions);
    array_copy(*pickable.bone_transform_indices, geometry.bone_transform_indices);
    array_copy(*pickable.bone_weights, geometry.bone_weights);
    return object_id;
}

remove_pickable :: (
    using picker: *Windowed_Program_3D_Picker,
    object_id: u32,
) -> bool {
    if object_id == WINDOWED_PROGRAM_3D_NO_OBJECT_ID return false;

    for *pickable, index: pickables {
        if pickable.object_id != object_id continue;

        deinit(*pickable.mesh, *selected_depth_renderer);
        array_free(pickable.bind_positions);
        array_free(pickable.bone_transform_indices);
        array_free(pickable.bone_weights);
        array_ordered_remove_by_index(*pickables, index);
        return true;
    }
    return false;
}

update_skeletal_pickables :: (
    using picker: *Windowed_Program_3D_Picker,
    bone_transforms: [] Matrix4,
) {
    for *pickable: pickables {
        if pickable.bind_positions.count == 0 continue;

        vertex_count := min(
            pickable.bind_positions.count,
            min(pickable.bone_transform_indices.count, pickable.bone_weights.count),
        );
        for vertex_index: 0..vertex_count - 1 {
            bind_position := pickable.bind_positions[vertex_index];
            bind_position_4 := Vector4.{bind_position.x, bind_position.y, bind_position.z, 1.0};
            skinned_position: Vector4;
            total_weight: float32;

            for influence_index: 0..3 {
                bone_index := pickable.bone_transform_indices[vertex_index][influence_index];
                weight := pickable.bone_weights[vertex_index][influence_index];
                if bone_index >= bone_transforms.count || weight <= 0 continue;
                skinned_position += (bone_transforms[bone_index] * bind_position_4) * weight;
                total_weight += weight;
            }

            if total_weight == 0 {
                pickable.mesh.positions[vertex_index] = bind_position;
            } else {
                pickable.mesh.positions[vertex_index] = .{
                    skinned_position.x,
                    skinned_position.y,
                    skinned_position.z,
                };
            }
        }
        update_pickable_local_bounds(pickable);
        rebuffer_object(*selected_depth_renderer, pickable.mesh);
    }
}

set_pickable_transform :: (
    using picker: *Windowed_Program_3D_Picker,
    object_id: u32,
    local_to_world: Matrix4,
) -> bool {
    if object_id == WINDOWED_PROGRAM_3D_NO_OBJECT_ID return false;
    for *pickable: pickables {
        if pickable.object_id == object_id {
            pickable.local_to_world = local_to_world;
            set_local_to_world_matrix(*selected_depth_renderer, pickable.mesh, local_to_world);
            return true;
        }
    }
    return false;
}

get_pickable_transform :: (
    using picker: *Windowed_Program_3D_Picker,
    object_id: u32,
) -> (local_to_world: Matrix4, found: bool) {
    if object_id == WINDOWED_PROGRAM_3D_NO_OBJECT_ID return Matrix4_Identity, false;
    for pickable: pickables {
        if pickable.object_id == object_id return pickable.local_to_world, true;
    }
    return Matrix4_Identity, false;
}

get_pickable_editor_permissions :: (
    using picker: *Windowed_Program_3D_Picker,
    object_id: u32,
) -> (permissions: Windowed_Program_3D_Editor_Permissions, found: bool) {
    if object_id == WINDOWED_PROGRAM_3D_NO_OBJECT_ID return .NONE, false;
    for pickable: pickables {
        if pickable.object_id == object_id return pickable.editor_permissions, true;
    }
    return .NONE, false;
}

set_pickable_editor_permissions :: (
    using picker: *Windowed_Program_3D_Picker,
    object_id: u32,
    editor_permissions: Windowed_Program_3D_Editor_Permissions,
) -> bool {
    if object_id == WINDOWED_PROGRAM_3D_NO_OBJECT_ID return false;
    for *pickable: pickables {
        if pickable.object_id != object_id continue;

        pickable.editor_permissions = editor_permissions;
        return true;
    }
    return false;
}

pickable_is_transformable :: (
    picker: *Windowed_Program_3D_Picker,
    object_id: u32,
) -> bool {
    permissions, found := get_pickable_editor_permissions(picker, object_id);
    return found && windowed_program_3d_has_editor_permission(permissions, .TRANSFORMABLE);
}

Windowed_Program_3D_Pick_Hit :: struct {
    object_id: u32;
    distance: float32;
    editor_permissions: Windowed_Program_3D_Editor_Permissions;
}

windowed_program_3d_ray_intersects_bounds :: (
    ray_origin: Vector3,
    ray_direction: Vector3,
    bounds_min: Vector3,
    bounds_max: Vector3,
) -> bool {
    minimum_distance: float32 = 0;
    maximum_distance: float32 = FLOAT32_MAX;
    for axis: 0..2 {
        origin := ray_origin.component[axis];
        direction := ray_direction.component[axis];
        minimum := bounds_min.component[axis];
        maximum := bounds_max.component[axis];

        if abs(direction) <= 0.0000001 {
            if origin < minimum || origin > maximum return false;
            continue;
        }

        inverse_direction := 1.0 / direction;
        entry := (minimum - origin) * inverse_direction;
        exit := (maximum - origin) * inverse_direction;
        if entry > exit swap(*entry, *exit);
        minimum_distance = max(minimum_distance, entry);
        maximum_distance = min(maximum_distance, exit);
        if maximum_distance < minimum_distance return false;
    }
    return maximum_distance >= 0;
}

windowed_program_3d_ray_triangle_distance :: (
    ray_origin: Vector3,
    ray_direction: Vector3,
    a: Vector3,
    b: Vector3,
    c: Vector3,
) -> (distance: float32, hit: bool) {
    edge_ab := b - a;
    edge_ac := c - a;
    perpendicular := cross(ray_direction, edge_ac);
    determinant := dot(edge_ab, perpendicular);
    if abs(determinant) <= 0.0000001 return 0, false;

    inverse_determinant := 1.0 / determinant;
    origin_to_a := ray_origin - a;
    u := dot(origin_to_a, perpendicular) * inverse_determinant;
    if u < 0 || u > 1 return 0, false;

    q := cross(origin_to_a, edge_ab);
    v := dot(ray_direction, q) * inverse_determinant;
    if v < 0 || u + v > 1 return 0, false;

    ray_distance := dot(edge_ac, q) * inverse_determinant;
    return ray_distance, ray_distance >= 0;
}

pick_all :: (
    using picker: *Windowed_Program_3D_Picker,
    ray_origin: Vector3,
    ray_direction: Vector3,
    hits: *[..] Windowed_Program_3D_Pick_Hit,
) {
    array_resize(hits, 0);

    for pickable: pickables {
        inverse_ok, world_to_local := inverse(pickable.local_to_world);
        if !inverse_ok || !pickable.local_bounds_valid continue;

        local_origin_4 := world_to_local * Vector4.{ray_origin.x, ray_origin.y, ray_origin.z, 1};
        local_direction_4 := world_to_local * Vector4.{ray_direction.x, ray_direction.y, ray_direction.z, 0};
        local_origin := Vector3.{local_origin_4.x, local_origin_4.y, local_origin_4.z};
        local_direction := Vector3.{local_direction_4.x, local_direction_4.y, local_direction_4.z};
        if length_squared(local_direction) <= 0.0000001 continue;
        if !windowed_program_3d_ray_intersects_bounds(
            local_origin,
            local_direction,
            pickable.local_bounds_min,
            pickable.local_bounds_max,
        ) continue;

        closest_distance: float32 = FLOAT32_MAX;
        positions := pickable.mesh.positions;
        indices := pickable.mesh.indices;
        triangle_count := indices.count / 3;
        if triangle_count > 0 {
            for triangle_index: 0..triangle_count - 1 {
                index_a := indices[triangle_index * 3 + 0];
                index_b := indices[triangle_index * 3 + 1];
                index_c := indices[triangle_index * 3 + 2];
                if index_a >= positions.count || index_b >= positions.count || index_c >= positions.count continue;

                distance, hit := windowed_program_3d_ray_triangle_distance(
                    local_origin,
                    local_direction,
                    positions[index_a],
                    positions[index_b],
                    positions[index_c],
                );
                if hit && distance < closest_distance closest_distance = distance;
            }
        }

        if closest_distance < FLOAT32_MAX {
            array_add(hits, .{
                object_id = pickable.object_id,
                distance = closest_distance,
                editor_permissions = pickable.editor_permissions,
            });
        }
    }

    if hits.count > 1 {
        for i: 0..hits.count - 2 {
            for j: i + 1..hits.count - 1 {
                if hits.*[j].distance < hits.*[i].distance swap(*hits.*[i], *hits.*[j]);
            }
        }
    }

    selectable_hit_count: s64;
    for hit: hits.* {
        if !windowed_program_3d_has_editor_permission(hit.editor_permissions, .SELECTABLE) break;
        hits.*[selectable_hit_count] = hit;
        selectable_hit_count += 1;
    }
    array_resize(hits, selectable_hit_count);
}

windowed_program_3d_project_to_screen :: (
    local_position: Vector3,
    local_to_world: Matrix4,
    world_to_camera: Matrix4,
    camera_to_clip: Matrix4,
    viewport_width: s32,
    viewport_height: s32,
) -> (screen: Vector2, ndc_depth: float32, ok: bool) {
    clip := camera_to_clip
        * world_to_camera
        * local_to_world
        * Vector4.{local_position.x, local_position.y, local_position.z, 1};
    if clip.w <= 0.000001 return .{}, 0, false;

    ndc := clip / clip.w;
    screen_position := Vector2.{
        (ndc.x + 1.0) * 0.5 * cast(float32) viewport_width,
        (ndc.y + 1.0) * 0.5 * cast(float32) viewport_height,
    };
    return screen_position, ndc.z, true;
}

windowed_program_3d_projected_triangle_overlaps_rectangle :: (
    a: Vector2,
    b: Vector2,
    c: Vector2,
    rectangle_min: Vector2,
    rectangle_max: Vector2,
) -> bool {
    triangle_min := Vector2.{min(a.x, min(b.x, c.x)), min(a.y, min(b.y, c.y))};
    triangle_max := Vector2.{max(a.x, max(b.x, c.x)), max(a.y, max(b.y, c.y))};
    if triangle_max.x < rectangle_min.x || triangle_min.x > rectangle_max.x ||
       triangle_max.y < rectangle_min.y || triangle_min.y > rectangle_max.y return false;

    rectangle_corners := Vector2.[
        .{rectangle_min.x, rectangle_min.y},
        .{rectangle_max.x, rectangle_min.y},
        .{rectangle_max.x, rectangle_max.y},
        .{rectangle_min.x, rectangle_max.y},
    ];
    triangle := Vector2.[a, b, c];

    /*
    x and Y were tested by the bounding boxes above. The remaining SAT
    axes are the normals of the triangle's three edges.
    */
    for edge_index: 0..2 {
        edge := triangle[(edge_index + 1) % 3] - triangle[edge_index];
        axis := Vector2.{-edge.y, edge.x};
        if length_squared(axis) <= 0.000001 continue;

        triangle_projection_min := dot(axis, triangle[0]);
        triangle_projection_max := triangle_projection_min;
        for vertex_index: 1..2 {
            projection := dot(axis, triangle[vertex_index]);
            triangle_projection_min = min(triangle_projection_min, projection);
            triangle_projection_max = max(triangle_projection_max, projection);
        }

        rectangle_projection_min := dot(axis, rectangle_corners[0]);
        rectangle_projection_max := rectangle_projection_min;
        for corner_index: 1..3 {
            projection := dot(axis, rectangle_corners[corner_index]);
            rectangle_projection_min = min(rectangle_projection_min, projection);
            rectangle_projection_max = max(rectangle_projection_max, projection);
        }

        if triangle_projection_max < rectangle_projection_min ||
           rectangle_projection_max < triangle_projection_min return false;
    }
    return true;
}

pick_in_screen_rectangle :: (
    using picker: *Windowed_Program_3D_Picker,
    start_mouse: Vector2,
    end_mouse: Vector2,
    viewport_width: s32,
    viewport_height: s32,
    world_to_camera: Matrix4,
    camera_to_clip: Matrix4,
    object_ids: *[..] u32,
) {
    array_resize(object_ids, 0);
    if viewport_width <= 0 || viewport_height <= 0 return;

    rectangle_min := Vector2.{min(start_mouse.x, end_mouse.x), min(start_mouse.y, end_mouse.y)};
    rectangle_max := Vector2.{max(start_mouse.x, end_mouse.x), max(start_mouse.y, end_mouse.y)};

    for pickable: pickables {
        if !windowed_program_3d_has_editor_permission(
            pickable.editor_permissions,
            .SELECTABLE,
        ) continue;

        positions := pickable.mesh.positions;
        indices := pickable.mesh.indices;
        triangle_count := indices.count / 3;
        intersects := false;
        for triangle_index: 0..triangle_count - 1 {
            index_a := indices[triangle_index * 3 + 0];
            index_b := indices[triangle_index * 3 + 1];
            index_c := indices[triangle_index * 3 + 2];
            if index_a >= positions.count || index_b >= positions.count || index_c >= positions.count continue;

            a, depth_a, a_ok := windowed_program_3d_project_to_screen(
                positions[index_a], pickable.local_to_world, world_to_camera,
                camera_to_clip, viewport_width, viewport_height,
            );
            b, depth_b, b_ok := windowed_program_3d_project_to_screen(
                positions[index_b], pickable.local_to_world, world_to_camera,
                camera_to_clip, viewport_width, viewport_height,
            );
            c, depth_c, c_ok := windowed_program_3d_project_to_screen(
                positions[index_c], pickable.local_to_world, world_to_camera,
                camera_to_clip, viewport_width, viewport_height,
            );
            if !a_ok || !b_ok || !c_ok continue;
            if (depth_a < -1 && depth_b < -1 && depth_c < -1) ||
               (depth_a > 1 && depth_b > 1 && depth_c > 1) continue;

            if windowed_program_3d_projected_triangle_overlaps_rectangle(
                a, b, c, rectangle_min, rectangle_max,
            ) {
                intersects = true;
                break;
            }
        }

        if intersects array_add(object_ids, pickable.object_id);
    }
}

windowed_program_3d_id_is_selected :: (selected_object_ids: [] u32, object_id: u32) -> bool {
    for selected_id: selected_object_ids {
        if selected_id == object_id return true;
    }
    return false;
}

prepare_selection_outline :: (
    using picker: *Windowed_Program_3D_Picker,
    selected_object_ids: [] u32,
    world_to_camera: Matrix4,
    camera_to_clip: Matrix4,
) -> bool {
    if !scene_depth_framebuffer_complete || !selected_depth_framebuffer_complete ||
       selected_object_ids.count == 0 {
        return false;
    }

    glViewport(0, 0, width, height);
    glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
    glDisable(GL_BLEND);
    glEnable(GL_DEPTH_TEST);
    glDepthMask(GL_TRUE);

    glUseProgram(selected_depth_renderer.shader_program_gl_handle);
    set_world_to_camera_uniform(*selected_depth_renderer, world_to_camera);
    set_camera_to_clip_uniform(*selected_depth_renderer, camera_to_clip);
    glUseProgram(0);

    /*
    render both depth textures through the same position-only shader. This
    keeps visible selected surfaces bit-stable across every scene renderer;
    the ordinary material shader's matrix evaluation cannot create false
    x-ray segments at grazing angles.
    */
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, scene_depth_framebuffer_gl_handle);
    glClear(GL_DEPTH_BUFFER_BIT);
    for pickable: pickables queue_render(*selected_depth_renderer, pickable.mesh);
    render(*selected_depth_renderer, GL_TRIANGLES);

    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, selected_depth_framebuffer_gl_handle);
    glClear(GL_DEPTH_BUFFER_BIT);
    selected_pickable_count: s64;
    for pickable: pickables {
        if !windowed_program_3d_id_is_selected(selected_object_ids, pickable.object_id) continue;
        queue_render(*selected_depth_renderer, pickable.mesh);
        selected_pickable_count += 1;
    }
    if selected_pickable_count == 0 {
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
        return false;
    }
    render(*selected_depth_renderer, GL_TRIANGLES);

    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
    glViewport(0, 0, width, height);
    return true;
}

draw_selection_outline :: (
    using picker: *Windowed_Program_3D_Picker,
    has_selection: bool,
    color: Vector4 = .{1.0, 0.7, 0.0, 1.0},
    thickness_px: u32 = 3,
    occluded_alpha: float32 = 0.32,
    depth_epsilon: float32 = 3.0 / 8388608.0,
) {
    if !selected_depth_framebuffer_complete || !has_selection return;

    glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
    glDisable(GL_DEPTH_TEST);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glUseProgram(outline_renderer.shader_program_gl_handle);

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, selected_depth_texture_gl_handle);
    set_selected_depth_texture_uniform(*outline_renderer, 0);
    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, scene_depth_texture_gl_handle);
    set_scene_depth_texture_uniform(*outline_renderer, 1);
    set_rgba_color_uniform(*outline_renderer, color);
    set_thickness_px_uniform(*outline_renderer, thickness_px);
    set_occluded_alpha_uniform(*outline_renderer, occluded_alpha);
    set_depth_epsilon_uniform(*outline_renderer, depth_epsilon);

    glBindVertexArray(outline_vao_gl_handle);
    glDrawArrays(GL_TRIANGLES, 0, 6);
    glBindVertexArray(0);

    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, 0);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, 0);
    glUseProgram(0);
    glDisable(GL_BLEND);
    glEnable(GL_DEPTH_TEST);
}
