#scope_file
// Window_Creation :: #import "Window_Creation";
// Sound_Player :: #import "Sound_Player";
Input :: #import "Input";
// Simp :: #import "Simp";
#scope_export

Performance_Graph :: struct {
    graph_min_ms: float = 4.0;
    graph_max_ms: float = 25.0;

    bar_graph_min_ms: float = 0.0;
    bar_graph_max_ms: float = 10.0;

    GRAPH_STEP_MS :: 0.5;
    GRAPH_MS_FLOOR :: 0.0;
    GRAPH_MS_CEILING :: 200.0;
    GRAPH_MIN_RANGE :: 0.5;
}


update_graph_visual :: (using pg: *Performance_Graph) {
    shift_down := key_pressed(Input.Key_Code.SHIFT);

    if shift_down {
        if key_just_pressed(.ARROW_UP) {
            bar_graph_max_ms -= GRAPH_STEP_MS;
            if bar_graph_max_ms < bar_graph_min_ms + GRAPH_MIN_RANGE  bar_graph_max_ms = bar_graph_min_ms + GRAPH_MIN_RANGE;
        }
        if key_just_pressed(.ARROW_DOWN) {
            bar_graph_max_ms += GRAPH_STEP_MS;
            if bar_graph_max_ms > GRAPH_MS_CEILING  bar_graph_max_ms = GRAPH_MS_CEILING;
        }
        if key_just_pressed(.ARROW_RIGHT) {
            bar_graph_min_ms += GRAPH_STEP_MS;
            if bar_graph_min_ms > bar_graph_max_ms - GRAPH_MIN_RANGE  bar_graph_min_ms = bar_graph_max_ms - GRAPH_MIN_RANGE;
        }
        if key_just_pressed(.ARROW_LEFT) {
            bar_graph_min_ms -= GRAPH_STEP_MS;
            if bar_graph_min_ms < GRAPH_MS_FLOOR  bar_graph_min_ms = GRAPH_MS_FLOOR;
        }
    } else {
        if key_just_pressed(.ARROW_UP) {
            graph_max_ms -= GRAPH_STEP_MS;
            if graph_max_ms < graph_min_ms + GRAPH_MIN_RANGE  graph_max_ms = graph_min_ms + GRAPH_MIN_RANGE;
        }
        if key_just_pressed(.ARROW_DOWN) {
            graph_max_ms += GRAPH_STEP_MS;
            if graph_max_ms > GRAPH_MS_CEILING  graph_max_ms = GRAPH_MS_CEILING;
        }
        if key_just_pressed(.ARROW_RIGHT) {
            graph_min_ms += GRAPH_STEP_MS;
            if graph_min_ms > graph_max_ms - GRAPH_MIN_RANGE  graph_min_ms = graph_max_ms - GRAPH_MIN_RANGE;
        }
        if key_just_pressed(.ARROW_LEFT) {
            graph_min_ms -= GRAPH_STEP_MS;
            if graph_min_ms < GRAPH_MS_FLOOR  graph_min_ms = GRAPH_MS_FLOOR;
        }
    }
}


create_frame_time_graph :: (st: *Section_Timer, graph_origin: Vector2 = .{-0.95, -0.95}, graph_size: Vector2 = .{0.5, 0.3}, min_ms: float = 0.0, max_ms: float = 33.33) -> Indexed_Triangle_Positions_Colors {

    points: [MAX_HISTORY] Vector2;
    point_count: int = 0;

    if st.completed_tree_count == 0 {
        empty: Indexed_Triangle_Positions_Colors;
        return empty;
    }

    count := cast(int) st.completed_tree_count;

    oldest_index: int;
    if count < MAX_HISTORY {
        oldest_index = 0;
    } else {
        oldest_index = cast(int) st.completed_tree_write_index;
    }

    range_ms := max_ms - min_ms;
    if range_ms <= 0 range_ms = 1.0;

    for i: 0..count-1 {
        idx := (oldest_index + i) % MAX_HISTORY;
        root := st.completed_tree_roots[idx];
        if root == null || !root.completed continue;

        x_norm := cast(float) i / cast(float) max(count - 1, 1);
        frame_ms := root.elapsed_seconds * 1000.0;
        y_norm := clamp((frame_ms - min_ms) / range_ms, 0.0, 1.0);

        points[point_count] = .{x_norm, y_norm};
        point_count += 1;
    }

    if point_count < 2 {
        empty: Indexed_Triangle_Positions_Colors;
        return empty;
    }

    points_slice: [] Vector2;
    points_slice.data = points.data;
    points_slice.count = point_count;

    graph_itp := create_graph(points_slice, graph_origin, graph_size);

    itpc: Indexed_Triangle_Positions_Colors;
    for graph_itp.indices array_add(*itpc.indices, it);
    for graph_itp.positions array_add(*itpc.positions, it);

    color := Vector3.{0.2, 0.8, 0.3};
    array_reserve(*itpc.rgb_colors, itpc.positions.count);
    for 1..itpc.positions.count array_add(*itpc.rgb_colors, color);

    return itpc;
}


