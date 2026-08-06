/*

The way you use this "engine" can be as modular as you want. If you want to do everything yourself then you can just grab Looping_Program so that you have a loop which
runs at a controlled rate. That can look something like this:

On the other hand, a good reason to use this engine is that it allows you to start rendering objects immediately. If you're new to jai, then this is like getting the key to the castle.
And so you can start focusing on making a game or something immediately, which is great overtime you'll explore the rooms of the castle and understand its layout. 
Eventually you'll want to to do something that doesn't exist in the castle, and then you can start moving away from it. Either way here is the highest level of support we currently give:
*/

#import "Basic";
#import "Math";
#import "GL";

#scope_file
// Window_Creation :: #import "Window_Creation";
// Sound_Player :: #import "Sound_Player";
// Simp :: #import "Simp";
// Input :: #import "Input";
Network :: #import "tbx/network";
#scope_export

#import "tbx/configuration";
#import "tbx/rectangle";
#import "tbx/movement";
#import "tbx/geometry";
#import "tbx/opengl";
#import "tbx/camera";
#import "tbx/time";
#import "tbx/turns";
#import "tbx/math";
#import "tbx/ui";
#import "tbx/assets";
#import "tbx/model_loading";
#import "tbx/software_rasterizer";
#import "tbx/texture_packing";
#import "tbx/animation";
#import "File_Utilities";

// ordering matters.
#load "build_type.jai";
#load "input.jai";
#load "looping_program.jai";
#load "crosshair.jai";
#load "windowed_program.jai";
#load "software_windowed_program.jai";
#load "windowed_program_2d.jai";
#load "windowed_program_3d.jai";
#load "windowed_menu_program.jai";
#load "graphs.jai";
#load "sound.jai";


format_vec3 :: (v: Vector3, decimals: int = 2) -> string {
    return tprint("(%, %, %)",
        FormatFloat.{value=v.x, trailing_width=decimals, zero_removal=.NO},
        FormatFloat.{value=v.y, trailing_width=decimals, zero_removal=.NO},
        FormatFloat.{value=v.z, trailing_width=decimals, zero_removal=.NO});
}

buf_to_string :: (buf: [] u8, len: s32) -> string {
    s: string;
    s.data = buf.data;
    s.count = len;
    return s;
}

world_to_screen :: (world_pos: Vector3, camera: *Camera, window_w: float32, window_h: float32) -> Vector2, bool {
    view       := get_world_to_camera_matrix(camera);
    proj       := get_projection_matrix(camera, xx window_w, xx window_h);
    view_proj  := multiply(proj, view);

    p := Vector4.{world_pos.x, world_pos.y, world_pos.z, 1.0};
    clip := multiply(view_proj, p);

    if clip.w <= 0 return .{}, false;

    ndc := Vector3.{clip.x / clip.w, clip.y / clip.w, clip.z / clip.w};
    screen := Vector2.{
        (ndc.x * 0.5 + 0.5) * window_w,
        (1.0 - (ndc.y * 0.5 + 0.5)) * window_h,  // flip Y
    };
    return screen, true;
}


screen_to_normalized_x :: inline (px: float32, window_w: float32) -> float32 {
    return (px / window_w) * 2.0 - 1.0;
}

screen_to_normalized_y :: inline (py: float32, window_h: float32) -> float32 {
    return -((py / window_h) * 2.0 - 1.0);
}


// The reason this is here is that it doesn't belong in the network or the serialization modules
// it needs to be somwehere, so maybe making the engine be the place where we combine them is a good thing.

#import "tbx/serialize";
#import "tbx/network";

// the packet is allocated on temporary storage, because packets get sent out soon.
create_packet :: (t: $T, packet_flags : Packet_Flags) -> *Packet {
    size_when_serialized := size_when_serialized_with_type_first(t);
    memory : *void = temporary_alloc(size_when_serialized);
    serialize_with_type_first(memory, t);
    packet := packet_create(memory, size_when_serialized, packet_flags);
    return packet;
}


