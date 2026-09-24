// Basic metallic/roughness PBR without lightmaps, skinning, or shadows.
Windowed_Program_3D_PBR :: struct {
    using #as base_3d: Windowed_Program_3D_Base;

    renderer: Gpu_Style_Pbr_Renderer;
    renderables: [..] Gpu_Style_Pbr_Renderable;
    material_textures: Windowed_Program_3D_Example_Material_Textures;
    lighting: Windowed_Program_3D_Example_PBR_Lighting;
    clear_color: Windowed_Program_3D_Example_Clear_Color;
}

init :: (using program: *Windowed_Program_3D_PBR) {
    init(*base_3d);
    init(*renderer);
}

deinit :: (using program: *Windowed_Program_3D_PBR) {
    for *renderable: renderables deinit(renderable, *renderer);
    array_free(renderables);
    deinit(*renderer);
    deinit(*base_3d);
}

add_renderable :: (
    using program: *Windowed_Program_3D_PBR,
    geometry: $T/interface Gpu_Style_Pbr_Geometry,
    local_to_world: Matrix4 = Matrix4_Identity,
) -> *Gpu_Style_Pbr_Renderable {
    renderable := array_add(*renderables);
    assign_geometry_copy(renderable, geometry);
    if !buffer_object(*renderer, renderable) return null;
    set_local_to_world_matrix(*renderer, renderable.*, local_to_world);
    return renderable;
}

per_frame_update :: (using program: *Windowed_Program_3D_PBR) {
    per_frame_update(*base_3d);

    glUseProgram(renderer.shader_program_gl_handle);
    set_world_to_camera_uniform(*renderer, world_to_camera);
    set_camera_to_clip_uniform(*renderer, camera_to_clip);
    set_camera_position_uniform(*renderer, camera.position);
    set_ambient_strength_uniform(*renderer, lighting.ambient_strength);
    set_directional_light_count_uniform(*renderer, 1);
    set_directional_light_0_direction_uniform(*renderer, normalize(lighting.direction));
    set_directional_light_0_color_uniform(*renderer, lighting.color);
    set_directional_light_0_intensity_uniform(*renderer, lighting.intensity);
    set_packed_textures_uniform(*renderer, 0);
    set_packed_texture_bounding_boxes_uniform(*renderer, 1);
    set_pbr_material_table_uniform(*renderer, 2);
    glUseProgram(0);
}

render_scene :: (using program: *Windowed_Program_3D_PBR) {
    begin_windowed_program_3d_example_render(*base_3d, clear_color);
    bind_windowed_program_3d_example_material_textures(material_textures);
    for renderable: renderables queue_render(*renderer, renderable);
    render(*renderer);
    end_windowed_program_3d_example_render(*base_3d);
}

run :: (using program: *Windowed_Program_3D_PBR) {
    while !end_program run_windowed_program_3d_example_frame(program, *base_3d);
}
