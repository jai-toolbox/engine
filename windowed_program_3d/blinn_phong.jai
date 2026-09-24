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
) -> *Gpu_Style_Blinn_Phong_Renderable {
    renderable := array_add(*renderables);
    assign_geometry_copy(renderable, geometry);
    if !buffer_object(*renderer, renderable) return null;
    set_local_to_world_matrix(*renderer, renderable.*, local_to_world);
    return renderable;
}

per_frame_update :: (using program: *Windowed_Program_3D_Blinn_Phong) {
    per_frame_update(*base_3d);

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
    render(*renderer);
    end_windowed_program_3d_example_render(*base_3d);
}

run :: (using program: *Windowed_Program_3D_Blinn_Phong) {
    while !end_program run_windowed_program_3d_example_frame(program, *base_3d);
}