attempt_to_connect_to_peer :: (host: *Network.Host, ip_address : string, port : u16) -> *Network.Peer, bool {
    peer_we_are_connecting_to : *Network.Peer;
    connected := false;

    address, address_ok := Network.get_host_ip_address(ip_address);
    if !address_ok {
        log_error("failed to resolve peer ip address '%'", ip_address);
        return null, false;
    }

    address.port = port;

    peer_we_are_connecting_to = Network.host_request_connect(host, address, 3, 5);

    event: Network.Event;

    // during the time we wait for the connect packet, we stop caring about all other incoming packets, this 
    // may lead to other issues if there were other important packets during this time, but I'm assuming that's not the case.
    connection_timer := Timer.{duration_sec = 3};
    start(*connection_timer);
    while !(time_up(*connection_timer) || connected) {
        if Network.host_service(host, *event, 100) > 0 {
            if event.type == .CONNECT {
                log("just connected to server, id: %", event.peer.connect_id);
                connected = true;
            }
        }
    }

    return peer_we_are_connecting_to, connected;
}



#import "tbx/networked_interpolator";

mode_color_map :: (m: NPSQ_Mode) -> Vector4 {
    if m == .REGULAR_OPERATION       return .{0.30, 0.75, 0.40, 0.85};
    if m == .POPULATE_INPUT_BUFFER   return .{0.85, 0.55, 0.20, 0.85};
    return .{0.5, 0.5, 0.5, 0.85};
}

emission_color_map :: (e: NPSQ_Emit_Type) -> Vector4 {
    if e == .NOT_READY  return .{0.20, 0.20, 0.25, 0.85};
    if e == .VALUE      return .{0.30, 0.80, 0.40, 0.85};
    if e == .EMPTY      return .{0.90, 0.30, 0.30, 0.85};
    return .{0.5, 0.5, 0.5, 0.85};
}

receive_heartbeat_color_map :: (received_count: u32) -> Vector4 {
    if received_count > 0 return .{0.35, 0.75, 1.0, 0.95};
    return .{0.90, 0.25, 0.25, 0.95};
}

Network_Diagnostics_Monitor :: struct {
    HISTORY_SIZE :: 120;

    receive_timer : Periodic_Timer;
    receive_sample_count : u32;

    has_last_update_number := false;
    last_update_number : u32;
    expected_update_number : u32;

    total_received : u32;
    total_gaps : u32;
    total_duplicate_updates : u32;
    total_out_of_order_updates : u32;
    total_missing_local_updates : u32;
    total_stale_local_last_applied : u32;

    current_frame_received : u32;
    current_frame_gaps : u32;
    current_frame_duplicate_updates : u32;
    current_frame_out_of_order_updates : u32;
    current_frame_missing_local_updates : u32;
    current_frame_stale_local_last_applied : u32;

    has_last_local_last_applied := false;
    last_local_last_applied : u32;
    local_last_applied : u32;
    local_last_applied_advance : s32;
    local_updates_behind : u32;
    local_found_in_last_state := false;

    receive_count_history : Circular_Array(u32, HISTORY_SIZE);
    receive_heartbeat_history : Circular_Array(u32, HISTORY_SIZE);
    gap_history : Circular_Array(u32, HISTORY_SIZE);
    duplicate_history : Circular_Array(u32, HISTORY_SIZE);
    out_of_order_history : Circular_Array(u32, HISTORY_SIZE);
    stale_local_history : Circular_Array(u32, HISTORY_SIZE);
    local_updates_behind_history : Circular_Array(u32, HISTORY_SIZE);
}

network_diagnostics_receive_rate_hz :: (monitor: *Network_Diagnostics_Monitor) -> float {
    if monitor.receive_sample_count <= 1 return 0.0;

    total_dt : float;
    count : s32;
    for dt : monitor.receive_timer.delta_times {
        if dt <= 0 continue;
        total_dt += dt;
        count += 1;
    }

    if count == 0 || total_dt <= 0 return 0.0;
    return cast(float) count / total_dt;
}

