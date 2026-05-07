/*

Doesn't use dynamic memory by default and doesn't need to be deinitialized. 
This might not be true if you make the pool (inside section timer) on the heap or something if you need more space.

*/
Looping_Program :: struct {

    end_program := false; // loop on this condition

    max_fps : u32 = 144;
    min_frame_time : float;

    tick_timer : Periodic_Timer;

    current_time_sec : float = 0;

    section_timer : Section_Timer;

    current_frame_start : Apollo_Time;
    delta_time : float;

    iteration := 0;
}

#if OS == .WINDOWS {
    kernel32 :: #system_library "kernel32";
    HANDLER_ROUTINE :: #type (dwCtrlType: u32) -> s32 #c_call;
    SetConsoleCtrlHandler :: (HandlerRoutine: HANDLER_ROUTINE, Add: s32) -> s32 #foreign kernel32;

    _signal_target: *bool;

    _ctrl_handler :: (ctrl_type: u32) -> s32 #c_call {
        if ctrl_type == 0 || ctrl_type == 1 {
            if _signal_target  _signal_target.* = true;
            return 1;
        }
        return 0;
    }

    install_shutdown_signal_handler :: (end_flag: *bool) {
        _signal_target = end_flag;
        SetConsoleCtrlHandler(_ctrl_handler, 1);
    }
} else #if OS == .LINUX || OS == .MACOS {
    #import "POSIX";

    _signal_target: *bool;

    _sigint_handler :: (sig: s32) #c_call {
        if _signal_target  _signal_target.* = true;
    }

    install_shutdown_signal_handler :: (end_flag: *bool) {
        _signal_target = end_flag;

        act: sigaction_t;
        act.sa_handler = _sigint_handler;
        sigemptyset(*act.sa_mask);
        act.sa_flags = 0;
        sigaction(SIGINT, *act, null);
        sigaction(SIGTERM, *act, null);
    }
}

set_max_fps :: (using lp: *Looping_Program, new_max_fps: u32) {
    max_fps = new_max_fps;
    min_frame_time = 1.0 / max_fps;
}

init :: (lp: *Looping_Program, max_fps : u32 = 144) {
    lp.max_fps = max_fps;
    lp.min_frame_time = 1.0 / max_fps;
    lp.delta_time = lp.min_frame_time; // an initial value, is this even required?

    // todo init section timer?

    install_shutdown_signal_handler(*lp.end_program);
}

// must be called at start of frame for delta_time to be correct
mark_frame_start :: (using lp: *Looping_Program) {
    current_frame_start = current_time_monotonic();
}

// must be called to maintain target frame rate, this is too spinny though
sleep_to_maintain_max_fps :: (using lp: *Looping_Program) {
    while true {
        current_time := current_time_monotonic();
        if to_float64_seconds(current_time - current_frame_start) >= min_frame_time break;
    }
}

// must be called at end of frame for delta_time to be correct, you should call it after you sleep or else delta time will be too small.
mark_frame_end :: (using lp: *Looping_Program) {
    reset_temporary_storage();
    frame_end := current_time_monotonic();
    delta_time = cast(float) to_float64_seconds(frame_end - current_frame_start);
    current_time_sec += delta_time;
    iteration += 1;
}

// not required to function
per_frame_update :: (using lp: *Looping_Program) {
    mark_cycle(*tick_timer);
}
