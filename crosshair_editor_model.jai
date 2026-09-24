// Polygon vertices retain their positions within a one-inch square. The
// selectable grid resolution only controls snapping during edits.
// A polygon can become concave while editing; ear clipping turns it into GPU
// triangles at draw time. Crossed edges are rejected during vertex drags.

#import "Math";

MIN_POLYGON_SIDES :: 3;
MAX_POLYGON_SIDES :: 32;
DEFAULT_GRID_SIDE :: 100;
FINE_GRID_SIDE :: 1000;
GEOMETRY_EPSILON :: 0.00000001;

Grid_Point :: struct {
    x: float;
    y: float;
}

Crosshair_Polygon :: struct {
    vertices: [MAX_POLYGON_SIDES] Grid_Point;
    count: s32;
    color: Vector4;
    mirror_x: bool;
    mirror_y: bool;
}

Polygon_Model :: struct {
    side: s32;
    polygons: [..] Crosshair_Polygon;
    selected: s32 = -1;
}

Polygon_Clipboard :: struct {
    polygon: Crosshair_Polygon;
    grid_side: s32;
    has_polygon: bool;
    paste_count: s32;
}

Polygon_Triangle :: struct {
    indices: [3] s32;
}

Polygon_Triangulation :: struct {
    triangles: [MAX_POLYGON_SIDES - 2] Polygon_Triangle;
    count: s32;
    valid: bool;
}

make_polygon_model :: (side: s32) -> Polygon_Model {
    result: Polygon_Model;
    result.side = side;
    result.selected = -1;
    return result;
}

free_polygon_model :: (model: *Polygon_Model) {
    array_free(model.polygons);
    model.* = .{};
}

delete_selected_polygon :: (model: *Polygon_Model) {
    if model.selected < 0 || model.selected >= model.polygons.count return;
    array_ordered_remove_by_index(*model.polygons, model.selected);
    model.selected = -1;
}

copy_selected_polygon :: (model: Polygon_Model, clipboard: *Polygon_Clipboard) -> bool {
    if model.selected < 0 || model.selected >= model.polygons.count return false;
    clipboard.polygon = model.polygons[model.selected];
    clipboard.grid_side = model.side;
    clipboard.has_polygon = true;
    clipboard.paste_count = 0;
    return true;
}

paste_polygon :: (model: *Polygon_Model, clipboard: *Polygon_Clipboard) -> s32 {
    if !clipboard.has_polygon return -1;
    pasted := clipboard.polygon;
    if clipboard.grid_side != model.side {
        pasted = rescale_polygon_grid(pasted, clipboard.grid_side, model.side);
        if !polygon_is_simple(pasted) return -1;
    }
    array_add(*model.polygons, pasted);
    model.selected = cast(s32) model.polygons.count - 1;
    clipboard.paste_count += 1;
    offset := clipboard.paste_count * max(cast(s32) 3, cast(s32) floor(cast(float) model.side * 0.03 + 0.5));
    move_polygon_from(model, model.selected, pasted.vertices, offset, offset);
    return model.selected;
}

// Mirror settings belong to the source shape. Derived copies are never stored
// in the editable polygon array.
toggle_selected_mirror :: (model: *Polygon_Model, over_x: bool, over_y: bool) -> bool {
    if model.selected < 0 || model.selected >= model.polygons.count return false;
    if !over_x && !over_y return false;
    polygon := *model.polygons[model.selected];
    if over_x && over_y {
        enabled := !(polygon.mirror_x && polygon.mirror_y);
        polygon.mirror_x = enabled;
        polygon.mirror_y = enabled;
    } else {
        if over_x polygon.mirror_x = !polygon.mirror_x;
        if over_y polygon.mirror_y = !polygon.mirror_y;
    }
    return true;
}

// The X axis runs left/right, so reflection over X reverses Y.
derived_mirror_polygon :: (source: Crosshair_Polygon, side: s32, over_x: bool, over_y: bool) -> Crosshair_Polygon {
    result := source;
    result.mirror_x = false;
    result.mirror_y = false;
    for i: 0..result.count - 1 {
        if over_x result.vertices[i].y = side - source.vertices[i].y;
        if over_y result.vertices[i].x = side - source.vertices[i].x;
    }
    return result;
}

