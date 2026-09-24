# Focused Windowed Program 3D Examples

Import `tbx/engine/windowed_program_3d` and choose the smallest program that matches the rendering path you need. Each program embeds `Windowed_Program_3D_Base`, owns only the renderer resources for that path, and exposes the same copyable shape:

1. `init(*program)` initializes the base and renderer.
2. `add_renderable(*program, geometry)` copies and buffers one object.
3. `per_frame_update(*program)` updates the base and renderer uniforms.
4. `render_scene(*program)` performs the path's draw pass and menu/UI presentation.
5. `run(*program)` supplies the standard timed frame loop.
6. `deinit(*program)` releases renderables, renderer resources, and the base.

Use `begin_frame(*program.base_3d)` and `end_frame(*program.base_3d)` instead of
`run` when the application needs custom per-frame work such as animation. The
spinning-cube example in `src/main.jai` demonstrates that form.

The examples are deliberately separated by render path:

- `color.jai`: `Camera_Per_Object_Transform_Color_Renderer`
- `vertex_colors.jai`: `Gpu_Style_Vertex_Color_Renderer`
- `blinn_phong.jai`: `Gpu_Style_Blinn_Phong_Renderer`
- `pbr.jai`: `Gpu_Style_Pbr_Renderer`
- `pbr_lightmapped.jai`: `Gpu_Style_Pbr_Lightmapped_Renderer`
- `pbr_directional_shadows.jai`: shaded PBR plus its depth-only shadow pass
- `pbr_skeletal_animation.jai`: skinned PBR plus its bone uniform buffer
- `pbr_directional_shadows_skeletal_animation.jai`: skinned, shadowed PBR and its depth pass

`common.jai` contains only presentation boilerplate and the GPU resources shared by multiple paths. There is intentionally no all-renderers implementation; applications choose a focused program or copy the closest one.

Minimal usage:

```jai
#import "Basic";
#import "tbx/engine/windowed_program_3d";
#import "tbx/opengl";

main :: () {
    program: Windowed_Program_3D_Vertex_Colors;
    program.window_name = "Vertex Colors";
    program.movement_mode = .GOD;

    init(*program);
    defer deinit(*program);

    // Fill a Gpu_Style_Vertex_Color_Geometry and add_renderable(*program, geometry).

    run(*program);
}
```

Material-based examples borrow their texture handles. The code that creates the packed texture array, bounds table, material table, and optional lightmap remains responsible for destroying them. Skeletal examples likewise leave animation sampling to the application; call `set_bone_transforms` with the current pose before rendering.
