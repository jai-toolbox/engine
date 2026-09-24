// Directional-shadow PBR is one rendering path made from a shaded renderer and
// a depth-only renderer. Keeping both here makes the complete pass easy to copy.
Windowed_Program_3D_PBR_Directional_Shadows_Renderable :: struct {
    shaded: Gpu_Style_Pbr_Directional_Shadows_Renderable;
    depth: Gpu_Style_Pbr_Directional_Shadow_Depth_Renderable;
}

Windowed_Program_3D_PBR_Directional_Shadows :: struct {
    using #as base_3d: Windowed_Program_3D_Base;

    renderer: Gpu_Style_Pbr_Directional_Shadows_Renderer;
    depth_renderer: Gpu_Style_Pbr_Directional_Shadow_Depth_Renderer;
    renderables: [..] Windowed_Program_3D_PBR_Directional_Shadows_Renderable;
    shadow_map: Windowed_Program_3D_Example_Shadow_Map;
    material_textures: Windowed_Program_3D_Example_Material_Textures;
    lighting: Windowed_Program_3D_Example_PBR_Lighting;

    shadow_center: Vector3;
    shadow_half_extent: float32 = 12.0;
    shadow_depth_extent: float32 = 24.0;
    clear_color: Windowed_Program_3D_Example_Clear_Color;
}

init :: (using program: *Windowed_Program_3D_PBR_Directional_Shadows) {
    init(*base_3d);
    init(*renderer);
    init(*depth_renderer);
    init(*shadow_map);
}

deinit :: (using program: *Windowed_Program_3D_PBR_Directional_Shadows) {
    for *renderable: renderables {
        deinit(*renderable.shaded, *renderer);
        deinit(*renderable.depth, *depth_renderer);
    }
    array_free(renderables);
    deinit(*shadow_map);
    deinit(*depth_renderer);
    deinit(*renderer);
    deinit(*base_3d);
}

add_renderable :: (
    using program: *Windowed_Program_3D_PBR_Directional_Shadows,
    geometry: $T/interface Gpu_Style_Pbr_Geometry,
    local_to_world: Matrix4 = Matrix4_Identity,
    editor_permissions: Windowed_Program_3D_Editor_Permissions = .ALL,
) -> *Windowed_Program_3D_PBR_Directional_Shadows_Renderable {
    renderable := array_add(*renderables);
    assign_geometry_copy(*renderable.shaded, geometry);
    array_copy(*renderable.depth.indices, geometry.indices);
    array_copy(*renderable.depth.positions, geometry.positions);

    if !buffer_object(*renderer, *renderable.shaded) {
        deinit(*renderable.shaded);
        deinit(*renderable.depth);
        array_resize(*renderables, renderables.count - 1);
        return null;
    }
    if !buffer_object(*depth_renderer, *renderable.depth) {
        deinit(*renderable.shaded, *renderer);
        deinit(*renderable.depth);
        array_resize(*renderables, renderables.count - 1);
        return null;
    }
    set_local_to_world_matrix(*renderer, renderable.shaded, local_to_world);
    set_local_to_world_matrix(*depth_renderer, renderable.depth, local_to_world);
    if add_pickable(*picker, geometry, local_to_world, editor_permissions) == WINDOWED_PROGRAM_3D_NO_OBJECT_ID {
        deinit(*renderable.shaded, *renderer);
        deinit(*renderable.depth, *depth_renderer);
        array_resize(*renderables, renderables.count - 1);
        return null;
    }
    return renderable;
}

set_renderable_transform :: (
    using program: *Windowed_Program_3D_PBR_Directional_Shadows,
    object_id: u32,
    local_to_world: Matrix4,
) -> bool {
    if object_id == 0 || object_id > cast(u32) renderables.count return false;
    renderable := renderables[cast(int) object_id - 1];
    set_local_to_world_matrix(*renderer, renderable.shaded, local_to_world);
    set_local_to_world_matrix(*depth_renderer, renderable.depth, local_to_world);
    return set_pickable_transform(*picker, object_id, local_to_world);
}

