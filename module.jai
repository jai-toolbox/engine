#import "Window_Creation";
#import "Math";
#import "Basic";
#import "GL";

Simp :: #import "Simp";
Input :: #import "Input";

#import "opengl";
#import "camera";
#import "movement";


Windowed_Program :: struct {
    window : Window_Type;
    saved_window_info : Saved_Window_Info;

    window_name : string = "";

    window_width : s32 = 1280;
    window_height : s32 = 720;

    fullscreen := false;

    right_handed_mouse_position := false;
}

init :: (using wp: *Windowed_Program) {
    window = create_window(window_width, window_height, window_name);
    Simp.set_render_target(window);
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



