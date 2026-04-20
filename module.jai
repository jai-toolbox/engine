/*

The way you use this "engine" can be as modular as you want. If you want to do everything yourself then you can just grab Looping_Program so that you have a loop which
runs at a controlled rate. That can look something like this:

On the other hand, a good reason to use this engine is that it allows you to start rendering objects immediately. If you're new to jai, then this is like getting the key to the castle.
And so you can start focusing on making a game or something immediately, which is great overtime you'll explore the rooms of the castle and understand its layout. 
Eventually you'll want to to do something that doesn't exist in the castle, and then you can start moving away from it. Either way here is the highest level of support we currently give:
*/

#import "Math";
#import "Basic";
#import "GL";

#scope_file
// Window_Creation :: #import "Window_Creation";
// Sound_Player :: #import "Sound_Player";
// Simp :: #import "Simp";
// Input :: #import "Input";
#scope_export


#import "tbx/opengl";
#import "tbx/camera";
#import "tbx/movement";
#import "tbx/rectangle";
#import "tbx/configuration";
#import "tbx/time";
#import "tbx/math";
#import "tbx/geometry";
#import "tbx/ui";


// ordering matters.
#load "input.jai";
#load "looping_program.jai";
#load "windowed_program.jai";
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


// The reason this is here is that it doesn't belong in the network or the serialization modules
// it needs to be somwehere, so maybe making the engine be the place where we combine them is a good thing.

#import "tbx/network";
#import "tbx/serialize";

// the packet is allocated on temporary storage, because packets get sent out soon.
packet_create :: (t: $T, packet_flags : Packet_Flags) -> *Packet {
    size_when_serialized := size_when_serialized_with_type_first(t);
    memory : *void = temporary_alloc(size_when_serialized);
    serialize_with_type_first(memory, t);
    packet := packet_create(memory, size_when_serialized, packet_flags);
    return packet;
}


#import "tbx/networked_interpolator";

render_npsq_monitor_graphs :: (
    renderer: *Absolute_Position_Color_Renderer,
    npsq: *Networked_Periodic_Signal_Quantizer($T, $MONITOR),
    origin_x: float = -0.95,
    origin_y: float = -0.95,
    graph_width: float = 0.4,
    graph_height: float = 0.1,
    gap: float = 0.02
) {
    #if !MONITOR {
        return;
    } else {
        push_allocator(temp);

        y := origin_y;

        {
            ref_lines: [2] float;
            ref_lines[0] = cast(float) npsq.target_num_states;
            ref_lines[1] = cast(float) npsq.max_num_states;

            ref_slice: [] float;
            ref_slice.data = ref_lines.data;
            ref_slice.count = 2;

            graph := create_time_series_graph(
                *npsq.buffer_occupancy_history,
                .{origin_x, y},
                .{graph_width, graph_height},
                min_val = 0.0,
                max_val = cast(float) npsq.max_num_states + 1.0,
                color = .{0.3, 0.6, 0.9},
                reference_lines = ref_slice
            );
            immediate_render(renderer, graph);
            y += graph_height + gap;
        }

        {
            graph := create_colored_timeline_strip(
                *npsq.mode_history,
                .{origin_x, y},
                .{graph_width, graph_height}
            );
            immediate_render(renderer, graph);
            y += graph_height + gap;
        }

        {
            graph := create_colored_timeline_strip(
                *npsq.emit_result_history,
                .{origin_x, y},
                .{graph_width, graph_height}
            );
            immediate_render(renderer, graph);
            y += graph_height + gap;
        }

        {
            graph := create_time_series_graph(
                *npsq.removal_count_history,
                .{origin_x, y},
                .{graph_width, graph_height},
                min_val = 0.0,
                max_val = cast(float) npsq.max_num_states,
                color = .{0.9, 0.6, 0.2}
            );
            immediate_render(renderer, graph);
        }
    }
}

