// Skeletal PBR keeps animation evaluation outside the window shell. Write the
// current skinning matrices into bone_buffer.matrices before the draw pass.
Windowed_Program_3D_PBR_Skeletal_Animation :: struct {
    using #as base_3d: Windowed_Program_3D_Base;

    renderer: Gpu_Style_Pbr_Skeletal_Animation_Renderer;
    renderables: [..] Gpu_Style_Pbr_Skeletal_Animation_Renderable;
    bone_buffer: Windowed_Program_3D_Example_Bone_Buffer;
    material_textures: Windowed_Program_3D_Example_Material_Textures;
    lighting: Windowed_Program_3D_Example_PBR_Lighting;
    clear_color: Windowed_Program_3D_Example_Clear_Color;
}

init :: (using program: *Windowed_Program_3D_PBR_Skeletal_Animation) {
    init(*base_3d);
    init(*renderer);
    init(*bone_buffer);
    bind_windowed_program_3d_example_bone_block(renderer.shader_program_gl_handle);
}

deinit :: (using program: *Windowed_Program_3D_PBR_Skeletal_Animation) {
    for *renderable: renderables deinit(renderable, *renderer);
    array_free(renderables);
    deinit(*bone_buffer);
    deinit(*renderer);
    deinit(*base_3d);
}

add_renderable :: (
    using program: *Windowed_Program_3D_PBR_Skeletal_Animation,
    geometry: $T/interface Gpu_Style_Pbr_Skeletal_Animation_Geometry,
    local_to_world: Matrix4 = Matrix4_Identity,
) -> *Gpu_Style_Pbr_Skeletal_Animation_Renderable {
    renderable := array_add(*renderables);
    assign_geometry_copy(renderable, geometry);
    if !buffer_object(*renderer, renderable) return null;
    set_local_to_world_matrix(*renderer, renderable.*, local_to_world);
    return renderable;
}

set_bone_transforms :: (
    using program: *Windowed_Program_3D_PBR_Skeletal_Animation,
    transforms: [] Matrix4,
) {
    for *matrix: bone_buffer.matrices matrix.* = Matrix4_Identity;
    count := min(transforms.count, WINDOWED_PROGRAM_3D_EXAMPLE_MAX_BONES);
    for i: 0..count - 1 bone_buffer.matrices[i] = transforms[i];
}

per_frame_update :: (using program: *Windowed_Program_3D_PBR_Skeletal_Animation) {
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

render_scene :: (using program: *Windowed_Program_3D_PBR_Skeletal_Animation) {
    begin_windowed_program_3d_example_render(*base_3d, clear_color);
    bind_windowed_program_3d_example_material_textures(material_textures);
    upload(*bone_buffer);
    for renderable: renderables queue_render(*renderer, renderable);
    render(*renderer);
    end_windowed_program_3d_example_render(*base_3d);
}

run :: (using program: *Windowed_Program_3D_PBR_Skeletal_Animation) {
    while !end_program run_windowed_program_3d_example_frame(program, *base_3d);
}
