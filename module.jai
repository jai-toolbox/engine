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
#import "tbx/math";
#import "tbx/ui";
#import "tbx/assets";
#import "tbx/model_loading";
#import "File_Utilities";

Build_Type :: enum {
    DEVELOPMENT;
    DISTRIBUTION;
}

BUILD_TYPE : Build_Type : .DEVELOPMENT;

// ordering matters.
#load "input.jai";
#load "looping_program.jai";
#load "crosshair.jai";
#load "windowed_program.jai";
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

    address := Network.get_host_ip_address(ip_address);
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

render_npsq_monitor_graphs :: (
    renderer: *Absolute_Position_Color_Alpha_Renderer,
    npsq: *Networked_Periodic_Signal_Quantizer($T),
    origin_x: float = -0.95,
    origin_y: float = -0.95,
    graph_width: float = 0.4,
    graph_height: float = 0.1,
    gap: float = 0.02
) {
    push_allocator(temp);

    y := origin_y;

    // input buffer size with reference lines for target and upper bound
    {
        ref_lines: [2] float;
        ref_lines[0] = cast(float) npsq.target_buffer_size;
        ref_lines[1] = cast(float) npsq.buffer_upper_bound;

        ref_slice: [] float;
        ref_slice.data = ref_lines.data;
        ref_slice.count = 2;

        graph := create_time_series_graph(
            *npsq.input_buffer_size_history,
            .{origin_x, y},
            .{graph_width, graph_height},
            min_val = 0.0,
            max_val = cast(float) npsq.buffer_upper_bound + 1.0,
            color = .{0.90, 0.60, 0.90, 0.95},
            reference_lines = ref_slice
        );
        immediate_render(renderer, graph);
        y += graph_height + gap;
    }

    // mode timeline
    {
        graph := create_colored_timeline_strip(
            *npsq.mode_history,
            .{origin_x, y},
            .{graph_width, graph_height},
            color_map_func = mode_color_map
        );
        immediate_render(renderer, graph);
        y += graph_height + gap;
    }

    // emission outcome timeline
    {
        graph := create_colored_timeline_strip(
            *npsq.emission_history,
            .{origin_x, y},
            .{graph_width, graph_height},
            color_map_func = emission_color_map
        );
        immediate_render(renderer, graph);
        y += graph_height + gap;
    }

    // overflow pressure
    {
        graph := create_time_series_graph(
            *npsq.overflow_history,
            .{origin_x, y},
            .{graph_width, graph_height},
            min_val = 0.0,
            max_val = cast(float) npsq.buffer_upper_bound,
            color = .{0.90, 0.60, 0.20, 0.95}
        );
        immediate_render(renderer, graph);
    }
}
