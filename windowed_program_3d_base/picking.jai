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
    renderable: Camera_Per_Object_Transform_Object_Id_Renderable;
    local_to_world: Matrix4 = Matrix4_Identity;

    // we store this data because we want to allow picking on animated things
    // but then the shader doesn't accept in bone things yet so we do a cpu side and rebuffer
    // which is really bad but works for now I guess.
    bind_positions: [..] Vector3;
    bone_transform_indices: [..] [4] u32;
    bone_weights: [..] [4] float32;
}

Windowed_Program_3D_Picker :: struct {
    framebuffer_gl_handle: GLuint;
    object_id_texture_gl_handle: GLuint;
    depth_texture_gl_handle: GLuint;
    width: u32;
    height: u32;
    framebuffer_complete: bool;

    renderer: Camera_Per_Object_Transform_Object_Id_Renderer;
    outline_renderer: Object_Id_Selection_Outline_Renderer;
    outline_vao_gl_handle: GLuint;

    pickables: [..] Windowed_Program_3D_Pickable;
    next_object_id: u32 = 1;
}

resize :: (using picker: *Windowed_Program_3D_Picker, new_width: u32, new_height: u32) -> bool {
    if new_width == 0 || new_height == 0 return false;
    if framebuffer_complete && width == new_width && height == new_height return true;

    width = new_width;
    height = new_height;

    glBindTexture(GL_TEXTURE_2D, object_id_texture_gl_handle);
    glTexImage2D(
        GL_TEXTURE_2D,
        0,
        GL_R32UI,
        xx width,
        xx height,
        0,
        GL_RED_INTEGER,
        GL_UNSIGNED_INT,
        null,
    );

    glBindTexture(GL_TEXTURE_2D, depth_texture_gl_handle);
    glTexImage2D(
        GL_TEXTURE_2D,
        0,
        GL_DEPTH_COMPONENT,
        xx width,
        xx height,
        0,
        GL_DEPTH_COMPONENT,
        GL_FLOAT,
        null,
    );

    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer_gl_handle);
    glFramebufferTexture2D(
        GL_FRAMEBUFFER,
        GL_COLOR_ATTACHMENT0,
        GL_TEXTURE_2D,
        object_id_texture_gl_handle,
        0,
    );
    glFramebufferTexture2D(
        GL_FRAMEBUFFER,
        GL_DEPTH_ATTACHMENT,
        GL_TEXTURE_2D,
        depth_texture_gl_handle,
        0,
    );
    glDrawBuffer(GL_COLOR_ATTACHMENT0);
    glReadBuffer(GL_COLOR_ATTACHMENT0);

    status := glCheckFramebufferStatus(GL_FRAMEBUFFER);
    framebuffer_complete = status == GL_FRAMEBUFFER_COMPLETE;
    if !framebuffer_complete {
        log_error("Windowed Program 3D picking framebuffer incomplete, status: 0x%", formatInt(status, base = 16));
    } else {
        clear_value: u32 = WINDOWED_PROGRAM_3D_NO_OBJECT_ID;
        glClearBufferuiv(GL_COLOR, 0, *clear_value);
        glDepthMask(GL_TRUE);
        glClear(GL_DEPTH_BUFFER_BIT);
    }

    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glBindTexture(GL_TEXTURE_2D, 0);
    return framebuffer_complete;
}

init :: (
    using picker: *Windowed_Program_3D_Picker,
    initial_width: u32,
    initial_height: u32,
) -> bool {
    init(*renderer);
    init(*outline_renderer);
    glGenVertexArrays(1, *outline_vao_gl_handle);

    glGenFramebuffers(1, *framebuffer_gl_handle);

    glGenTextures(1, *object_id_texture_gl_handle);
    glBindTexture(GL_TEXTURE_2D, object_id_texture_gl_handle);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

    glGenTextures(1, *depth_texture_gl_handle);
    glBindTexture(GL_TEXTURE_2D, depth_texture_gl_handle);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glBindTexture(GL_TEXTURE_2D, 0);

    return resize(picker, initial_width, initial_height);
}

