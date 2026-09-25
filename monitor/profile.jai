// Common monitor measurements. Platform backends are in platform.jai.

#import "Math";
#import "File_Utilities";

Monitor_Backend :: enum {
    EDID;
    X11;
    WAYLAND;
    WINDOWS;
    MACOS;
}

Monitor_Profile :: struct {
    backend: Monitor_Backend;
    connector: string;
    name: string;
    native_width: s32;
    native_height: s32;
    mode_width: s32;
    mode_height: s32;
    mode_is_observed: bool;
    width_mm: s32;
    height_mm: s32;
    ppi_x: float64;
    ppi_y: float64;
    editor_side: s32;
}

#load "platform.jai";

make_monitor_profile_from_dimensions :: (connector: string, name: string,
                                         native_width: s32, native_height: s32,
                                         mode_width: s32, mode_height: s32,
                                         width_mm: s32, height_mm: s32,
                                         backend: Monitor_Backend) -> Monitor_Profile, bool {
    if native_width <= 0 || native_height <= 0 || mode_width <= 0 || mode_height <= 0 ||
       width_mm <= 0 || height_mm <= 0 return .{}, false;
    profile: Monitor_Profile;
    profile.backend = backend;
    profile.connector = copy_string(connector);
    profile.name = copy_string(name);
    profile.native_width = native_width;
    profile.native_height = native_height;
    profile.mode_width = mode_width;
    profile.mode_height = mode_height;
    profile.mode_is_observed = backend != .EDID;
    profile.width_mm = width_mm;
    profile.height_mm = height_mm;
    profile.ppi_x = cast(float64) native_width * 25.4 / cast(float64) width_mm;
    profile.ppi_y = cast(float64) native_height * 25.4 / cast(float64) height_mm;
    profile.editor_side = round_to_even_pixel_count((profile.ppi_x + profile.ppi_y) * 0.5);
    return profile, true;
}

round_to_even_pixel_count :: (value: float64) -> s32 {
    if value <= 0 return 0;
    return 2 * cast(s32) floor(value * 0.5 + 0.5);
}

crosshair_has_prefix :: (value: string, prefix: string) -> bool {
    if value.count < prefix.count return false;
    for i: 0..prefix.count-1 if value[i] != prefix[i] return false;
    return true;
}

make_monitor_profile :: (edid: string, connector: string) -> Monitor_Profile, bool {
    profile: Monitor_Profile;
    if edid.count < 128 return profile, false;

    header := u8.[0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00];
    for i: 0..7 if edid[i] != header[i] return profile, false;

    checksum: u32 = 0;
    for i: 0..127 checksum += cast(u32) edid[i];
    if (checksum & 0xff) != 0 return profile, false;

    // Only call the first detailed timing native when EDID marks it preferred.
    // A list of available desktop modes can include lower or virtual sizes.
    if (edid[24] & 0x02) == 0 return .{}, false;
    offset := 54;
    pixel_clock := cast(s32) edid[offset] | (cast(s32) edid[offset + 1] << 8);
    if pixel_clock == 0 return .{}, false;
    profile.native_width = cast(s32) edid[offset + 2] | ((cast(s32) edid[offset + 4] & 0xf0) << 4);
    profile.native_height = cast(s32) edid[offset + 5] | ((cast(s32) edid[offset + 7] & 0xf0) << 4);
    profile.width_mm = cast(s32) edid[offset + 12] | ((cast(s32) edid[offset + 14] & 0xf0) << 4);
    profile.height_mm = cast(s32) edid[offset + 13] | ((cast(s32) edid[offset + 14] & 0x0f) << 8);

    if profile.native_width <= 0 || profile.native_height <= 0 return .{}, false;
    if profile.width_mm <= 0 || profile.height_mm <= 0 {
        profile.width_mm = cast(s32) edid[21] * 10;
        profile.height_mm = cast(s32) edid[22] * 10;
    }
    if profile.width_mm <= 0 || profile.height_mm <= 0 return .{}, false;

    assembled, valid := make_monitor_profile_from_dimensions(connector, "Unknown display",
        profile.native_width, profile.native_height, profile.native_width, profile.native_height,
        profile.width_mm, profile.height_mm, .EDID);
    if !valid return .{}, false;
    profile = assembled;

    for descriptor: 0..3 {
        offset := 54 + descriptor * 18;
        if edid[offset] != 0 || edid[offset + 1] != 0 || edid[offset + 3] != 0xfc continue;
        name_start := offset + 5;
        name_length := 0;
        while name_length < 13 {
            c := edid[name_start + name_length];
            if c == 0 || c == 10 break;
            name_length += 1;
        }
        while name_length > 0 && edid[name_start + name_length - 1] == 32 name_length -= 1;
        if name_length > 0 {
            free(profile.name);
            name_slice: string;
            name_slice.data = edid.data + name_start;
            name_slice.count = name_length;
            profile.name = copy_string(name_slice);
        }
        break;
    }
    return profile, true;
}

