// wl_output geometry and mode events, adapted from the transpiled GLFW
// Wayland monitor backend. The protocol reports hardware mode pixels even
// when the compositor uses scaled logical coordinates.

Monitor_WL_Interface :: struct {
    name: *u8;
    version: s32;
    method_count: s32;
    methods: *void;
    event_count: s32;
    events: *void;
}

Monitor_WL_Argument :: union {
    unsigned: u32;
    signed: s32;
    pointer: *void;
}

Monitor_WL_Output :: struct {
    proxy: *void;
    connector: string;
    name: string;
    width_mm, height_mm: s32;
    current_width, current_height: s32;
    preferred_width, preferred_height: s32;
    largest_width, largest_height: s32;
}

Monitor_WL_Collector :: struct {
    registry: *void;
    output_interface: *Monitor_WL_Interface;
    outputs: [..] *Monitor_WL_Output;
}

Monitor_WL_Registry_Listener :: struct {
    global: #type (data: *void, registry: *void, id: u32, interface_name: *u8, version: u32) #c_call;
    global_remove: #type (data: *void, registry: *void, id: u32) #c_call;
}

Monitor_WL_Output_Listener :: struct {
    geometry: #type (data: *void, output: *void, x: s32, y: s32, width_mm: s32, height_mm: s32,
                     subpixel: s32, make: *u8, model: *u8, transform: s32) #c_call;
    mode: #type (data: *void, output: *void, flags: u32, width: s32, height: s32, refresh: s32) #c_call;
    done: #type (data: *void, output: *void) #c_call;
    scale: #type (data: *void, output: *void, factor: s32) #c_call;
    name: #type (data: *void, output: *void, name: *u8) #c_call;
    description: #type (data: *void, output: *void, description: *u8) #c_call;
}

// libwayland retains this pointer, so the callback table must outlive a
// registry callback and both initial round trips.
monitor_wl_output_listener: Monitor_WL_Output_Listener;

monitor_wayland :: #library,system "libwayland-client";
monitor_wl_connect :: (name: *u8) -> *void #foreign monitor_wayland "wl_display_connect";
monitor_wl_disconnect :: (display: *void) #foreign monitor_wayland "wl_display_disconnect";
monitor_wl_roundtrip :: (display: *void) -> s32 #foreign monitor_wayland "wl_display_roundtrip";
monitor_wl_marshal :: (proxy: *void, opcode: u32, interface_ptr: *Monitor_WL_Interface, version: u32,
                      flags: u32, arguments: *Monitor_WL_Argument) -> *void #foreign monitor_wayland "wl_proxy_marshal_array_flags";
monitor_wl_version :: (proxy: *void) -> u32 #foreign monitor_wayland "wl_proxy_get_version";
monitor_wl_add_listener :: (proxy: *void, listener: *void, data: *void) -> s32 #foreign monitor_wayland "wl_proxy_add_listener";
monitor_wl_destroy :: (proxy: *void) #foreign monitor_wayland "wl_proxy_destroy";

monitor_wl_output_geometry :: (data: *void, output: *void, x: s32, y: s32,
                               width_mm: s32, height_mm: s32, subpixel: s32,
                               make: *u8, model: *u8, transform: s32) #c_call {
    push_context {
        found := cast(*Monitor_WL_Output) data;
        found.width_mm = width_mm;
        found.height_mm = height_mm;
        if model != null {
            free(found.name);
            found.name = copy_string(to_string(model));
        }
    }
}

monitor_wl_output_mode :: (data: *void, output: *void, flags: u32,
                           width: s32, height: s32, refresh: s32) #c_call {
    found := cast(*Monitor_WL_Output) data;
    if width <= 0 || height <= 0 return;
    if (flags & 1) != 0 {
        found.current_width = width;
        found.current_height = height;
    }
    if (flags & 2) != 0 {
        found.preferred_width = width;
        found.preferred_height = height;
    }
    if width * height > found.largest_width * found.largest_height {
        found.largest_width = width;
        found.largest_height = height;
    }
}

monitor_wl_output_done :: (data: *void, output: *void) #c_call {}
monitor_wl_output_scale :: (data: *void, output: *void, factor: s32) #c_call {}

