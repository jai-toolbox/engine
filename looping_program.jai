
Looping_Program :: struct {
    end_program := false; // loop on this condition

    max_fps : u32 = 144;
    min_frame_time :float;

    tick_timer : Periodic_Timer;

    current_time_sec : float = 0;

    section_timer : Section_Timer;

    current_frame_start : Apollo_Time;
    delta_time :float;

    iteration := 0;
}


set_max_fps :: (using lp: *Looping_Program, new_max_fps : u32) {
    max_fps = new_max_fps;
    min_frame_time = 1.0 / max_fps;
}

init :: (using lp: *Looping_Program) {
    min_frame_time = 1.0 / max_fps;
    delta_time = min_frame_time;
}

// must be called at start of frame for delta_time to be correct
mark_frame_start :: (using lp: *Looping_Program) {
    current_frame_start = current_time_monotonic();
}

// must be called to maintain target frame rate
sleep_to_maintain_max_fps :: (using lp: *Looping_Program) {
    while true {
        current_time := current_time_monotonic();
        if to_float64_seconds(current_time - current_frame_start) >= min_frame_time break;
    }
}

// must be called at end of frame for delta_time to be correct
mark_frame_end :: (using lp: *Looping_Program) {
    reset_temporary_storage();
    frame_end := current_time_monotonic();
    delta_time = cast (float) to_float64_seconds(frame_end - current_frame_start);
    current_time_sec += delta_time;
    iteration += 1;
}

// not required to function
per_frame_update :: (using lp: *Looping_Program) {
    mark_cycle(*tick_timer);
}
