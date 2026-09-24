// The examples deliberately share only window presentation and the two small
// GPU resources that are not tied to a particular material renderer. Renderer
// ownership, uniforms, renderables, and draw calls stay visible in each file.

#scope_file
Simp :: #import "Simp";
#scope_export

Windowed_Program_3D_Example_Clear_Color :: struct {
    r: float32 = 0.04;
    g: float32 = 0.04;
    b: float32 = 0.05;
    a: float32 = 1.0;
}

begin_windowed_program_3d_example_render :: (
    base: *Windowed_Program_3D_Base,
    clear_color: Windowed_Program_3D_Example_Clear_Color,
) {
    Simp.update_window(base.window);
    Simp.clear_render_target(clear_color.r, clear_color.g, clear_color.b, clear_color.a);
    ui_begin(*base.wp);

    glDepthMask(GL_TRUE);
    glEnable(GL_DEPTH_TEST);
    glClear(GL_DEPTH_BUFFER_BIT);
}

end_windowed_program_3d_example_render :: (base: *Windowed_Program_3D_Base) {
    if base.current_menu == .NONE {
        render_crosshair(*base.wp.base);
    } else {
        render_menus(*base.wp);
    }
    ui_end(*base.wp);
    drain_ui_audio_events(*base.wp);
    Simp.swap_buffers(base.window, false);
}

run_windowed_program_3d_example_frame :: (
    program: *$Program,
    base: *Windowed_Program_3D_Base,
) {
    begin_frame(base);
    per_frame_update(program);
    render_scene(program);
    end_frame(base);
}

begin_frame :: (base: *Windowed_Program_3D_Base) {
    mark_frame_start(base);
}

end_frame :: (base: *Windowed_Program_3D_Base) {
    sleep_to_maintain_max_fps(base);
    mark_frame_end(base);
}

Windowed_Program_3D_Example_PBR_Lighting :: struct {
    ambient_strength: float32 = 0.03;
    direction: Vector3 = .{-0.35, -0.8, -0.45};
    color: Vector3 = .{1.0, 0.96, 0.90};
    intensity: float32 = 2.25;
}

// These handles are borrowed. The application that creates the textures also
// owns and destroys them. All PBR and Blinn-Phong examples use the same slots.
Windowed_Program_3D_Example_Material_Textures :: struct {
    packed_texture_array_gl_id: GLuint;          // texture unit 0, GL_TEXTURE_2D_ARRAY
    packed_texture_bounds_gl_id: GLuint;         // texture unit 1, GL_TEXTURE_1D
    material_table_gl_id: GLuint;                // texture unit 2, GL_TEXTURE_1D
}

bind_windowed_program_3d_example_material_textures :: (
    textures: Windowed_Program_3D_Example_Material_Textures,
) {
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D_ARRAY, textures.packed_texture_array_gl_id);
    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_1D, textures.packed_texture_bounds_gl_id);
    glActiveTexture(GL_TEXTURE2);
    glBindTexture(GL_TEXTURE_1D, textures.material_table_gl_id);
    glActiveTexture(GL_TEXTURE0);
}

WINDOWED_PROGRAM_3D_EXAMPLE_SHADOW_MAP_SIZE :: 1024;

Windowed_Program_3D_Example_Shadow_Map :: struct {
    framebuffer_gl_handle: GLuint;
    depth_texture_gl_handle: GLuint;
    initialized: bool;
}

init :: (shadow_map: *Windowed_Program_3D_Example_Shadow_Map) {
    glGenFramebuffers(1, *shadow_map.framebuffer_gl_handle);
    glGenTextures(1, *shadow_map.depth_texture_gl_handle);
    glBindTexture(GL_TEXTURE_2D, shadow_map.depth_texture_gl_handle);
    glTexImage2D(
        GL_TEXTURE_2D,
        0,
        GL_DEPTH_COMPONENT,
        WINDOWED_PROGRAM_3D_EXAMPLE_SHADOW_MAP_SIZE,
        WINDOWED_PROGRAM_3D_EXAMPLE_SHADOW_MAP_SIZE,
        0,
        GL_DEPTH_COMPONENT,
        GL_FLOAT,
        null,
    );
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_BORDER);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_BORDER);
    border_color := float32.[1, 1, 1, 1];
    glTexParameterfv(GL_TEXTURE_2D, GL_TEXTURE_BORDER_COLOR, border_color.data);

    glBindFramebuffer(GL_FRAMEBUFFER, shadow_map.framebuffer_gl_handle);
    glFramebufferTexture2D(
        GL_FRAMEBUFFER,
        GL_DEPTH_ATTACHMENT,
        GL_TEXTURE_2D,
        shadow_map.depth_texture_gl_handle,
        0,
    );
    glDrawBuffer(GL_NONE);
    glReadBuffer(GL_NONE);
    shadow_map.initialized = glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
    if !shadow_map.initialized log_error("Windowed_Program_3D example shadow framebuffer is incomplete");
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

