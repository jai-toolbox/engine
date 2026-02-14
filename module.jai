
// usage of this engine is at the bottom of the file

#import "Window_Creation";
#import "Math";
#import "Basic";
#import "GL";

#scope_file
Sound :: #import "Sound_Player";
Simp :: #import "Simp";
Input :: #import "Input";
#scope_export

#import "GetRect";

#import "tbx/opengl";
#import "tbx/camera";
#import "tbx/movement";
#import "tbx/rectangle";
#import "tbx/time";
#import "tbx/math";

Current_Menu :: enum {
    MAIN;
    GRAPHICS_SETTINGS;
    USER_SETTINGS;
    SOUND_SETTINGS;
    NONE;
}

/*

In the beginning you want results, in the end all you want is control. - Eskil Steenburg

This "engine" is for when all you want is results, designed modularly enough so that when you want control you can lop off pieces of it incrementally.

There are some things which are genuinely useful all the time such as the looping program so that you don't have to compute a delta time yourself every frame.

*/

Looping_Program :: struct {
    end_program := false;

    // max_fps : u32 = 60;
    max_fps : u32 = 144;
    // frames must take at least this long, they may be longer, and in that case our fps will be under 60, which is what we want.
    // if they were any shorter we'd get over 60, which is not what we want because we set our max_fps above.
    min_frame_time :float;

    tick_timer : Periodic_Timer;

    current_time_sec : float = 0;

    current_frame_start : Apollo_Time;
    delta_time :float; 
}


/*

A windowed program is a program that has a window and assume that you're going to use GetRect and Simp to do ui stuff. You can still bring your own rendering.

The point of it is that when you make a new program you don't have to remember which per-frame updates you need to call
and instead you can just focus on making the program happen instead of the boilerplate you would normally write at the start of a new program.

In the future it might be good to have one that doesn't rely on GetRect but for now it seems totally fine.

*/
Windowed_Program :: struct {

    using # as lp : Looping_Program;

    window : Window_Type;
    saved_window_info : Saved_Window_Info;

    window_name : string = "";

    window_width : s32 = 1280;
    window_height : s32 = 720;

    current_menu := Current_Menu.MAIN;

    vsync := false;

    fullscreen := false;

    right_handed_mouse_position := false;

    current_theme: s32 = xx Default_Themes.Default;
    my_theme: Overall_Theme;  // This gets filled out by calling the Theme_Proc for current_theme.
}

set_max_fps :: (using lp: *Looping_Program, new_max_fps : u32) {
    max_fps = new_max_fps;
    min_frame_time = 1.0 / max_fps;
}

init :: (using lp: *Looping_Program) {
    min_frame_time = 1.0 / max_fps;
    // we're just setting it to this so the first iteration has a value.
    delta_time = min_frame_time;
}

init :: (using wp: *Windowed_Program) {
    init(*lp);
    window = create_window(window_width, window_height, window_name);
    Simp.set_render_target(window);
    ui_init();
    proc := default_theme_procs[current_theme];
    my_theme = proc();
    set_default_theme(my_theme); 
    set_vsync(vsync);

    // NOTE: if you try and do this before the windows opens, it messes up and only plays sounds when the window is hidden
    // this probably occurs because the sound player has a default of turning off the audio when you alt-tab, and that logic gets
    // accidentally inverted.
    if !Sound.sound_player_init(.{}) {
        print("Failed to initialize sound player!\n");
        // return;
    }
}

deinit :: (using wp: *Windowed_Program) {
    Sound.sound_player_shutdown();
}

// it's important to note that this can be called on windowed program or windowed program 3d 
// only because we put the looping program at the very start of both of those structs so 
// they can prance around as looping programs and when we interpret it as such it's all good. else it would be a memory error
mark_frame_start :: (using lp: *Looping_Program) {
    current_frame_start = current_time_monotonic();
}

sleep_to_maintain_max_fps :: (using lp: *Looping_Program) {
    while true {
        current_time := current_time_monotonic();
        if to_float64_seconds(current_time - current_frame_start) >= min_frame_time break;
    }
}

sleep_to_maintain_max_fps :: (using wp: *Windowed_Program) {
    if vsync return;
    sleep_to_maintain_max_fps(*lp);
}


mark_frame_end :: (using lp: *Looping_Program) {
    frame_end := current_time_monotonic();
    delta_time = cast (float) to_float64_seconds(frame_end - current_frame_start);
    current_time_sec += delta_time;
}

per_frame_update :: (using lp: *Looping_Program) {
    mark_cycle(*tick_timer);
}



