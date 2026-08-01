#scope_file
Window_Creation :: #import "Window_Creation";
Sound_Player :: #import "Sound_Player";
Input :: #import "Input";
Simp :: #import "Simp";
#if OS == .LINUX {
    X11 :: #import "X11";
}
#scope_export

#if OS == .LINUX {
    libXi :: #library,system "libXi";

    XIAllDevices : s32 : 0;
    XI_RawMotion : s32 : 17;
    XI_LASTEVENT : s32 : 32;

    XIEventMask :: struct {
        deviceid: s32;
        mask_len: s32;
        mask: *u8;
    }

    XIValuatorState :: struct {
        mask_len: s32;
        mask: *u8;
        values: *float64;
    }

    XIRawEvent :: struct {
        type: s32;
        serial: u64;
        send_event: X11.Bool;
        display: *X11.Display;
        extension: s32;
        evtype: s32;
        time: X11.Time;
        deviceid: s32;
        sourceid: s32;
        detail: s32;
        flags: s32;
        valuators: XIValuatorState;
        raw_values: *float64;
    }

    XIQueryVersion :: (display: *X11.Display, major_version_inout: *s32, minor_version_inout: *s32) -> X11.Status #foreign libXi;
    XISelectEvents :: (dpy: *X11.Display, win: X11.Window, masks: *XIEventMask, num_masks: s32) -> s32 #foreign libXi;

    xi_set_mask :: (mask: *u8, event_type: s32) {
        mask[event_type >> 3] |= cast(u8)(1 << (event_type & 7));
    }

    xi_mask_is_set :: (mask: *u8, index: s32) -> bool {
        return (mask[index >> 3] & cast(u8)(1 << (index & 7))) != 0;
    }

    xi_count_valuator_values :: (using state: XIValuatorState) -> int {
        count := 0;
        for i: 0..mask_len * 8 - 1 {
            if xi_mask_is_set(mask, i) count += 1;
        }
        return count;
    }
}

Camera_Mode :: enum {
    FIRST_PERSON;
    THIRD_PERSON;
    TWO_DIMENSIONS;
}

Movement_Mode :: enum {
    GOD;
    MANUAL;
    FPS;
}

Windowed_Program_3D_Render_Path :: enum {
    Legacy_Color;
    Vertex_Color;
    Blinn_Phong;
    PBR;
    PBR_Lightmapped;
    PBR_Directional_Shadows;
    PBR_Skeletal;
    PBR_Directional_Shadows_Skeletal;
}

Orientation :: struct {
    forward: Vector3;
    right: Vector3;
    up: Vector3;
}

STANDARD_ORIENTATION :: #run Orientation.{X3, -Y3, Z3};
GL_ORIENTATION :: Orientation.{Z3, X3, Y3};
NEGATIVE_Z_GL_ORIENTATION :: #run Orientation.{-Z3, X3, Y3};

WINDOWED_PROGRAM_3D_SHADOW_MAP_SIZE :: 1024;
WINDOWED_PROGRAM_3D_BLINN_PHONG_MATERIAL_TABLE_SLOTS  :: 5;
WINDOWED_PROGRAM_3D_BLINN_PHONG_MATERIAL_TABLE_TEXELS :: GPU_STYLE_BLINN_PHONG_MAX_MATERIALS * WINDOWED_PROGRAM_3D_BLINN_PHONG_MATERIAL_TABLE_SLOTS;
WINDOWED_PROGRAM_3D_PBR_MAX_MATERIALS :: 64;
WINDOWED_PROGRAM_3D_PBR_MATERIAL_TABLE_SLOTS  :: 4;
WINDOWED_PROGRAM_3D_PBR_MATERIAL_TABLE_TEXELS :: WINDOWED_PROGRAM_3D_PBR_MAX_MATERIALS * WINDOWED_PROGRAM_3D_PBR_MATERIAL_TABLE_SLOTS;
WINDOWED_PROGRAM_3D_MAX_BONES :: 100;
WINDOWED_PROGRAM_3D_BONE_UBO_BINDING :: 1;

Windowed_Program_3D_Directional_Shadow_Map :: struct {
    framebuffer_gl_handle: GLuint;
    depth_texture_gl_handle: GLuint;
    world_to_light_clip: Matrix4 = Matrix4_Identity;
    initialized: bool;
}

Windowed_Program_3D_PBR_Renderable :: struct {
    base: Gpu_Style_Pbr_Renderable;
    shadowed: Gpu_Style_Pbr_Directional_Shadows_Renderable;
    shadow_depth: Gpu_Style_Pbr_Directional_Shadow_Depth_Renderable;
}

Windowed_Program_3D_PBR_Lightmapped_Renderable :: struct {
    base: Gpu_Style_Pbr_Lightmapped_Renderable;
}

Windowed_Program_3D_PBR_Skeletal_Renderable :: struct {
    base: Gpu_Style_Pbr_Skeletal_Animation_Renderable;
    shadowed: Gpu_Style_Pbr_Directional_Shadows_Skeletal_Animation_Renderable;
    shadow_depth: Gpu_Style_Pbr_Directional_Shadow_Depth_Skeletal_Animation_Renderable;
}

Windowed_Program_3D_PBR_Geometry :: struct {
    indices : [..] u32;
    positions: [..] Vector3;
    normals: [..] Vector3;
    tangents: [..] Vector3;
    uvs: [..] Vector2;
    material_indices: [..] u32;
}

Windowed_Program_3D_PBR_Lightmapped_Geometry :: struct {
    indices : [..] u32;
    positions: [..] Vector3;
    normals: [..] Vector3;
    tangents: [..] Vector3;
    uvs: [..] Vector2;
    lightmap_uvs: [..] Vector2;
    material_indices: [..] u32;
}

Windowed_Program_3D_PBR_Skeletal_Geometry :: struct {
    indices : [..] u32;
    positions: [..] Vector3;
    normals: [..] Vector3;
    tangents: [..] Vector3;
    uvs: [..] Vector2;
    material_indices: [..] u32;
    bone_transform_indices: [..] [4] u32;
    bone_weights: [..] [4] float32;
}

Windowed_Program_3D_PBR_Skeletal_Primitive :: struct {
    using pbr: Triangles_PBR;

    bone_transform_indices: [..] [4] u32;
    bone_weights: [..] [4] float32;
}

Windowed_Program_3D_PBR_Skeletal_Scene :: struct {
    using #as base: Base_Scene;

    primitives: [..] Windowed_Program_3D_PBR_Skeletal_Primitive;
    materials: [..] GPU_Style_PBR_Material;

    skeleton: Skeleton;
    clips: [..] Animation_Clip;
    bone_transforms: [..] Matrix4;
    active_clip_index: s32 = 0;
    animation_time: float32;
}

Windowed_Program_3D_Vertex_Color_Geometry :: struct {
    indices : [..] u32;
    positions: [..] Vector3;
    colors: [..] Vector3;
}

Windowed_Program_3D_Blinn_Phong_Geometry :: struct {
    indices : [..] u32;
    positions: [..] Vector3;
    normals: [..] Vector3;
    tangents: [..] Vector3;
    uvs: [..] Vector2;
    material_indices: [..] s32;
}

Windowed_Program_3D_Blinn_Phong_Packed_Resources :: struct {
    using #as packed_texture_base: Packed_Texture_Rendering_Base;
    material_table_gl_id: GLuint;
    initialized: bool;
}

Windowed_Program_3D_PBR_Packed_Resources :: struct {
    using #as packed_texture_base: Packed_Texture_Rendering_Base;
    material_table_gl_id: GLuint;
    lightmap_texture_gl_id: GLuint;
    lightmap_width: u32;
    lightmap_height: u32;
    initialized: bool;
}

Windowed_Program_3D_Bone_Animation_Buffer :: struct {
    matrices: [WINDOWED_PROGRAM_3D_MAX_BONES] Matrix4;
    gl_uniform_buffer_handle: GLuint;
    initialized: bool;
}

init_windowed_program_3d_shadow_map :: (shadow_map: *Windowed_Program_3D_Directional_Shadow_Map) {
    glGenFramebuffers(1, *shadow_map.framebuffer_gl_handle);

    glGenTextures(1, *shadow_map.depth_texture_gl_handle);
    glBindTexture(GL_TEXTURE_2D, shadow_map.depth_texture_gl_handle);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT, WINDOWED_PROGRAM_3D_SHADOW_MAP_SIZE, WINDOWED_PROGRAM_3D_SHADOW_MAP_SIZE, 0, GL_DEPTH_COMPONENT, GL_FLOAT, null);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_BORDER);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_BORDER);

    border_color := float32.[1.0, 1.0, 1.0, 1.0];
    glTexParameterfv(GL_TEXTURE_2D, GL_TEXTURE_BORDER_COLOR, border_color.data);

    glBindFramebuffer(GL_FRAMEBUFFER, shadow_map.framebuffer_gl_handle);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, shadow_map.depth_texture_gl_handle, 0);
    glDrawBuffer(GL_NONE);
    glReadBuffer(GL_NONE);

    if glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE {
        log_error("Windowed_Program_3D directional shadow framebuffer is incomplete");
    } else {
        shadow_map.initialized = true;
    }

    glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

deinit :: (shadow_map: *Windowed_Program_3D_Directional_Shadow_Map) {
    if shadow_map.framebuffer_gl_handle != 0 glDeleteFramebuffers(1, *shadow_map.framebuffer_gl_handle);
    if shadow_map.depth_texture_gl_handle != 0 glDeleteTextures(1, *shadow_map.depth_texture_gl_handle);
    shadow_map.* = .{};
}

