# Toolbox Engine

This module is a small stack of window and loop helpers. You can use the lowest layer and own everything yourself, or climb the stack until the engine gives you an OpenGL window, UI, menus, camera movement, and common renderers.

- `Looping_Program`: Use when you only want a fixed-rate loop with timing, `delta_time`, and a shutdown flag.
- `Software_Windowed_Program`: Use when you want a CPU framebuffer and no OpenGL dependency. It owns loop timing, the Win32/GDI window, software framebuffer, event polling, and blit.
- `Windowed_Program`: Use when you want an OpenGL window with UI, audio, assets, configuration, loop timing, and a basic renderer initialized.
- `Windowed_Menu_Program`: Use when you want `Windowed_Program` plus common game menus for resolution, fullscreen, vsync, max FPS, and user settings.
- `Windowed_Program_2D`: Use when you want a simple 2D OpenGL scene shell with a menu window, 2D camera, color renderer, and renderable list.
- `Windowed_Program_3D`: Use when you want a 3D OpenGL scene shell with a menu window, camera, movement, mouse look, color renderer, and renderable list.

OpenGL window layers expect the project data directory to exist, including UI font assets such as `data/fonts/pt_serif/atlas.json` and `atlas.png`. This is bad and I need a better method for handling this

## Imports

Most entry points should just import the engine module:

```jai
#import "Basic";
#import "tbx/engine";
```

## Looping_Program

Use this when you do not need a window helper and just want stable frame timing.

```jai
#import "Basic";
#import "tbx/engine";

main :: () {
    lp: Looping_Program;
    init(*lp, 60);

    while !lp.end_program {
        mark_frame_start(*lp);

        // Update and render your app here.

        sleep_to_maintain_max_fps(*lp);
        mark_frame_end(*lp);
    }
}
```

Important calls:

- `init(*lp, max_fps)` installs the shutdown handler and initializes timing.
- `mark_frame_start(*lp)` starts the frame.
- `sleep_to_maintain_max_fps(*lp)` sleeps/yields until the target frame end.
- `mark_frame_end(*lp)` updates `delta_time`, `current_time_sec`, and `iteration`.

## Software_Windowed_Program

Use this when you want a window with a CPU-side pixel buffer. This path currently uses Win32/GDI and doesn't support linux yet

```jai
#import "Basic";
#import "Windows";
#import "tbx/engine";

main :: () {
    #if OS != .WINDOWS {
        print("Software_Windowed_Program currently uses Win32/GDI.\n");
        return;
    }

    swp: Software_Windowed_Program;
    swp.framebuffer_width  = 320;
    swp.framebuffer_height = 180;
    swp.window_width       = 1280;
    swp.window_height      = 720;
    swp.class_name         = "tbx_software_window_example";
    swp.window_name        = "Software Window Example";

    if !init(*swp) {
        print("Software window creation failed.\n");
        return;
    }
    defer deinit(*swp);

    set_max_fps(*swp, 60);

    while swp.running && !swp.end_program {
        mark_frame_start(*swp);

        poll_events(*swp);
        if key_pressed_once(*swp, VK_ESCAPE) swp.running = false;

        for *pixel: swp.framebuffer.pixels {
            pixel.* = 0xff202020;
        }

        blit_to_window(*swp);

        sleep_to_maintain_max_fps(*swp);
        mark_frame_end(*swp);
    }
}
```

Important calls:

- `init(*swp)` initializes loop timing and creates the window/framebuffer.
- `poll_events(*swp)` pumps Win32 events and updates `running`.
- `key_pressed_once(*swp, vk)` checks one-frame key transitions.
- Write `u32` pixels into `swp.framebuffer.pixels`.
- `blit_to_window(*swp)` presents the framebuffer.
- `mark_frame_start(*swp)`, `sleep_to_maintain_max_fps(*swp)`, and `mark_frame_end(*swp)` come from the embedded `Looping_Program`.
- `deinit(*swp)` frees framebuffer and recording resources.

## Windowed_Program

Use this when you want the basic OpenGL app shell: window creation, loop timing, assets, UI, sound, config, and an alpha color renderer.

```jai
#import "Basic";
#import "tbx/engine";

main :: () {
    wp: Windowed_Program;
    wp.window_name = "Windowed Program Example";
    wp.window_width = 1280;
    wp.window_height = 720;
    wp.vsync = false;

    init(*wp);
    defer deinit(*wp);

    while !wp.end_program {
        mark_frame_start(*wp);

        per_frame_update(*wp);

        ui_begin(*wp);
        ui_label("Hello from the engine UI.");
        ui_end(*wp);

        sleep_to_maintain_max_fps(*wp);
        mark_frame_end(*wp);
    }
}
```