per_frame_update :: (using wp: *Windowed_Program) {
    per_frame_update(*lp);

    Input.update_window_events();
    for Input.events_this_frame {
        getrect_handle_event(it);

        if it.type == .QUIT then end_program = true;
        if it.type == {
          case .KEYBOARD;
            if it.key_pressed && it.key_code == .ESCAPE end_program = true;
        }
    }

    for Input.get_window_resizes() {
        Simp.update_window(it.window);  
        if it.window == window {
            resolution_has_changed := (it.width != window_width) || (it.height != window_height);
            if (resolution_has_changed) {
                window_width  = it.width;
                window_height = it.height;
            }
        }
    }

    apollo_current_time := current_time_consensus();
    current_time := to_float64_seconds(apollo_current_time);

    width, height := Simp.get_render_dimensions(window);
    ui_per_frame_update(window, width, height, current_time);
}

set_fullscreen :: (using wp: *Windowed_Program, enabled : bool) {

    if enabled == fullscreen return; // nothing happens cause it's already how you want.

    saved_window_info.rect.left = 0;
    saved_window_info.rect.top = 0;
    saved_window_info.rect.bottom = window_width;
    saved_window_info.rect.right = window_height;

    // todo need to do somethign with these values right?
    success, new_width, new_height := toggle_fullscreen(window, enabled, *saved_window_info);
    fullscreen = enabled;
    set_vsync(vsync);
}

enable_fullscreen :: (using wp: *Windowed_Program) {
    set_fullscreen(wp, true);
}

disable_fullscreen :: (using wp: *Windowed_Program) {
    set_fullscreen(wp, false);
}

get_rect_normalized :: (r: Rectangle, screen_width: float, screen_height: float) -> Rect {
    return get_rect_normalized(r.x, r.y, r.w, r.h, screen_width, screen_height);
}

get_rect_normalized :: (x: float, y: float, w: float, h: float, screen_width: float, screen_height: float) -> Rect {
    r: Rect;
    
    // convert from [-1, 1] space to [0, screen_size] space
    // the center in screen coordinates:
    center_screen_x := (x + 1.0) * 0.5 * screen_width;
    center_screen_y := (y + 1.0) * 0.5 * screen_height;
    
    // convert width and height from [-1, 1] range to screen pixels
    // since w and h span from -1 to 1, a value of 2.0 would be full screen
    // so we multiply by 0.5 to get the ratio, then by screen dimensions
    screen_w := w * 0.5 * screen_width;
    screen_h := h * 0.5 * screen_height;
    
    // since rect specifies bottom-left corner, subtract half the dimensions from center
    r.x = center_screen_x - screen_w * 0.5;
    r.y = center_screen_y - screen_h * 0.5;
    r.w = screen_w;
    r.h = screen_h;
    
    return r;
}

render_main_menu :: (using wp : *Windowed_Program) {
    width, height := Simp.get_render_dimensions(window);
    label_theme := my_theme.label_theme;

    r := get_rect_normalized(create_rectangle(0, 1, 1, 0.2, .TOP_CENTER), xx width, xx height);
    label(r, window_name, *label_theme);

    // create a button in the top left hand corner.
    k := height * 0.10;
    // r := get_rect(5.0, (xx height) - 5.0 - k, 8.5*k, k);
    r = get_rect_normalized(0, 0, 1, .125, xx width, xx height);

    center_area_rect := Rectangle.{0, 0, 1, 1};

    rectangles := subdivide_rectangle(center_area_rect, 8, .HORIZONTAL);

    rects : [..] Rect;
    defer array_free(rects);
    for rectangles array_add(*rects, get_rect_normalized(it, xx width, xx height));

    if button(rects[0], "start") {
        toggle_menu(wp);
    }

    if button(rects[1], "graphics settings") {
        current_menu = .GRAPHICS_SETTINGS;
    }

    if button(rects[2], "user settings") {
        current_menu = .USER_SETTINGS;
    }
    if button(rects[3], "sound settings") {
        current_menu = .SOUND_SETTINGS;
    }

  r = get_rect_normalized(-0.8, -.8, .2, .1, xx width, xx height);
  if button(r, "exit") end_program = true;
}

