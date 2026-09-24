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
standard editor behavior remains in the base update in either form.

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

Every program includes the shared crosshair menu and geometry editor through
`Windowed_Program_3D_Base`. Crosshairs are loaded from `data/crosshairs` as OBJ
geometry, and missing built-in crosshairs are generated there on first use. Open
**User Settings** to select an OBJ or create and edit one. The selected geometry
is also rendered over the scene by the common presentation pass.

## Editing controls and selection

The shared base has two 3D interaction states:

- Captured camera: the mouse looks, movement controls are active, and clicks do
  not select scene objects.
- Free mouse: the camera is locked, the operating-system cursor is visible, and
  left click selects the closest renderable under the cursor.

Right click switches between the states. `M` is retained as a keyboard shortcut,
and `Escape` returns from free-mouse mode to the captured camera before opening a
menu. A selected renderable is outlined in gold. `selected_object_id` is zero
when nothing is selected, and `selection_changed` is true for the frame in which
the selection changes. Each focused program also provides
`get_selected_renderable(*program)`.

Renderable object IDs are one-based and remain stable for the lifetime of the
program. Use `set_renderable_transform(*program, object_id, matrix)` when editing
an object's transform so the visible and picking passes stay synchronized.
The skeletal variants likewise refresh their picking meshes from each pose
passed to `set_bone_transforms`.

Every `add_renderable` overload accepts optional editor permission flags after
the transform. The default is `.ALL` (`.SELECTABLE | .TRANSFORMABLE`):

```jai
add_renderable(*program, geometry, transform, .NONE); // Physics-owned.

// Selectable for inspection, but G/R/S is disabled.
add_renderable(*program, geometry, transform, .SELECTABLE);
```

Permissions can also change at runtime with
`set_renderable_selectable(*program, object_id, enabled)`,
`set_renderable_transformable(...)`, or `set_renderable_editor_permissions(...)`.
Disabling selection clears that object if selected. Disabling transforms cancels
an active edit and restores its original matrix. A non-selectable object still
writes picker depth with object ID zero, so it occludes objects behind it rather
than allowing clicks to pass through. Physics and animation code should continue
using `set_renderable_transform` or `set_bone_transforms` to keep picking geometry
synchronized.

In free-mouse mode, select an object and press `G`, `R`, or `S` to move,
rotate, or scale it. `X`, `Y`, and `Z` constrain the active operation to a world
axis; pressing the active constraint again returns to free manipulation. Left
click confirms the operation. Right click or `Escape` restores the original
transform. These controls update the ordinary renderable, picking proxy, and
selection outline together in every focused 3D program.

All focused 3D programs also render the shared infinite grid. Perspective views
always use the XZ floor plane. Only an orthographic, axis-aligned camera moves
the grid to the plane perpendicular to the view direction. In free-mouse mode,
`2`, `3`, and `4` select top/XZ, side/YZ, and front/XY orthographic views. The
first axis preset saves the current perspective camera; `1`, or re-entering
captured camera-look mode, restores it. Set `view_preset_focus` and
`view_preset_distance` to frame a program's scene, or set
`view_preset_shortcuts_enabled` to false to disable these keys.

`O` independently toggles perspective/orthographic projection, and the mouse
wheel controls the orthographic view height. A Blender-style X/Y/Z orientation
widget in the upper-right corner rotates with the camera and displays an
`ORTHO` badge while orthographic projection is active. Set
`show_view_axis_gizmo` to false to hide it.
The **Graphics Settings** menu contains persistent **Wireframe** and
**Infinite Grid** toggles.

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
