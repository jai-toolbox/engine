// Hand port of GLFW's win32_monitor.c measurement path. An active display
// adapter provides its current DEVMODE, GDI provides millimeters, and the
// largest advertised mode stands in for a preferred panel mode.

Monitor_Windows :: #import "Windows";
Monitor_Windows_Utf8 :: #import "Windows_Utf8";
monitor_win_user32 :: #library,system "user32";
monitor_win_gdi32 :: #library,system "gdi32";

Monitor_Win_Display_Device :: struct {
    size: u32;
    device_name: [32] u16;
    device_string: [128] u16;
    state_flags: u32;
    device_id: [128] u16;
    device_key: [128] u16;
}

// Same 220-byte layout as DEVMODEW. Only its display fields are read.
Monitor_Win_Dev_Mode :: struct {
    device_name: [32] u16;
    spec_version, driver_version, size, driver_extra: u16;
    fields: u32;
    printer_or_display: [16] u8;
    color, duplex, y_resolution, tt_option, collate: s16;
    form_name: [32] u16;
    log_pixels: u16;
    bits_per_pixel, width, height, display_flags, frequency: u32;
    icm_method, icm_intent, media_type, dither_type: u32;
    reserved1, reserved2, panning_width, panning_height: u32;
}

monitor_win_enum_devices :: (device: *u16, index: u32, result: *Monitor_Win_Display_Device,
                             flags: u32) -> s32 #foreign monitor_win_user32 "EnumDisplayDevicesW";
monitor_win_enum_settings :: (device: *u16, index: u32, result: *Monitor_Win_Dev_Mode) -> s32 #foreign monitor_win_user32 "EnumDisplaySettingsW";
monitor_win_create_dc :: (driver: *u16, device: *u16, output: *u16,
                          init: *void) -> Monitor_Windows.HDC #foreign monitor_win_gdi32 "CreateDCW";

monitor_win_use_gdi_millimeters :: () -> bool {
    version: Monitor_Windows.OSVERSIONINFOW;
    version.dwOSVersionInfoSize = cast(u32) size_of(Monitor_Windows.OSVERSIONINFOW);
    Monitor_Windows.RtlGetVersion(*version);
    return version.dwMajorVersion > 6 ||
           (version.dwMajorVersion == 6 && version.dwMinorVersion >= 3);
}

monitor_win_append_adapter :: (profiles: *[..] Monitor_Profile,
                               adapter: *Monitor_Win_Display_Device,
                               display: *Monitor_Win_Display_Device) {
    adapter_name := *adapter.device_name[0];
    current: Monitor_Win_Dev_Mode;
    current.size = cast(u16) size_of(Monitor_Win_Dev_Mode);
    if monitor_win_enum_settings(adapter_name, cast(u32) 0xffffffff, *current) == 0 return;
    if current.width == 0 || current.height == 0 return;

    // This is the GDI path used by GLFW. Older Windows or bad drivers can
    // require its DPI-derived fallback rather than EDID-backed millimeters.
    driver := u16.[68, 73, 83, 80, 76, 65, 89, 0]; // L"DISPLAY"
    dc := monitor_win_create_dc(*driver[0], adapter_name, null, null);
    if dc == null return;
    width_mm: s32 = 0;
    height_mm: s32 = 0;
    if monitor_win_use_gdi_millimeters() {
        width_mm = Monitor_Windows.GetDeviceCaps(dc, Monitor_Windows.HORZSIZE);
        height_mm = Monitor_Windows.GetDeviceCaps(dc, Monitor_Windows.VERTSIZE);
    }
    if width_mm <= 0 || height_mm <= 0 {
        dpi_x := Monitor_Windows.GetDeviceCaps(dc, Monitor_Windows.LOGPIXELSX);
        dpi_y := Monitor_Windows.GetDeviceCaps(dc, Monitor_Windows.LOGPIXELSY);
        if dpi_x > 0 && dpi_y > 0 {
            width_mm = cast(s32) (cast(float64) current.width * 25.4 / cast(float64) dpi_x);
            height_mm = cast(s32) (cast(float64) current.height * 25.4 / cast(float64) dpi_y);
        }
    }
    Monitor_Windows.DeleteDC(dc);

    native_width := cast(s32) current.width;
    native_height := cast(s32) current.height;
    mode_index: u32 = 0;
    while true {
        mode: Monitor_Win_Dev_Mode;
        mode.size = cast(u16) size_of(Monitor_Win_Dev_Mode);
        if monitor_win_enum_settings(adapter_name, mode_index, *mode) == 0 break;
        mode_index += 1;
        if mode.width == 0 || mode.height == 0 continue;
        if cast(s64) mode.width * cast(s64) mode.height >
           cast(s64) native_width * cast(s64) native_height {
            native_width = cast(s32) mode.width;
            native_height = cast(s32) mode.height;
        }
    }

    connector_wide := ifx display != null then *display.device_name[0] else adapter_name;
    connector, connector_ok := Monitor_Windows_Utf8.wide_to_utf8(connector_wide);
    if !connector_ok return;
    defer free(connector);
    display_name := ifx display != null then *display.device_string[0] else *adapter.device_string[0];
    name, name_ok := Monitor_Windows_Utf8.wide_to_utf8(display_name);
    if !name_ok name = copy_string("Windows display");
    defer free(name);
    profile, valid := make_monitor_profile_from_dimensions(connector, name,
        native_width, native_height, cast(s32) current.width, cast(s32) current.height,
        width_mm, height_mm, .WINDOWS);
    if valid array_add(profiles, profile);
}

find_windows_monitor_profiles :: () -> [..] Monitor_Profile {
    profiles: [..] Monitor_Profile;
    adapter_index: u32 = 0;
    while true {
        adapter: Monitor_Win_Display_Device;
        adapter.size = cast(u32) size_of(Monitor_Win_Display_Device);
        if monitor_win_enum_devices(null, adapter_index, *adapter, 0) == 0 break;
        adapter_index += 1;
        if (adapter.state_flags & 1) == 0 continue; // DISPLAY_DEVICE_ACTIVE
        display_index: u32 = 0;
        while true {
            display: Monitor_Win_Display_Device;
            display.size = cast(u32) size_of(Monitor_Win_Display_Device);
            if monitor_win_enum_devices(*adapter.device_name[0], display_index, *display, 0) == 0 break;
            display_index += 1;
            if (display.state_flags & 1) == 0 continue;
            monitor_win_append_adapter(*profiles, *adapter, *display);
        }
        // GLFW uses the adapter itself when it reports no child display.
        if display_index == 0 monitor_win_append_adapter(*profiles, *adapter, null);
    }
    return profiles;
}