create_frame_time_graph_with_background :: (st: *Section_Timer, graph_origin: Vector2 = .{-0.95, -0.95}, graph_size: Vector2 = .{0.5, 0.3}, min_ms: float = 0.0, max_ms: float = 33.33, target_ms: float = 16.67) -> Indexed_Triangle_Positions_Colors {
    itpc: Indexed_Triangle_Positions_Colors;

    range_ms := max_ms - min_ms;
    if range_ms <= 0 range_ms = 1.0;

    merge(*itpc, create_itpc_with_color(
        create_quad(graph_origin.x, graph_origin.y, graph_origin.x + graph_size.x, graph_origin.y + graph_size.y, 0.02),
        .{0.1, 0.1, 0.1}));

    line_half_height := graph_size.y * 0.005;
    first_tick_ms := cast(float) cast(int) min_ms + 1.0;
    tick_ms := first_tick_ms;
    while tick_ms < max_ms {
        if tick_ms != target_ms {
            y_norm := (tick_ms - min_ms) / range_ms;
            if y_norm >= 0.0 && y_norm <= 1.0 {
                y := graph_origin.y + y_norm * graph_size.y;
                merge(*itpc, create_itpc_with_color(
                    create_quad(graph_origin.x, y - line_half_height, graph_origin.x + graph_size.x, y + line_half_height, 0.01),
                    .{0.35, 0.35, 0.35}));
            }
        }
        tick_ms += 1.0;
    }

    merge(*itpc, create_frame_time_graph(st, graph_origin, graph_size, min_ms, max_ms));

    target_y_norm := (target_ms - min_ms) / range_ms;
    if target_y_norm >= 0.0 && target_y_norm <= 1.0 {
        target_y := graph_origin.y + target_y_norm * graph_size.y;
        line_half_height_target := graph_size.y * 0.01;
        merge(*itpc, create_itpc_with_color(
            create_quad(graph_origin.x, target_y - line_half_height_target, graph_origin.x + graph_size.x, target_y + line_half_height_target, -0.01),
            .{1.0, 0.0, 0.0}));
    }

    return itpc;
}


Section_Color_Entry :: struct {
    name: string;
    color: Vector3;
}

seen_section_colors: [MAX_SECTIONS] Section_Color_Entry;
seen_section_color_count: int = 0;

hash_section_name_to_color :: (name: string) -> Vector3 {
    for i: 0..seen_section_color_count-1 {
        if seen_section_colors[i].name == name return seen_section_colors[i].color;
    }

    h: u32 = 5381;
    for i: 0..name.count-1 {
        h = ((h << 5) + h) + cast(u32) name[i];
    }

    r_hash := cast(float)((h * 2654435761) % 1000) / 1000.0;
    g_hash := cast(float)((h * 2246822519) % 1000) / 1000.0;
    b_hash := cast(float)((h * 3266489917) % 1000) / 1000.0;

    color := Vector3.{
        0.3 + r_hash * 0.6,
        0.3 + g_hash * 0.6,
        0.3 + b_hash * 0.6
    };

    if seen_section_color_count < MAX_SECTIONS {
        seen_section_colors[seen_section_color_count] = .{name, color};
        seen_section_color_count += 1;
    }

    return color;
}