record_network_game_state_received :: (
    monitor : *Network_Diagnostics_Monitor,
    update_number : u32,
    local_found : bool = false,
    local_last_applied : u32 = 0
) {
    mark_cycle(*monitor.receive_timer);
    monitor.receive_sample_count += 1;
    monitor.total_received += 1;
    monitor.current_frame_received += 1;

    if monitor.has_last_update_number {
        expected := monitor.last_update_number + 1;
        monitor.expected_update_number = expected;

        if update_number == monitor.last_update_number {
            monitor.total_duplicate_updates += 1;
            monitor.current_frame_duplicate_updates += 1;
        } else if update_number < monitor.last_update_number {
            monitor.total_out_of_order_updates += 1;
            monitor.current_frame_out_of_order_updates += 1;
        } else if update_number > expected {
            gap := update_number - expected;
            monitor.total_gaps += gap;
            monitor.current_frame_gaps += gap;
        }
    } else {
        monitor.expected_update_number = update_number + 1;
    }

    monitor.last_update_number = update_number;
    monitor.has_last_update_number = true;

    monitor.local_found_in_last_state = local_found;
    if local_found {
        monitor.local_last_applied = local_last_applied;
        monitor.local_updates_behind = ifx update_number > local_last_applied then update_number - local_last_applied else 0;

        if monitor.has_last_local_last_applied {
            monitor.local_last_applied_advance = cast(s32) local_last_applied - cast(s32) monitor.last_local_last_applied;
            if local_last_applied == monitor.last_local_last_applied {
                monitor.total_stale_local_last_applied += 1;
                monitor.current_frame_stale_local_last_applied += 1;
            }
        } else {
            monitor.local_last_applied_advance = 0;
        }

        monitor.last_local_last_applied = local_last_applied;
        monitor.has_last_local_last_applied = true;
    } else {
        monitor.total_missing_local_updates += 1;
        monitor.current_frame_missing_local_updates += 1;
        monitor.local_last_applied_advance = 0;
    }
}

mark_network_diagnostics_frame :: (monitor : *Network_Diagnostics_Monitor) {
    carray_add(*monitor.receive_count_history, monitor.current_frame_received);
    carray_add(*monitor.receive_heartbeat_history, monitor.current_frame_received);
    carray_add(*monitor.gap_history, monitor.current_frame_gaps);
    carray_add(*monitor.duplicate_history, monitor.current_frame_duplicate_updates);
    carray_add(*monitor.out_of_order_history, monitor.current_frame_out_of_order_updates);
    carray_add(*monitor.stale_local_history, monitor.current_frame_stale_local_last_applied + monitor.current_frame_missing_local_updates);
    carray_add(*monitor.local_updates_behind_history, monitor.local_updates_behind);

    monitor.current_frame_received = 0;
    monitor.current_frame_gaps = 0;
    monitor.current_frame_duplicate_updates = 0;
    monitor.current_frame_out_of_order_updates = 0;
    monitor.current_frame_missing_local_updates = 0;
    monitor.current_frame_stale_local_last_applied = 0;
}

network_diag_text :: (label: string, value: string, x: float32, y: *float32, color: Vector4 = .{0.86, 0.88, 0.90, 1.0}) {
    fs : float32 = 12.0;
    ui_cmd_text(label, x, y.*, fs, .{0.54, 0.58, 0.64, 1.0});
    ui_cmd_text(value, x + 168.0, y.*, fs, color);
    y.* += 15.0;
}

Network_Diagnostics_Graph_Layout :: struct {
    panel_x : float32;
    panel_y : float32;
    panel_w : float32;
    panel_h : float32;
    label_x : float32;
    graph_x : float32;
    first_row_y : float32;
    graph_w : float32;
    graph_h : float32;
    row_gap : float32;
}