render_graphics_settings :: (using wp : * Windowed_Program) {
    width, height := Simp.get_render_dimensions(window);
    label_theme := my_theme.label_theme;
    r := get_rect_normalized(create_rectangle(0, 1, 1, 0.2, .TOP_CENTER), xx width, xx height);
    label(r, "Graphics Settings", *label_theme);

    // create a button in the top left hand corner.
    k := height * 0.10;
    r = get_rect_normalized(0, 0, 1, .125, xx width, xx height);

    resolutions :: string.["1080x1920", "720x1280", "480x640"];
    val : s32; // stupid throwaway to make the below work.
    dropdown(r, resolutions , *val); // val is global

    r = get_rect_normalized(0, -.125, 1, .125, xx width, xx height);

    changed, checkbox_state := base_checkbox(r, "full screen", fullscreen);
    if changed fullscreen = !fullscreen;

    r = get_rect_normalized(0, -.25, 1, .125, xx width, xx height);

    // this has to be on the camera settings.

    slider_theme := my_theme.slider_theme;
    // slider(r, *graphics_settings.field_of_view, 30, 110, 1, *slider_theme, "field of view: ");

    r = get_rect_normalized(0, -.375, 1, .125, xx width, xx height);

    slider(r, *max_fps, 30, 512, 1, *slider_theme, "max fps: ");

    r = get_rect_normalized(-0.8, -.8, .2, .1, xx width, xx height);
    if button(r, "back") current_menu = .MAIN;

    r = get_rect_normalized(0.8, .8, .3, .1, xx width, xx height);
    // if button(r, "defaults") current_menu = .MAIN;

    r = get_rect_normalized(0.8, -.8, .3, .1, xx width, xx height);
    if button(r, "apply") {
        set_fullscreen(wp, fullscreen);
        // not sure why setting this here causes the window to just disappear, which is bad.
        // set_max_fps(wp, max_fps);
    }

    defer draw_popups();
}

render_user_settings :: (using wp : *Windowed_Program) {
    width, height := Simp.get_render_dimensions(window);
    label_theme := my_theme.label_theme;
    r := get_rect_normalized(create_rectangle(0, 1, 1, 0.2, .TOP_CENTER), xx width, xx height);
    label(r, "User Settings", *label_theme);

    r = get_rect_normalized(-0.8, -.8, .2, .1, xx width, xx height);
    if button(r, "back") current_menu = .MAIN;
}

render_sound_settings :: (using wp : *Windowed_Program) {
    width, height := Simp.get_render_dimensions(window);
    label_theme := my_theme.label_theme;
    r := get_rect_normalized(create_rectangle(0, 1, 1, 0.2, .TOP_CENTER), xx width, xx height);
    label(r, "Sound Settings", *label_theme);

    r = get_rect_normalized(-0.8, -.8, .2, .1, xx width, xx height);
    if button(r, "back") current_menu = .MAIN;

    slider_theme := my_theme.slider_theme;

    r = get_rect_normalized(0, -.375, 1, .125, xx width, xx height);
    slider(r, *volume, 0, 100, 1, *slider_theme, "volume: ");
}

render_menus :: (using wp : *Windowed_Program) {
    if current_menu == {
        case .MAIN;
            render_main_menu(wp);
        case .GRAPHICS_SETTINGS;
            render_graphics_settings(wp);
        case .USER_SETTINGS;
            render_user_settings(wp);
        case .SOUND_SETTINGS;
            render_user_settings(wp);
    }
}

render_tick_stats :: (using wp : *Windowed_Program) {
    average_tick_ms : int = xx (get_average_delta_time(*tick_timer) * 1000);
    average_fps : int = xx (1 / get_average_delta_time(*tick_timer));

    label_theme := my_theme.label_theme;
    r := get_rect_normalized(create_rectangle(1, 1, 0.25, 0.1, .TOP_RIGHT), xx window_width, xx window_height);

    label(r,sprint("%/%ms", average_fps, average_tick_ms), *label_theme);
}

toggle_menu :: (using wp : *Windowed_Program) {
    if (current_menu == .NONE) {
        current_menu = .MAIN;
        show_cursor();
    } else {
        current_menu = .NONE;
        hide_cursor();
    }
}

Camera_Mode :: enum {
    FIRST_PERSON;
    THIRD_PERSON;
}

Movement_Mode :: enum {
    GOD;
    MANUAL;
    FPS; // you'll need to do collision detection in this case.
}

is_key_down :: inline (key : Input.Key_Code) -> bool #must {
	return (Input.input_button_states[cast (s64) key] & .DOWN) != 0;
}

is_key_just_pressed :: inline (key : Input.Key_Code) -> bool #must {
	return (Input.input_button_states[cast (s64) key] & .START) != 0;
}

