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
    editor_permissions: Windowed_Program_3D_Editor_Permissions = .ALL,
) -> *Gpu_Style_Vertex_Color_Renderable {
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
    using program: *Windowed_Program_3D_Vertex_Colors,
    object_id: u32,
    local_to_world: Matrix4,
) -> bool {
    if object_id == 0 || object_id > cast(u32) renderables.count return false;
    set_local_to_world_matrix(*renderer, renderables[cast(int) object_id - 1], local_to_world);
    return set_pickable_transform(*picker, object_id, local_to_world);
}

get_selected_renderable :: (using program: *Windowed_Program_3D_Vertex_Colors) -> *Gpu_Style_Vertex_Color_Renderable {
    index := windowed_program_3d_selected_renderable_index(*base_3d);
    if index < 0 || index >= renderables.count return null;
    return *renderables[index];
}

per_frame_update :: (using program: *Windowed_Program_3D_Vertex_Colors) {
    per_frame_update(*base_3d);
    apply_windowed_program_3d_editor_transform(program, *base_3d);
    glUseProgram(renderer.shader_program_gl_handle);
    set_world_to_camera_uniform(*renderer, world_to_camera);
    set_camera_to_clip_uniform(*renderer, camera_to_clip);
    glUseProgram(0);
}

render_scene :: (using program: *Windowed_Program_3D_Vertex_Colors) {
    begin_windowed_program_3d_example_render(*base_3d, clear_color);
    for renderable: renderables queue_render(*renderer, renderable);
    begin_windowed_program_3d_geometry_render(*base_3d);
    render(*renderer);
    end_windowed_program_3d_geometry_render(*base_3d);
    end_windowed_program_3d_example_render(*base_3d);
}

run :: (using program: *Windowed_Program_3D_Vertex_Colors) {
    while !end_program run_windowed_program_3d_example_frame(program, *base_3d);
}