Important calls:

- `init(*wp)` initializes `Looping_Program`, assets, window, UI, renderers, sound, config, and vsync.
- `per_frame_update(*wp)` updates input/events and sets `end_program` on quit.
- `ui_begin(*wp)` and `ui_end(*wp)` bracket UI drawing.
- `sleep_to_maintain_max_fps(*wp)` respects `wp.vsync`.
- `deinit(*wp)` shuts down sound, UI, config, crosshair data, and assets.

## Windowed_Menu_Program

Use this when you want `Windowed_Program` plus a stock menu/settings layer. It is a good starting point for game-like applications.

```jai
#import "Basic";
#import "tbx/engine";

main :: () {
    wmp: Windowed_Menu_Program;
    wmp.window_name = "Menu Program Example";

    init(*wmp);
    defer deinit(*wmp);

    enumerate_resolutions(*wmp);
    init_menu_defaults(*wmp);

    while !wmp.end_program {
        mark_frame_start(*wmp);

        per_frame_update(*wmp);

        ui_begin(*wmp);
        render_menus(*wmp);
        ui_end(*wmp);

        sleep_to_maintain_max_fps(*wmp);
        mark_frame_end(*wmp);
    }
}
```

Useful menu calls:

- `enumerate_resolutions(*wmp)` fills `available_resolutions`.
- `init_menu_defaults(*wmp)` copies current graphics settings into pending menu settings.
- `toggle_menu(*wmp)` opens/closes the in-game menu.
- `render_menus(*wmp)` renders the active menu.
- `apply_graphics_settings(*wmp)` applies fullscreen, vsync, resolution, and max FPS.
- `save_settings(*wmp)` and `load_menu_settings(*wmp)` persist menu settings.

## Windowed_Program_2D

Use this when you want a 2D OpenGL scene shell with camera controls and a color renderer.

```jai
#import "Basic";
#import "tbx/engine";
#import "tbx/geometry";
#import "tbx/opengl";

main :: () {
    wp2: Windowed_Program_2D;
    init(*wp2, "2D Example");
    defer deinit(*wp2);

    renderable := array_add(*wp2.renderables);
    geometry := create_itpc_with_color_variation(create_torus(ZERO3, Z3, 2, 1, 8, 8));
    assign_geometry(renderable, geometry);
    buffer_object(*wp2.camera_per_object_transform_color_renderer, renderable);

    while !wp2.end_program {
        mark_frame_start(*wp2);

        per_frame_update(*wp2);
        render_scene(*wp2);

        sleep_to_maintain_max_fps(*wp2);
        mark_frame_end(*wp2);
    }
}
```

Notes:

- `Windowed_Program_2D` uses `Windowed_Menu_Program`.
- `renderables` stores `Camera_Per_Object_Transform_Color_Renderable`.
- `per_frame_update(*wp2)` updates the base window/menu/input and 2D camera.
- `render_scene(*wp2)` renders the 2D scene using the built-in renderer.

## Windowed_Program_3D

Use this when you want a 3D OpenGL scene shell with camera movement, mouse look, menus, and a color renderer.

```jai
#import "Basic";
#import "tbx/engine";
#import "tbx/geometry";
#import "tbx/opengl";

main :: () {
    wp3: Windowed_Program_3D;
    wp3.window_name = "3D Example";
    wp3.camera.position = .{0, -6, 3};
    wp3.movement_mode = .GOD;

    init(*wp3);
    defer deinit(*wp3);

    renderable := array_add(*wp3.renderables);
    geometry := create_itpc_with_color_variation(create_cube(.{}, 2.0));
    assign_geometry(renderable, geometry);
    buffer_object(*wp3.camera_per_object_transform_color_renderer, renderable);

    while !wp3.end_program {
        mark_frame_start(*wp3);

        per_frame_update(*wp3);
        render_scene(*wp3);

        sleep_to_maintain_max_fps(*wp3);
        mark_frame_end(*wp3);
    }
}
```

Notes:

- `Windowed_Program_3D` uses `Windowed_Menu_Program`.
- `camera_mode` defaults to `.FIRST_PERSON`.
- `movement_mode` controls how the camera/player movement is interpreted.
- `camera_look_active` controls mouse-look behavior.
- `render_scene(*wp3)` renders the default 3D scene and UI overlays.
