#scope_file
Input :: #import "Input";
#scope_export

key_pressed :: inline (key : Input.Key_Code) -> bool #must {
    return (Input.input_button_states[cast (s64) key] & .DOWN) != 0;
}

key_just_pressed :: inline (key : Input.Key_Code) -> bool #must {
    return (Input.input_button_states[cast (s64) key] & .START) != 0;
}

right_mouse_just_pressed :: () -> bool #must {
    return Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT] & .START != 0;
}

left_mouse_just_pressed :: () -> bool #must {
    return Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_LEFT] & .START != 0;
}

left_mouse_pressed :: () -> bool #must {
    return Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_LEFT] & .DOWN != 0;
}

right_mouse_pressed :: () -> bool #must {
    return Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT] & .DOWN != 0;
}

set_mouse_pointer_position :: inline (x : int, y : int) {
    #if OS == .WINDOWS {
        user32 :: #system_library "User32";
        SetCursorPos :: (x : s32, y : s32) -> s32 #foreign user32;
        SetCursorPos (xx x, xx y);
    } else {
        // @Todo!
    }
}