deinit :: (using picker: *Windowed_Program_3D_Picker) {
    for *pickable: pickables {
        deinit(*pickable.renderable, *renderer);
        array_free(pickable.bind_positions);
        array_free(pickable.bone_transform_indices);
        array_free(pickable.bone_weights);
    }
    array_free(pickables);

    if outline_vao_gl_handle != 0 glDeleteVertexArrays(1, *outline_vao_gl_handle);
    deinit(*outline_renderer);
    deinit(*renderer);

    if depth_texture_gl_handle != 0 glDeleteTextures(1, *depth_texture_gl_handle);
    if object_id_texture_gl_handle != 0 glDeleteTextures(1, *object_id_texture_gl_handle);
    if framebuffer_gl_handle != 0 glDeleteFramebuffers(1, *framebuffer_gl_handle);
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
    array_copy(*pickable.renderable.indices, geometry.indices);
    array_copy(*pickable.renderable.positions, geometry.positions);
    array_resize(*pickable.renderable.object_ids, geometry.positions.count);
    picking_object_id := ifx windowed_program_3d_has_editor_permission(editor_permissions, .SELECTABLE)
        then object_id else WINDOWED_PROGRAM_3D_NO_OBJECT_ID;
    for *id: pickable.renderable.object_ids id.* = picking_object_id;

    if !buffer_object(*renderer, *pickable.renderable) {
        deinit(*pickable.renderable);
        return WINDOWED_PROGRAM_3D_NO_OBJECT_ID;
    }

    set_local_to_world_matrix(*renderer, pickable.renderable, local_to_world);
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
                pickable.renderable.positions[vertex_index] = bind_position;
            } else {
                pickable.renderable.positions[vertex_index] = .{
                    skinned_position.x,
                    skinned_position.y,
                    skinned_position.z,
                };
            }
        }
        rebuffer_object(*renderer, pickable.renderable);
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
            set_local_to_world_matrix(*renderer, pickable.renderable, local_to_world);
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

        was_selectable := windowed_program_3d_has_editor_permission(
            pickable.editor_permissions,
            .SELECTABLE,
        );
        is_selectable := windowed_program_3d_has_editor_permission(
            editor_permissions,
            .SELECTABLE,
        );
        selectability_changed := was_selectable != is_selectable;
        pickable.editor_permissions = editor_permissions;
        if selectability_changed {
            picking_object_id := ifx is_selectable
                then object_id else WINDOWED_PROGRAM_3D_NO_OBJECT_ID;
            for *id: pickable.renderable.object_ids id.* = picking_object_id;
            rebuffer_object(*renderer, pickable.renderable);
        }
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

render_object_ids :: (
    using picker: *Windowed_Program_3D_Picker,
    world_to_camera: Matrix4,
    camera_to_clip: Matrix4,
) {
    if !framebuffer_complete return;

    glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
    glViewport(0, 0, width, height);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, framebuffer_gl_handle);
    clear_value: u32 = WINDOWED_PROGRAM_3D_NO_OBJECT_ID;
    glClearBufferuiv(GL_COLOR, 0, *clear_value);
    glDisable(GL_BLEND);
    glDepthMask(GL_TRUE);
    glEnable(GL_DEPTH_TEST);
    glClear(GL_DEPTH_BUFFER_BIT);

    glUseProgram(renderer.shader_program_gl_handle);
    set_world_to_camera_uniform(*renderer, world_to_camera);
    set_camera_to_clip_uniform(*renderer, camera_to_clip);
    set_point_size_uniform(*renderer, 1.0);
    glUseProgram(0);

    for pickable: pickables queue_render(*renderer, pickable.renderable);
    render(*renderer, GL_TRIANGLES);

    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
}