/*

A windowed program 3d is something you can use to get to rendering things on the screen fast

*/

// this should be moved to its own file because it seems kinda important for some reason.

Orientation :: struct {
    forward: Vector3;
    right: Vector3;
    up: Vector3;
}

// #running away from our problems
STANDARD_ORIENTATION :: #run Orientation.{X3, -Y3, Z3};
GL_ORIENTATION :: Orientation.{Z3, X3, Y3};
NEGATIVE_Z_GL_ORIENTATION :: #run Orientation.{-Z3, X3, Y3};

Windowed_Program_3D :: struct {

    using #as wp : Windowed_Program;

    orientation := STANDARD_ORIENTATION;

    /*
    the reasoning for this choice is as follows. 
    - We are humans, at rest we look forward, the easiest direction to move is forward, in order to move or look left or right, it takes extra effort, additionally looking up is even more difficult.
    - Because of that it makes sense to map the first direction, so we pick e1/x/(1, 0, 0) to represent forward. 
    - In two dimensions cos and sin rotate counter clockwise as theta increases (see the turns module for more details)
    - Thus if we follow the rotation of cos/sin then we eventually get to e2/y/(0, 1, 0), so the default cartesian plane has right handedness baked into it
    - If x is forward, then that means y is left based on the previous line, so -y would be right
    - Once you have x and y, you add z, if you add z and make it down then the basis is left handed, which changes from the 2d basis, so it's less confusing to not do that
    - So we make z up.
    */

    /*

    The basis E = (e1, e2, 3) is right handed, the reason why is because we defined our 3d grid system in a way such that the right hand rule works on it ie 
    y was placed counter clockwise to x and z counterclockwise to y. This is why we can call this right handed in the first place. If we had not made our grid system like this
    then it wouldn't be called right handed anymore.

    Alternatively if we claimed that the basis E = (e1, e2, e3) is right handed, then it would force our axes to be lined up in some way to make sure that its true. 
    We can see that either way this is just a convention to make things work.

    Given two bases B = (b1, b2, b3) and C = (c1, c2, c3) then we can determine if C is the same handedness of B by writing the basis vectors c1, c2, c3 in the B basis to obtain
    C' = (j1, j2, j3) and then using a the standard procedure to determine of B and C' are of the same handedness.

    Additionally the basis (e1, e2, e3) can be thought of as (forward, left, up) because of the previous talk. So we can ask ourselves if the basis (-e3, -e1, e2) is right handed
    and yes it is because if you rotate around e2 counter clockwise 90 degrees and then around z 90 degrees you get the second basis, and rotations don't change the handedness.

    Concrete example we want to know if the basis given by 
    */
 
    per_object_transform_renderer : Per_Object_Transform_Renderer;
    per_object_absolute_position_color_renderer : Per_Object_Absolute_Position_Color_Renderer;

    camera : Camera;
    camera_mode := Camera_Mode.FIRST_PERSON;
    camera_active := false;

    // only used if you want to use the default movement modes.
    camera_velocity : Vector3;
    movement_mode : Movement_Mode;

    // you only use this when you're really not doing anything unique in your program and you're fine
    // with the windowed program 3d handling the rendering of your objects so that you don't have to manually render
    // most programs will outgrow this but it's nice at the start
    object_indices_to_render : [..] u32;
}

init :: (using wp3 : *Windowed_Program_3D) {
    init(*wp);
    init(*per_object_transform_renderer);
    init(*per_object_absolute_position_color_renderer);
}

set_mouse_pointer_position :: inline (x : int, y : int) {
	#if OS == .WINDOWS {
		// Windows module does not have SetCursorPos
		// win32 :: #import "Windows";
		// win32.SetCursorPos (xx x, xx y);
		// Hugh...
		user32 :: #system_library "User32";
		SetCursorPos :: (x : s32, y : s32) -> s32 #foreign user32;
		SetCursorPos (xx x, xx y);
	} else {
		// @Todo!
	}
}

format_vec3 :: (v: Vector3, decimals: int = 2) -> string {
    return tprint("(%, %, %)",
        FormatFloat.{value=v.x, trailing_width=decimals, zero_removal=.NO},
        FormatFloat.{value=v.y, trailing_width=decimals, zero_removal=.NO},
        FormatFloat.{value=v.z, trailing_width=decimals, zero_removal=.NO});
}