get_network_diagnostics_graph_layout :: (window_width : float32, window_height : float32) -> Network_Diagnostics_Graph_Layout {
    panel_w : float32 = 392.0;
    panel_x : float32 = max(12.0, window_width - panel_w - 16.0);
    panel_y : float32 = 318.0;
    graph_count :: 10;
    graph_h : float32 = 24.0;
    row_gap : float32 = 7.0;
    panel_h : float32 = 20.0 + graph_count * graph_h + (graph_count - 1) * row_gap;

    layout : Network_Diagnostics_Graph_Layout;
    layout.panel_x = panel_x;
    layout.panel_y = panel_y;
    layout.panel_w = panel_w;
    layout.panel_h = panel_h;
    layout.label_x = panel_x + 10.0;
    layout.graph_x = panel_x + 126.0;
    layout.first_row_y = panel_y + 10.0;
    layout.graph_w = panel_w - 138.0;
    layout.graph_h = graph_h;
    layout.row_gap = row_gap;
    return layout;
}

network_diag_graph_label :: (layout : Network_Diagnostics_Graph_Layout, row_index : s32, text : string, color : Vector4) {
    row_y := layout.first_row_y + cast(float32) row_index * (layout.graph_h + layout.row_gap);
    ui_cmd_text(text, layout.label_x, row_y + layout.graph_h * 0.68, 10.0, color);
}

network_diag_graph_rect :: (layout : Network_Diagnostics_Graph_Layout, row_index : s32) -> UI_Rect {
    row_y := layout.first_row_y + cast(float32) row_index * (layout.graph_h + layout.row_gap);
    return .{layout.graph_x, row_y, layout.graph_w, layout.graph_h};
}

network_diag_draw_time_series_graph :: (
    history : *Circular_Array($V, $N),
    rect : UI_Rect,
    min_val : float,
    max_val : float,
    color : Vector4,
    reference_lines : [] float = .[]
) {
    ui_cmd_rect(rect, .{0.055, 0.06, 0.075, 0.92});

    range_val := max_val - min_val;
    if range_val <= 0 range_val = 1.0;

    count := history.count;
    if count > 0 {
        bar_w := rect.w / cast(float32) count;
        idx := history.tail;

        for i : 0..count - 1 {
            val := cast(float) history.data[idx];
            y_norm := clamp((val - min_val) / range_val, 0.0, 1.0);
            bar_h := max(1.0, cast(float32) y_norm * rect.h);
            x := rect.x + cast(float32) i * bar_w;
            y := rect.y + rect.h - bar_h;
            ui_cmd_rect(.{x, y, max(1.0, bar_w - 1.0), bar_h}, color);

            idx = (idx + 1) % N;
        }
    }

    for ref_val : reference_lines {
        y_norm := (ref_val - min_val) / range_val;
        if y_norm >= 0.0 && y_norm <= 1.0 {
            y := rect.y + rect.h - cast(float32) y_norm * rect.h;
            ui_cmd_rect(.{rect.x, y, rect.w, 1.0}, .{1.0, 1.0, 1.0, 0.75});
        }
    }
}

network_diag_draw_timeline_graph :: (
    history : *Circular_Array($V, $N),
    rect : UI_Rect,
    color_map_func : (V) -> Vector4
) {
    ui_cmd_rect(rect, .{0.055, 0.06, 0.075, 0.92});

    count := history.count;
    if count == 0 return;

    bar_w := rect.w / cast(float32) count;
    idx := history.tail;

    for i : 0..count - 1 {
        val := history.data[idx];
        color := color_map_func(val);
        x := rect.x + cast(float32) i * bar_w;
        ui_cmd_rect(.{x, rect.y, max(1.0, bar_w - 1.0), rect.h}, color);
        idx = (idx + 1) % N;
    }
}