read_sysfs_file :: (path: string, max_bytes: s64) -> string, bool {
    file, opened := file_open(path, log_errors = false);
    if !opened return "", false;
    defer file_close(*file);

    data := cast(*u8) alloc(max_bytes);
    ok, count := file_read(file, data, max_bytes);
    if !ok || count == 0 {
        free(data);
        return "", false;
    }
    result: string;
    result.data = data;
    result.count = count;
    return result, true;
}

find_sysfs_edid_monitor_profiles :: () -> [..] Monitor_Profile {
    profiles: [..] Monitor_Profile;
    #if OS == .LINUX {
        visitor :: (info: *File_Visit_Info, result: *[..] Monitor_Profile) {
            status, ok := read_sysfs_file(tprint("%/status", info.full_name), 32);
            if !ok return;
            defer free(status);
            if !crosshair_has_prefix(status, "connected") return;

            edid, edid_ok := read_sysfs_file(tprint("%/edid", info.full_name), 4096);
            if !edid_ok return;
            defer free(edid);
            profile, valid := make_monitor_profile(edid, info.short_name);
            if valid array_add(result, profile);
        }
        visit_files("/sys/class/drm", false, *profiles, visitor, visit_files = false, visit_directories = true);
    }
    return profiles;
}

free_monitor_profiles :: (profiles: *[..] Monitor_Profile) {
    for profile: profiles.* {
        free(profile.connector);
        free(profile.name);
    }
    array_free(profiles.*);
}

run_monitor_profile_tests :: () {
    #if OS == .LINUX {
        // Match the XRandR ABI used by linux_x11.jai on x64 Linux.
        assert(size_of(Monitor_XRR_Mode) == 80);
        assert(size_of(Monitor_XRR_Resources) == 64);
        assert(size_of(Monitor_XRR_Output) == 96);
        assert(size_of(Monitor_XRR_Crtc) == 64);
    }
    #if OS == .WINDOWS {
        assert(size_of(Monitor_Win_Dev_Mode) == 220);
        assert(size_of(Monitor_Win_Display_Device) == 840);
    }
    bytes: [128] u8;
    header := u8.[0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00];
    for i: 0..7 bytes[i] = header[i];
    bytes[24] = 0x02; // preferred detailed timing present
    bytes[54] = 0x02; bytes[55] = 0x3a; // 148.5 MHz pixel clock
    bytes[56] = 0x80; bytes[58] = 0x70; // 1920 active pixels
    bytes[59] = 0x38; bytes[61] = 0x40; // 1080 active lines
    bytes[66] = 0x56; bytes[67] = 0x50; bytes[68] = 0x21; // 598 x 336 mm
    bytes[111] = 0xfc;
    name := "BenQ GW2780";
    for i: 0..name.count-1 bytes[113+i] = name[i];
    bytes[113+name.count] = 10;
    checksum: u32 = 0;
    for i: 0..126 checksum += cast(u32) bytes[i];
    bytes[127] = cast(u8) ((256 - (checksum & 0xff)) & 0xff);

    edid: string;
    edid.data = bytes.data;
    edid.count = 128;
    profile, ok := make_monitor_profile(edid, "test-connector");
    assert(ok);
    assert(profile.native_width == 1920 && profile.native_height == 1080);
    assert(profile.width_mm == 598 && profile.height_mm == 336);
    assert(profile.editor_side == 82);
    assert(profile.name == name);
    free(profile.connector);
    free(profile.name);

    scaled, scaled_ok := make_monitor_profile_from_dimensions("test", "Scaled mode",
        1920, 1080, 1280, 720, 598, 336, .WAYLAND);
    assert(scaled_ok);
    assert(scaled.mode_width == 1280 && scaled.mode_height == 720);
    assert(scaled.ppi_x > 81.5 && scaled.ppi_x < 81.6);
    assert(scaled.editor_side == 82);
    free(scaled.connector);
    free(scaled.name);

    bytes[56] += 1; // invalid checksum must be rejected
    _, ok = make_monitor_profile(edid, "test-connector");
    assert(!ok);
}
