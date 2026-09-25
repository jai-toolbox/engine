// A one-inch crosshair is an OBJ in data/crosshairs. Each editable polygon is
// one OBJ object/face; mirrored instances are extra objects for ordinary OBJ
// readers. The source object's name retains its linked mirror modifiers.

#import "File";
#import "File_Utilities";
#import "String";
#import "Math";
Crosshair_Obj :: #import "tbx/model_loading";

CROSSHAIR_LIBRARY_DIRECTORY :: "data/crosshairs";
CROSSHAIR_EDITOR_OBJECT_PREFIX :: "__crosshair_source_mx";
CROSSHAIR_EDITOR_DERIVED_PREFIX :: "__crosshair_derived_";
CROSSHAIR_COLOR_COMMENT :: "# crosshair-color ";
CROSSHAIR_GRID_COMMENT :: "# crosshair-grid ";
CROSSHAIR_DEFAULT_COUNT :: 9;

Crosshair_Library :: struct {
    paths: [..] string;
}

free_crosshair_library :: (library: *Crosshair_Library) {
    for path: library.paths free(path);
    array_free(library.paths);
}

crosshair_has_suffix :: (value: string, suffix: string) -> bool {
    if value.count < suffix.count return false;
    return slice(value, value.count - suffix.count, value.count) == suffix;
}

crosshair_obj_filename :: (path: string) -> string {
    start := 0;
    for i: 0..path.count - 1 {
        if path[i] == #char "/" || path[i] == #char "\\" start = i + 1;
    }
    return slice(path, start, path.count);
}

crosshair_obj_display_name :: (path: string) -> string {
    filename := crosshair_obj_filename(path);
    stem := ifx crosshair_has_suffix(filename, ".obj") then slice(filename, 0, filename.count - 4)
            else filename;
    bytes := NewArray(stem.count, u8,, allocator = temp);
    capitalize := true;
    for i: 0..stem.count - 1 {
        c := stem[i];
        if c == #char "_" {
            bytes[i] = #char " ";
            capitalize = true;
        } else {
            bytes[i] = ifx capitalize && c >= #char "a" && c <= #char "z" then c - 32 else c;
            capitalize = false;
        }
    }
    result: string;
    result.data = bytes.data;
    result.count = stem.count;
    return result;
}

crosshair_snake_stem :: (name: string) -> string {
    stem := ifx crosshair_has_suffix(name, ".obj") then slice(name, 0, name.count - 4) else name;
    bytes := NewArray(stem.count * 2 + 1, u8,, allocator = temp);
    count: s64 = 0;
    previous_was_lower_or_digit := false;
    for c: stem {
        upper := c >= #char "A" && c <= #char "Z";
        lower := c >= #char "a" && c <= #char "z";
        digit := c >= #char "0" && c <= #char "9";
        if upper || lower || digit {
            if upper && previous_was_lower_or_digit && count > 0 && bytes[count - 1] != #char "_" {
                bytes[count] = #char "_";
                count += 1;
            }
            bytes[count] = ifx upper then c + 32 else c;
            count += 1;
            previous_was_lower_or_digit = lower || digit;
        } else if count > 0 && bytes[count - 1] != #char "_" {
            bytes[count] = #char "_";
            count += 1;
            previous_was_lower_or_digit = false;
        }
    }
    if count > 0 && bytes[count - 1] == #char "_" count -= 1;
    if count == 0 return "crosshair";
    result: string;
    result.data = bytes.data;
    result.count = count;
    if result == "pinwheel" return "pin_wheel";
    return result;
}