render_movement_stats :: (using wp3 : *Windowed_Program_3D) {
    label_theme := my_theme.label_theme;
    rect_height := 0.1;
    rect_width := 0.4;
    r_pos := get_rect_normalized(create_rectangle(-1, 1, rect_width, rect_height, .TOP_LEFT), xx window_width, xx window_height);
    r_vel := get_rect_normalized(create_rectangle(-1, 1 - rect_height, rect_width, rect_height, .TOP_LEFT), xx window_width, xx window_height);

    label(r_pos, format_vec3(camera.position), *label_theme);
    label(r_vel, format_vec3(camera_velocity), *label_theme);
}

render_camera_stats :: (using wp3 : *Windowed_Program_3D) {
    label_theme := my_theme.label_theme;
    rect_height := 0.1;
    rect_width := 0.4;
    r := get_rect_normalized(create_rectangle(-1, -1, rect_width, rect_height, .BOTTOM_LEFT), xx window_width, xx window_height);

    label(r, format_vec3(get_forward(*camera)), *label_theme);
}


keep_mouse_in_center_of_screen :: (using wp: *Windowed_Program) {
    #if OS == .WINDOWS {
        // so that the cursor doesn't fall off the screen.
        x, y, w, h := get_dimensions(window, right_handed_mouse_position);
        set_mouse_pointer_position (w / 2, h / 2);
    } else {
        // don't yet have ability to hide cursor properly on linux
    }
}

update_listener_orientation :: (position: Vector3, yaw: float) {
    yaw_quat: Quaternion;
    // explain why negative yaw...
    set_from_axis_and_angle(*yaw_quat, 0, 0, 1, -yaw);

    rotation_y: Quaternion;
    set_from_axis_and_angle(*rotation_y, 0, 1, 0, PI/2);
    
    rotation_z: Quaternion;
    set_from_axis_and_angle(*rotation_z, 0, 0, 1, PI/2);

    // our objects position in the sound system adheres to NEGATIVE_Z_GL_ORIENTATION
    // listener position assume the STANDARD_ORIENTATION so we have to correct it or else
    // it going to think left right and up down are reversed, here' we're making our yaw into pitch
    // todo probably better to put the positions in the right way no? yeah, but this works right now change later if needed.
    correction_quat := rotation_z * rotation_y;

    listener_orientation := yaw_quat * correction_quat;

    Sound.update_listener(position, listener_orientation);
}

