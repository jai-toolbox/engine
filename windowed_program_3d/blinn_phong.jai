// One Blinn-Phong renderer, its renderables, and the state its shader consumes.
Windowed_Program_3D_Blinn_Phong :: struct {
    using #as base_3d: Windowed_Program_3D_Base;

    renderer: Gpu_Style_Blinn_Phong_Renderer;
    renderables: [..] Gpu_Style_Blinn_Phong_Renderable;
    material_textures: Windowed_Program_3D_Example_Material_Textures;

    ambient: float32 = 0.16;
    specular_strength: float32 = 0.25;
    light_direction: Vector3 = .{0.35, 0.80, 0.45};
    clear_color: Windowed_Program_3D_Example_Clear_Color;
}

init :: (using program: *Windowed_Program_3D_Blinn_Phong) {
    init(*base_3d);
    init(*renderer);
}

deinit :: (using program: *Windowed_Program_3D_Blinn_Phong) {
    for *renderable: renderables deinit(renderable, *renderer);
    array_free(renderables);
    deinit(*renderer);
    deinit(*base_3d);
}

add_renderable :: (
    using program: *Windowed_Program_3D_Blinn_Phong,
    geometry: $T/interface Gpu_Style_Blinn_Phong_Geometry,
    local_to_world: Matrix4 = Matrix4_Identity,
    editor_permissions: Windowed_Program_3D_Editor_Permissions = .ALL,
) -> *Gpu_Style_Blinn_Phong_Renderable {
    renderable := array_add(*renderables);
    assign_geometry_copy(renderable, geometry);
    if !buffer_object(*renderer, renderable) {
        deinit(renderable);
        array_resize(*renderables, renderables.count - 1);
        return null;
    }
    set_local_to_world_matrix(*renderer, renderable.*, local_to_world);
    if add_pickable(*picker, geometry, local_to_world, editor_permissions) == WINDOWED_PROGRAM_3D_NO_OBJECT_ID {
        deinit(renderable, *renderer);
        array_resize(*renderables, renderables.count - 1);
        return null;
    }
    return renderable;
}

set_renderable_transform :: (
    using program: *Windowed_Program_3D_Blinn_Phong,
    object_id: u32,
    local_to_world: Matrix4,
) -> bool {
    if object_id == 0 || object_id > cast(u32) renderables.count return false;
    set_local_to_world_matrix(*renderer, renderables[cast(int) object_id - 1], local_to_world);
    return set_pickable_transform(*picker, object_id, local_to_world);
}

get_selected_renderable :: (using program: *Windowed_Program_3D_Blinn_Phong) -> *Gpu_Style_Blinn_Phong_Renderable {
    index := windowed_program_3d_selected_renderable_index(*base_3d);
    if index < 0 || index >= renderables.count return null;
    return *renderables[index];
}

per_frame_update :: (using program: *Windowed_Program_3D_Blinn_Phong) {
    per_frame_update(*base_3d);
    apply_windowed_program_3d_editor_transform(program, *base_3d);

    glUseProgram(renderer.shader_program_gl_handle);
    set_world_to_camera_uniform(*renderer, world_to_camera);
    set_camera_to_clip_uniform(*renderer, camera_to_clip);
    set_camera_position_uniform(*renderer, camera.position);
    set_ambient_uniform(*renderer, ambient);
    set_specular_strength_uniform(*renderer, specular_strength);
    set_fallback_light_direction_uniform(*renderer, normalize(light_direction));
    set_directional_light_count_uniform(*renderer, 0);
    set_point_light_count_uniform(*renderer, 0);
    set_spot_light_count_uniform(*renderer, 0);
    set_packed_textures_uniform(*renderer, 0);
    set_packed_texture_bounding_boxes_uniform(*renderer, 1);
    set_blinn_phong_material_table_uniform(*renderer, 2);
    glUseProgram(0);
}

render_scene :: (using program: *Windowed_Program_3D_Blinn_Phong) {
    begin_windowed_program_3d_example_render(*base_3d, clear_color);
    bind_windowed_program_3d_example_material_textures(material_textures);
    for renderable: renderables queue_render(*renderer, renderable);
    begin_windowed_program_3d_geometry_render(*base_3d);
    render(*renderer);
    end_windowed_program_3d_geometry_render(*base_3d);
    end_windowed_program_3d_example_render(*base_3d);
}

run :: (using program: *Windowed_Program_3D_Blinn_Phong) {
    while !end_program run_windowed_program_3d_example_frame(program, *base_3d);
}
