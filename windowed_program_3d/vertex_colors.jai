// Copy this file when a renderer only needs camera matrices, object transforms,
// positions, indices, and per-vertex RGB colors.
Windowed_Program_3D_Vertex_Colors :: struct {
    using #as base_3d: Windowed_Program_3D_Base;

    renderer: Gpu_Style_Vertex_Color_Renderer;
    renderables: [..] Gpu_Style_Vertex_Color_Renderable;
    clear_color: Windowed_Program_3D_Example_Clear_Color;
}

init :: (using program: *Windowed_Program_3D_Vertex_Colors) {
    init(*base_3d);
    init(*renderer);
}

deinit :: (using program: *Windowed_Program_3D_Vertex_Colors) {
    for *renderable: renderables deinit(renderable, *renderer);
    array_free(renderables);
    deinit(*renderer);
    deinit(*base_3d);
}

add_renderable :: (
    using program: *Windowed_Program_3D_Vertex_Colors,
    geometry: $T/interface Gpu_Style_Vertex_Color_Geometry,
    local_to_world: Matrix4 = Matrix4_Identity,
) -> *Gpu_Style_Vertex_Color_Renderable {
    renderable := array_add(*renderables);
    assign_geometry_copy(renderable, geometry);
    if !buffer_object(*renderer, renderable) return null;
    set_local_to_world_matrix(*renderer, renderable.*, local_to_world);
    return renderable;
}

per_frame_update :: (using program: *Windowed_Program_3D_Vertex_Colors) {
    per_frame_update(*base_3d);
    glUseProgram(renderer.shader_program_gl_handle);
    set_world_to_camera_uniform(*renderer, world_to_camera);
    set_camera_to_clip_uniform(*renderer, camera_to_clip);
    glUseProgram(0);
}

render_scene :: (using program: *Windowed_Program_3D_Vertex_Colors) {
    begin_windowed_program_3d_example_render(*base_3d, clear_color);
    for renderable: renderables queue_render(*renderer, renderable);
    render(*renderer);
    end_windowed_program_3d_example_render(*base_3d);
}

run :: (using program: *Windowed_Program_3D_Vertex_Colors) {
    while !end_program run_windowed_program_3d_example_frame(program, *base_3d);
}