per_frame_update :: (using wp3 : *Windowed_Program_3D) {
    per_frame_update(*wp3.wp);

    if (current_menu == .NONE) {
        #if OS == .WINDOWS {
            keep_mouse_in_center_of_screen(*wp3.wp);
            update_angles_with_deltas(*camera, Input.mouse_delta_x, Input.mouse_delta_y);
        } else {
            // don't yet have ability to hide cursor properly on linux
            x, y, success := get_mouse_pointer_position(window, right_handed_mouse_position); 
            if success update_angles(*camera, x, y);
        }
    }


    x, y, success := get_mouse_pointer_position(window, right_handed_mouse_position); 
    if success update_angles(*camera, x, y);

    // "virtual dimensions" makes sense when you have multiple monitors
    vx, vy, vw, vh := get_dimensions (window, right_handed_mouse_position);
    if camera_mode == {
        case .FIRST_PERSON;
            update_matrices(*camera, vw, vh);
        case .THIRD_PERSON;
            update_matrices_third_person(*camera, vw, vh);
    }

    if movement_mode == {
        case .GOD;
            gmi := God_Mode_Input.{
                is_key_down (xx #char "E"),
                is_key_down (xx #char "Q"),
                is_key_down (xx #char "W"),
                is_key_down (xx #char "S"),
                is_key_down (xx #char "D"),
                is_key_down (xx #char "A"),
                is_key_down (xx #char " "),
                is_key_down (Input.Key_Code.SHIFT),
            }; 


            // log("doing god with delta time: %", delta_time);
            camera_velocity = get_new_god_mode_velocity(camera_velocity , get_forward(*camera), gmi, delta_time);
    }

    if movement_mode != .MANUAL camera.position += camera_velocity * delta_time;

    update_listener_orientation(camera.position, camera.yaw);

    Sound.update(delta_time);

    glUseProgram(per_object_transform_renderer.shader_program_gl_handle);

    row_major := GL_TRUE;
    num_matrices_we_are_updating :u32 = 1;

    // todo one day we will replace glGetUniformLocation with the safe alternative that uses an enum, so we can never type a bad string.
    glUniformMatrix4fv(glGetUniformLocation(per_object_transform_renderer.shader_program_gl_handle, "world_to_camera"), num_matrices_we_are_updating, row_major, *camera.world_to_camera.coef[0][0]);
    glUniformMatrix4fv(glGetUniformLocation(per_object_transform_renderer.shader_program_gl_handle, "camera_to_clip"), num_matrices_we_are_updating, row_major, *camera.camera_to_clip.coef[0][0]);

}

// this is what you call when you really don't care about control yet, you're just like I want geometry on the screen now and I want menus 
// and I don't want to care about graphics or anything, but I'm just testing some sort of minimal 3d program and that's all. 
// most people would only ever call this when they're doing basic experimentation and graphics is not the point of the program.
// this function provides a good starting point to see how to integrate simp and your own rendering logic.
render_scene :: (using wp3 : *Windowed_Program_3D) {

    for object_indices_to_render queue_render(*wp3.per_object_transform_renderer, it);

    Simp.update_window(wp3.window);
    Simp.clear_render_target(.15, .08, .08, 1);

    if (wp3.current_menu == .NONE) {
        // re-enable depth testing for 3d rendering without these lines depth is messed up, this is because simp disables it probably, look into this later when caring more
        glDepthMask(GL_TRUE);
        glEnable(GL_DEPTH_TEST);
        glClear(GL_DEPTH_BUFFER_BIT);
        render(*wp3.per_object_transform_renderer);

        context.simp.current_shader = null; 
        // rendering these things should be optional at somepoint but it seems useful for now.
        render_tick_stats(wp3); // shouldn't this be a pointer?
        render_movement_stats(wp3);
        render_camera_stats(wp3);
    } else {
        // when you render with your own custom rendering it clobbers the opengl global state or at least would use the program and then set the program to be empty
        // either way simp internally keeps track of the last shader it used and it would be the same as last draw, it doesn't have to re-bind the shader
        // this is fine in the context of simp but with your own rendering it messes up this state causing simp to not rebind a shader when it should
        // by setting this to null it forces simp to rebind all the shaders it needs
        context.simp.current_shader = null; 
        render_menus(*wp3.wp);
    }


    // swap_buffers(windowed_program_3d.window, windowed_program_3d.vsync);
    Simp.swap_buffers(wp3.window, false);
}

show_cursor :: inline () {
	#if OS == .WINDOWS {
		win32 :: #import "Windows";
		win32.ShowCursor (1);
	} else {
		// @Todo!
	}
}

hide_cursor :: inline () {
	#if OS == .WINDOWS {
		win32 :: #import "Windows";
		win32.ShowCursor (0);
	} else {
		// @Todo!
	}
}



/*

The way you use this "engine" can be as modular as you want. If you want to do pretty much everything yourself then you can just grab Looping_Program so that you have a loop which
runs at a controlled rate. That can look something like this: 

On the other hand, a good reason to use this engine is that it allows you to start rendering objects immediately. If you're new to jai, then this is like getting the key to the castle.
And so you can start focusing on making a game or something immediately, which is great overtime you'll explore the rooms of the castle and understand its layout. 
Eventually you'll want to to do something that doesn't exist in the castle, and then you can start moving away from it. Either way here is the highest level of support we currently give:

#import "Basic";
#import "Math";
#import "System";

#import "tbx/engine";
#import "tbx/opengl";
#import "tbx/geometry";
Input :: #import "Input";
Simp :: #import "Simp";

#import "GL";

main :: () {
	// This is here because on Windows, segfaults and stuff are silent.
	// If the program ends without printing this message, then something bad happened.
	defer print ("Program ended gracefully, if you stop seeing this then something bad happend.\n");


    wp3 : Windowed_Program_3D;
    wp3.vsync = false;
    wp3.movement_mode = .GOD;
    wp3.window_name = "my_program";
    init(*wp3);


    box := create_itpc_with_color_variation(create_box());    
    box_render_index, box_local_to_world_index := buffer_object(*wp3.per_object_transform_renderer, box.indices, box.positions, box.rgb_colors);
    wp3.per_object_transform_renderer.local_to_world_matrices[box_local_to_world_index] = make_translation_matrix4(.{1, 1, 1});

    array_add(*wp3.object_indices_to_render, box_render_index);

    while !wp3.end_program {
        mark_frame_start(*wp3);
        
        per_frame_update(*wp3);

        render_scene(*wp3);

        sleep_to_maintain_max_fps(*wp3);
        mark_frame_end(*wp3);
    }
}

In this system you can just create new geometry and modify the transform of objects. Very minimal but at least you don't have to write 500 lines of boilerplate to make it happen.

*/