render_network_diagnostics_graph_panel :: (
    npsq : *Networked_Periodic_Signal_Quantizer($T),
    monitor : *Network_Diagnostics_Monitor,
    window_width : float32,
    window_height : float32
) {
    layout := get_network_diagnostics_graph_layout(window_width, window_height);
    panel := UI_Rect.{layout.panel_x, layout.panel_y, layout.panel_w, layout.panel_h};
    ui_cmd_rect(panel, .{0.03, 0.035, 0.045, 0.82});
    ui_cmd_rect_outline(panel, .{0.28, 0.34, 0.42, 0.92});

    label_color := Vector4.{0.78, 0.82, 0.88, 0.95};
    network_diag_graph_label(layout, 0, "NPSQ buffer", .{0.90, 0.60, 0.90, 0.95});
    network_diag_graph_label(layout, 1, "NPSQ mode", label_color);
    network_diag_graph_label(layout, 2, "NPSQ emit", label_color);
    network_diag_graph_label(layout, 3, "NPSQ overflow", .{0.90, 0.60, 0.20, 0.95});
    network_diag_graph_label(layout, 4, "Update heartbeat", .{0.35, 0.75, 1.0, 0.95});
    network_diag_graph_label(layout, 5, "Recv / frame", .{0.35, 0.75, 1.0, 0.95});
    network_diag_graph_label(layout, 6, "State gaps", .{0.95, 0.45, 0.25, 0.95});
    network_diag_graph_label(layout, 7, "Duplicate states", .{0.95, 0.85, 0.25, 0.95});
    network_diag_graph_label(layout, 8, "Stale local", .{0.95, 0.30, 0.55, 0.95});
    network_diag_graph_label(layout, 9, "Local behind", .{0.65, 0.75, 1.0, 0.95});

    ref_lines: [2] float;
    ref_lines[0] = cast(float) npsq.target_buffer_size;
    ref_lines[1] = cast(float) npsq.buffer_upper_bound;

    ref_slice: [] float;
    ref_slice.data = ref_lines.data;
    ref_slice.count = 2;

    network_diag_draw_time_series_graph(*npsq.input_buffer_size_history, network_diag_graph_rect(layout, 0), 0.0, cast(float) npsq.buffer_upper_bound + 1.0, .{0.90, 0.60, 0.90, 0.95}, ref_slice);
    network_diag_draw_timeline_graph(*npsq.mode_history, network_diag_graph_rect(layout, 1), mode_color_map);
    network_diag_draw_timeline_graph(*npsq.emission_history, network_diag_graph_rect(layout, 2), emission_color_map);
    network_diag_draw_time_series_graph(*npsq.overflow_history, network_diag_graph_rect(layout, 3), 0.0, cast(float) npsq.buffer_upper_bound, .{0.90, 0.60, 0.20, 0.95});
    network_diag_draw_timeline_graph(*monitor.receive_heartbeat_history, network_diag_graph_rect(layout, 4), receive_heartbeat_color_map);
    network_diag_draw_time_series_graph(*monitor.receive_count_history, network_diag_graph_rect(layout, 5), 0.0, 4.0, .{0.35, 0.75, 1.0, 0.95});
    network_diag_draw_time_series_graph(*monitor.gap_history, network_diag_graph_rect(layout, 6), 0.0, 4.0, .{0.95, 0.45, 0.25, 0.95});
    network_diag_draw_time_series_graph(*monitor.duplicate_history, network_diag_graph_rect(layout, 7), 0.0, 4.0, .{0.95, 0.85, 0.25, 0.95});
    network_diag_draw_time_series_graph(*monitor.stale_local_history, network_diag_graph_rect(layout, 8), 0.0, 4.0, .{0.95, 0.30, 0.55, 0.95});
    network_diag_draw_time_series_graph(*monitor.local_updates_behind_history, network_diag_graph_rect(layout, 9), 0.0, 12.0, .{0.65, 0.75, 1.0, 0.95});
}