monitor_wl_output_name :: (data: *void, output: *void, name: *u8) #c_call {
    push_context {
        if name == null return;
        found := cast(*Monitor_WL_Output) data;
        free(found.connector);
        found.connector = copy_string(to_string(name));
    }
}

monitor_wl_output_description :: (data: *void, output: *void, description: *u8) #c_call {}
monitor_wl_registry_remove :: (data: *void, registry: *void, id: u32) #c_call {}

monitor_wl_registry_global :: (data: *void, registry: *void, id: u32,
                               interface_name: *u8, version: u32) #c_call {
    push_context {
        collector := cast(*Monitor_WL_Collector) data;
        if interface_name == null || to_string(interface_name) != "wl_output" return;
        if version < 2 return;
        bind_version := min(version, cast(u32) 4);
        arguments: [4] Monitor_WL_Argument;
        arguments[0].unsigned = id;
        arguments[1].pointer = collector.output_interface.name;
        arguments[2].unsigned = bind_version;
        arguments[3].pointer = null;
        proxy := monitor_wl_marshal(registry, 0, collector.output_interface,
                                    bind_version, 0, *arguments[0]);
        if proxy == null return;
        found := cast(*Monitor_WL_Output) alloc(size_of(Monitor_WL_Output));
        found.* = .{};
        found.proxy = proxy;
        found.connector = copy_string(tprint("wl-output-%", id));
        found.name = copy_string("Wayland display");
        if monitor_wl_add_listener(proxy, cast(*void) *monitor_wl_output_listener, found) != 0 {
            monitor_wl_destroy(proxy);
            free(found.connector);
            free(found.name);
            free(found);
            return;
        }
        array_add(*collector.outputs, found);
    }
}

find_wayland_monitor_profiles :: () -> [..] Monitor_Profile {
    profiles: [..] Monitor_Profile;
    monitor_wl_output_listener = .{
        geometry = monitor_wl_output_geometry,
        mode = monitor_wl_output_mode,
        done = monitor_wl_output_done,
        scale = monitor_wl_output_scale,
        name = monitor_wl_output_name,
        description = monitor_wl_output_description,
    };
    display := monitor_wl_connect(null);
    if display == null return profiles;
    defer monitor_wl_disconnect(display);
    library := Monitor_POSIX.dlopen("libwayland-client.so.0".data,
                                    Monitor_POSIX.RTLD_LAZY | Monitor_POSIX.RTLD_LOCAL);
    if library == null return profiles;
    defer Monitor_POSIX.dlclose(library);
    registry_interface := cast(*Monitor_WL_Interface) Monitor_POSIX.dlsym(library, "wl_registry_interface".data);
    output_interface := cast(*Monitor_WL_Interface) Monitor_POSIX.dlsym(library, "wl_output_interface".data);
    if registry_interface == null || output_interface == null return profiles;
    registry_arguments: [1] Monitor_WL_Argument;
    registry_arguments[0].pointer = null; // get_registry has one new_id argument
    registry := monitor_wl_marshal(display, 1, registry_interface,
                                   monitor_wl_version(display), 0, *registry_arguments[0]);
    if registry == null return profiles;
    defer monitor_wl_destroy(registry);
    collector: Monitor_WL_Collector;
    collector.registry = registry;
    collector.output_interface = output_interface;
    defer {
        for found: collector.outputs {
            monitor_wl_destroy(found.proxy);
            free(found.connector);
            free(found.name);
            free(found);
        }
        array_free(collector.outputs);
    }
    listener := Monitor_WL_Registry_Listener.{
        global = monitor_wl_registry_global,
        global_remove = monitor_wl_registry_remove,
    };
    if monitor_wl_add_listener(registry, cast(*void) *listener, *collector) != 0 return profiles;
    if monitor_wl_roundtrip(display) < 0 || monitor_wl_roundtrip(display) < 0 return profiles;

    for found: collector.outputs {
        native_width := ifx found.preferred_width > 0 then found.preferred_width else found.largest_width;
        native_height := ifx found.preferred_height > 0 then found.preferred_height else found.largest_height;
        profile, valid := make_monitor_profile_from_dimensions(found.connector, found.name,
            native_width, native_height, found.current_width, found.current_height,
            found.width_mm, found.height_mm, .WAYLAND);
        if valid array_add(*profiles, profile);
    }
    return profiles;
}