rendered_polygon_count :: (model: Polygon_Model) -> s32 {
    total: s32 = 0;
    for polygon: model.polygons {
        total += 1;
        if polygon.mirror_x total += 1;
        if polygon.mirror_y total += 1;
        if polygon.mirror_x && polygon.mirror_y total += 1;
    }
    return total;
}

grid_snap :: (value: float, side: s32) -> float {
    return cast(float) clamp(cast(s32) floor(value + 0.5), 0, side);
}

rescale_polygon_grid :: (polygon: Crosshair_Polygon, old_side: s32, new_side: s32) -> Crosshair_Polygon {
    result := polygon;
    ratio := cast(float) new_side / cast(float) old_side;
    for i: 0..result.count - 1 {
        result.vertices[i].x = polygon.vertices[i].x * ratio;
        result.vertices[i].y = polygon.vertices[i].y * ratio;
    }
    return result;
}

// Switching the snap lattice does not round existing vertices.
set_grid_resolution :: (model: *Polygon_Model, new_side: s32) -> bool {
    if new_side != DEFAULT_GRID_SIDE && new_side != FINE_GRID_SIDE return false;
    if new_side == model.side return true;
    if model.polygons.count > 0 {
        for i: 0..model.polygons.count - 1 {
            model.polygons[i] = rescale_polygon_grid(model.polygons[i], model.side, new_side);
        }
    }
    model.side = new_side;
    return true;
}

polygon_cross :: (a: Grid_Point, b: Grid_Point, c: Grid_Point) -> float {
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
}

polygon_area_twice :: (polygon: Crosshair_Polygon) -> float {
    result: float = 0;
    for i: 0..polygon.count - 1 {
        a := polygon.vertices[i];
        b := polygon.vertices[(i + 1) % polygon.count];
        result += a.x * b.y - b.x * a.y;
    }
    return result;
}

point_on_segment :: (a: Grid_Point, b: Grid_Point, p: Grid_Point) -> bool {
    return abs(polygon_cross(a, b, p)) <= GEOMETRY_EPSILON &&
           p.x >= min(a.x, b.x) - GEOMETRY_EPSILON && p.x <= max(a.x, b.x) + GEOMETRY_EPSILON &&
           p.y >= min(a.y, b.y) - GEOMETRY_EPSILON && p.y <= max(a.y, b.y) + GEOMETRY_EPSILON;
}

segments_intersect :: (a: Grid_Point, b: Grid_Point, c: Grid_Point, d: Grid_Point) -> bool {
    ab_c := polygon_cross(a, b, c);
    ab_d := polygon_cross(a, b, d);
    cd_a := polygon_cross(c, d, a);
    cd_b := polygon_cross(c, d, b);
    if abs(ab_c) <= GEOMETRY_EPSILON && point_on_segment(a, b, c) return true;
    if abs(ab_d) <= GEOMETRY_EPSILON && point_on_segment(a, b, d) return true;
    if abs(cd_a) <= GEOMETRY_EPSILON && point_on_segment(c, d, a) return true;
    if abs(cd_b) <= GEOMETRY_EPSILON && point_on_segment(c, d, b) return true;
    return (ab_c < -GEOMETRY_EPSILON) != (ab_d < -GEOMETRY_EPSILON) &&
           (cd_a < -GEOMETRY_EPSILON) != (cd_b < -GEOMETRY_EPSILON);
}

polygon_is_simple :: (polygon: Crosshair_Polygon) -> bool {
    if polygon.count < MIN_POLYGON_SIDES || polygon.count > MAX_POLYGON_SIDES return false;
    if abs(polygon_area_twice(polygon)) <= GEOMETRY_EPSILON return false;
    for i: 0..polygon.count - 1 {
        a := polygon.vertices[i];
        b := polygon.vertices[(i + 1) % polygon.count];
        if abs(a.x - b.x) <= GEOMETRY_EPSILON && abs(a.y - b.y) <= GEOMETRY_EPSILON return false;
        j := i + 1;
        while j < polygon.count {
            if j != i + 1 && !(i == 0 && j == polygon.count - 1) {
                c := polygon.vertices[j];
                d := polygon.vertices[(j + 1) % polygon.count];
                if segments_intersect(a, b, c, d) return false;
            }
            j += 1;
        }
    }
    return true;
}