init_windowed_program_3d_default_pbr_material_table :: (wp3: *Windowed_Program_3D) {
    if wp3.pbr_material_table_gl_id != 0 glDeleteTextures(1, *wp3.pbr_material_table_gl_id);

    material_texels: [WINDOWED_PROGRAM_3D_PBR_MATERIAL_TABLE_TEXELS] Vector4;
    material_texels[0] = .{-1, -1, 0, 0};
    material_texels[1] = .{0.75, 0.75, 0.75, 1.0};
    material_texels[2] = .{-1, -1, 0, 0};
    material_texels[3] = .{-1, -1, 0.0, 0.55};

    glActiveTexture(GL_TEXTURE2);
    glGenTextures(1, *wp3.pbr_material_table_gl_id);
    glBindTexture(GL_TEXTURE_1D, wp3.pbr_material_table_gl_id);
    glTexImage1D(GL_TEXTURE_1D, 0, GL_RGBA32F, WINDOWED_PROGRAM_3D_PBR_MATERIAL_TABLE_TEXELS, 0, GL_RGBA, GL_FLOAT, material_texels.data);
    glTexParameteri(GL_TEXTURE_1D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_1D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_1D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glActiveTexture(GL_TEXTURE0);
}

bind_windowed_program_3d_pbr_material_table :: (wp3: *Windowed_Program_3D) {
    if wp3.pbr_packed_resources.initialized {
        bind_packed_textures(wp3.pbr_packed_resources.packed_texture_base);
    }

    glActiveTexture(GL_TEXTURE2);
    glBindTexture(GL_TEXTURE_1D, wp3.pbr_material_table_gl_id);
    glActiveTexture(GL_TEXTURE0);
}

bind_windowed_program_3d_blinn_phong_material_table :: (wp3: *Windowed_Program_3D) {
    if wp3.blinn_phong_packed_resources.initialized {
        bind_packed_textures(wp3.blinn_phong_packed_resources.packed_texture_base);
    }

    glActiveTexture(GL_TEXTURE2);
    glBindTexture(GL_TEXTURE_1D, wp3.blinn_phong_packed_resources.material_table_gl_id);
    glActiveTexture(GL_TEXTURE0);
}

deinit :: (resources: *Windowed_Program_3D_Blinn_Phong_Packed_Resources) {
    if resources.material_table_gl_id != 0 glDeleteTextures(1, *resources.material_table_gl_id);
    if resources.packed_texture_array_gl_id != 0 glDeleteTextures(1, *resources.packed_texture_array_gl_id);
    if resources.packed_texture_bounding_boxes_gl_id != 0 glDeleteTextures(1, *resources.packed_texture_bounding_boxes_gl_id);
    resources.* = .{};
}

deinit :: (resources: *Windowed_Program_3D_PBR_Packed_Resources) {
    if resources.lightmap_texture_gl_id != 0 glDeleteTextures(1, *resources.lightmap_texture_gl_id);
    if resources.packed_texture_array_gl_id != 0 glDeleteTextures(1, *resources.packed_texture_array_gl_id);
    if resources.packed_texture_bounding_boxes_gl_id != 0 glDeleteTextures(1, *resources.packed_texture_bounding_boxes_gl_id);
    resources.* = .{};
}

deinit :: (primitive: *Windowed_Program_3D_PBR_Skeletal_Primitive) {
    deinit(*primitive.pbr);
    array_free(primitive.bone_transform_indices);
    array_free(primitive.bone_weights);
}

deinit :: (scene: *Windowed_Program_3D_PBR_Skeletal_Scene) {
    for * primitive: scene.primitives deinit(primitive);
    array_free(scene.primitives);
    deinit(*scene.base);
    array_free(scene.materials);

    for * clip: scene.clips {
        if clip.name.count > 0 free(clip.name);
        for * channel: clip.channels {
            array_free(channel.position_keyframes);
            array_free(channel.rotation_keyframes);
            array_free(channel.scale_keyframes);
        }
        array_free(clip.channels);
        array_free(clip.armature_position_keyframes);
        array_free(clip.armature_rotation_keyframes);
        array_free(clip.armature_scale_keyframes);
    }
    array_free(scene.clips);

    for * bone: scene.skeleton.bones {
        if bone.name.count > 0 free(bone.name);
    }
    array_free(scene.skeleton.bones);
    array_free(scene.bone_transforms);
}

init :: (buffer: *Windowed_Program_3D_Bone_Animation_Buffer) {
    for i: 0..WINDOWED_PROGRAM_3D_MAX_BONES - 1 buffer.matrices[i] = Matrix4_Identity;

    glGenBuffers(1, *buffer.gl_uniform_buffer_handle);
    glBindBuffer(GL_UNIFORM_BUFFER, buffer.gl_uniform_buffer_handle);
    glBufferData(GL_UNIFORM_BUFFER, WINDOWED_PROGRAM_3D_MAX_BONES * size_of(Matrix4), buffer.matrices.data, GL_DYNAMIC_DRAW);
    glBindBufferBase(GL_UNIFORM_BUFFER, WINDOWED_PROGRAM_3D_BONE_UBO_BINDING, buffer.gl_uniform_buffer_handle);
    glBindBuffer(GL_UNIFORM_BUFFER, 0);
    buffer.initialized = true;
}

deinit :: (buffer: *Windowed_Program_3D_Bone_Animation_Buffer) {
    if buffer.gl_uniform_buffer_handle != 0 glDeleteBuffers(1, *buffer.gl_uniform_buffer_handle);
    buffer.* = .{};
}

upload :: (buffer: *Windowed_Program_3D_Bone_Animation_Buffer) {
    if !buffer.initialized return;

    glBindBuffer(GL_UNIFORM_BUFFER, buffer.gl_uniform_buffer_handle);
    glBufferSubData(GL_UNIFORM_BUFFER, 0, WINDOWED_PROGRAM_3D_MAX_BONES * size_of(Matrix4), buffer.matrices.data);
    glBindBufferBase(GL_UNIFORM_BUFFER, WINDOWED_PROGRAM_3D_BONE_UBO_BINDING, buffer.gl_uniform_buffer_handle);
    glBindBuffer(GL_UNIFORM_BUFFER, 0);
}

bind_windowed_program_3d_bone_animation_block :: (shader_program_gl_handle: GLuint) {
    block_name := temp_c_string("BoneAnimationTransforms");
    block_index := glGetUniformBlockIndex(shader_program_gl_handle, block_name);
    if block_index == GL_INVALID_INDEX return;
    glUniformBlockBinding(shader_program_gl_handle, block_index, WINDOWED_PROGRAM_3D_BONE_UBO_BINDING);
}

windowed_program_3d_packed_lookup_for_texture_index :: (
    scene: *Base_Scene,
    lookup_table: *Table(string, Packed_Texture_Lookup),
    texture_index: s32
) -> texture_layer: s32, bounding_box_index: s32 {
    if texture_index < 0 || texture_index >= scene.texture_paths.count return -1, -1;
    texture_path := scene.texture_paths[texture_index];
    if texture_path.count == 0 return -1, -1;

    lookup, found := find_packed_texture(lookup_table, texture_path);
    if !found {
        log("Could not find packed material texture '%'; using shader fallback", texture_path);
        return -1, -1;
    }

    return lookup.container_index, lookup.metadata_index;
}

upload_windowed_program_3d_blinn_phong_material_table :: (wp3: *Windowed_Program_3D, scene: *Blinn_Phong_Scene) {
    if wp3.blinn_phong_packed_resources.material_table_gl_id != 0 glDeleteTextures(1, *wp3.blinn_phong_packed_resources.material_table_gl_id);
    wp3.blinn_phong_packed_resources.material_table_gl_id = 0;

    lookup_table := build_packed_texture_lookup_table(*wp3.blinn_phong_packed_resources.metadata);

    material_texels: [WINDOWED_PROGRAM_3D_BLINN_PHONG_MATERIAL_TABLE_TEXELS] Vector4;
    material_count := min(scene.materials.count, GPU_STYLE_BLINN_PHONG_MAX_MATERIALS);

    for material_index: 0..material_count - 1 {
        material := scene.materials[material_index];
        diffuse_layer, diffuse_bbox := windowed_program_3d_packed_lookup_for_texture_index(*scene.base, *lookup_table, material.diffuse_texture_index);
        normal_layer, normal_bbox := windowed_program_3d_packed_lookup_for_texture_index(*scene.base, *lookup_table, material.normal_texture_index);
        sg_layer, sg_bbox := windowed_program_3d_packed_lookup_for_texture_index(*scene.base, *lookup_table, material.specular_glossiness_texture_index);

        texel_index := material_index * WINDOWED_PROGRAM_3D_BLINN_PHONG_MATERIAL_TABLE_SLOTS;
        material_texels[texel_index + 0] = .{cast(float32)diffuse_layer, cast(float32)diffuse_bbox, 0, 0};
        material_texels[texel_index + 1] = material.diffuse_factor;
        material_texels[texel_index + 2] = .{cast(float32)normal_layer, cast(float32)normal_bbox, material.normal_texture_scale, 0};
        material_texels[texel_index + 3] = .{
            cast(float32)sg_layer,
            cast(float32)sg_bbox,
            clamp01(material.glossiness_factor),
            0
        };
        material_texels[texel_index + 4] = .{material.specular_factor.x, material.specular_factor.y, material.specular_factor.z, 1};
    }

    glActiveTexture(GL_TEXTURE2);
    glGenTextures(1, *wp3.blinn_phong_packed_resources.material_table_gl_id);
    glBindTexture(GL_TEXTURE_1D, wp3.blinn_phong_packed_resources.material_table_gl_id);
    glTexImage1D(GL_TEXTURE_1D, 0, GL_RGBA32F, WINDOWED_PROGRAM_3D_BLINN_PHONG_MATERIAL_TABLE_TEXELS, 0, GL_RGBA, GL_FLOAT, material_texels.data);
    glTexParameteri(GL_TEXTURE_1D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_1D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_1D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glActiveTexture(GL_TEXTURE0);
}

upload_windowed_program_3d_pbr_material_table :: (wp3: *Windowed_Program_3D, base_scene: *Base_Scene, materials: [] GPU_Style_PBR_Material) {
    if wp3.pbr_material_table_gl_id != 0 glDeleteTextures(1, *wp3.pbr_material_table_gl_id);
    wp3.pbr_packed_resources.material_table_gl_id = 0;

    lookup_table := build_packed_texture_lookup_table(*wp3.pbr_packed_resources.metadata);

    material_texels: [WINDOWED_PROGRAM_3D_PBR_MATERIAL_TABLE_TEXELS] Vector4;
    material_count := min(materials.count, WINDOWED_PROGRAM_3D_PBR_MAX_MATERIALS);

    for material_index: 0..material_count - 1 {
        material := materials[material_index];
        base_layer, base_bbox := windowed_program_3d_packed_lookup_for_texture_index(base_scene, *lookup_table, material.base_color_texture_index);
        normal_layer, normal_bbox := windowed_program_3d_packed_lookup_for_texture_index(base_scene, *lookup_table, material.normal_texture_index);
        mr_layer, mr_bbox := windowed_program_3d_packed_lookup_for_texture_index(base_scene, *lookup_table, material.metallic_roughness_texture_index);

        texel_index := material_index * WINDOWED_PROGRAM_3D_PBR_MATERIAL_TABLE_SLOTS;
        material_texels[texel_index + 0] = .{cast(float32)base_layer, cast(float32)base_bbox, 0, 0};
        material_texels[texel_index + 1] = material.base_color_factor;
        material_texels[texel_index + 2] = .{cast(float32)normal_layer, cast(float32)normal_bbox, 0, 0};
        material_texels[texel_index + 3] = .{
            cast(float32)mr_layer,
            cast(float32)mr_bbox,
            clamp01(material.metallic_factor),
            min(max(material.roughness_factor, 0.04), 1.0)
        };
    }

    glActiveTexture(GL_TEXTURE2);
    glGenTextures(1, *wp3.pbr_material_table_gl_id);
    wp3.pbr_packed_resources.material_table_gl_id = wp3.pbr_material_table_gl_id;
    glBindTexture(GL_TEXTURE_1D, wp3.pbr_material_table_gl_id);
    glTexImage1D(GL_TEXTURE_1D, 0, GL_RGBA32F, WINDOWED_PROGRAM_3D_PBR_MATERIAL_TABLE_TEXELS, 0, GL_RGBA, GL_FLOAT, material_texels.data);
    glTexParameteri(GL_TEXTURE_1D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_1D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_1D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glActiveTexture(GL_TEXTURE0);
}

upload_windowed_program_3d_pbr_material_table :: (wp3: *Windowed_Program_3D, scene: *PBR_Scene) {
    upload_windowed_program_3d_pbr_material_table(wp3, *scene.base, scene.materials);
}

upload_windowed_program_3d_pbr_material_table :: (wp3: *Windowed_Program_3D, scene: *PBR_Lightmapped_Scene) {
    upload_windowed_program_3d_pbr_material_table(wp3, *scene.base, scene.materials);
}

upload_windowed_program_3d_pbr_material_table :: (wp3: *Windowed_Program_3D, scene: *Windowed_Program_3D_PBR_Skeletal_Scene) {
    upload_windowed_program_3d_pbr_material_table(wp3, *scene.base, scene.materials);
}

upload_windowed_program_3d_pbr_lightmap_f32 :: (wp3: *Windowed_Program_3D, scene: *PBR_Lightmapped_Scene) -> bool {
    if wp3.pbr_packed_resources.lightmap_texture_gl_id != 0 {
        glDeleteTextures(1, *wp3.pbr_packed_resources.lightmap_texture_gl_id);
        wp3.pbr_packed_resources.lightmap_texture_gl_id = 0;
    }

    if scene.lightmap_f32_pixels.count == 0 || scene.lightmap_f32_width == 0 || scene.lightmap_f32_height == 0 {
        log_error("Lightmapped PBR scene has no float lightmap pixels to upload");
        return false;
    }

    expected_count := cast(int)scene.lightmap_f32_width * cast(int)scene.lightmap_f32_height * 4;
    if scene.lightmap_f32_pixels.count < expected_count {
        log_error(
            "Lightmapped PBR scene float lightmap is truncated: pixels=%, expected=%",
            scene.lightmap_f32_pixels.count,
            expected_count
        );
        return false;
    }

    glActiveTexture(GL_TEXTURE3);
    glGenTextures(1, *wp3.pbr_packed_resources.lightmap_texture_gl_id);
    glBindTexture(GL_TEXTURE_2D, wp3.pbr_packed_resources.lightmap_texture_gl_id);
    glTexImage2D(
        GL_TEXTURE_2D,
        0,
        GL_RGBA32F,
        xx scene.lightmap_f32_width,
        xx scene.lightmap_f32_height,
        0,
        GL_RGBA,
        GL_FLOAT,
        scene.lightmap_f32_pixels.data
    );
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glActiveTexture(GL_TEXTURE0);

    wp3.pbr_packed_resources.lightmap_width = scene.lightmap_f32_width;
    wp3.pbr_packed_resources.lightmap_height = scene.lightmap_f32_height;
    return true;
}

init_windowed_program_3d_blinn_phong_packed_resources :: (wp3: *Windowed_Program_3D, scene: *Blinn_Phong_Scene) {
    deinit(*wp3.blinn_phong_packed_resources);

    texture_paths: [..] string;
    defer array_free(texture_paths);
    for path: scene.texture_paths {
        if path.count > 0 array_add(*texture_paths, path);
    }

    if texture_paths.count > 0 {
        pack_texture_paths(4096, true, texture_paths);
    }

    init(*wp3.blinn_phong_packed_resources.packed_texture_base);
    wp3.blinn_phong_packed_resources.initialized = true;
    upload_windowed_program_3d_blinn_phong_material_table(wp3, scene);
}

init_windowed_program_3d_pbr_packed_resources :: (wp3: *Windowed_Program_3D, base_scene: *Base_Scene, materials: [] GPU_Style_PBR_Material) {
    deinit(*wp3.pbr_packed_resources);
    wp3.pbr_material_table_gl_id = 0;

    texture_paths: [..] string;
    defer array_free(texture_paths);
    for path: base_scene.texture_paths {
        if path.count > 0 array_add(*texture_paths, path);
    }

    if texture_paths.count > 0 {
        pack_texture_paths(4096, true, texture_paths);
    }

    init(*wp3.pbr_packed_resources.packed_texture_base);
    wp3.pbr_packed_resources.initialized = true;
    upload_windowed_program_3d_pbr_material_table(wp3, base_scene, materials);
}

init_windowed_program_3d_pbr_packed_resources :: (wp3: *Windowed_Program_3D, scene: *PBR_Scene) {
    init_windowed_program_3d_pbr_packed_resources(wp3, *scene.base, scene.materials);
}

init_windowed_program_3d_pbr_packed_resources :: (wp3: *Windowed_Program_3D, scene: *PBR_Lightmapped_Scene) {
    init_windowed_program_3d_pbr_packed_resources(wp3, *scene.base, scene.materials);
    upload_windowed_program_3d_pbr_lightmap_f32(wp3, scene);
}

init_windowed_program_3d_pbr_packed_resources :: (wp3: *Windowed_Program_3D, scene: *Windowed_Program_3D_PBR_Skeletal_Scene) {
    init_windowed_program_3d_pbr_packed_resources(wp3, *scene.base, scene.materials);
}

windowed_program_3d_light_clip_matrix :: (using wp3: *Windowed_Program_3D) -> Matrix4 {
    direction := normalize(pbr_light_direction);
    up_reference := Vector3.{0, 1, 0};
    if abs(dot(direction, up_reference)) > 0.95 up_reference = .{0, 0, 1};

    right := normalize(cross(direction, up_reference));
    up := cross(right, direction);
    eye := pbr_shadow_center - direction * (pbr_shadow_depth_extent * 0.5);

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
        left = -pbr_shadow_half_extent,
        right = pbr_shadow_half_extent,
        bottom = -pbr_shadow_half_extent,
        top = pbr_shadow_half_extent,
        near = -pbr_shadow_depth_extent,
        far = pbr_shadow_depth_extent,
        depth_range_01 = false
    );

    return light_to_clip * world_to_light;
}

windowed_program_3d_render_path :: (wp3: *Windowed_Program_3D) -> Windowed_Program_3D_Render_Path {
    if wp3.render_model == .Vertex_Color && wp3.vertex_color_renderables.count > 0 return .Vertex_Color;
    if wp3.render_model == .Blinn_Phong && wp3.blinn_phong_renderables.count > 0 return .Blinn_Phong;
    if wp3.render_model == .PBR && wp3.pbr_skeletal_renderables.count > 0 {
        if wp3.directional_shadows return .PBR_Directional_Shadows_Skeletal;
        return .PBR_Skeletal;
    }
    if wp3.render_model == .PBR && wp3.pbr_lightmapped_renderables.count > 0 return .PBR_Lightmapped;
    if wp3.render_model == .PBR && wp3.pbr_renderables.count > 0 {
        if wp3.directional_shadows return .PBR_Directional_Shadows;
        return .PBR;
    }
    return .Legacy_Color;
}

apply_windowed_program_3d_vertex_color_uniforms :: (
    wp3: *Windowed_Program_3D,
    renderer: *Gpu_Style_Vertex_Color_Renderer,
    world_to_camera: Matrix4,
    camera_to_clip: Matrix4
) {
    glUseProgram(renderer.shader_program_gl_handle);
    set_world_to_camera_uniform(renderer, world_to_camera);
    set_camera_to_clip_uniform(renderer, camera_to_clip);
    glUseProgram(0);
}

apply_windowed_program_3d_blinn_phong_uniforms :: (
    wp3: *Windowed_Program_3D,
    renderer: *Gpu_Style_Blinn_Phong_Renderer,
    world_to_camera: Matrix4,
    camera_to_clip: Matrix4
) {
    glUseProgram(renderer.shader_program_gl_handle);
    set_world_to_camera_uniform(renderer, world_to_camera);
    set_camera_to_clip_uniform(renderer, camera_to_clip);
    set_camera_position_uniform(renderer, wp3.camera.position);
    set_ambient_uniform(renderer, 0.16);
    set_specular_strength_uniform(renderer, 0.25);
    set_fallback_light_direction_uniform(renderer, normalize(Vector3.{0.35, 0.80, 0.45}));

    directional_count := ifx wp3.loaded_blinn_phong_scene_valid then min(wp3.loaded_blinn_phong_scene.directional_lights.count, 1) else 0;
    set_directional_light_count_uniform(renderer, xx directional_count);
    if directional_count > 0 {
        light := wp3.loaded_blinn_phong_scene.directional_lights[0];
        set_directional_light_0_direction_uniform(renderer, normalize_hot(light.direction));
        set_directional_light_0_color_uniform(renderer, light.color);
        set_directional_light_0_intensity_uniform(renderer, light.intensity);
    }

    point_count := ifx wp3.loaded_blinn_phong_scene_valid then min(wp3.loaded_blinn_phong_scene.point_lights.count, 1) else 0;
    set_point_light_count_uniform(renderer, xx point_count);
    if point_count > 0 {
        light := wp3.loaded_blinn_phong_scene.point_lights[0];
        set_point_light_0_position_uniform(renderer, light.position);
        set_point_light_0_color_uniform(renderer, light.color);
        set_point_light_0_intensity_uniform(renderer, light.intensity);
        set_point_light_0_range_uniform(renderer, light.range);
    }

    spot_count := ifx wp3.loaded_blinn_phong_scene_valid then min(wp3.loaded_blinn_phong_scene.spot_lights.count, 1) else 0;
    set_spot_light_count_uniform(renderer, xx spot_count);
    if spot_count > 0 {
        light := wp3.loaded_blinn_phong_scene.spot_lights[0];
        set_spot_light_0_position_uniform(renderer, light.position);
        set_spot_light_0_direction_uniform(renderer, normalize_hot(light.direction));
        set_spot_light_0_color_uniform(renderer, light.color);
        set_spot_light_0_intensity_uniform(renderer, light.intensity);
        set_spot_light_0_range_uniform(renderer, light.range);
        set_spot_light_0_inner_cos_uniform(renderer, light.inner_cos);
        set_spot_light_0_outer_cos_uniform(renderer, light.outer_cos);
    }

    set_packed_textures_uniform(renderer, 0);
    set_packed_texture_bounding_boxes_uniform(renderer, 1);
    set_blinn_phong_material_table_uniform(renderer, 2);
    glUseProgram(0);
}

apply_windowed_program_3d_pbr_uniforms :: (
    wp3: *Windowed_Program_3D,
    renderer: *Gpu_Style_Pbr_Renderer,
    world_to_camera: Matrix4,
    camera_to_clip: Matrix4
) {
    glUseProgram(renderer.shader_program_gl_handle);
    set_world_to_camera_uniform(renderer, world_to_camera);
    set_camera_to_clip_uniform(renderer, camera_to_clip);
    set_camera_position_uniform(renderer, wp3.camera.position);
    set_ambient_strength_uniform(renderer, wp3.pbr_ambient_strength);
    set_directional_light_count_uniform(renderer, 1);
    set_directional_light_0_direction_uniform(renderer, normalize(wp3.pbr_light_direction));
    set_directional_light_0_color_uniform(renderer, wp3.pbr_light_color);
    set_directional_light_0_intensity_uniform(renderer, wp3.pbr_light_intensity);
    set_packed_textures_uniform(renderer, 0);
    set_packed_texture_bounding_boxes_uniform(renderer, 1);
    set_pbr_material_table_uniform(renderer, 2);
    glUseProgram(0);
}

apply_windowed_program_3d_pbr_uniforms :: (
    wp3: *Windowed_Program_3D,
    renderer: *Gpu_Style_Pbr_Lightmapped_Renderer,
    world_to_camera: Matrix4,
    camera_to_clip: Matrix4
) {
    glUseProgram(renderer.shader_program_gl_handle);
    set_world_to_camera_uniform(renderer, world_to_camera);
    set_camera_to_clip_uniform(renderer, camera_to_clip);
    set_camera_position_uniform(renderer, wp3.camera.position);
    set_ambient_strength_uniform(renderer, wp3.pbr_ambient_strength);
    set_directional_light_count_uniform(renderer, 1);
    set_directional_light_0_direction_uniform(renderer, normalize(wp3.pbr_light_direction));
    set_directional_light_0_color_uniform(renderer, wp3.pbr_light_color);
    set_directional_light_0_intensity_uniform(renderer, wp3.pbr_light_intensity);
    set_packed_textures_uniform(renderer, 0);
    set_packed_texture_bounding_boxes_uniform(renderer, 1);
    set_pbr_material_table_uniform(renderer, 2);
    set_lightmap_texture_uniform(renderer, 3);
    glUseProgram(0);
}

apply_windowed_program_3d_pbr_uniforms :: (
    wp3: *Windowed_Program_3D,
    renderer: *Gpu_Style_Pbr_Directional_Shadows_Renderer,
    world_to_camera: Matrix4,
    camera_to_clip: Matrix4,
    world_to_light_clip: Matrix4
) {
    glUseProgram(renderer.shader_program_gl_handle);
    set_world_to_camera_uniform(renderer, world_to_camera);
    set_camera_to_clip_uniform(renderer, camera_to_clip);
    set_world_to_light_clip_uniform(renderer, world_to_light_clip);
    set_camera_position_uniform(renderer, wp3.camera.position);
    set_ambient_strength_uniform(renderer, wp3.pbr_ambient_strength);
    set_directional_light_count_uniform(renderer, 1);
    set_directional_light_0_direction_uniform(renderer, normalize(wp3.pbr_light_direction));
    set_directional_light_0_color_uniform(renderer, wp3.pbr_light_color);
    set_directional_light_0_intensity_uniform(renderer, wp3.pbr_light_intensity);
    set_directional_shadow_map_uniform(renderer, 3);
    set_use_directional_shadow_map_uniform(renderer, wp3.pbr_shadow_map.initialized && wp3.directional_shadows);
    set_packed_textures_uniform(renderer, 0);
    set_packed_texture_bounding_boxes_uniform(renderer, 1);
    set_pbr_material_table_uniform(renderer, 2);
    glUseProgram(0);
}

apply_windowed_program_3d_pbr_uniforms :: (
    wp3: *Windowed_Program_3D,
    renderer: *Gpu_Style_Pbr_Skeletal_Animation_Renderer,
    world_to_camera: Matrix4,
    camera_to_clip: Matrix4
) {
    glUseProgram(renderer.shader_program_gl_handle);
    set_world_to_camera_uniform(renderer, world_to_camera);
    set_camera_to_clip_uniform(renderer, camera_to_clip);
    set_camera_position_uniform(renderer, wp3.camera.position);
    set_ambient_strength_uniform(renderer, wp3.pbr_ambient_strength);
    set_directional_light_count_uniform(renderer, 1);
    set_directional_light_0_direction_uniform(renderer, normalize(wp3.pbr_light_direction));
    set_directional_light_0_color_uniform(renderer, wp3.pbr_light_color);
    set_directional_light_0_intensity_uniform(renderer, wp3.pbr_light_intensity);
    set_packed_textures_uniform(renderer, 0);
    set_packed_texture_bounding_boxes_uniform(renderer, 1);
    set_pbr_material_table_uniform(renderer, 2);
    glUseProgram(0);
}

apply_windowed_program_3d_pbr_uniforms :: (
    wp3: *Windowed_Program_3D,
    renderer: *Gpu_Style_Pbr_Directional_Shadows_Skeletal_Animation_Renderer,
    world_to_camera: Matrix4,
    camera_to_clip: Matrix4,
    world_to_light_clip: Matrix4
) {
    glUseProgram(renderer.shader_program_gl_handle);
    set_world_to_camera_uniform(renderer, world_to_camera);
    set_camera_to_clip_uniform(renderer, camera_to_clip);
    set_world_to_light_clip_uniform(renderer, world_to_light_clip);
    set_camera_position_uniform(renderer, wp3.camera.position);
    set_ambient_strength_uniform(renderer, wp3.pbr_ambient_strength);
    set_directional_light_count_uniform(renderer, 1);
    set_directional_light_0_direction_uniform(renderer, normalize(wp3.pbr_light_direction));
    set_directional_light_0_color_uniform(renderer, wp3.pbr_light_color);
    set_directional_light_0_intensity_uniform(renderer, wp3.pbr_light_intensity);
    set_directional_shadow_map_uniform(renderer, 3);
    set_use_directional_shadow_map_uniform(renderer, wp3.pbr_shadow_map.initialized && wp3.directional_shadows);
    set_packed_textures_uniform(renderer, 0);
    set_packed_texture_bounding_boxes_uniform(renderer, 1);
    set_pbr_material_table_uniform(renderer, 2);
    glUseProgram(0);
}

render_windowed_program_3d_shadow_map :: (using wp3: *Windowed_Program_3D, world_to_light_clip: Matrix4) {
    if !pbr_shadow_map.initialized return;

    pbr_shadow_map.world_to_light_clip = world_to_light_clip;

    glViewport(0, 0, WINDOWED_PROGRAM_3D_SHADOW_MAP_SIZE, WINDOWED_PROGRAM_3D_SHADOW_MAP_SIZE);
    glBindFramebuffer(GL_FRAMEBUFFER, pbr_shadow_map.framebuffer_gl_handle);
    glClear(GL_DEPTH_BUFFER_BIT);

    glUseProgram(pbr_shadow_depth_renderer.shader_program_gl_handle);
    set_world_to_light_clip_uniform(*pbr_shadow_depth_renderer, world_to_light_clip);
    glUseProgram(0);

    for renderable: pbr_renderables queue_render(*pbr_shadow_depth_renderer, renderable.shadow_depth);
    render(*pbr_shadow_depth_renderer);

    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glDrawBuffer(GL_BACK);
    glReadBuffer(GL_BACK);
    glViewport(0, 0, cast(u32) window_width, cast(u32) window_height);
}

render_windowed_program_3d_skeletal_shadow_map :: (using wp3: *Windowed_Program_3D, world_to_light_clip: Matrix4) {
    if !pbr_shadow_map.initialized return;

    pbr_shadow_map.world_to_light_clip = world_to_light_clip;

    glViewport(0, 0, WINDOWED_PROGRAM_3D_SHADOW_MAP_SIZE, WINDOWED_PROGRAM_3D_SHADOW_MAP_SIZE);
    glBindFramebuffer(GL_FRAMEBUFFER, pbr_shadow_map.framebuffer_gl_handle);
    glClear(GL_DEPTH_BUFFER_BIT);

    glUseProgram(pbr_skeletal_shadow_depth_renderer.shader_program_gl_handle);
    set_world_to_light_clip_uniform(*pbr_skeletal_shadow_depth_renderer, world_to_light_clip);
    glUseProgram(0);

    for renderable: pbr_skeletal_renderables queue_render(*pbr_skeletal_shadow_depth_renderer, renderable.shadow_depth);
    render(*pbr_skeletal_shadow_depth_renderer);

    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glDrawBuffer(GL_BACK);
    glReadBuffer(GL_BACK);
    glViewport(0, 0, cast(u32) window_width, cast(u32) window_height);
}

render_windowed_program_3d_pbr_scene :: (using wp3: *Windowed_Program_3D) {
    bind_windowed_program_3d_pbr_material_table(wp3);

    path := windowed_program_3d_render_path(wp3);
    if path == .PBR_Directional_Shadows {
        world_to_light_clip := windowed_program_3d_light_clip_matrix(wp3);
        render_windowed_program_3d_shadow_map(wp3, world_to_light_clip);

        glActiveTexture(GL_TEXTURE3);
        glBindTexture(GL_TEXTURE_2D, pbr_shadow_map.depth_texture_gl_handle);
        glActiveTexture(GL_TEXTURE0);

        glUseProgram(pbr_shadowed_renderer.shader_program_gl_handle);
        set_world_to_light_clip_uniform(*pbr_shadowed_renderer, world_to_light_clip);
        set_use_directional_shadow_map_uniform(*pbr_shadowed_renderer, pbr_shadow_map.initialized);
        glUseProgram(0);

        for renderable: pbr_renderables queue_render(*pbr_shadowed_renderer, renderable.shadowed);
        render(*pbr_shadowed_renderer);
        return;
    }

    for renderable: pbr_renderables queue_render(*pbr_renderer, renderable.base);
    render(*pbr_renderer);
}

render_windowed_program_3d_pbr_lightmapped_scene :: (using wp3: *Windowed_Program_3D) {
    bind_windowed_program_3d_pbr_material_table(wp3);
    glActiveTexture(GL_TEXTURE3);
    glBindTexture(GL_TEXTURE_2D, pbr_packed_resources.lightmap_texture_gl_id);
    glActiveTexture(GL_TEXTURE0);

    for renderable: pbr_lightmapped_renderables queue_render(*pbr_lightmapped_renderer, renderable.base);
    render(*pbr_lightmapped_renderer);
}

render_windowed_program_3d_pbr_skeletal_scene :: (using wp3: *Windowed_Program_3D) {
    bind_windowed_program_3d_pbr_material_table(wp3);
    upload(*pbr_bone_animation_buffer);

    path := windowed_program_3d_render_path(wp3);
    if path == .PBR_Directional_Shadows_Skeletal {
        world_to_light_clip := windowed_program_3d_light_clip_matrix(wp3);
        render_windowed_program_3d_skeletal_shadow_map(wp3, world_to_light_clip);

        glActiveTexture(GL_TEXTURE3);
        glBindTexture(GL_TEXTURE_2D, pbr_shadow_map.depth_texture_gl_handle);
        glActiveTexture(GL_TEXTURE0);

        glUseProgram(pbr_skeletal_shadowed_renderer.shader_program_gl_handle);
        set_world_to_light_clip_uniform(*pbr_skeletal_shadowed_renderer, world_to_light_clip);
        set_use_directional_shadow_map_uniform(*pbr_skeletal_shadowed_renderer, pbr_shadow_map.initialized);
        glUseProgram(0);

        for renderable: pbr_skeletal_renderables queue_render(*pbr_skeletal_shadowed_renderer, renderable.shadowed);
        render(*pbr_skeletal_shadowed_renderer);
        return;
    }

    for renderable: pbr_skeletal_renderables queue_render(*pbr_skeletal_renderer, renderable.base);
    render(*pbr_skeletal_renderer);
}

render_windowed_program_3d_vertex_color_scene :: (using wp3: *Windowed_Program_3D) {
    for renderable: vertex_color_renderables queue_render(*vertex_color_renderer, renderable);
    render(*vertex_color_renderer);
}

render_windowed_program_3d_blinn_phong_scene :: (using wp3: *Windowed_Program_3D) {
    bind_windowed_program_3d_blinn_phong_material_table(wp3);

    for renderable: blinn_phong_renderables queue_render(*blinn_phong_renderer, renderable);
    render(*blinn_phong_renderer);
}

add_vertex_color_renderable :: (
    wp3: *Windowed_Program_3D,
    geometry: $T/interface Windowed_Program_3D_Vertex_Color_Geometry,
    local_to_world: Matrix4 = Matrix4_Identity
) -> *Gpu_Style_Vertex_Color_Renderable {
    renderable := array_add(*wp3.vertex_color_renderables);

    assign_geometry_copy(renderable, geometry);

    if !buffer_object(*wp3.vertex_color_renderer, renderable) {
        log_error("Failed to buffer Windowed_Program_3D vertex-color renderable");
        return null;
    }

    set_local_to_world_matrix(*wp3.vertex_color_renderer, renderable.*, local_to_world);
    return renderable;
}

add_blinn_phong_renderable :: (
    wp3: *Windowed_Program_3D,
    geometry: $T/interface Windowed_Program_3D_Blinn_Phong_Geometry,
    local_to_world: Matrix4 = Matrix4_Identity
) -> *Gpu_Style_Blinn_Phong_Renderable {
    renderable := array_add(*wp3.blinn_phong_renderables);

    assign_geometry_copy(renderable, geometry);

    if !buffer_object(*wp3.blinn_phong_renderer, renderable) {
        log_error("Failed to buffer Windowed_Program_3D Blinn-Phong renderable");
        return null;
    }

    set_local_to_world_matrix(*wp3.blinn_phong_renderer, renderable.*, local_to_world);
    return renderable;
}

add_pbr_renderable :: (
    wp3: *Windowed_Program_3D,
    geometry: $T/interface Windowed_Program_3D_PBR_Geometry,
    local_to_world: Matrix4 = Matrix4_Identity
) -> *Windowed_Program_3D_PBR_Renderable {
    renderable := array_add(*wp3.pbr_renderables);

    assign_geometry_copy(*renderable.base, geometry);
    assign_geometry_copy(*renderable.shadowed, geometry);
    array_copy(*renderable.shadow_depth.indices, geometry.indices);
    array_copy(*renderable.shadow_depth.positions, geometry.positions);

    base_ok := buffer_object(*wp3.pbr_renderer, *renderable.base);
    shadowed_ok := buffer_object(*wp3.pbr_shadowed_renderer, *renderable.shadowed);
    depth_ok := buffer_object(*wp3.pbr_shadow_depth_renderer, *renderable.shadow_depth);

    if !base_ok || !shadowed_ok || !depth_ok {
        log_error("Failed to buffer Windowed_Program_3D PBR renderable");
        return null;
    }

    set_local_to_world_matrix(*wp3.pbr_renderer, renderable.base, local_to_world);
    set_local_to_world_matrix(*wp3.pbr_shadowed_renderer, renderable.shadowed, local_to_world);
    set_local_to_world_matrix(*wp3.pbr_shadow_depth_renderer, renderable.shadow_depth, local_to_world);
    return renderable;
}

add_pbr_lightmapped_renderable :: (
    wp3: *Windowed_Program_3D,
    geometry: $T/interface Windowed_Program_3D_PBR_Lightmapped_Geometry,
    local_to_world: Matrix4 = Matrix4_Identity
) -> *Windowed_Program_3D_PBR_Lightmapped_Renderable {
    renderable := array_add(*wp3.pbr_lightmapped_renderables);

    assign_geometry_copy(*renderable.base, geometry);

    if !buffer_object(*wp3.pbr_lightmapped_renderer, *renderable.base) {
        log_error("Failed to buffer Windowed_Program_3D lightmapped PBR renderable");
        return null;
    }

    set_local_to_world_matrix(*wp3.pbr_lightmapped_renderer, renderable.base, local_to_world);
    return renderable;
}

add_pbr_skeletal_renderable :: (
    wp3: *Windowed_Program_3D,
    geometry: $T/interface Windowed_Program_3D_PBR_Skeletal_Geometry,
    local_to_world: Matrix4 = Matrix4_Identity
) -> *Windowed_Program_3D_PBR_Skeletal_Renderable {
    renderable := array_add(*wp3.pbr_skeletal_renderables);

    assign_geometry_copy(*renderable.base, geometry);
    assign_geometry_copy(*renderable.shadowed, geometry);
    array_copy(*renderable.shadow_depth.indices, geometry.indices);
    array_copy(*renderable.shadow_depth.positions, geometry.positions);
    array_copy(*renderable.shadow_depth.bone_transform_indices, geometry.bone_transform_indices);
    array_copy(*renderable.shadow_depth.bone_weights, geometry.bone_weights);

    base_ok := buffer_object(*wp3.pbr_skeletal_renderer, *renderable.base);
    shadowed_ok := buffer_object(*wp3.pbr_skeletal_shadowed_renderer, *renderable.shadowed);
    depth_ok := buffer_object(*wp3.pbr_skeletal_shadow_depth_renderer, *renderable.shadow_depth);

    if !base_ok || !shadowed_ok || !depth_ok {
        log_error("Failed to buffer Windowed_Program_3D skeletal PBR renderable");
        return null;
    }

    set_local_to_world_matrix(*wp3.pbr_skeletal_renderer, renderable.base, local_to_world);
    set_local_to_world_matrix(*wp3.pbr_skeletal_shadowed_renderer, renderable.shadowed, local_to_world);
    set_local_to_world_matrix(*wp3.pbr_skeletal_shadow_depth_renderer, renderable.shadow_depth, local_to_world);
    return renderable;
}

clear_pbr_renderables :: (using wp3: *Windowed_Program_3D) {
    for * renderable: pbr_renderables {
        deinit(*renderable.base, *pbr_renderer);
        deinit(*renderable.shadowed, *pbr_shadowed_renderer);
        deinit(*renderable.shadow_depth, *pbr_shadow_depth_renderer);
    }
    array_reset(*pbr_renderables);
}

clear_pbr_lightmapped_renderables :: (using wp3: *Windowed_Program_3D) {
    for * renderable: pbr_lightmapped_renderables {
        deinit(*renderable.base, *pbr_lightmapped_renderer);
    }
    array_reset(*pbr_lightmapped_renderables);
}

clear_pbr_skeletal_renderables :: (using wp3: *Windowed_Program_3D) {
    for * renderable: pbr_skeletal_renderables {
        deinit(*renderable.base, *pbr_skeletal_renderer);
        deinit(*renderable.shadowed, *pbr_skeletal_shadowed_renderer);
        deinit(*renderable.shadow_depth, *pbr_skeletal_shadow_depth_renderer);
    }
    array_reset(*pbr_skeletal_renderables);
}

clear_vertex_color_renderables :: (using wp3: *Windowed_Program_3D) {
    for * renderable: vertex_color_renderables {
        deinit(renderable, *vertex_color_renderer);
    }
    array_reset(*vertex_color_renderables);
}

clear_blinn_phong_renderables :: (using wp3: *Windowed_Program_3D) {
    for * renderable: blinn_phong_renderables {
        deinit(renderable, *blinn_phong_renderer);
    }
    array_reset(*blinn_phong_renderables);
}

clear_loaded_vertex_color_scene :: (using wp3: *Windowed_Program_3D) {
    clear_vertex_color_renderables(wp3);

    if loaded_vertex_color_scene_valid {
        deinit(*loaded_vertex_color_scene);
        loaded_vertex_color_scene_valid = false;
    }
}

clear_loaded_blinn_phong_scene :: (using wp3: *Windowed_Program_3D) {
    clear_blinn_phong_renderables(wp3);

    if loaded_blinn_phong_scene_valid {
        deinit(*loaded_blinn_phong_scene);
        loaded_blinn_phong_scene_valid = false;
    }

    deinit(*blinn_phong_packed_resources);
}

clear_loaded_pbr_scene :: (using wp3: *Windowed_Program_3D, restore_default_material: bool = true) {
    clear_pbr_renderables(wp3);

    if loaded_pbr_scene_valid {
        deinit(*loaded_pbr_scene);
        loaded_pbr_scene_valid = false;
    }

    deinit(*pbr_packed_resources);
    if pbr_material_table_gl_id != 0 {
        glDeleteTextures(1, *pbr_material_table_gl_id);
        pbr_material_table_gl_id = 0;
    }

    if restore_default_material init_windowed_program_3d_default_pbr_material_table(wp3);
}

clear_loaded_pbr_lightmapped_scene :: (using wp3: *Windowed_Program_3D, restore_default_material: bool = true) {
    clear_pbr_lightmapped_renderables(wp3);

    if loaded_pbr_lightmapped_scene_valid {
        deinit(*loaded_pbr_lightmapped_scene);
        loaded_pbr_lightmapped_scene_valid = false;
    }

    deinit(*pbr_packed_resources);
    if pbr_material_table_gl_id != 0 {
        glDeleteTextures(1, *pbr_material_table_gl_id);
        pbr_material_table_gl_id = 0;
    }

    if restore_default_material init_windowed_program_3d_default_pbr_material_table(wp3);
}

clear_loaded_pbr_skeletal_scene :: (using wp3: *Windowed_Program_3D, restore_default_material: bool = true) {
    clear_pbr_skeletal_renderables(wp3);

    if loaded_pbr_skeletal_scene_valid {
        deinit(*loaded_pbr_skeletal_scene);
        loaded_pbr_skeletal_scene_valid = false;
    }

    deinit(*pbr_packed_resources);
    if pbr_material_table_gl_id != 0 {
        glDeleteTextures(1, *pbr_material_table_gl_id);
        pbr_material_table_gl_id = 0;
    }

    if restore_default_material init_windowed_program_3d_default_pbr_material_table(wp3);
}

clear_loaded_windowed_program_3d_scene :: (using wp3: *Windowed_Program_3D, restore_default_material: bool = true) {
    clear_loaded_vertex_color_scene(wp3);
    clear_loaded_blinn_phong_scene(wp3);
    clear_loaded_pbr_scene(wp3, restore_default_material = false);
    clear_loaded_pbr_lightmapped_scene(wp3, restore_default_material = false);
    clear_loaded_pbr_skeletal_scene(wp3, restore_default_material);

    if loaded_gltf_path.count {
        free(loaded_gltf_path);
        loaded_gltf_path = "";
    }
}

add_vertex_color_primitive :: (wp3: *Windowed_Program_3D, scene: *Vertex_Color_Scene, primitive: *Triangles_Vertex_Color) {
    geometry: Windowed_Program_3D_Vertex_Color_Geometry;
    geometry.indices = primitive.indices;
    geometry.positions = primitive.positions;
    geometry.colors = primitive.rgb_colors;

    local_to_world := Matrix4_Identity;
    if primitive.local_to_world_index >= 0 && primitive.local_to_world_index < scene.local_to_world_matrices.count {
        local_to_world = scene.local_to_world_matrices[primitive.local_to_world_index];
    }

    add_vertex_color_renderable(wp3, geometry, local_to_world);
}

add_blinn_phong_primitive :: (wp3: *Windowed_Program_3D, scene: *Blinn_Phong_Scene, primitive: *Triangles_Blinn_Phong) {
    geometry: Windowed_Program_3D_Blinn_Phong_Geometry;
    defer array_free(geometry.material_indices);

    geometry.indices = primitive.indices;
    geometry.positions = primitive.positions;
    geometry.normals = primitive.normals;
    geometry.tangents = primitive.tangents;
    geometry.uvs = primitive.uvs;

    material_index := primitive.material_index;
    if material_index < 0 || material_index >= scene.materials.count material_index = 0;
    array_resize(*geometry.material_indices, primitive.positions.count);
    for i: 0..geometry.material_indices.count - 1 geometry.material_indices[i] = material_index;

    local_to_world := Matrix4_Identity;
    if primitive.local_to_world_index >= 0 && primitive.local_to_world_index < scene.local_to_world_matrices.count {
        local_to_world = scene.local_to_world_matrices[primitive.local_to_world_index];
    }

    add_blinn_phong_renderable(wp3, geometry, local_to_world);
}

add_pbr_primitive :: (wp3: *Windowed_Program_3D, scene: *PBR_Scene, primitive: *Triangles_PBR) {
    geometry: Windowed_Program_3D_PBR_Geometry;
    defer array_free(geometry.material_indices);

    geometry.indices = primitive.indices;
    geometry.positions = primitive.positions;
    geometry.normals = primitive.normals;
    geometry.tangents = primitive.tangents;
    geometry.uvs = primitive.uvs;

    material_index := primitive.material_index;
    if material_index < 0 || material_index >= scene.materials.count material_index = 0;
    array_resize(*geometry.material_indices, primitive.positions.count);
    for i: 0..geometry.material_indices.count - 1 geometry.material_indices[i] = cast(u32)material_index;

    local_to_world := Matrix4_Identity;
    if primitive.local_to_world_index >= 0 && primitive.local_to_world_index < scene.local_to_world_matrices.count {
        local_to_world = scene.local_to_world_matrices[primitive.local_to_world_index];
    }

    add_pbr_renderable(wp3, geometry, local_to_world);
}

add_pbr_lightmapped_primitive :: (wp3: *Windowed_Program_3D, scene: *PBR_Lightmapped_Scene, primitive: *Triangles_PBR_Lightmapped) {
    geometry: Windowed_Program_3D_PBR_Lightmapped_Geometry;
    defer array_free(geometry.material_indices);

    geometry.indices = primitive.indices;
    geometry.positions = primitive.positions;
    geometry.normals = primitive.normals;
    geometry.tangents = primitive.tangents;
    geometry.uvs = primitive.uvs;
    geometry.lightmap_uvs = primitive.lightmap_uvs;

    material_index := primitive.material_index;
    if material_index < 0 || material_index >= scene.materials.count material_index = 0;
    array_resize(*geometry.material_indices, primitive.positions.count);
    for i: 0..geometry.material_indices.count - 1 geometry.material_indices[i] = cast(u32)material_index;

    local_to_world := Matrix4_Identity;
    if primitive.local_to_world_index >= 0 && primitive.local_to_world_index < scene.local_to_world_matrices.count {
        local_to_world = scene.local_to_world_matrices[primitive.local_to_world_index];
    }

    add_pbr_lightmapped_renderable(wp3, geometry, local_to_world);
}

add_pbr_skeletal_primitive :: (
    wp3: *Windowed_Program_3D,
    scene: *Windowed_Program_3D_PBR_Skeletal_Scene,
    primitive: *Windowed_Program_3D_PBR_Skeletal_Primitive
) {
    geometry: Windowed_Program_3D_PBR_Skeletal_Geometry;
    defer array_free(geometry.material_indices);

    geometry.indices = primitive.indices;
    geometry.positions = primitive.positions;
    geometry.normals = primitive.normals;
    geometry.tangents = primitive.tangents;
    geometry.uvs = primitive.uvs;
    geometry.bone_transform_indices = primitive.bone_transform_indices;
    geometry.bone_weights = primitive.bone_weights;

    material_index := primitive.material_index;
    if material_index < 0 || material_index >= scene.materials.count material_index = 0;
    array_resize(*geometry.material_indices, primitive.positions.count);
    for i: 0..geometry.material_indices.count - 1 geometry.material_indices[i] = cast(u32)material_index;

    local_to_world := Matrix4_Identity;
    if primitive.local_to_world_index >= 0 && primitive.local_to_world_index < scene.local_to_world_matrices.count {
        local_to_world = scene.local_to_world_matrices[primitive.local_to_world_index];
    }

    add_pbr_skeletal_renderable(wp3, geometry, local_to_world);
}

load_windowed_program_3d_pbr_skeletal_node_recursive :: (
    scene: *Windowed_Program_3D_PBR_Skeletal_Scene,
    gltf: *Gltf_Data,
    skin_index: int,
    node_index: int,
    parent_transform: Matrix4
) {
    if node_index < 0 || node_index >= gltf.all_nodes.count return;

    node := *gltf.all_nodes[node_index];
    world_transform := parent_transform * compute_node_local_transform(node);

    if node.light_index >= 0 && node.light_index < gltf.all_lights.count {
        add_gltf_light(*scene.base, *gltf.all_lights[node.light_index], world_transform);
    }

    if node.mesh_index >= 0 && node.mesh_index < gltf.all_meshes.count && node.skin_index == skin_index {
        mesh := *gltf.all_meshes[node.mesh_index];

        for * prim: mesh.primitives {
            if prim.mode != .TRIANGLES continue;
            if prim.position_accessor < 0 continue;
            if prim.joints_accessors.count == 0 || prim.weights_accessors.count == 0 continue;
            if scene.local_to_world_matrices.count >= GPU_STYLE_PBR_MAX_MATRICES break;

            positions := read_accessor_as_vector3_array(gltf, prim.position_accessor);
            normals := read_accessor_as_vector3_array(gltf, prim.normal_accessor);
            tangents := read_accessor_as_vector4_array(gltf, prim.tangent_accessor);
            uvs := read_primitive_texcoords(gltf, prim, 0);
            indices := read_accessor_as_index_array(gltf, prim.indices_accessor);
            joints := read_accessor_as_u32x4_array(gltf, prim.joints_accessors[0]);
            weights := read_accessor_as_f32x4_array(gltf, prim.weights_accessors[0]);
            defer array_free(positions);
            defer array_free(normals);
            defer array_free(tangents);
            defer array_free(uvs);
            defer array_free(indices);
            defer array_free(joints);
            defer array_free(weights);

            primitive: Windowed_Program_3D_PBR_Skeletal_Primitive;
            primitive.material_index = cast(s32)prim.material_index;
            if primitive.material_index < 0 || primitive.material_index >= cast(s32)scene.materials.count primitive.material_index = 0;
            primitive.local_to_world_index = cast(s32)scene.local_to_world_matrices.count;

            array_reserve(*primitive.positions, positions.count);
            array_reserve(*primitive.normals, positions.count);
            array_reserve(*primitive.tangents, positions.count);
            array_reserve(*primitive.uvs, positions.count);
            array_reserve(*primitive.bone_transform_indices, positions.count);
            array_reserve(*primitive.bone_weights, positions.count);

            for p, vertex_index: positions {
                array_add(*primitive.positions, p);
                update_bounds(*scene.base, transform_point(world_transform, p));

                n := Vector3.{0, 1, 0};
                if vertex_index < normals.count n = normalize_hot(normals[vertex_index]);
                array_add(*primitive.normals, n);

                tangent := Vector3.{1, 0, 0};
                if vertex_index < tangents.count {
                    t := tangents[vertex_index];
                    tangent = normalize_hot(.{t.x, t.y, t.z});
                }
                array_add(*primitive.tangents, tangent);

                uv := Vector2.{0, 0};
                if vertex_index < uvs.count uv = uvs[vertex_index];
                array_add(*primitive.uvs, uv);

                joint_indices: [4] u32 = .[0, 0, 0, 0];
                if vertex_index < joints.count joint_indices = joints[vertex_index];
                array_add(*primitive.bone_transform_indices, joint_indices);

                joint_weights: [4] float32 = .[1.0, 0.0, 0.0, 0.0];
                if vertex_index < weights.count joint_weights = weights[vertex_index];
                array_add(*primitive.bone_weights, joint_weights);
            }

            copy_indices_or_generate(*primitive.indices, indices, primitive.positions.count);

            array_add(*scene.primitives, primitive);
            array_add(*scene.local_to_world_matrices, world_transform);
        }
    }

    for child: node.children load_windowed_program_3d_pbr_skeletal_node_recursive(scene, gltf, skin_index, child, world_transform);
}

load_windowed_program_3d_pbr_skeletal_scene_from_gltf :: (gltf: *Gltf_Data) -> Windowed_Program_3D_PBR_Skeletal_Scene, bool {
    scene: Windowed_Program_3D_PBR_Skeletal_Scene;
    if gltf.all_meshes.count == 0 || gltf.all_skins.count == 0 || gltf.all_animations.count == 0 return scene, false;

    skin_index := 0;
    scene.skeleton = build_skeleton_from_gltf(gltf, skin_index);
    array_resize(*scene.bone_transforms, scene.skeleton.bones.count);
    for i: 0..scene.bone_transforms.count - 1 scene.bone_transforms[i] = Matrix4_Identity;

    array_reserve(*scene.clips, gltf.all_animations.count);
    for animation_index: 0..gltf.all_animations.count - 1 {
        clip := build_animation_clip_from_gltf(gltf, animation_index, skin_index);
        array_add(*scene.clips, clip);
    }

    load_scene_textures(*scene.base, gltf, GPU_STYLE_PBR_MAX_TEXTURES);

    material_count := min(max(gltf.all_materials.count, 1), WINDOWED_PROGRAM_3D_PBR_MAX_MATERIALS);
    array_resize(*scene.materials, material_count);
    for material_index: 0..material_count - 1 {
        material := *scene.materials[material_index];
        material.* = gpu_style_pbr_material_from_gltf(null);
        if material_index < gltf.all_materials.count {
            material.* = gpu_style_pbr_material_from_gltf(*gltf.all_materials[material_index]);
        }
    }

    gltf_scene := get_default_scene(gltf);
    if gltf_scene != null {
        for node_index: gltf_scene.nodes load_windowed_program_3d_pbr_skeletal_node_recursive(*scene, gltf, skin_index, node_index, Matrix4_Identity);
    } else {
        for node_index: 0..gltf.all_nodes.count - 1 load_windowed_program_3d_pbr_skeletal_node_recursive(*scene, gltf, skin_index, node_index, Matrix4_Identity);
    }

    add_default_light_if_needed(*scene.base);
    return scene, scene.primitives.count > 0 && scene.clips.count > 0 && scene.skeleton.bones.count > 0;
}

frame_camera_for_scene :: (using wp3: *Windowed_Program_3D, scene: *Base_Scene) {
    camera.fov = ONE_SIXTH_TURN;
    if !scene.has_bounds {
        camera.position = .{0, 0.15, 3.0};
        return;
    }

    center := (scene.min_p + scene.max_p) * 0.5;
    extent := scene.max_p - scene.min_p;
    radius := max(max(extent.x, extent.y), extent.z) * 0.5;
    distance := max(radius * 2.6, cast(float32)2.5);
    camera.position = center + Vector3.{0, radius * 0.35 + 0.4, distance};
    camera.yaw = 0.0;
    camera.pitch = -0.18 / (cast(float32)2.0 * cast(float32)3.14159265359);
    pbr_shadow_center = center;
    pbr_shadow_half_extent = max(radius * 1.8, cast(float32)4.0);
    pbr_shadow_depth_extent = max(radius * 4.0, cast(float32)12.0);
}

update_windowed_program_3d_pbr_skeletal_animation :: (using wp3: *Windowed_Program_3D) {
    if !loaded_pbr_skeletal_scene_valid return;
    if loaded_pbr_skeletal_scene.clips.count == 0 return;

    clip_index := loaded_pbr_skeletal_scene.active_clip_index;
    if clip_index < 0 || clip_index >= cast(s32)loaded_pbr_skeletal_scene.clips.count clip_index = 0;

    loaded_pbr_skeletal_scene.animation_time += cast(float32)delta_time;
    compute_bone_animation_transforms(
        *loaded_pbr_skeletal_scene.skeleton,
        *loaded_pbr_skeletal_scene.clips[clip_index],
        loaded_pbr_skeletal_scene.animation_time,
        loaded_pbr_skeletal_scene.bone_transforms,
        .SOURCE,
        true
    );

    for i: 0..WINDOWED_PROGRAM_3D_MAX_BONES - 1 pbr_bone_animation_buffer.matrices[i] = Matrix4_Identity;
    bone_count := min(loaded_pbr_skeletal_scene.bone_transforms.count, WINDOWED_PROGRAM_3D_MAX_BONES);
    for i: 0..bone_count - 1 pbr_bone_animation_buffer.matrices[i] = loaded_pbr_skeletal_scene.bone_transforms[i];
}

load_gltf_into_windowed_program_3d :: (using wp3: *Windowed_Program_3D, path: string) -> bool {
    normalized_path := copy_temporary_string(path);
    normalize_slashes(normalized_path);

    gltf := load_gltf(normalized_path);
    defer deinit(*gltf);

    asset_render_model := choose_renderer_for_gltf(*gltf);
    if render_model == .PBR && asset_render_model != .PBR {
        log_error("Cannot open '%' with PBR rendering; this glTF appears to require Blinn-Phong/specular-glossiness materials.", normalized_path);
        return false;
    }

    if render_model == .Vertex_Color {
        scene, ok := load_vertex_color_scene_from_gltf(*gltf);
        if !ok {
            log_error("Failed to load vertex-color scene from glTF: %", normalized_path);
            deinit(*scene);
            return false;
        }

        clear_loaded_windowed_program_3d_scene(wp3);
        loaded_gltf_path = copy_string(normalized_path);
        loaded_vertex_color_scene = scene;
        loaded_vertex_color_scene_valid = true;

        for * primitive: loaded_vertex_color_scene.primitives {
            add_vertex_color_primitive(wp3, *loaded_vertex_color_scene, primitive);
        }

        frame_camera_for_scene(wp3, *loaded_vertex_color_scene.base);
    } else if render_model == .Blinn_Phong {
        scene, ok := load_blinn_phong_scene_from_gltf(*gltf);
        if !ok {
            log_error("Failed to load Blinn-Phong scene from glTF: %", normalized_path);
            deinit(*scene);
            return false;
        }

        clear_loaded_windowed_program_3d_scene(wp3);
        loaded_gltf_path = copy_string(normalized_path);
        loaded_blinn_phong_scene = scene;
        loaded_blinn_phong_scene_valid = true;
        init_windowed_program_3d_blinn_phong_packed_resources(wp3, *loaded_blinn_phong_scene);

        for * primitive: loaded_blinn_phong_scene.primitives {
            add_blinn_phong_primitive(wp3, *loaded_blinn_phong_scene, primitive);
        }

        frame_camera_for_scene(wp3, *loaded_blinn_phong_scene.base);
    } else if render_model == .PBR {
        if gltf.all_skins.count > 0 && gltf.all_animations.count > 0 {
            skeletal_scene, skeletal_ok := load_windowed_program_3d_pbr_skeletal_scene_from_gltf(*gltf);
            if skeletal_ok {
                clear_loaded_windowed_program_3d_scene(wp3);
                loaded_gltf_path = copy_string(normalized_path);
                loaded_pbr_skeletal_scene = skeletal_scene;
                loaded_pbr_skeletal_scene_valid = true;

                init_windowed_program_3d_pbr_packed_resources(wp3, *loaded_pbr_skeletal_scene);

                if loaded_pbr_skeletal_scene.directional_lights.count > 0 {
                    light := loaded_pbr_skeletal_scene.directional_lights[0];
                    pbr_light_direction = normalize(light.direction);
                    pbr_light_color = light.color;
                    pbr_light_intensity = light.intensity;
                }

                for * primitive: loaded_pbr_skeletal_scene.primitives {
                    add_pbr_skeletal_primitive(wp3, *loaded_pbr_skeletal_scene, primitive);
                }

                frame_camera_for_scene(wp3, *loaded_pbr_skeletal_scene.base);
                current_menu = .NONE;
                return true;
            }

            deinit(*skeletal_scene);
        }

        lightmapped_scene, lightmapped_ok := load_pbr_lightmapped_scene_from_gltf(*gltf);
        if lightmapped_ok {
            clear_loaded_windowed_program_3d_scene(wp3);
            loaded_gltf_path = copy_string(normalized_path);
            loaded_pbr_lightmapped_scene = lightmapped_scene;
            loaded_pbr_lightmapped_scene_valid = true;

            init_windowed_program_3d_pbr_packed_resources(wp3, *loaded_pbr_lightmapped_scene);

            if loaded_pbr_lightmapped_scene.directional_lights.count > 0 {
                light := loaded_pbr_lightmapped_scene.directional_lights[0];
                pbr_light_direction = normalize(light.direction);
                pbr_light_color = light.color;
                pbr_light_intensity = light.intensity;
            }

            for * primitive: loaded_pbr_lightmapped_scene.primitives {
                add_pbr_lightmapped_primitive(wp3, *loaded_pbr_lightmapped_scene, primitive);
            }

            frame_camera_for_scene(wp3, *loaded_pbr_lightmapped_scene.base);
            current_menu = .NONE;
            return true;
        }
        deinit(*lightmapped_scene);

        scene, ok := load_pbr_scene_from_gltf(*gltf);
        if !ok {
            log_error("Failed to load PBR scene from glTF: %", normalized_path);
            deinit(*scene);
            return false;
        }

        clear_loaded_windowed_program_3d_scene(wp3);
        loaded_gltf_path = copy_string(normalized_path);
        loaded_pbr_scene = scene;
        loaded_pbr_scene_valid = true;

        init_windowed_program_3d_pbr_packed_resources(wp3, *loaded_pbr_scene);

        if loaded_pbr_scene.directional_lights.count > 0 {
            light := loaded_pbr_scene.directional_lights[0];
            pbr_light_direction = normalize(light.direction);
            pbr_light_color = light.color;
            pbr_light_intensity = light.intensity;
        }

        for * primitive: loaded_pbr_scene.primitives {
            add_pbr_primitive(wp3, *loaded_pbr_scene, primitive);
        }

        frame_camera_for_scene(wp3, *loaded_pbr_scene.base);
    }

    current_menu = .NONE;
    return true;
}

// it might be nice to make a dedicated 2d program.

Windowed_Program_3D :: struct {

    using #as wp : Windowed_Menu_Program;

    orientation := STANDARD_ORIENTATION;

    camera_per_object_transform_color_renderer : Camera_Per_Object_Transform_Color_Renderer;
    vertex_color_renderer: Gpu_Style_Vertex_Color_Renderer;
    blinn_phong_renderer: Gpu_Style_Blinn_Phong_Renderer;
    pbr_renderer: Gpu_Style_Pbr_Renderer;
    pbr_lightmapped_renderer: Gpu_Style_Pbr_Lightmapped_Renderer;
    pbr_shadowed_renderer: Gpu_Style_Pbr_Directional_Shadows_Renderer;
    pbr_shadow_depth_renderer: Gpu_Style_Pbr_Directional_Shadow_Depth_Renderer;
    pbr_skeletal_renderer: Gpu_Style_Pbr_Skeletal_Animation_Renderer;
    pbr_skeletal_shadowed_renderer: Gpu_Style_Pbr_Directional_Shadows_Skeletal_Animation_Renderer;
    pbr_skeletal_shadow_depth_renderer: Gpu_Style_Pbr_Directional_Shadow_Depth_Skeletal_Animation_Renderer;
    pbr_shadow_map: Windowed_Program_3D_Directional_Shadow_Map;
    pbr_bone_animation_buffer: Windowed_Program_3D_Bone_Animation_Buffer;
    pbr_material_table_gl_id: GLuint;
    pbr_packed_resources: Windowed_Program_3D_PBR_Packed_Resources;
    blinn_phong_packed_resources: Windowed_Program_3D_Blinn_Phong_Packed_Resources;
    loaded_vertex_color_scene: Vertex_Color_Scene;
    loaded_vertex_color_scene_valid: bool;
    loaded_blinn_phong_scene: Blinn_Phong_Scene;
    loaded_blinn_phong_scene_valid: bool;
    loaded_pbr_scene: PBR_Scene;
    loaded_pbr_scene_valid: bool;
    loaded_pbr_lightmapped_scene: PBR_Lightmapped_Scene;
    loaded_pbr_lightmapped_scene_valid: bool;
    loaded_pbr_skeletal_scene: Windowed_Program_3D_PBR_Skeletal_Scene;
    loaded_pbr_skeletal_scene_valid: bool;
    loaded_gltf_path: string;
    active_render_model := Renderer_Mode.PBR;

    camera : Camera;
    camera_mode := Camera_Mode.FIRST_PERSON;

    camera_look_active := true;

    camera_velocity : Vector3;
    movement_mode : Movement_Mode;

    renderables : [..] Camera_Per_Object_Transform_Color_Renderable;
    vertex_color_renderables: [..] Gpu_Style_Vertex_Color_Renderable;
    blinn_phong_renderables: [..] Gpu_Style_Blinn_Phong_Renderable;
    pbr_renderables: [..] Windowed_Program_3D_PBR_Renderable;
    pbr_lightmapped_renderables: [..] Windowed_Program_3D_PBR_Lightmapped_Renderable;
    pbr_skeletal_renderables: [..] Windowed_Program_3D_PBR_Skeletal_Renderable;

    pbr_light_direction: Vector3 = .{-0.35, -0.8, -0.45};
    pbr_light_color: Vector3 = .{1.0, 0.96, 0.90};
    pbr_light_intensity: float32 = 2.25;
    pbr_ambient_strength: float32 = 0.03;
    pbr_shadow_center: Vector3 = .{0, 0, 0};
    pbr_shadow_half_extent: float32 = 12.0;
    pbr_shadow_depth_extent: float32 = 24.0;

    raw_mouse_supported := false;
    raw_mouse_extension_opcode: s32;
    raw_mouse_dx, raw_mouse_dy: float64;
    raw_mouse_events: int;

    // 2D camera state
    ortho_center : Vector2;
    ortho_height := 10.0;

    // drag state
    is_dragging := false;
    drag_start_mouse : Vector2;
    drag_start_center : Vector2;
}

init :: (using wp3 : *Windowed_Program_3D) {
    init(*wp);
    init(*camera_per_object_transform_color_renderer);
    init(*vertex_color_renderer);
    init(*blinn_phong_renderer);
    init(*pbr_renderer);
    init(*pbr_lightmapped_renderer);
    init(*pbr_shadowed_renderer);
    init(*pbr_shadow_depth_renderer);
    init(*pbr_skeletal_renderer);
    init(*pbr_skeletal_shadowed_renderer);
    init(*pbr_skeletal_shadow_depth_renderer);
    init(*pbr_bone_animation_buffer);
    bind_windowed_program_3d_bone_animation_block(pbr_skeletal_renderer.shader_program_gl_handle);
    bind_windowed_program_3d_bone_animation_block(pbr_skeletal_shadowed_renderer.shader_program_gl_handle);
    bind_windowed_program_3d_bone_animation_block(pbr_skeletal_shadow_depth_renderer.shader_program_gl_handle);
    init_windowed_program_3d_default_pbr_material_table(wp3);
    init_windowed_program_3d_shadow_map(*pbr_shadow_map);
    init(*section_timer);

    #if OS == .LINUX {
        init_raw_mouse_input(wp3);
    }

    performance_graph.graph_min_ms = min_frame_time * 1000 - 1;
    performance_graph.graph_max_ms = min_frame_time * 1000 + 5;

    // enumerate available resolutions before loading settings
    enumerate_resolutions(*wp3.wp);

    // menu_fullscreen_checkbox = fullscreen;
    // menu_vsync_checkbox = vsync;

    conf_sens, ok_s := get_float(*configuration, "input", "sensitivity");
    if ok_s camera.sensitivity = conf_sens;

    load_menu_settings(*wp3.wp);
    active_render_model = render_model;
}

deinit :: (using wp3: *Windowed_Program_3D) {
    clear_loaded_windowed_program_3d_scene(wp3, restore_default_material = false);
    array_free(vertex_color_renderables);
    array_free(blinn_phong_renderables);
    array_free(pbr_renderables);
    array_free(pbr_lightmapped_renderables);
    array_free(pbr_skeletal_renderables);

    for * renderable: renderables deinit(renderable);
    array_free(renderables);

    deinit(*pbr_shadow_map);
    deinit(*pbr_bone_animation_buffer);
    deinit(*pbr_skeletal_shadow_depth_renderer);
    deinit(*pbr_skeletal_shadowed_renderer);
    deinit(*pbr_skeletal_renderer);
    deinit(*pbr_shadow_depth_renderer);
    deinit(*pbr_shadowed_renderer);
    deinit(*pbr_lightmapped_renderer);
    deinit(*pbr_renderer);
    deinit(*blinn_phong_renderer);
    deinit(*vertex_color_renderer);
    deinit(*camera_per_object_transform_color_renderer);
    deinit(*wp);
}

#if OS == .LINUX {
    init_raw_mouse_input :: (using wp3: *Windowed_Program_3D) {
        display := X11.x_global_display;
        if !display {
            return;
        }

        opcode, event, error: s32;
        if !X11.XQueryExtension(display, "XInputExtension", *opcode, *event, *error) {
            return;
        }

        major := cast(s32) 2;
        minor := cast(s32) 0;
        if XIQueryVersion(display, *major, *minor) == X11.BadRequest {
            return;
        }

        mask: [(XI_LASTEVENT + 7) / 8] u8;
        xi_set_mask(mask.data, XI_RawMotion);

        event_mask: XIEventMask;
        event_mask.deviceid = XIAllDevices;
        event_mask.mask_len = size_of(type_of(mask));
        event_mask.mask = mask.data;

        root := X11.DefaultRootWindow(display);
        result := XISelectEvents(display, root, *event_mask, 1);
        X11.XFlush(display);

        raw_mouse_supported = result == 0;
        raw_mouse_extension_opcode = opcode;
    }

    read_raw_mouse_events :: (using wp3: *Windowed_Program_3D) {
        raw_mouse_dx = 0;
        raw_mouse_dy = 0;
        raw_mouse_events = 0;

        if !raw_mouse_supported return;

        display := X11.x_global_display;
        events_to_put_back: [..] X11.XEvent;
        defer array_free(events_to_put_back);

        while X11.XPending(display) {
            event: X11.XEvent;
            X11.XNextEvent(display, *event);

            is_raw_mouse_event := false;
            if event.type == X11.GenericEvent && event.xcookie.extension == raw_mouse_extension_opcode {
                if X11.XGetEventData(display, *event.xcookie) != 0 {
                    if event.xcookie.evtype == XI_RawMotion {
                        raw := cast(*XIRawEvent) event.xcookie.data;
                        value_count := xi_count_valuator_values(raw.valuators);
                        if value_count >= 1 raw_mouse_dx += raw.raw_values[0];
                        if value_count >= 2 raw_mouse_dy += raw.raw_values[1];
                        raw_mouse_events += 1;
                        is_raw_mouse_event = true;
                    }
                    X11.XFreeEventData(display, *event.xcookie);
                }
            }

            if !is_raw_mouse_event {
                array_add(*events_to_put_back, event);
            }
        }

        for i: 0..events_to_put_back.count - 1 {
            index := events_to_put_back.count - 1 - i;
            X11.XPutBackEvent(display, *events_to_put_back[index]);
        }
    }
}