read_region :: (
    using picker: *Windowed_Program_3D_Picker,
    x: u32,
    y: u32,
    width_to_read: u32,
    height_to_read: u32,
    object_ids: [] u32,
) {
    if !framebuffer_complete || width_to_read == 0 || height_to_read == 0 return;

    glBindFramebuffer(GL_READ_FRAMEBUFFER, framebuffer_gl_handle);
    glReadBuffer(GL_COLOR_ATTACHMENT0);
    glReadPixels(
        cast(s32) x,
        cast(s32) y,
        xx width_to_read,
        xx height_to_read,
        GL_RED_INTEGER,
        GL_UNSIGNED_INT,
        object_ids.data,
    );
    glBindFramebuffer(GL_READ_FRAMEBUFFER, 0);
}

pick_closest :: (
    picker: *Windowed_Program_3D_Picker,
    mouse_x: s32,
    mouse_y: s32,
    radius: s32 = 5,
) -> u32 {
    if !picker.framebuffer_complete || picker.width == 0 || picker.height == 0 {
        return WINDOWED_PROGRAM_3D_NO_OBJECT_ID;
    }
    if mouse_x < 0 || mouse_y < 0 || mouse_x >= cast(s32) picker.width || mouse_y >= cast(s32) picker.height {
        return WINDOWED_PROGRAM_3D_NO_OBJECT_ID;
    }

    x0 := clamp(mouse_x - radius, 0, cast(s32) picker.width - 1);
    y0 := clamp(mouse_y - radius, 0, cast(s32) picker.height - 1);
    x1 := clamp(mouse_x + radius, 0, cast(s32) picker.width - 1);
    y1 := clamp(mouse_y + radius, 0, cast(s32) picker.height - 1);
    region_width := cast(u32)(x1 - x0 + 1);
    region_height := cast(u32)(y1 - y0 + 1);

    object_ids: [..] u32;
    array_resize(*object_ids, region_width * region_height);
    defer array_free(object_ids);
    read_region(
        picker,
        cast(u32) x0,
        cast(u32) y0,
        region_width,
        region_height,
        object_ids,
    );

    closest_id: u32 = WINDOWED_PROGRAM_3D_NO_OBJECT_ID;
    closest_distance_squared := S32_MAX;
    for row: 0..cast(s32) region_height - 1 {
        for column: 0..cast(s32) region_width - 1 {
            object_id := object_ids[row * cast(s32) region_width + column];
            if object_id == WINDOWED_PROGRAM_3D_NO_OBJECT_ID continue;

            dx := x0 + column - mouse_x;
            dy := y0 + row - mouse_y;
            distance_squared := dx * dx + dy * dy;
            if distance_squared > radius * radius continue;
            if distance_squared < closest_distance_squared {
                closest_distance_squared = distance_squared;
                closest_id = object_id;
            }
        }
    }
    return closest_id;
}

draw_selection_outline :: (
    using picker: *Windowed_Program_3D_Picker,
    selected_object_id: u32,
    color: Vector4 = .{1.0, 0.7, 0.0, 1.0},
    thickness_px: u32 = 3,
) {
    if !framebuffer_complete || selected_object_id == WINDOWED_PROGRAM_3D_NO_OBJECT_ID return;

    glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
    glDisable(GL_DEPTH_TEST);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glUseProgram(outline_renderer.shader_program_gl_handle);

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, object_id_texture_gl_handle);
    set_object_id_texture_uniform(*outline_renderer, 0);
    set_selected_object_id_uniform(*outline_renderer, selected_object_id);
    set_rgba_color_uniform(*outline_renderer, color);
    set_thickness_px_uniform(*outline_renderer, thickness_px);

    glBindVertexArray(outline_vao_gl_handle);
    glDrawArrays(GL_TRIANGLES, 0, 6);
    glBindVertexArray(0);

    glUseProgram(0);
    glDisable(GL_BLEND);
    glEnable(GL_DEPTH_TEST);
}
