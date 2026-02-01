#import "Window_Creation";
#import "Math";
#import "Basic";
#import "GL";

Simp :: #import "Simp";
Input :: #import "Input";
#import "GetRect";

#import "opengl";
#import "camera";
#import "movement";
#import "rectangle";

Current_Menu :: enum {
    MAIN;
    GRAPHICS_SETTINGS;
    USER_SETTINGS;
    SOUND_SETTINGS;
}

Windowed_Program :: struct {
    window : Window_Type;
    saved_window_info : Saved_Window_Info;

    end_program := false;

    window_name : string = "";

    window_width : s32 = 1280;
    window_height : s32 = 720;

    current_menu := Current_Menu.MAIN;

    max_fps : u32 = 60;

    fullscreen := false;

    right_handed_mouse_position := false;

    current_theme: s32 = xx Default_Themes.Default;
    my_theme: Overall_Theme;  // This gets filled out by calling the Theme_Proc for current_theme.
    
}

init :: (using wp: *Windowed_Program) {
    window = create_window(window_width, window_height, window_name);
    Simp.set_render_target(window);
    ui_init();
    proc := default_theme_procs[current_theme];
    my_theme = proc();
    set_default_theme(my_theme); 
}

per_frame_update :: (using wp: *Windowed_Program) {
    apollo_current_time := current_time_consensus();
    current_time := to_float64_seconds(apollo_current_time);

    width, height := Simp.get_render_dimensions(window);
    ui_per_frame_update(window, width, height, current_time);
}

set_fullscreen :: (using wp: *Windowed_Program, enabled : bool) {
    toggle_fullscreen(window, enabled, *saved_window_info);
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
        // start your program here.
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

    slider(r, *max_fps, 30, 1024, 1, *slider_theme, "max fps: ");

    r = get_rect_normalized(-0.8, -.8, .2, .1, xx width, xx height);
    if button(r, "back") current_menu = .MAIN;

    r = get_rect_normalized(0.8, .8, .3, .1, xx width, xx height);
    // if button(r, "defaults") current_menu = .MAIN;

    r = get_rect_normalized(0.8, -.8, .3, .1, xx width, xx height);
    if button(r, "apply") {
        set_fullscreen(wp, fullscreen);
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

Windowed_Program_3D :: struct {

    using #as wp : Windowed_Program;
    per_object_transform_renderer : Per_Object_Transform_Renderer;

    camera : Camera;
    camera_mode := Camera_Mode.FIRST_PERSON;
    camera_active := false;

    // only used if you want to use the default movement modes.
    camera_velocity : Vector3;
    movement_mode : Movement_Mode;
}

init :: (using wp3 : *Windowed_Program_3D) {
    init(*wp);

    shader_program_handle, success := create_shader_program(VERTEX_SHADER_WITH_CAMERA_AND_PER_OBJECT_TRANSFORMS, VERTEX_COLOR_FRAGMENT_SHADER);
	if !success
        log("shader compilation failed");
		// return false;
    if success 
        log("shader compilation succeeded");

    // todo: doing this first is slightly annoying
    per_object_transform_renderer.shader_program_gl_handle = shader_program_handle;
    init(*per_object_transform_renderer);
}

per_frame_update :: (using wp3 : *Windowed_Program_3D, delta_time : float) {

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
                is_key_down (xx #char "V"),
                is_key_down (Input.Key_Code.SHIFT),
            }; 

            camera_velocity = get_new_god_mode_velocity(camera_velocity , get_forward(*camera), gmi, delta_time);
    }
    if movement_mode != .MANUAL camera.position += camera_velocity * delta_time;

    glUseProgram(per_object_transform_renderer.shader_program_gl_handle);


    row_major := GL_TRUE;
    num_matrices_we_are_updating :u32 = 1;

    glUniformMatrix4fv(glGetUniformLocation(per_object_transform_renderer.shader_program_gl_handle, "world_to_camera"), num_matrices_we_are_updating, row_major, *camera.world_to_camera.coef[0][0]);
    glUniformMatrix4fv(glGetUniformLocation(per_object_transform_renderer.shader_program_gl_handle, "camera_to_clip"), num_matrices_we_are_updating, row_major, *camera.camera_to_clip.coef[0][0]);

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