create_section_bar_graph :: (st: *Section_Timer, graph_origin: Vector2 = .{-0.95, -0.95}, graph_size: Vector2 = .{0.3, 0.3}, min_ms: float = 0.0, max_ms: float = 33.33, target_ms: float = 16.67, print_legend: bool = false) -> Indexed_Triangle_Positions_Colors {
    itpc: Indexed_Triangle_Positions_Colors;

    range_ms := max_ms - min_ms;
    if range_ms <= 0 range_ms = 1.0;

    merge(*itpc, create_itpc_with_color(
        create_quad(graph_origin.x, graph_origin.y, graph_origin.x + graph_size.x, graph_origin.y + graph_size.y, 0.02),
        .{0.1, 0.1, 0.1}));

    line_half_height := graph_size.y * 0.005;
    tick_ms := cast(float)(cast(int) min_ms + 1);
    while tick_ms < max_ms {
        if tick_ms != target_ms {
            y_norm := (tick_ms - min_ms) / range_ms;
            if y_norm >= 0.0 && y_norm <= 1.0 {
                y := graph_origin.y + y_norm * graph_size.y;
                merge(*itpc, create_itpc_with_color(
                    create_quad(graph_origin.x, y - line_half_height, graph_origin.x + graph_size.x, y + line_half_height, 0.01),
                    .{0.35, 0.35, 0.35}));
            }
        }
        tick_ms += 1.0;
    }

    target_y_norm := (target_ms - min_ms) / range_ms;
    if target_y_norm >= 0.0 && target_y_norm <= 1.0 {
        target_y := graph_origin.y + target_y_norm * graph_size.y;
        line_half_height_target := graph_size.y * 0.01;
        merge(*itpc, create_itpc_with_color(
            create_quad(graph_origin.x, target_y - line_half_height_target, graph_origin.x + graph_size.x, target_y + line_half_height_target, -0.02),
            .{1.0, 0.0, 0.0}));
    }

    root := get_latest_completed_section(st);
    if root == null return itpc;
    if root.child_count == 0 return itpc;

    child_count := cast(int) root.child_count;

    gap_fraction := 0.1;
    bar_slot_width := graph_size.x / cast(float) child_count;
    gap_width := bar_slot_width * gap_fraction;
    bar_width := bar_slot_width - gap_width;

    if print_legend {
        print("[section_bar_graph] Legend (left to right):\n");
    }

    for i: 0..child_count-1 {
        child := root.children[i];
        if child == null continue;
        if !child.completed continue;

        child_ms := child.elapsed_seconds * 1000.0;
        bar_height_norm := clamp((child_ms - min_ms) / range_ms, 0.0, 1.0);

        bar_x0 := graph_origin.x + cast(float) i * bar_slot_width + gap_width * 0.5;
        bar_x1 := bar_x0 + bar_width;
        bar_y0 := graph_origin.y;
        bar_y1 := graph_origin.y + bar_height_norm * graph_size.y;

        color := hash_section_name_to_color(child.name);

        if print_legend {
            print("  [%] '%' -> (%, %, %)\n",
                i,
                child.name,
                FormatFloat.{value=color.x, trailing_width=2, zero_removal=.NO},
                FormatFloat.{value=color.y, trailing_width=2, zero_removal=.NO},
                FormatFloat.{value=color.z, trailing_width=2, zero_removal=.NO});
        }

        merge(*itpc, create_itpc_with_color(
            create_quad(bar_x0, bar_y0, bar_x1, bar_y1, -0.01),
            color));
    }

    if print_legend print("\n");

    return itpc;
}


#import "tbx/circular_array";