add_crosshair_polygon :: (model: *Polygon_Model, requested_sides: s32, color: Vector4) -> s32 {
    sides := clamp(requested_sides, MIN_POLYGON_SIDES, MAX_POLYGON_SIDES);
    polygon: Crosshair_Polygon;
    polygon.count = sides;
    polygon.color = color;
    radius := cast(float) model.side * 0.15;
    center := cast(float) model.side * 0.5;
    stagger := cast(float) (model.polygons.count % 5) * cast(float) model.side * 0.03;
    first_angle := cast(float) (-PI * 0.5);
    if sides % 2 == 0 first_angle -= cast(float) PI / cast(float) sides;
    for i: 0..sides - 1 {
        angle := first_angle + cast(float) i * cast(float) TAU / cast(float) sides;
        polygon.vertices[i] = .{
            grid_snap(center + stagger + radius * cos(angle), model.side),
            grid_snap(center + radius * sin(angle), model.side),
        };
    }
    assert(polygon_is_simple(polygon));
    array_add(*model.polygons, polygon);
    model.selected = cast(s32) model.polygons.count - 1;
    return model.selected;
}

polygon_contains :: (polygon: Crosshair_Polygon, x: float, y: float) -> bool {
    if !polygon_is_simple(polygon) return false;
    inside := false;
    j := polygon.count - 1;
    for i: 0..polygon.count - 1 {
        a := polygon.vertices[j];
        b := polygon.vertices[i];
        if ((cast(float) a.y > y) != (cast(float) b.y > y)) &&
           x < cast(float) (b.x - a.x) * (y - cast(float) a.y) /
               cast(float) (b.y - a.y) + cast(float) a.x {
            inside = !inside;
        }
        j = i;
    }
    return inside;
}

polygon_at :: (model: Polygon_Model, x: float, y: float) -> s32 {
    i := cast(s32) model.polygons.count - 1;
    while i >= 0 {
        if polygon_contains(model.polygons[i], x, y) return i;
        i -= 1;
    }
    return -1;
}

move_polygon_from :: (model: *Polygon_Model, index: s32,
                      original: [MAX_POLYGON_SIDES] Grid_Point, dx: s32, dy: s32) {
    if index < 0 || index >= model.polygons.count return;
    polygon := *model.polygons[index];
    low_x := cast(float) model.side;
    low_y := cast(float) model.side;
    high_x: float = 0;
    high_y: float = 0;
    for i: 0..polygon.count - 1 {
        p := original[i];
        low_x = min(low_x, p.x);
        low_y = min(low_y, p.y);
        high_x = max(high_x, p.x);
        high_y = max(high_y, p.y);
    }
    move_x := clamp(cast(float) dx, -low_x, cast(float) model.side - high_x);
    move_y := clamp(cast(float) dy, -low_y, cast(float) model.side - high_y);
    for i: 0..polygon.count - 1 {
        model.polygons[index].vertices[i] = .{original[i].x + move_x, original[i].y + move_y};
    }
}

move_polygon_vertex :: (model: *Polygon_Model, index: s32, vertex: s32, x: float, y: float) -> bool {
    if index < 0 || index >= model.polygons.count return false;
    if vertex < 0 || vertex >= model.polygons[index].count return false;
    before := model.polygons[index].vertices[vertex];
    model.polygons[index].vertices[vertex] = .{grid_snap(x, model.side), grid_snap(y, model.side)};
    if !polygon_is_simple(model.polygons[index]) {
        model.polygons[index].vertices[vertex] = before;
        return false;
    }
    return true;
}

point_in_triangle_or_on :: (p: Grid_Point, a: Grid_Point, b: Grid_Point, c: Grid_Point, winding: float) -> bool {
    return polygon_cross(a, b, p) * winding >= -GEOMETRY_EPSILON &&
           polygon_cross(b, c, p) * winding >= -GEOMETRY_EPSILON &&
           polygon_cross(c, a, p) * winding >= -GEOMETRY_EPSILON;
}

