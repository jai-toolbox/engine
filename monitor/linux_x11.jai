// XRandR measurement path adapted from GLFW's transpiled x11_monitor.jai:
// XRRGetOutputInfo supplies mm, XRRGetCrtcInfo supplies the active mode, and
// the output's preferred RandR mode supplies the master pixel dimensions.

Monitor_X11 :: #import "X11";
monitor_xrandr :: #library,system "libXrandr";

Monitor_XRR_Mode :: struct {
    id: u64;
    width, height: u32;
    dot_clock: u64;
    h_sync_start, h_sync_end, h_total, h_skew: u32;
    v_sync_start, v_sync_end, v_total: u32;
    name: *u8;
    name_length: u32;
    mode_flags: u64;
}

Monitor_XRR_Resources :: struct {
    timestamp, config_timestamp: u64;
    ncrtc: s32;
    crtcs: *u64;
    noutput: s32;
    outputs: *u64;
    nmode: s32;
    modes: *Monitor_XRR_Mode;
}

Monitor_XRR_Output :: struct {
    timestamp, crtc: u64;
    name: *u8;
    name_length: s32;
    mm_width, mm_height: u64;
    connection, subpixel_order: u16;
    ncrtc: s32;
    crtcs: *u64;
    nclone: s32;
    clones: *u64;
    nmode, npreferred: s32;
    modes: *u64;
}

Monitor_XRR_Crtc :: struct {
    timestamp: u64;
    x, y: s32;
    width, height: u32;
    mode: u64;
    rotation: u16;
    noutput: s32;
    outputs: *u64;
    rotations: u16;
    npossible: s32;
    possible: *u64;
}

monitor_xrr_get_resources :: (display: *Monitor_X11.Display, root: Monitor_X11.Window) -> *Monitor_XRR_Resources #foreign monitor_xrandr "XRRGetScreenResourcesCurrent";
monitor_xrr_free_resources :: (resources: *Monitor_XRR_Resources) #foreign monitor_xrandr "XRRFreeScreenResources";
monitor_xrr_get_output :: (display: *Monitor_X11.Display, resources: *Monitor_XRR_Resources, output: u64) -> *Monitor_XRR_Output #foreign monitor_xrandr "XRRGetOutputInfo";
monitor_xrr_free_output :: (output: *Monitor_XRR_Output) #foreign monitor_xrandr "XRRFreeOutputInfo";
monitor_xrr_get_crtc :: (display: *Monitor_X11.Display, resources: *Monitor_XRR_Resources, crtc: u64) -> *Monitor_XRR_Crtc #foreign monitor_xrandr "XRRGetCrtcInfo";
monitor_xrr_free_crtc :: (crtc: *Monitor_XRR_Crtc) #foreign monitor_xrandr "XRRFreeCrtcInfo";

monitor_xrr_find_mode :: (resources: *Monitor_XRR_Resources, id: u64) -> *Monitor_XRR_Mode {
    if resources.nmode <= 0 return null;
    for i: 0..resources.nmode-1 if resources.modes[i].id == id return *resources.modes[i];
    return null;
}

find_x11_monitor_profiles :: () -> [..] Monitor_Profile {
    profiles: [..] Monitor_Profile;
    display := Monitor_X11.XOpenDisplay(null);
    if display == null return profiles;
    defer Monitor_X11.XCloseDisplay(display);
    resources := monitor_xrr_get_resources(display, Monitor_X11.XDefaultRootWindow(display));
    if resources == null return profiles;
    defer monitor_xrr_free_resources(resources);
    if resources.noutput <= 0 return profiles;

    for i: 0..resources.noutput-1 {
        output := monitor_xrr_get_output(display, resources, resources.outputs[i]);
        if output == null continue;
        defer monitor_xrr_free_output(output);
        // RandR connection == 0 is RR_Connected; disabled outputs have no CRTC.
        if output.connection != 0 || output.crtc == 0 || output.name_length <= 0 continue;
        crtc := monitor_xrr_get_crtc(display, resources, output.crtc);
        if crtc == null continue;
        defer monitor_xrr_free_crtc(crtc);
        rotated := crtc.rotation == 2 || crtc.rotation == 8;
        mode_width := cast(s32) (ifx rotated then crtc.height else crtc.width);
        mode_height := cast(s32) (ifx rotated then crtc.width else crtc.height);
        mm_width := cast(s32) (ifx rotated then output.mm_height else output.mm_width);
        mm_height := cast(s32) (ifx rotated then output.mm_width else output.mm_height);

        native_width: s32 = 0;
        native_height: s32 = 0;
        // RandR puts preferred modes first. If none are marked, use the
        // largest advertised mode, matching the editor's chosen fallback.
        candidates := ifx output.npreferred > 0 then output.npreferred else output.nmode;
        if candidates > output.nmode candidates = output.nmode;
        if candidates > 0 {
            for j: 0..candidates-1 {
                mode := monitor_xrr_find_mode(resources, output.modes[j]);
                if mode == null continue;
                width := cast(s32) (ifx rotated then mode.height else mode.width);
                height := cast(s32) (ifx rotated then mode.width else mode.height);
                if width * height > native_width * native_height {
                    native_width = width;
                    native_height = height;
                }
            }
        }
        if native_width <= 0 || native_height <= 0 {
            native_width = mode_width;
            native_height = mode_height;
        }
        connector: string;
        connector.data = output.name;
        connector.count = output.name_length;
        profile, valid := make_monitor_profile_from_dimensions(connector, connector,
            native_width, native_height, mode_width, mode_height, mm_width, mm_height, .X11);
        if valid array_add(*profiles, profile);
    }
    return profiles;
}