crosshair_valid_name :: (name: string) -> bool {
    if name.count == 0 || name.count > 100 || trim(name) != name return false;
    for c: name {
        if (c >= #char "a" && c <= #char "z") ||
           (c >= #char "A" && c <= #char "Z") ||
           (c >= #char "0" && c <= #char "9") ||
           c == #char " " || c == #char "_" || c == #char "-" continue;
        return false;
    }
    return true;
}

crosshair_obj_path :: (name: string) -> string {
    return tprint("%/%.obj", CROSSHAIR_LIBRARY_DIRECTORY, crosshair_snake_stem(name));
}

crosshair_default_filename :: (index: s32) -> string {
    names := string.[
        "dot.obj", "cross.obj", "x.obj", "cross_missing_top.obj",
        "cross_with_hole.obj", "x_with_hole.obj", "upward_caret.obj",
        "cross_missing_top_bottom_with_hole.obj", "ring.obj",
    ];
    if index < 0 || index >= names.count return "";
    return names[index];
}

normalize_existing_crosshair_files :: () {
    existing: Crosshair_Library;
    visitor :: (info: *File_Visit_Info, library: *Crosshair_Library) {
        if info.is_directory || !crosshair_has_suffix(info.short_name, ".obj") return;
        array_add(*library.paths, copy_string(info.full_name));
    }
    visit_files(CROSSHAIR_LIBRARY_DIRECTORY, false, *existing, visitor);
    defer free_crosshair_library(*existing);
    for path: existing.paths {
        filename := crosshair_obj_filename(path);
        target := crosshair_obj_path(filename);
        if filename == crosshair_obj_filename(target) continue;
        if file_exists(target) {
            stem := crosshair_snake_stem(filename);
            suffix: s32 = 2;
            while file_exists(tprint("%/%_%.obj", CROSSHAIR_LIBRARY_DIRECTORY, stem, suffix)) suffix += 1;
            target = tprint("%/%_%.obj", CROSSHAIR_LIBRARY_DIRECTORY, stem, suffix);
        }
        if !file_move(path, target) print("Could not rename crosshair OBJ '%' to '%'.\n", path, target);
    }
}

scan_crosshair_library :: () -> Crosshair_Library {
    result: Crosshair_Library;
    if !make_directory_if_it_does_not_exist(CROSSHAIR_LIBRARY_DIRECTORY, recursive = true) return result;
    normalize_existing_crosshair_files();
    generate_missing_default_crosshairs();
    visitor :: (info: *File_Visit_Info, library: *Crosshair_Library) {
        if info.is_directory || !crosshair_has_suffix(info.short_name, ".obj") return;
        array_add(*library.paths, copy_string(info.full_name));
    }
    visit_files(CROSSHAIR_LIBRARY_DIRECTORY, false, *result, visitor);
    return result;
}

crosshair_color_from_obj_text :: (contents: string, fallback: Vector4) -> Vector4 {
    lines := split(contents, "\n");
    defer array_free(lines);
    for raw_line: lines {
        line := trim(raw_line);
        if !begins_with(line, CROSSHAIR_COLOR_COMMENT) continue;
        values := trim(advance(line, CROSSHAIR_COLOR_COMMENT.count));
        r, ok_r, tail_r := string_to_float(values);
        g, ok_g, tail_g := string_to_float(trim(tail_r));
        b, ok_b, tail_b := string_to_float(trim(tail_g));
        a, ok_a, _      := string_to_float(trim(tail_b));
        if ok_r && ok_g && ok_b && ok_a {
            return .{clamp(cast(float32) r, 0.0, 1.0),
                    clamp(cast(float32) g, 0.0, 1.0),
                    clamp(cast(float32) b, 0.0, 1.0),
                    clamp(cast(float32) a, 0.0, 1.0)};
        }
    }
    return fallback;
}

read_crosshair_obj_color :: (path: string, fallback: Vector4) -> Vector4 {
    contents, ok := read_entire_file(path, log_errors = false);
    if !ok return fallback;
    defer free(contents);
    return crosshair_color_from_obj_text(contents, fallback);
}

crosshair_grid_from_obj_text :: (contents: string) -> s32 {
    lines := split(contents, "\n");
    defer array_free(lines);
    for raw_line: lines {
        line := trim(raw_line);
        if !begins_with(line, CROSSHAIR_GRID_COMMENT) continue;
        side, ok, _ := string_to_int(trim(advance(line, CROSSHAIR_GRID_COMMENT.count)), T = s32);
        if ok && (side == DEFAULT_GRID_SIDE || side == FINE_GRID_SIDE) return side;
    }
    return 0;
}

crosshair_grid_for_obj :: (contents: string, obj: *Crosshair_Obj.Obj_Data) -> s32 {
    annotated := crosshair_grid_from_obj_text(contents);
    if annotated != 0 return annotated;
    for point: obj.all_positions {
        gx := (cast(float64) point.x + 0.5) * 100.0;
        gy := (0.5 - cast(float64) point.y) * 100.0;
        if abs(gx - floor(gx + 0.5)) > 0.0001 ||
           abs(gy - floor(gy + 0.5)) > 0.0001 return FINE_GRID_SIDE;
    }
    return DEFAULT_GRID_SIDE;
}

// The built-in shapes are defined as geometry, then written through the same
// OBJ serializer as user-created crosshairs. Coordinates below are thousandths
// of an inch from the center of the one-inch canvas.
crosshair_preset_round :: (value: float64) -> float {
    rounded := floor(abs(value) + 0.500000001);
    return cast(float) (ifx value < 0 then -rounded else rounded);
}

crosshair_preset_grid_point :: (point: Grid_Point) -> Grid_Point {
    return .{500 + point.x, 500 - point.y};
}

crosshair_preset_add_quad :: (model: *Polygon_Model, a: Grid_Point, b: Grid_Point,
                              c: Grid_Point, d: Grid_Point) {
    polygon: Crosshair_Polygon;
    polygon.count = 4;
    polygon.color = .{0.95, 0.95, 0.95, 0.9};
    polygon.vertices[0] = crosshair_preset_grid_point(a);
    polygon.vertices[1] = crosshair_preset_grid_point(b);
    polygon.vertices[2] = crosshair_preset_grid_point(c);
    polygon.vertices[3] = crosshair_preset_grid_point(d);
    assert(polygon_is_simple(polygon));
    array_add(*model.polygons, polygon);
}

crosshair_preset_add_rect :: (model: *Polygon_Model,
                              left: float, bottom: float, right: float, top: float) {
    crosshair_preset_add_quad(model, .{left, bottom}, .{right, bottom},
                             .{right, top}, .{left, top});
}

crosshair_preset_rotate_quarter :: (point: Grid_Point, turns: s32) -> Grid_Point {
    result := point;
    for _: 0..turns - 1 result = .{-result.y, result.x};
    return result;
}

crosshair_preset_add_x :: (model: *Polygon_Model, with_hole: bool) {
    a := ifx with_hole then Grid_Point.{55, 101} else Grid_Point.{0, 51};
    b := ifx with_hole then Grid_Point.{101, 55} else Grid_Point.{51, 0};
    c := ifx with_hole then Grid_Point.{221, 175} else Grid_Point.{205, 154};
    d := ifx with_hole then Grid_Point.{175, 221} else Grid_Point.{154, 205};
    for turn: 0..3 {
        rotation := cast(s32) turn;
        crosshair_preset_add_quad(model,
            crosshair_preset_rotate_quarter(a, rotation),
            crosshair_preset_rotate_quarter(b, rotation),
            crosshair_preset_rotate_quarter(c, rotation),
            crosshair_preset_rotate_quarter(d, rotation));
    }
    if !with_hole crosshair_preset_add_quad(model, .{0, -51}, .{51, 0},
                                           .{0, 51}, .{-51, 0});
}

crosshair_preset_add_dot :: (model: *Polygon_Model) {
    polygon: Crosshair_Polygon;
    polygon.count = 24;
    polygon.color = .{0.95, 0.95, 0.95, 0.9};
    for i: 0..polygon.count - 1 {
        angle := cast(float64) i * TAU64 / cast(float64) polygon.count;
        point := Grid_Point.{crosshair_preset_round(42.4 * cos(angle)),
                             crosshair_preset_round(42.4 * sin(angle))};
        polygon.vertices[i] = crosshair_preset_grid_point(point);
    }
    assert(polygon_is_simple(polygon));
    array_add(*model.polygons, polygon);
}

crosshair_preset_add_ring :: (model: *Polygon_Model) {
    segments := 48;
    for i: 0..segments - 1 {
        a0 := cast(float64) i * TAU64 / cast(float64) segments;
        a1 := cast(float64) (i + 1) * TAU64 / cast(float64) segments;
        inner0 := Grid_Point.{crosshair_preset_round(195.0 * cos(a0)),
                              crosshair_preset_round(195.0 * sin(a0))};
        outer0 := Grid_Point.{crosshair_preset_round(273.0 * cos(a0)),
                              crosshair_preset_round(273.0 * sin(a0))};
        outer1 := Grid_Point.{crosshair_preset_round(273.0 * cos(a1)),
                              crosshair_preset_round(273.0 * sin(a1))};
        inner1 := Grid_Point.{crosshair_preset_round(195.0 * cos(a1)),
                              crosshair_preset_round(195.0 * sin(a1))};
        crosshair_preset_add_quad(model, inner0, outer0, outer1, inner1);
    }
}

make_default_crosshair :: (index: s32) -> Polygon_Model {
    model := make_polygon_model(FINE_GRID_SIDE);
    if index == 0 {
        crosshair_preset_add_dot(*model);
    } else if index == 1 || index == 3 {
        crosshair_preset_add_rect(*model, 36, -36, 254, 36);
        crosshair_preset_add_rect(*model, -254, -36, -36, 36);
        if index == 1 crosshair_preset_add_rect(*model, -36, 36, 36, 254);
        crosshair_preset_add_rect(*model, -36, -254, 36, -36);
        crosshair_preset_add_rect(*model, -36, -36, 36, 36);
    } else if index == 2 || index == 5 {
        crosshair_preset_add_x(*model, index == 5);
    } else if index == 4 || index == 7 {
        crosshair_preset_add_rect(*model, 111, -33, 280, 33);
        crosshair_preset_add_rect(*model, -280, -33, -111, 33);
        if index == 4 {
            crosshair_preset_add_rect(*model, -33, 111, 33, 280);
            crosshair_preset_add_rect(*model, -33, -280, 33, -111);
        }
    } else if index == 6 {
        crosshair_preset_add_quad(*model, .{-13, -59}, .{-59, -13},
                                 .{-244, -198}, .{-198, -244});
        crosshair_preset_add_quad(*model, .{59, -13}, .{13, -59},
                                 .{198, -244}, .{244, -198});
    } else if index == 8 {
        crosshair_preset_add_ring(*model);
    }
    return model;
}

generate_missing_default_crosshairs :: () {
    for i: 0..CROSSHAIR_DEFAULT_COUNT - 1 {
        filename := crosshair_default_filename(cast(s32) i);
        path := tprint("%/%", CROSSHAIR_LIBRARY_DIRECTORY, filename);
        if file_exists(path) continue; // Preserve edits to an existing preset.
        model := make_default_crosshair(cast(s32) i);
        saved, reason := save_crosshair_obj(path, model, .{0.95, 0.95, 0.95, 0.9});
        if !saved print("Could not generate default crosshair '%': %\n", path, reason);
        free_polygon_model(*model);
    }
}

crosshair_write_obj_polygon :: (builder: *String_Builder, polygon: Crosshair_Polygon,
                                side: s32, name: string, next_vertex: *s32) {
    print_to_builder(builder, "o %\n", name);
    first := next_vertex.*;
    for i: 0..polygon.count - 1 {
        point := polygon.vertices[i];
        x := cast(float) point.x / cast(float) side - 0.5;
        y := 0.5 - cast(float) point.y / cast(float) side;
        print_to_builder(builder, "v % % 0\n", x, y);
        next_vertex.* += 1;
    }
    print_to_builder(builder, "f");
    for i: 0..polygon.count - 1 print_to_builder(builder, " %", first + i);
    print_to_builder(builder, "\n");
}

save_crosshair_obj :: (path: string, model: Polygon_Model, color: Vector4) -> bool, string {
    if model.polygons.count == 0 return false, "Add at least one shape before saving.";
    for polygon: model.polygons {
        if !polygon_is_simple(polygon) return false, "A shape has invalid or crossed edges.";
    }
    if !make_directory_if_it_does_not_exist(CROSSHAIR_LIBRARY_DIRECTORY, recursive = true) {
        return false, "Could not create data/crosshairs.";
    }

    builder: String_Builder;
    defer free_buffers(*builder);
    print_to_builder(*builder, "# crosshair-editor 1\n");
    print_to_builder(*builder, "% %\n", CROSSHAIR_GRID_COMMENT, model.side);
    print_to_builder(*builder, "% % % % %\n", CROSSHAIR_COLOR_COMMENT,
                     color.x, color.y, color.z, color.w);
    print_to_builder(*builder, "# Coordinates are inches from the screen center; z is zero.\n");
    next_vertex: s32 = 1;
    for polygon: model.polygons {
        source_name := ifx polygon.mirror_x then
            (ifx polygon.mirror_y then "__crosshair_source_mx1_my1" else "__crosshair_source_mx1_my0")
            else (ifx polygon.mirror_y then "__crosshair_source_mx0_my1" else "__crosshair_source_mx0_my0");
        crosshair_write_obj_polygon(*builder, polygon, model.side, source_name, *next_vertex);
        if polygon.mirror_x {
            mirrored := derived_mirror_polygon(polygon, model.side, true, false);
            crosshair_write_obj_polygon(*builder, mirrored, model.side,
                                        "__crosshair_derived_x", *next_vertex);
        }
        if polygon.mirror_y {
            mirrored := derived_mirror_polygon(polygon, model.side, false, true);
            crosshair_write_obj_polygon(*builder, mirrored, model.side,
                                        "__crosshair_derived_y", *next_vertex);
        }
        if polygon.mirror_x && polygon.mirror_y {
            mirrored := derived_mirror_polygon(polygon, model.side, true, true);
            crosshair_write_obj_polygon(*builder, mirrored, model.side,
                                        "__crosshair_derived_xy", *next_vertex);
        }
    }
    if !write_entire_file(path, *builder) return false, "Could not write the crosshair OBJ.";
    return true, "";
}

load_crosshair_obj_for_editing :: (path: string, fallback_color: Vector4) -> Polygon_Model, Vector4, bool, string {
    model := make_polygon_model(DEFAULT_GRID_SIDE);
    contents, opened := read_entire_file(path, log_errors = false);
    if !opened return model, fallback_color, false, "Could not open the crosshair OBJ.";
    defer free(contents);
    color := crosshair_color_from_obj_text(contents, fallback_color);
    obj := Crosshair_Obj.parse_obj(contents);
    defer Crosshair_Obj.deinit(*obj);
    model.side = crosshair_grid_for_obj(contents, *obj);

    for *object: obj.all_objects {
        if begins_with(object.name, CROSSHAIR_EDITOR_DERIVED_PREFIX) continue;
        mirror_x := false;
        mirror_y := false;
        if begins_with(object.name, CROSSHAIR_EDITOR_OBJECT_PREFIX) {
            offset := CROSSHAIR_EDITOR_OBJECT_PREFIX.count;
            if object.name.count >= offset + 5 {
                mirror_x = object.name[offset] == #char "1";
                mirror_y = object.name[offset + 4] == #char "1";
            }
        }
        for *face: object.faces {
            if face.face_vertices.count < MIN_POLYGON_SIDES ||
               face.face_vertices.count > MAX_POLYGON_SIDES {
                free_polygon_model(*model);
                return make_polygon_model(DEFAULT_GRID_SIDE), color, false, "An OBJ face needs 3 to 32 corners.";
            }
            polygon: Crosshair_Polygon;
            polygon.count = cast(s32) face.face_vertices.count;
            polygon.color = color;
            polygon.mirror_x = mirror_x;
            polygon.mirror_y = mirror_y;
            for i: 0..polygon.count - 1 {
                index := face.face_vertices[i].position_index;
                if index < 0 || index >= obj.all_positions.count {
                    free_polygon_model(*model);
                    return make_polygon_model(DEFAULT_GRID_SIDE), color, false, "An OBJ face references a missing vertex.";
                }
                point := obj.all_positions[index];
                if abs(point.z) > 0.001 || point.x < -0.500001 || point.x > 0.500001 ||
                   point.y < -0.500001 || point.y > 0.500001 {
                    free_polygon_model(*model);
                    return make_polygon_model(DEFAULT_GRID_SIDE), color, false, "OBJ vertices must fit in the one-inch square.";
                }
                polygon.vertices[i] = .{
                    clamp((cast(float) point.x + 0.5) * cast(float) model.side, 0, cast(float) model.side),
                    clamp((0.5 - cast(float) point.y) * cast(float) model.side, 0, cast(float) model.side),
                };
            }
            if !polygon_is_simple(polygon) {
                free_polygon_model(*model);
                return make_polygon_model(DEFAULT_GRID_SIDE), color, false, "An OBJ face is collapsed or self-intersecting.";
            }
            array_add(*model.polygons, polygon);
        }
    }
    if model.polygons.count == 0 return model, color, false, "No editable polygons were found.";
    model.selected = 0;
    return model, color, true, "";
}

test_crosshair_obj_roundtrip :: () {
    path := "/tmp/crosshair-editor-roundtrip.obj";
    defer file_delete(path);
    color := Vector4.{0.22, 0.91, 1.0, 1.0};
    model := make_polygon_model(100);
    defer free_polygon_model(*model);
    add_crosshair_polygon(*model, 3, color);
    toggle_selected_mirror(*model, true, true);
    add_crosshair_polygon(*model, 4, color);
    saved, _ := save_crosshair_obj(path, model, color);
    assert(saved);

    contents, opened := read_entire_file(path);
    assert(opened);
    defer free(contents);
    obj := Crosshair_Obj.parse_obj(contents);
    defer Crosshair_Obj.deinit(*obj);
    assert(obj.all_objects.count == 5);
    for object: obj.all_objects assert(object.faces.count == 1);

    restored, restored_color, loaded, _ := load_crosshair_obj_for_editing(path, .{1, 1, 1, 1});
    defer free_polygon_model(*restored);
    assert(loaded && restored.polygons.count == 2);
    assert(restored.polygons[0].mirror_x && restored.polygons[0].mirror_y);
    assert(!restored.polygons[1].mirror_x && !restored.polygons[1].mirror_y);
    assert(restored_color.x > 0.21 && restored_color.x < 0.23);
    for i: 0..model.polygons.count - 1 {
        assert(restored.polygons[i].count == model.polygons[i].count);
        for j: 0..model.polygons[i].count - 1 {
            assert(restored.polygons[i].vertices[j].x == model.polygons[i].vertices[j].x);
            assert(restored.polygons[i].vertices[j].y == model.polygons[i].vertices[j].y);
        }
    }

    // A grid choice controls future edits, not whether an imported corner is
    // accepted or rounded. Changing grids and saving must retain its location.
    precise_path := "/tmp/crosshair-editor-precise.obj";
    precise_saved_path := "/tmp/crosshair-editor-precise-saved.obj";
    defer file_delete(precise_path);
    defer file_delete(precise_saved_path);
    precise_text := "# crosshair-grid 100\no precise\nv -0.012345 0.067891 0\nv 0.012345 0.067891 0\nv 0 -0.010001 0\nf 1 2 3\n";
    assert(write_entire_file(precise_path, precise_text));
    precise, _, precise_loaded, _ := load_crosshair_obj_for_editing(precise_path, color);
    defer free_polygon_model(*precise);
    assert(precise_loaded && precise.side == 100 && precise.polygons.count == 1);
    original_x := precise.polygons[0].vertices[0].x;
    original_y := precise.polygons[0].vertices[0].y;
    assert(abs(original_x - 48.7655) < 0.0001);
    assert(abs(original_y - 43.2109) < 0.0001);
    assert(set_grid_resolution(*precise, FINE_GRID_SIDE));
    assert(abs(precise.polygons[0].vertices[0].x - original_x * 10) < 0.001);
    assert(set_grid_resolution(*precise, DEFAULT_GRID_SIDE));
    assert(abs(precise.polygons[0].vertices[0].x - original_x) < 0.0001);
    assert(abs(precise.polygons[0].vertices[0].y - original_y) < 0.0001);
    saved_precise, _ := save_crosshair_obj(precise_saved_path, precise, color);
    assert(saved_precise);
    saved_contents, read_saved := read_entire_file(precise_saved_path);
    assert(read_saved);
    defer free(saved_contents);
    saved_obj := Crosshair_Obj.parse_obj(saved_contents);
    defer Crosshair_Obj.deinit(*saved_obj);
    assert(saved_obj.all_positions.count == 3);
    assert(abs(saved_obj.all_positions[0].x + 0.012345) < 0.000001);
    assert(abs(saved_obj.all_positions[0].y - 0.067891) < 0.000001);

    // Files without an editor grid hint start on the finer grid if needed.
    no_hint := "o precise\nv -0.012345 0.067891 0\nv 0.012345 0.067891 0\nv 0 -0.010001 0\nf 1 2 3\n";
    assert(write_entire_file(precise_path, no_hint));
    inferred, _, inferred_loaded, _ := load_crosshair_obj_for_editing(precise_path, color);
    defer free_polygon_model(*inferred);
    assert(inferred_loaded && inferred.side == FINE_GRID_SIDE);
}