triangulate_polygon :: (polygon: Crosshair_Polygon) -> Polygon_Triangulation {
    result: Polygon_Triangulation;
    if !polygon_is_simple(polygon) return result;
    winding: float = ifx polygon_area_twice(polygon) > 0 then 1.0 else -1.0;
    indices: [MAX_POLYGON_SIDES] s32;
    remaining := polygon.count;
    for i: 0..remaining - 1 indices[i] = cast(s32) i;

    // A dragged vertex may sit exactly on a straight edge. Such points are
    // redundant for the fill, though they remain editable in the model.
    changed := true;
    while changed && remaining > 3 {
        changed = false;
        i: s32 = 0;
        while i < remaining {
            previous := indices[(i + remaining - 1) % remaining];
            current := indices[i];
            next := indices[(i + 1) % remaining];
            if abs(polygon_cross(polygon.vertices[previous], polygon.vertices[current], polygon.vertices[next])) <= GEOMETRY_EPSILON &&
               point_on_segment(polygon.vertices[previous], polygon.vertices[next], polygon.vertices[current]) {
                j := i;
                while j < remaining - 1 {
                    indices[j] = indices[j + 1];
                    j += 1;
                }
                remaining -= 1;
                changed = true;
                break;
            }
            i += 1;
        }
    }

    while remaining > 3 {
        found_ear := false;
        for i: 0..remaining - 1 {
            previous := indices[(i + remaining - 1) % remaining];
            current := indices[i];
            next := indices[(i + 1) % remaining];
            a := polygon.vertices[previous];
            b := polygon.vertices[current];
            c := polygon.vertices[next];
            if polygon_cross(a, b, c) * winding <= GEOMETRY_EPSILON continue;
            blocked := false;
            for j: 0..remaining - 1 {
                candidate := indices[j];
                if candidate == previous || candidate == current || candidate == next continue;
                if point_in_triangle_or_on(polygon.vertices[candidate], a, b, c, winding) {
                    blocked = true;
                    break;
                }
            }
            if blocked continue;
            result.triangles[result.count].indices = s32.[previous, current, next];
            result.count += 1;
            j := i;
            while j < remaining - 1 {
                indices[j] = indices[j + 1];
                j += 1;
            }
            remaining -= 1;
            found_ear = true;
            break;
        }
        if !found_ear return .{};
    }
    if abs(polygon_cross(polygon.vertices[indices[0]], polygon.vertices[indices[1]], polygon.vertices[indices[2]])) <= GEOMETRY_EPSILON return .{};
    result.triangles[result.count].indices = s32.[indices[0], indices[1], indices[2]];
    result.count += 1;
    result.valid = true;
    return result;
}