render_network_diagnostics_overlay :: (
    ni : *Networked_Interpolator($T),
    monitor : *Network_Diagnostics_Monitor,
    window_width : float32,
    window_height : float32
) {
    push_allocator(temp);

    panel_w : float32 = 392.0;
    panel_h : float32 = 232.0;
    panel_x : float32 = max(12.0, window_width - panel_w - 16.0);
    panel_y : float32 = 74.0;
    panel := UI_Rect.{panel_x, panel_y, panel_w, panel_h};

    ui_cmd_rect(panel, .{0.03, 0.035, 0.045, 0.82});
    ui_cmd_rect_outline(panel, .{0.28, 0.34, 0.42, 0.92});

    x := panel_x + 12.0;
    y := panel_y + 22.0;
    ui_cmd_text("Network Diagnostics", x, y, 14.0, .{0.92, 0.94, 0.96, 1.0});
    y += 20.0;

    npsq := *ni.npsq;
    receive_rate := network_diagnostics_receive_rate_hz(monitor);
    receive_color := ifx receive_rate >= 55.0 then Vector4.{0.45, 0.95, 0.50, 1.0} else ifx receive_rate >= 45.0 then Vector4.{0.95, 0.78, 0.30, 1.0} else Vector4.{0.95, 0.35, 0.32, 1.0};
    mode_color := ifx npsq.mode == .REGULAR_OPERATION then Vector4.{0.45, 0.95, 0.50, 1.0} else Vector4.{0.95, 0.70, 0.25, 1.0};
    buffer_color := ifx npsq.input_buffer.count == 0 || npsq.input_buffer.count > npsq.buffer_upper_bound then Vector4.{0.95, 0.35, 0.32, 1.0} else Vector4.{0.86, 0.88, 0.90, 1.0};
    local_color := ifx monitor.local_found_in_last_state then Vector4.{0.86, 0.88, 0.90, 1.0} else Vector4.{0.95, 0.35, 0.32, 1.0};

    network_diag_text("Receive rate", tprint("% hz", FormatFloat.{value=receive_rate, trailing_width=1, zero_removal=.NO}), x, *y, receive_color);
    network_diag_text("Last / expected state", tprint("% / %", monitor.last_update_number, monitor.expected_update_number), x, *y);
    network_diag_text("Gaps / dupes / old", tprint("% / % / %", monitor.total_gaps, monitor.total_duplicate_updates, monitor.total_out_of_order_updates), x, *y, ifx monitor.total_gaps + monitor.total_duplicate_updates + monitor.total_out_of_order_updates > 0 then Vector4.{0.95, 0.70, 0.25, 1.0} else Vector4.{0.86, 0.88, 0.90, 1.0});
    network_diag_text("NPSQ mode", tprint("%", npsq.mode), x, *y, mode_color);
    network_diag_text("NPSQ buffer", tprint("% target=% upper=%", npsq.input_buffer.count, npsq.target_buffer_size, npsq.buffer_upper_bound), x, *y, buffer_color);
    network_diag_text("Interp window", tprint("% -> %  t=%", ni.active_start_state.number, ni.active_end_state.number, FormatFloat.{value=ni.active_t, trailing_width=2, zero_removal=.NO}), x, *y);
    network_diag_text("Window updated", tprint("%", ni.updated_interpolation_window_on_last_per_frame_update), x, *y, ifx ni.updated_interpolation_window_on_last_per_frame_update then Vector4.{0.45, 0.95, 0.50, 1.0} else Vector4.{0.86, 0.88, 0.90, 1.0});
    network_diag_text("Has current/start/end", tprint("% / % / %", ni.has_current_interpolated_state, ni.has_active_start_state, ni.has_active_end_state), x, *y);
    network_diag_text("Local in state", tprint("%", monitor.local_found_in_last_state), x, *y, local_color);
    network_diag_text("Local last applied", tprint("%  advance=%", monitor.local_last_applied, monitor.local_last_applied_advance), x, *y, ifx monitor.local_last_applied_advance == 0 then Vector4.{0.95, 0.70, 0.25, 1.0} else Vector4.{0.86, 0.88, 0.90, 1.0});
    network_diag_text("Local stale/missing", tprint("% / %", monitor.total_stale_local_last_applied, monitor.total_missing_local_updates), x, *y, ifx monitor.total_stale_local_last_applied + monitor.total_missing_local_updates > 0 then Vector4.{0.95, 0.70, 0.25, 1.0} else Vector4.{0.86, 0.88, 0.90, 1.0});

    render_network_diagnostics_graph_panel(npsq, monitor, window_width, window_height);
}