deinit :: (shadow_map: *Windowed_Program_3D_Example_Shadow_Map) {
    if shadow_map.framebuffer_gl_handle != 0 glDeleteFramebuffers(1, *shadow_map.framebuffer_gl_handle);
    if shadow_map.depth_texture_gl_handle != 0 glDeleteTextures(1, *shadow_map.depth_texture_gl_handle);
    shadow_map.* = .{};
}

windowed_program_3d_example_light_clip_matrix :: (
    direction: Vector3,
    center: Vector3,
    half_extent: float32,
    depth_extent: float32,
) -> Matrix4 {
    direction = normalize(direction);
    eye := center - direction * depth_extent * 0.5;
    up_hint := Vector3.{0, 1, 0};
    if abs(dot(up_hint, direction)) > 0.95 up_hint = .{1, 0, 0};
    right := normalize(cross(up_hint, direction));
    up := cross(direction, right);

    world_to_light := Matrix4_Identity;
    world_to_light.coef[0][0] = right.x;
    world_to_light.coef[0][1] = right.y;
    world_to_light.coef[0][2] = right.z;
    world_to_light.coef[0][3] = -dot(right, eye);
    world_to_light.coef[1][0] = up.x;
    world_to_light.coef[1][1] = up.y;
    world_to_light.coef[1][2] = up.z;
    world_to_light.coef[1][3] = -dot(up, eye);
    world_to_light.coef[2][0] = -direction.x;
    world_to_light.coef[2][1] = -direction.y;
    world_to_light.coef[2][2] = -direction.z;
    world_to_light.coef[2][3] = dot(direction, eye);

    light_to_clip := orthographic_projection_matrix(
        left = -half_extent,
        right = half_extent,
        bottom = -half_extent,
        top = half_extent,
        near = -depth_extent,
        far = depth_extent,
        depth_range_01 = false,
    );
    return light_to_clip * world_to_light;
}

WINDOWED_PROGRAM_3D_EXAMPLE_MAX_BONES :: 100;
WINDOWED_PROGRAM_3D_EXAMPLE_BONE_UBO_BINDING :: 1;

Windowed_Program_3D_Example_Bone_Buffer :: struct {
    matrices: [WINDOWED_PROGRAM_3D_EXAMPLE_MAX_BONES] Matrix4;
    gl_uniform_buffer_handle: GLuint;
}

init :: (buffer: *Windowed_Program_3D_Example_Bone_Buffer) {
    for *matrix: buffer.matrices matrix.* = Matrix4_Identity;
    glGenBuffers(1, *buffer.gl_uniform_buffer_handle);
    glBindBuffer(GL_UNIFORM_BUFFER, buffer.gl_uniform_buffer_handle);
    glBufferData(
        GL_UNIFORM_BUFFER,
        WINDOWED_PROGRAM_3D_EXAMPLE_MAX_BONES * size_of(Matrix4),
        buffer.matrices.data,
        GL_DYNAMIC_DRAW,
    );
    glBindBufferBase(GL_UNIFORM_BUFFER, WINDOWED_PROGRAM_3D_EXAMPLE_BONE_UBO_BINDING, buffer.gl_uniform_buffer_handle);
    glBindBuffer(GL_UNIFORM_BUFFER, 0);
}

deinit :: (buffer: *Windowed_Program_3D_Example_Bone_Buffer) {
    if buffer.gl_uniform_buffer_handle != 0 glDeleteBuffers(1, *buffer.gl_uniform_buffer_handle);
    buffer.* = .{};
}

upload :: (buffer: *Windowed_Program_3D_Example_Bone_Buffer) {
    glBindBuffer(GL_UNIFORM_BUFFER, buffer.gl_uniform_buffer_handle);
    glBufferSubData(
        GL_UNIFORM_BUFFER,
        0,
        WINDOWED_PROGRAM_3D_EXAMPLE_MAX_BONES * size_of(Matrix4),
        buffer.matrices.data,
    );
    glBindBufferBase(GL_UNIFORM_BUFFER, WINDOWED_PROGRAM_3D_EXAMPLE_BONE_UBO_BINDING, buffer.gl_uniform_buffer_handle);
    glBindBuffer(GL_UNIFORM_BUFFER, 0);
}

bind_windowed_program_3d_example_bone_block :: (shader_program_gl_handle: GLuint) {
    block_index := glGetUniformBlockIndex(shader_program_gl_handle, temp_c_string("BoneAnimationTransforms"));
    if block_index != GL_INVALID_INDEX {
        glUniformBlockBinding(
            shader_program_gl_handle,
            block_index,
            WINDOWED_PROGRAM_3D_EXAMPLE_BONE_UBO_BINDING,
        );
    }
}