test_polygon_model :: () {
    model := make_polygon_model(82);
    defer free_polygon_model(*model);
    red := Vector4.{1, 0, 0, 1};
    for sides: MIN_POLYGON_SIDES..MAX_POLYGON_SIDES {
        index := add_crosshair_polygon(*model, cast(s32) sides, red);
        polygon := model.polygons[index];
        assert(polygon.count == sides && polygon_is_simple(polygon));
        triangles := triangulate_polygon(polygon);
        assert(triangles.valid && triangles.count > 0 && triangles.count <= sides - 2);
        area_sum: float = 0;
        for t: 0..triangles.count - 1 {
            ids := triangles.triangles[t].indices;
            area_sum += abs(polygon_cross(polygon.vertices[ids[0]], polygon.vertices[ids[1]], polygon.vertices[ids[2]]));
        }
        assert(abs(area_sum - abs(polygon_area_twice(polygon))) < 0.01);
    }
    assert(model.polygons.count == MAX_POLYGON_SIDES - MIN_POLYGON_SIDES + 1);
    square := model.polygons[1];
    assert(square.count == 4 && polygon_contains(square, 44, 41));
    assert(polygon_at(model, -10, -10) == -1);
    original := model.polygons[0].vertices;
    move_polygon_from(*model, 0, original, 100, 0);
    max_x: float = 0;
    for i: 0..2 max_x = max(max_x, model.polygons[0].vertices[i].x);
    assert(max_x == 82);
    before := model.polygons[1].vertices[0];
    assert(!move_polygon_vertex(*model, 1, 0, cast(float) model.polygons[1].vertices[1].x,
                               cast(float) model.polygons[1].vertices[1].y));
    assert(model.polygons[1].vertices[0].x == before.x && model.polygons[1].vertices[0].y == before.y);
    assert(move_polygon_vertex(*model, 1, 0, 43.6, 25.2));
    assert(model.polygons[1].vertices[0].x == 44 && model.polygons[1].vertices[0].y == 25);

    concave: Crosshair_Polygon;
    concave.count = 5;
    concave.vertices[0] = .{10, 10};
    concave.vertices[1] = .{30, 10};
    concave.vertices[2] = .{30, 30};
    concave.vertices[3] = .{20, 20};
    concave.vertices[4] = .{10, 30};
    assert(polygon_is_simple(concave));
    assert(polygon_contains(concave, 20, 15) && !polygon_contains(concave, 20, 25));
    concave_mesh := triangulate_polygon(concave);
    assert(concave_mesh.valid && concave_mesh.count == 3);
    concave_area: float = 0;
    for t: 0..concave_mesh.count - 1 {
        ids := concave_mesh.triangles[t].indices;
        concave_area += abs(polygon_cross(concave.vertices[ids[0]], concave.vertices[ids[1]], concave.vertices[ids[2]]));
    }
    assert(abs(concave_area - abs(polygon_area_twice(concave))) < 0.01);

    editable := make_polygon_model(82);
    defer free_polygon_model(*editable);
    convex := concave;
    convex.vertices[3] = .{20, 30};
    array_add(*editable.polygons, convex);
    assert(move_polygon_vertex(*editable, 0, 3, 20, 20));
    assert(triangulate_polygon(editable.polygons[0]).valid);

    delete_selected_polygon(*model);
    assert(model.polygons.count == MAX_POLYGON_SIDES - MIN_POLYGON_SIDES && model.selected == -1);

    shapes := make_polygon_model(82);
    defer free_polygon_model(*shapes);
    clipboard: Polygon_Clipboard;
    assert(!copy_selected_polygon(shapes, *clipboard));
    assert(paste_polygon(*shapes, *clipboard) == -1);
    source_index := add_crosshair_polygon(*shapes, 3, red);
    source := shapes.polygons[source_index];
    assert(copy_selected_polygon(shapes, *clipboard));
    pasted_index := paste_polygon(*shapes, *clipboard);
    assert(pasted_index == 1 && shapes.polygons.count == 2);
    assert(shapes.polygons[pasted_index].color.x == source.color.x);
    for i: 0..source.count - 1 {
        assert(shapes.polygons[source_index].vertices[i].x == source.vertices[i].x);
        assert(shapes.polygons[source_index].vertices[i].y == source.vertices[i].y);
        assert(shapes.polygons[pasted_index].vertices[i].x == source.vertices[i].x + 3);
        assert(shapes.polygons[pasted_index].vertices[i].y == source.vertices[i].y + 3);
    }
    assert(!toggle_selected_mirror(*shapes, false, false));
    delete_selected_polygon(*shapes);
    assert(shapes.polygons.count == 1 && shapes.selected == -1);
    assert(!toggle_selected_mirror(*shapes, true, false) && rendered_polygon_count(shapes) == 1);

    assert(set_grid_resolution(*shapes, 100));
    assert(shapes.side == 100);
    assert(shapes.polygons[0].count == source.count && shapes.polygons[0].color.x == red.x);
    for i: 0..source.count - 1 {
        before_x := cast(float) source.vertices[i].x / 82.0;
        before_y := cast(float) source.vertices[i].y / 82.0;
        after_x := cast(float) shapes.polygons[0].vertices[i].x / 100.0;
        after_y := cast(float) shapes.polygons[0].vertices[i].y / 100.0;
        assert(abs(before_x - after_x) < 0.000001 && abs(before_y - after_y) < 0.000001);
    }
    for polygon: shapes.polygons assert(polygon_is_simple(polygon));
    pasted_after_resize := paste_polygon(*shapes, *clipboard);
    assert(pasted_after_resize == 1 && polygon_is_simple(shapes.polygons[pasted_after_resize]));
    assert(abs(shapes.polygons[pasted_after_resize].vertices[0].x -
               (shapes.polygons[0].vertices[0].x + 6)) < 0.0001);
    assert(!set_grid_resolution(*shapes, 99) && shapes.side == 100);

    empty := make_polygon_model(82);
    defer free_polygon_model(*empty);
    assert(set_grid_resolution(*empty, 100) && empty.side == 100);

    tiny := make_polygon_model(200);
    defer free_polygon_model(*tiny);
    little: Crosshair_Polygon;
    little.count = 3;
    little.vertices[0] = .{100, 100};
    little.vertices[1] = .{101, 100};
    little.vertices[2] = .{100, 101};
    assert(polygon_is_simple(little));
    array_add(*tiny.polygons, little);
    assert(!set_grid_resolution(*tiny, 32));
    assert(tiny.side == 200 && tiny.polygons[0].vertices[1].x == 101);

    linked := make_polygon_model(82);
    defer free_polygon_model(*linked);
    source_shape: Crosshair_Polygon;
    source_shape.count = 3;
    source_shape.color = red;
    source_shape.vertices[0] = .{10, 10};
    source_shape.vertices[1] = .{20, 10};
    source_shape.vertices[2] = .{10, 20};
    assert(polygon_is_simple(source_shape));
    array_add(*linked.polygons, source_shape);
    linked.selected = 0;
    assert(toggle_selected_mirror(*linked, true, false));
    assert(linked.polygons.count == 1 && linked.selected == 0 && rendered_polygon_count(linked) == 2);
    x_reflection := derived_mirror_polygon(linked.polygons[0], linked.side, true, false);
    assert(polygon_is_simple(x_reflection));
    assert(x_reflection.vertices[0].x == 10 && x_reflection.vertices[0].y == 72);
    assert(polygon_at(linked, 12, 69) == -1); // Reflections cannot be selected.
    assert(move_polygon_vertex(*linked, 0, 0, 11, 9));
    x_after_edit := derived_mirror_polygon(linked.polygons[0], linked.side, true, false);
    assert(x_after_edit.vertices[0].x == 11 && x_after_edit.vertices[0].y == 73);
    assert(toggle_selected_mirror(*linked, false, true));
    assert(linked.polygons.count == 1 && rendered_polygon_count(linked) == 4);
    y_reflection := derived_mirror_polygon(linked.polygons[0], linked.side, false, true);
    both_reflection := derived_mirror_polygon(linked.polygons[0], linked.side, true, true);
    assert(y_reflection.vertices[0].x == 71 && y_reflection.vertices[0].y == 9);
    assert(both_reflection.vertices[0].x == 71 && both_reflection.vertices[0].y == 73);
    assert(triangulate_polygon(both_reflection).valid);
    assert(toggle_selected_mirror(*linked, true, true));
    assert(!linked.polygons[0].mirror_x && !linked.polygons[0].mirror_y && rendered_polygon_count(linked) == 1);
    assert(toggle_selected_mirror(*linked, true, true));
    assert(linked.polygons[0].mirror_x && linked.polygons[0].mirror_y && rendered_polygon_count(linked) == 4);
    assert(set_grid_resolution(*linked, 100));
    assert(linked.polygons[0].mirror_x && linked.polygons[0].mirror_y && rendered_polygon_count(linked) == 4);
    resized_reflection := derived_mirror_polygon(linked.polygons[0], linked.side, true, true);
    assert(resized_reflection.vertices[0].x == 100 - linked.polygons[0].vertices[0].x);
    assert(resized_reflection.vertices[0].y == 100 - linked.polygons[0].vertices[0].y);
    linked_clipboard: Polygon_Clipboard;
    assert(copy_selected_polygon(linked, *linked_clipboard));
    linked_copy := paste_polygon(*linked, *linked_clipboard);
    assert(linked_copy == 1 && linked.polygons[linked_copy].mirror_x && linked.polygons[linked_copy].mirror_y);
    assert(rendered_polygon_count(linked) == 8);
    delete_selected_polygon(*linked);
    assert(linked.polygons.count == 1 && linked.polygons[0].mirror_x && rendered_polygon_count(linked) == 4);
    linked.selected = 0;
    delete_selected_polygon(*linked);
    assert(linked.polygons.count == 0 && rendered_polygon_count(linked) == 0);
}