get_selected_renderable :: (
    using program: *Windowed_Program_3D_PBR_Directional_Shadows,
) -> *Windowed_Program_3D_PBR_Directional_Shadows_Renderable {
    index := windowed_program_3d_selected_renderable_index(*base_3d);
    if index < 0 || index >= renderables.count return null;
    return *renderables[index];
}

windowed_program_3d_world_to_light_clip :: (
    using program: *Windowed_Program_3D_PBR_Directional_Shadows,
) -> Matrix4 {
    return windowed_program_3d_example_light_clip_matrix(
        lighting.direction,
        shadow_center,
        shadow_half_extent,
        shadow_depth_extent,
    );
}

per_frame_update :: (using program: *Windowed_Program_3D_PBR_Directional_Shadows) {
    per_frame_update(*base_3d);
    apply_windowed_program_3d_editor_transform(program, *base_3d);
    world_to_light_clip := windowed_program_3d_world_to_light_clip(program);

    glUseProgram(renderer.shader_program_gl_handle);
    set_world_to_camera_uniform(*renderer, world_to_camera);
    set_camera_to_clip_uniform(*renderer, camera_to_clip);
    set_world_to_light_clip_uniform(*renderer, world_to_light_clip);
    set_camera_position_uniform(*renderer, camera.position);
    set_ambient_strength_uniform(*renderer, lighting.ambient_strength);
    set_directional_light_count_uniform(*renderer, 1);
    set_directional_light_0_direction_uniform(*renderer, normalize(lighting.direction));
    set_directional_light_0_color_uniform(*renderer, lighting.color);
    set_directional_light_0_intensity_uniform(*renderer, lighting.intensity);
    set_directional_shadow_map_uniform(*renderer, 3);
    set_use_directional_shadow_map_uniform(*renderer, shadow_map.initialized);
    set_packed_textures_uniform(*renderer, 0);
    set_packed_texture_bounding_boxes_uniform(*renderer, 1);
    set_pbr_material_table_uniform(*renderer, 2);
    glUseProgram(0);
}

render_shadow_map :: (using program: *Windowed_Program_3D_PBR_Directional_Shadows) {
    if !shadow_map.initialized return;
    world_to_light_clip := windowed_program_3d_world_to_light_clip(program);

    glViewport(0, 0, WINDOWED_PROGRAM_3D_EXAMPLE_SHADOW_MAP_SIZE, WINDOWED_PROGRAM_3D_EXAMPLE_SHADOW_MAP_SIZE);
    glBindFramebuffer(GL_FRAMEBUFFER, shadow_map.framebuffer_gl_handle);
    glClear(GL_DEPTH_BUFFER_BIT);
    glUseProgram(depth_renderer.shader_program_gl_handle);
    set_world_to_light_clip_uniform(*depth_renderer, world_to_light_clip);
    glUseProgram(0);
    for renderable: renderables queue_render(*depth_renderer, renderable.depth);
    render(*depth_renderer);

    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glDrawBuffer(GL_BACK);
    glReadBuffer(GL_BACK);
    glViewport(0, 0, cast(u32) window_width, cast(u32) window_height);
}

render_scene :: (using program: *Windowed_Program_3D_PBR_Directional_Shadows) {
    begin_windowed_program_3d_example_render(*base_3d, clear_color);
    render_shadow_map(program);
    bind_windowed_program_3d_example_material_textures(material_textures);
    glActiveTexture(GL_TEXTURE3);
    glBindTexture(GL_TEXTURE_2D, shadow_map.depth_texture_gl_handle);
    glActiveTexture(GL_TEXTURE0);
    for renderable: renderables queue_render(*renderer, renderable.shaded);
    begin_windowed_program_3d_geometry_render(*base_3d);
    render(*renderer);
    end_windowed_program_3d_geometry_render(*base_3d);
    end_windowed_program_3d_example_render(*base_3d);
}

run :: (using program: *Windowed_Program_3D_PBR_Directional_Shadows) {
    while !end_program run_windowed_program_3d_example_frame(program, *base_3d);
}
