#if OS == .WINDOWS {
    #import "File";
    #import "File_Utilities";
    #import "Windows";
    #import "stb_image_write";

    gdi32 :: #system_library "gdi32";

    StretchDIBits :: (
        hdc: HDC,
        xDest: s32, yDest: s32, DestWidth: s32, DestHeight: s32,
        xSrc: s32, ySrc: s32, SrcWidth: s32, SrcHeight: s32,
        lpBits: *void,
        lpbmi: *BITMAPINFO,
        iUsage: u32,
        rop: ROP
    ) -> s32 #foreign gdi32;

    Software_Framebuffer :: struct {
        width: s32;
        height: s32;
        pixels: [] u32;
        depth: [] u32;
        bitmap_info: BITMAPINFO;
    }

    Software_Window_Recording :: struct {
        active := false;
        frame: s32 = 0;
        directory: string;
        framebuffer: Software_Framebuffer;
        fps: s32 = 60;
    }

    Software_Windowed_Program :: struct {
        using #as lp : Looping_Program;

        window: HWND;
        framebuffer: Software_Framebuffer;
        recording: Software_Window_Recording;
        running := false;
        window_width: s32 = 1280;
        window_height: s32 = 720;
        framebuffer_width: s32 = 320;
        framebuffer_height: s32 = 180;
        class_name: string = "tbx_software_windowed_program_window";
        window_name: string = "CPU Software Window";
        key_pressed_this_frame: [256] bool;
    }

    // Win32 calls software_window_proc as a plain callback, so it does not receive our program pointer.
    // This is the single-window bridge that lets the callback update running/key state.
    active_software_windowed_program: *Software_Windowed_Program;

    init :: (using swp: *Software_Windowed_Program) -> bool {
        init(*lp, max_fps);
        init_framebuffer(*framebuffer, framebuffer_width, framebuffer_height);

        class_name_w := software_to_wide_temp(class_name);
        window_name_w := software_to_wide_temp(window_name);

        window_class: WNDCLASSEXW;
        window_class.cbSize = size_of(WNDCLASSEXW);
        window_class.lpfnWndProc = cast(*void) software_window_proc;
        window_class.lpszClassName = class_name_w.data;
        window_class.hCursor = LoadCursorW(null, IDC_ARROW);

        if RegisterClassExW(*window_class) == 0 {
            // Class names are process-global; registering an existing one is okay for this tiny shell.
        }

        window = CreateWindowExW(
            0,
            class_name_w.data,
            window_name_w.data,
            WS_OVERLAPPEDWINDOW,
            CW_USEDEFAULT, CW_USEDEFAULT,
            window_width, window_height,
            null, null, null, null
        );

        if window == null return false;

        active_software_windowed_program = swp;
        running = true;
        ShowWindow(window, SW_SHOW);
        UpdateWindow(window);
        return true;
    }

    deinit :: (using swp: *Software_Windowed_Program) {
        array_free(framebuffer.pixels);
        array_free(framebuffer.depth);
        array_free(recording.framebuffer.pixels);
        array_free(recording.framebuffer.depth);
        if recording.directory.count > 0 free(recording.directory);
        if active_software_windowed_program == swp active_software_windowed_program = null;
    }

    init_framebuffer :: (fb: *Software_Framebuffer, width: s32, height: s32) {
        fb.width = width;
        fb.height = height;
        array_resize(*fb.pixels, width * height);
        array_resize(*fb.depth, width * height);

        fb.bitmap_info = .{};
        fb.bitmap_info.bmiHeader.biSize = size_of(BITMAPINFOHEADER);
        fb.bitmap_info.bmiHeader.biWidth = width;
        fb.bitmap_info.bmiHeader.biHeight = -height;
        fb.bitmap_info.bmiHeader.biPlanes = 1;
        fb.bitmap_info.bmiHeader.biBitCount = 32;
        fb.bitmap_info.bmiHeader.biCompression = BI_RGB;
    }

    poll_events :: (using swp: *Software_Windowed_Program) {
        for * key_pressed_this_frame it.* = false;

        message: MSG;
        while PeekMessageW(*message, null, 0, 0, PM_REMOVE) != 0 {
            if message.message == WM_QUIT {
                running = false;
                break;
            }

            TranslateMessage(*message);
            DispatchMessageW(*message);
        }
    }

    key_pressed_once :: (using swp: *Software_Windowed_Program, vk: s32) -> bool {
        if vk < 0 || vk >= key_pressed_this_frame.count return false;
        return key_pressed_this_frame[vk];
    }

    blit_to_window :: (using swp: *Software_Windowed_Program) {
        if window == null || framebuffer.pixels.count == 0 return;

        rect: RECT;
        GetClientRect(window, *rect);
        client_width  := rect.right - rect.left;
        client_height := rect.bottom - rect.top;
        if client_width <= 0 || client_height <= 0 return;

        dc := GetDC(window);
        if dc == null return;
        defer ReleaseDC(window, dc);

        SetStretchBltMode(dc, .COLORONCOLOR);
        StretchDIBits(
            dc,
            0, 0, client_width, client_height,
            0, 0, framebuffer.width, framebuffer.height,
            framebuffer.pixels.data,
            *framebuffer.bitmap_info,
            DIB_RGB_COLORS,
            .SRCCOPY
        );
    }

    is_recording :: (using swp: *Software_Windowed_Program) -> bool {
        return recording.active;
    }

    recording_delta_time :: (using swp: *Software_Windowed_Program) -> float32 {
        if recording.fps <= 0 return 0;
        return 1.0 / cast(float32)recording.fps;
    }

    toggle_recording :: (swp: *Software_Windowed_Program, width: s32, height: s32, fps: s32 = 60) {
        if swp.recording.active {
            stop_recording(swp);
        } else {
            start_recording(swp, width, height, fps);
        }
    }

    start_recording :: (using swp: *Software_Windowed_Program, width: s32, height: s32, fps: s32 = 60) {
        if recording.active return;

        if recording.directory.count > 0 {
            free(recording.directory);
            recording.directory = "";
        }

        directory := make_recording_directory_name();
        make_directory_if_it_does_not_exist(directory, recursive = true);

        if recording.framebuffer.width != width || recording.framebuffer.height != height {
            init_framebuffer(*recording.framebuffer, width, height);
        }

        recording.directory = copy_string(directory);
        recording.frame = 0;
        recording.fps = fps;
        recording.active = true;

        info := tprint("width=%\nheight=%\nfps=%\n", width, height, fps);
        write_entire_file(tprint("%/recording_info.txt", recording.directory), info);
        print("Recording started: % (%x% @ % fps)\n", recording.directory, width, height, fps);
    }

    stop_recording :: (using swp: *Software_Windowed_Program) {
        if !recording.active return;
        recording.active = false;
        print("Recording stopped: % (% frames)\n", recording.directory, recording.frame);
    }

    write_recording_frame :: (using swp: *Software_Windowed_Program) {
        if !recording.active return;
        if recording.framebuffer.pixels.count == 0 return;

        frame_name := tprint("%/frame_%.bmp",
            recording.directory,
            formatInt(recording.frame, minimum_digits=6));
        write_bmp32(frame_name, recording.framebuffer.width, recording.framebuffer.height, recording.framebuffer.pixels);
        recording.frame += 1;
    }

    save_screenshot :: (using swp: *Software_Windowed_Program) {
        if framebuffer.pixels.count == 0 return;

        make_directory_if_it_does_not_exist("screenshots", recursive = true);
        path := make_screenshot_file_name();
        write_png32(path, framebuffer.width, framebuffer.height, framebuffer.pixels);
        print("Screenshot saved: % (%x%)\n", path, framebuffer.width, framebuffer.height);
    }

    make_recording_directory_name :: () -> string {
        t: SYSTEMTIME;
        GetLocalTime(*t);
        return tprint("recordings/%_%_%_%_%_%",
            formatInt(t.wYear, minimum_digits=4),
            formatInt(t.wMonth, minimum_digits=2),
            formatInt(t.wDay, minimum_digits=2),
            formatInt(t.wHour, minimum_digits=2),
            formatInt(t.wMinute, minimum_digits=2),
            formatInt(t.wSecond, minimum_digits=2));
    }

    make_screenshot_file_name :: () -> string {
        t: SYSTEMTIME;
        GetLocalTime(*t);
        return tprint("screenshots/screenshot_%_%_%_%_%_%_%.png",
            formatInt(t.wYear, minimum_digits=4),
            formatInt(t.wMonth, minimum_digits=2),
            formatInt(t.wDay, minimum_digits=2),
            formatInt(t.wHour, minimum_digits=2),
            formatInt(t.wMinute, minimum_digits=2),
            formatInt(t.wSecond, minimum_digits=2),
            formatInt(t.wMilliseconds, minimum_digits=3));
    }

    write_png32 :: (path: string, width: s32, height: s32, pixels: [] u32) {
        if width <= 0 || height <= 0 return;
        expected_count := width * height;
        if pixels.count < expected_count return;

        rgb: [..] u8;
        defer array_free(rgb);
        array_resize(*rgb, expected_count * 3);

        dst := rgb.data;
        for i: 0..expected_count - 1 {
            color := pixels[i];
            pixel_offset := i * 3;
            (dst + pixel_offset + 0).* = cast(u8)((color >> 16) & 0xff);
            (dst + pixel_offset + 1).* = cast(u8)((color >> 8) & 0xff);
            (dst + pixel_offset + 2).* = cast(u8)( color        & 0xff);
        }

        if stbi_write_png(temp_c_string(path), width, height, 3, rgb.data, width * 3) == 0 {
            print("Failed to write screenshot %\n", path);
        }
    }

    write_bmp32 :: (path: string, width: s32, height: s32, pixels: [] u32) {
        if width <= 0 || height <= 0 return;
        expected_count := width * height;
        if pixels.count < expected_count return;

        file_header_size :: 14;
        dib_header_size  :: 40;
        pixel_bytes := expected_count * 4;
        file_size := file_header_size + dib_header_size + pixel_bytes;

        bytes: [..] u8;
        defer array_free(bytes);
        array_reserve(*bytes, file_size);

        array_add(*bytes, #char "B");
        array_add(*bytes, #char "M");
        append_u32_le(*bytes, cast(u32)file_size);
        append_u16_le(*bytes, 0);
        append_u16_le(*bytes, 0);
        append_u32_le(*bytes, file_header_size + dib_header_size);

        append_u32_le(*bytes, dib_header_size);
        append_s32_le(*bytes, width);
        append_s32_le(*bytes, -height);
        append_u16_le(*bytes, 1);
        append_u16_le(*bytes, 32);
        append_u32_le(*bytes, 0); // BI_RGB
        append_u32_le(*bytes, cast(u32)pixel_bytes);
        append_s32_le(*bytes, 2835);
        append_s32_le(*bytes, 2835);
        append_u32_le(*bytes, 0);
        append_u32_le(*bytes, 0);

        for i: 0..expected_count - 1 append_u32_le(*bytes, pixels[i]);

        if !write_entire_file(path, bytes.data, bytes.count) {
            print("Failed to write recording frame %\n", path);
        }
    }

    append_u16_le :: (bytes: *[..] u8, value: u16) {
        array_add(bytes, cast(u8)( value       & 0xff));
        array_add(bytes, cast(u8)((value >> 8) & 0xff));
    }

    append_s32_le :: (bytes: *[..] u8, value: s32) {
        append_u32_le(bytes, cast(u32)value);
    }

    append_u32_le :: (bytes: *[..] u8, value: u32) {
        array_add(bytes, cast(u8)( value        & 0xff));
        array_add(bytes, cast(u8)((value >>  8) & 0xff));
        array_add(bytes, cast(u8)((value >> 16) & 0xff));
        array_add(bytes, cast(u8)((value >> 24) & 0xff));
    }

    software_window_proc :: (window: HWND, message: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT #c_call {
        swp := active_software_windowed_program;

        if message == {
            case WM_CLOSE;
                if swp swp.running = false;
                DestroyWindow(window);
                return 0;

            case WM_DESTROY;
                if swp swp.running = false;
                PostQuitMessage(0);
                return 0;

            case WM_KEYDOWN;
                repeated := (lparam & cast(LPARAM)0x40000000) != 0;
                if swp && !repeated && wparam < 256 {
                    swp.key_pressed_this_frame[wparam] = true;
                }
                return 0;
        }

        return DefWindowProcW(window, message, wparam, lparam);
    }

    software_to_wide_temp :: (text: string) -> [] u16 {
        result: [..] u16;
        array_reserve(*result, text.count + 1);
        for c: text array_add(*result, cast(u16)c);
        array_add(*result, 0);
        return result;
    }
}
