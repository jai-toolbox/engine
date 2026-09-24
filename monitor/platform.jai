// The platform code returns physical millimeters, a current mode, and a
// preferred (or highest advertised) mode. The PPI arithmetic lives in
// profile.jai and is shared by all four backends.

#if OS == .LINUX {
    #load "linux_x11.jai";
    #load "linux_wayland.jai";
    Monitor_POSIX :: #import "POSIX";

    find_connected_monitor_profiles :: () -> [..] Monitor_Profile {
        wayland_name := Monitor_POSIX.getenv("WAYLAND_DISPLAY".data);
        profiles: [..] Monitor_Profile;
        if wayland_name != null && wayland_name[0] != 0 {
            profiles = find_wayland_monitor_profiles();
            if profiles.count == 0 profiles = find_x11_monitor_profiles();
        } else {
            profiles = find_x11_monitor_profiles();
            if profiles.count == 0 profiles = find_wayland_monitor_profiles();
        }
        // Headless probes can still read the physical connector's EDID.
        if profiles.count == 0 profiles = find_sysfs_edid_monitor_profiles();
        return profiles;
    }
} else #if OS == .WINDOWS {
    #load "windows.jai";
    find_connected_monitor_profiles :: () -> [..] Monitor_Profile {
        return find_windows_monitor_profiles();
    }
} else #if OS == .MACOS {
    #load "macos.jai";
    find_connected_monitor_profiles :: () -> [..] Monitor_Profile {
        return find_macos_monitor_profiles();
    }
} else {
    find_connected_monitor_profiles :: () -> [..] Monitor_Profile { return .{}; }
}
