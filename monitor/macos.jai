// Hand port of the measurement portion of GLFW's cocoa_monitor.m. GLFW reads
// millimeters from CGDisplayScreenSize; this reader uses the mode's pixel
// dimensions rather than its logical width/height for Retina displays.

monitor_core_graphics :: #library,system "CoreGraphics";
monitor_core_foundation :: #library,system "CoreFoundation";

Monitor_CG_Size :: struct { width, height: float64; }
Monitor_CG_Display :: u32;
Monitor_CG_Mode :: *void;
Monitor_CF_Array :: *void;

monitor_cg_get_displays :: (max_count: u32, displays: *Monitor_CG_Display,
                            count: *u32) -> s32 #foreign monitor_core_graphics "CGGetOnlineDisplayList";
monitor_cg_display_asleep :: (display: Monitor_CG_Display) -> s32 #foreign monitor_core_graphics "CGDisplayIsAsleep";
monitor_cg_screen_size :: (display: Monitor_CG_Display) -> Monitor_CG_Size #foreign monitor_core_graphics "CGDisplayScreenSize";
monitor_cg_current_mode :: (display: Monitor_CG_Display) -> Monitor_CG_Mode #foreign monitor_core_graphics "CGDisplayCopyDisplayMode";
monitor_cg_all_modes :: (display: Monitor_CG_Display, options: *void) -> Monitor_CF_Array #foreign monitor_core_graphics "CGDisplayCopyAllDisplayModes";
monitor_cg_pixel_width :: (mode: Monitor_CG_Mode) -> u64 #foreign monitor_core_graphics "CGDisplayModeGetPixelWidth";
monitor_cg_pixel_height :: (mode: Monitor_CG_Mode) -> u64 #foreign monitor_core_graphics "CGDisplayModeGetPixelHeight";
monitor_cg_release_mode :: (mode: Monitor_CG_Mode) #foreign monitor_core_graphics "CGDisplayModeRelease";
monitor_cf_count :: (array: Monitor_CF_Array) -> s64 #foreign monitor_core_foundation "CFArrayGetCount";
monitor_cf_item :: (array: Monitor_CF_Array, index: s64) -> *void #foreign monitor_core_foundation "CFArrayGetValueAtIndex";
monitor_cf_release :: (object: *void) #foreign monitor_core_foundation "CFRelease";

find_macos_monitor_profiles :: () -> [..] Monitor_Profile {
    profiles: [..] Monitor_Profile;
    count: u32 = 0;
    if monitor_cg_get_displays(0, null, *count) != 0 || count == 0 return profiles;
    ids := cast(*Monitor_CG_Display) alloc(count * size_of(Monitor_CG_Display));
    defer free(ids);
    if monitor_cg_get_displays(count, ids, *count) != 0 return profiles;
    for i: 0..count-1 {
        id := ids[i];
        if monitor_cg_display_asleep(id) != 0 continue;
        physical := monitor_cg_screen_size(id);
        current := monitor_cg_current_mode(id);
        if current == null continue;
        current_width := cast(s32) monitor_cg_pixel_width(current);
        current_height := cast(s32) monitor_cg_pixel_height(current);
        monitor_cg_release_mode(current);

        native_width := current_width;
        native_height := current_height;
        modes := monitor_cg_all_modes(id, null);
        if modes != null {
            mode_count := monitor_cf_count(modes);
            if mode_count > 0 {
                for j: 0..mode_count-1 {
                    mode := monitor_cf_item(modes, j);
                    if mode == null continue;
                    width := cast(s32) monitor_cg_pixel_width(mode);
                    height := cast(s32) monitor_cg_pixel_height(mode);
                    if width * height > native_width * native_height {
                        native_width = width;
                        native_height = height;
                    }
                }
            }
            monitor_cf_release(modes);
        }
        connector := tprint("CGDisplay-%", id);
        profile, valid := make_monitor_profile_from_dimensions(connector, connector,
            native_width, native_height, current_width, current_height,
            cast(s32) (physical.width + 0.5), cast(s32) (physical.height + 0.5), .MACOS);
        if valid array_add(*profiles, profile);
    }
    return profiles;
}