create_time_series_graph :: (
    history: *Circular_Array($V, $N),
    graph_origin: Vector2,
    graph_size: Vector2,
    min_val: float,
    max_val: float,
    color: Vector4 = .{0.2, 0.8, 0.3, 1.0},
    reference_lines: [] float = .[]
) -> Indexed_Triangle_Positions_Color_Alphas {

    itpca: Indexed_Triangle_Positions_Color_Alphas;

    range_val := max_val - min_val;
    if range_val <= 0 range_val = 1.0;

    // background, slightly translucent so overlapping graphs don't fully occlude
    bg_quad := create_quad(graph_origin.x, graph_origin.y, graph_origin.x + graph_size.x, graph_origin.y + graph_size.y, 0.02);
    merge(*itpca, create_itpca_with_color_alpha(bg_quad, .{0.08, 0.08, 0.08, 0.85}));

    count := history.count;
    if count >= 2 {
        points: [N] Vector2;
        point_count := 0;

        idx := history.tail;
        for i: 0..count-1 {
            x_norm := cast(float) i / cast(float) max(count - 1, 1);
            val := cast(float) history.data[idx];
            y_norm := clamp((val - min_val) / range_val, 0.0, 1.0);

            points[point_count] = .{x_norm, y_norm};
            point_count += 1;

            idx = (idx + 1) % N;
        }

        points_slice: [] Vector2;
        points_slice.data = points.data;
        points_slice.count = point_count;

        graph_itp := create_graph(points_slice, graph_origin, graph_size);
        merge(*itpca, create_itpca_with_color_alpha(graph_itp, color));
    }

    line_half_height := graph_size.y * 0.008;
    for ref_idx: 0..reference_lines.count-1 {
        ref_val := reference_lines[ref_idx];
        y_norm := (ref_val - min_val) / range_val;
        if y_norm >= 0.0 && y_norm <= 1.0 {
            y := graph_origin.y + y_norm * graph_size.y;
            ref_quad := create_quad(graph_origin.x, y - line_half_height, graph_origin.x + graph_size.x, y + line_half_height, -0.01);
            merge(*itpca, create_itpca_with_color_alpha(ref_quad, .{1.0, 1.0, 1.0, 0.85}));
        }
    }

    return itpca;
}

create_colored_timeline_strip :: (
    history: *Circular_Array($V, $N),
    graph_origin: Vector2,
    graph_size: Vector2,
    color_map_func: (V) -> Vector4 = null
) -> Indexed_Triangle_Positions_Color_Alphas {

    itpca: Indexed_Triangle_Positions_Color_Alphas;

    bg_quad := create_quad(graph_origin.x, graph_origin.y, graph_origin.x + graph_size.x, graph_origin.y + graph_size.y, 0.02);
    merge(*itpca, create_itpca_with_color_alpha(bg_quad, .{0.08, 0.08, 0.08, 0.85}));

    count := history.count;
    if count == 0 return itpca;

    bar_width := graph_size.x / cast(float) count;

    idx := history.tail;
    for i: 0..count-1 {
        val := history.data[idx];

        color: Vector4;
        if color_map_func != null {
            color = color_map_func(val);
        } else {
            color = default_color_map(val);
        }

        x0 := graph_origin.x + cast(float) i * bar_width;
        x1 := x0 + bar_width;

        bar_quad := create_quad(x0, graph_origin.y, x1, graph_origin.y + graph_size.y, -0.01);
        merge(*itpca, create_itpca_with_color_alpha(bar_quad, color));

        idx = (idx + 1) % N;
    }

    return itpca;
}

default_color_map :: (val: $V) -> Vector4 {
    #if V == float || V == float64 {
        if val > 0.5 return .{0.2, 0.8, 0.2, 1.0};
        return .{0.8, 0.2, 0.2, 1.0};
    } else {
        idx := cast(int) val;
        return enum_palette_color(idx);
    }
}

ENUM_PALETTE :: Vector4.[
    .{0.30, 0.65, 0.95, 1.0},
    .{0.95, 0.45, 0.30, 1.0},
    .{0.40, 0.85, 0.40, 1.0},
    .{0.90, 0.85, 0.30, 1.0},
    .{0.75, 0.40, 0.85, 1.0},
    .{0.85, 0.30, 0.55, 1.0},
    .{0.40, 0.85, 0.85, 1.0},
    .{0.65, 0.65, 0.65, 1.0},
];

enum_palette_color :: (idx: int) -> Vector4 {
    if idx < 0 return .{0.5, 0.5, 0.5, 1.0};
    return ENUM_PALETTE[idx % ENUM_PALETTE.count];
}