render_movement_stats :: (using wp3 : *Windowed_Program_3D) {
    ui_label(tprint("pos: %", format_vec3(camera.position)));
    ui_label(tprint("vel: %", format_vec3(camera_velocity)));
}

render_camera_stats :: (using wp3 : *Windowed_Program_3D) {
    ui_label(tprint("fwd: %", format_vec3(get_forward(*camera))));
}

render_iteration :: (using wp3 : *Windowed_Program_3D) {
    ui_label(tprint("iter: %", iteration));
}

per_frame_update :: (using wp3 : *Windowed_Program_3D) {
    linux_motion_dx := 0;
    linux_motion_dy := 0;
    linux_nonzero_motion_events := 0;

    #if OS == .LINUX {
        if camera_look_active && current_menu == .NONE && camera_mode != .TWO_DIMENSIONS && window_has_focus {
            read_raw_mouse_events(wp3);
            _, _, w, h := Window_Creation.get_dimensions(window, right_handed_mouse_position);

            motion_event: X11.XEvent;
            while X11.XCheckTypedWindowEvent(X11.x_global_display, window, X11.MotionNotify, *motion_event) {
                event_dx := motion_event.xmotion.x - w / 2;
                event_dy := motion_event.xmotion.y - h / 2;
                if event_dx != 0 || event_dy != 0 {
                    linux_motion_dx += event_dx;
                    linux_motion_dy += event_dy;
                    linux_nonzero_motion_events += 1;
                }
            }
        }
    }

    per_frame_update(*wp3.wp);

    if active_render_model != render_model {
        path_to_reload: string;
        if loaded_gltf_path.count > 0 {
            path_to_reload = copy_string(loaded_gltf_path);
        }

        active_render_model = render_model;

        if path_to_reload.count > 0 {
            load_gltf_into_windowed_program_3d(wp3, path_to_reload);
            free(path_to_reload);
        } else {
            clear_loaded_windowed_program_3d_scene(wp3);
        }
    }

    if pending_gltf_load {
        pending_gltf_load = false;
        if pending_gltf_path.count > 0 {
            load_gltf_into_windowed_program_3d(wp3, pending_gltf_path);
        }
    }

    camera.sensitivity = sensitivity;

    // handle ESC to toggle in-game menu
    // handle M to toggle mouse cursor without opening menu
    for Input.events_this_frame {
        if it.type == .KEYBOARD && it.key_pressed {
            if it.key_code == .ESCAPE {
                if !camera_look_active {
                    // if mouse mode is active, pressing ESC should re-lock the camera first
                    camera_look_active = true;
                } else {
                    toggle_menu(wp3);
                }
            }

            if it.key_code == xx #char "M" && current_menu == .NONE {
                camera_look_active = !camera_look_active;
            }

        }
    }

    want_cursor_captured := camera_look_active
                         && current_menu == .NONE
                         && camera_mode != .TWO_DIMENSIONS
                         && window_has_focus;

    if want_cursor_captured {
        hide_cursor(*wp);
        #if OS == .WINDOWS {
            keep_mouse_in_center_of_screen(*wp3.wp);
            update_angles_with_deltas(*camera, Input.mouse_delta_x, Input.mouse_delta_y);
        } else #if OS == .LINUX {
            dx := 0;
            dy := 0;

            if raw_mouse_events > 0 {
                dx = cast(int) raw_mouse_dx;
                dy = cast(int) raw_mouse_dy;
            } else if linux_nonzero_motion_events > 0 {
                dx = linux_motion_dx;
                dy = linux_motion_dy;
            } else {
                x, y, success := Window_Creation.get_mouse_pointer_position(window, right_handed_mouse_position);
                _, _, w, h := Window_Creation.get_dimensions(window, right_handed_mouse_position);
                if success {
                    dx = x - w / 2;
                    dy = y - h / 2;
                }
            }

            update_angles_with_deltas(*camera, dx, dy);
            keep_mouse_in_center_of_screen(*wp3.wp);
        } else {
            x, y, success := Window_Creation.get_mouse_pointer_position(window, right_handed_mouse_position);
            if success update_angles(*camera, x, y);
        }
    } else {
        show_cursor(*wp);
    }

    vx, vy, vw, vh := Window_Creation.get_dimensions(window, right_handed_mouse_position);

    if camera_mode != .TWO_DIMENSIONS && want_cursor_captured {
        if movement_mode == {
            case .GOD;
                gmi := God_Mode_Input.{
                    key_pressed(xx #char "E"),
                    key_pressed(xx #char "Q"),
                    key_pressed(xx #char "W"),
                    key_pressed(xx #char "S"),
                    key_pressed(xx #char "D"),
                    key_pressed(xx #char "A"),
                    key_pressed(xx #char " "),
                    key_pressed(Input.Key_Code.SHIFT),
                };
                camera_velocity = get_new_god_mode_velocity(camera_velocity, get_forward(*camera), gmi, delta_time);
        }
    }

    if movement_mode != .MANUAL camera.position += camera_velocity * delta_time;

    update_windowed_program_3d_pbr_skeletal_animation(wp3);

    update_listener_orientation(camera.position, camera.yaw);
    // Sound_Player.update(delta_time);

    // handle 2d drag and scroll
    if camera_mode == .TWO_DIMENSIONS && current_menu == .NONE {
        aspect := cast(float) vw / cast(float) vh;
        ortho_width := ortho_height * aspect;

        for Input.events_this_frame {
            if it.type == .MOUSE_WHEEL {
                if it.wheel_delta > 0 {
                    ortho_height *= 0.9;
                    if ortho_height < 0.1  ortho_height = 0.1;
                } else if it.wheel_delta < 0 {
                    ortho_height *= 1.1;
                }
            }
        }

        mouse_left_down := key_pressed(xx Input.Key_Code.MOUSE_BUTTON_LEFT);
        mx, my, mouse_success := Window_Creation.get_mouse_pointer_position(window, true);

        if mouse_success {
            mouse_world_x := (cast(float) mx / cast(float) vw - 0.5) * ortho_width + ortho_center.x;
            mouse_world_y := (cast(float) my / cast(float) vh - 0.5) * ortho_height + ortho_center.y;

            if mouse_left_down {
                if !is_dragging {
                    is_dragging = true;
                    drag_start_mouse = .{mouse_world_x, mouse_world_y};
                    drag_start_center = ortho_center;
                } else {
                    current_mouse_world_x := (cast(float) mx / cast(float) vw - 0.5) * ortho_width + drag_start_center.x;
                    current_mouse_world_y := (cast(float) my / cast(float) vh - 0.5) * ortho_height + drag_start_center.y;

                    ortho_center.x = drag_start_center.x - (current_mouse_world_x - drag_start_mouse.x);
                    ortho_center.y = drag_start_center.y - (current_mouse_world_y - drag_start_mouse.y);
                }
            } else {
                is_dragging = false;
            }
        }
    }

    world_to_camera := Matrix4_Identity;
    camera_to_clip := Matrix4_Identity;
    if camera_mode != .TWO_DIMENSIONS {
        world_to_camera = get_world_to_camera_matrix(*camera);
        camera_to_clip = get_projection_matrix(*camera, window_width, window_height);
    } else {
        aspect := cast(float) vw / cast(float) vh;
        ortho_width := ortho_height * aspect;
        half_w := ortho_width * 0.5;
        half_h := ortho_height * 0.5;

        camera_to_clip = orthographic_projection_matrix(
            left   = ortho_center.x - half_w,
            right  = ortho_center.x + half_w,
            bottom = ortho_center.y - half_h,
            top    = ortho_center.y + half_h,
            near   = -100.0,
            far    =  100.0,
            depth_range_01 = false
        );
    }

    glUseProgram(absolute_position_color_alpha_renderer.shader_program_gl_handle);

    glUseProgram(camera_per_object_transform_color_renderer.shader_program_gl_handle);
    set_world_to_camera_uniform(*camera_per_object_transform_color_renderer, world_to_camera);
    set_camera_to_clip_uniform(*camera_per_object_transform_color_renderer, camera_to_clip);
    glUseProgram(0);

    apply_windowed_program_3d_vertex_color_uniforms(wp3, *vertex_color_renderer, world_to_camera, camera_to_clip);
    apply_windowed_program_3d_blinn_phong_uniforms(wp3, *blinn_phong_renderer, world_to_camera, camera_to_clip);
    apply_windowed_program_3d_pbr_uniforms(wp3, *pbr_renderer, world_to_camera, camera_to_clip);
    apply_windowed_program_3d_pbr_uniforms(wp3, *pbr_lightmapped_renderer, world_to_camera, camera_to_clip);
    apply_windowed_program_3d_pbr_uniforms(wp3, *pbr_shadowed_renderer, world_to_camera, camera_to_clip, windowed_program_3d_light_clip_matrix(wp3));
    apply_windowed_program_3d_pbr_uniforms(wp3, *pbr_skeletal_renderer, world_to_camera, camera_to_clip);
    apply_windowed_program_3d_pbr_uniforms(wp3, *pbr_skeletal_shadowed_renderer, world_to_camera, camera_to_clip, windowed_program_3d_light_clip_matrix(wp3));
}

render_scene :: (using wp3 : *Windowed_Program_3D) {
    Simp.update_window(wp3.window);
    Simp.clear_render_target(.15, .08, .08, 1);

    // begin the UI frame
    ui_begin(*wp3.wp);

    // always render the 3D scene (it shows behind the overlay when menu is open)
    glDepthMask(GL_TRUE);
    glEnable(GL_DEPTH_TEST);
    glClear(GL_DEPTH_BUFFER_BIT);

    if windowed_program_3d_render_path(wp3) == {
        case .Legacy_Color;
            for renderables queue_render(*wp3.camera_per_object_transform_color_renderer, it.object_index);
            render(*wp3.camera_per_object_transform_color_renderer);
        case .Vertex_Color;
            render_windowed_program_3d_vertex_color_scene(wp3);
        case .Blinn_Phong;
            render_windowed_program_3d_blinn_phong_scene(wp3);
        case .PBR;
            render_windowed_program_3d_pbr_scene(wp3);
        case .PBR_Lightmapped;
            render_windowed_program_3d_pbr_lightmapped_scene(wp3);
        case .PBR_Directional_Shadows;
            render_windowed_program_3d_pbr_scene(wp3);
        case .PBR_Skeletal;
            render_windowed_program_3d_pbr_skeletal_scene(wp3);
        case .PBR_Directional_Shadows_Skeletal;
            render_windowed_program_3d_pbr_skeletal_scene(wp3);
    }

    if wp3.current_menu == .NONE {
        // HUD elements via the custom UI as small windows
        if ui_begin_window("hud_stats", 5, 5, 300, 100) {
             if wp3.camera_look_active {
                ui_label_colored("M - toggle mouse cursor", .{0.5, 0.5, 0.5, 0.6});
            } else {
                ui_label_colored("M - lock camera (mouse free)", .{0.3, 1.0, 0.3, 0.8});
            }
            render_tick_stats(wp3);
            render_movement_stats(wp3);
            render_camera_stats(wp3);
            render_iteration(wp3);
            ui_end_window();
        }

        render_crosshair(*wp3.wp.base);

        update_graph_visual(*wp3.performance_graph);
        render_performance_graph(wp3);
        render_section_bar_graph(wp3);
    } else if wp3.current_menu == .MAIN {
        // initial menu, no 3D scene visible (or you could show it, up to you)
        render_menus(*wp3.wp);
    } else {
        // in-game menu or settings, render over the 3D scene
        render_menus(*wp3.wp);
    }

    // end the UI frame, flushes all draw commands
    ui_end(*wp3.wp);
    render_crosshair_preview(*wp3.wp.base);

    // play UI sounds from audio events emitted during the frame
    drain_ui_audio_events(*wp3.wp);

    Simp.swap_buffers(wp3.window, false);
}


sample_first_person_movement_input :: (forward := #char "W", backward := #char "S", right := #char "D", left := #char "A", jump := #char " ") -> First_Person_Movement_Input {
    return .{
        key_pressed(xx forward),
        key_pressed(xx backward),
        key_pressed(xx right),
        key_pressed(xx left),
        key_pressed(xx jump),
    };
}

get_forward_and_side_input :: (using fpmi : First_Person_Movement_Input) -> forward_input: float, side_input: float {
    forward_input : float = 0.0;
    right_input   : float = 0.0;

    if forward_pressed forward_input += 1.0;
    if back_pressed forward_input    -= 1.0;
    if right_pressed right_input     += 1.0;
    if left_pressed right_input      -= 1.0;

    return forward_input, right_input;
}
