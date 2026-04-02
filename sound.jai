#scope_file
Sound_Player :: #import "Sound_Player";
#scope_export

#import "Hash_Table";

// ============================================================
// Loading
// ============================================================

load_sound :: (path : string) -> Sound_Player.Sound_Data {
    data := Sound_Player.load_audio_file(path);
    if !data.loaded exit(1);
    return data;
}

// ============================================================
// Direct playback (from Sound_Data pointer)
// ============================================================

play_sound :: (data: *Sound_Player.Sound_Data, category := Sound_Player.Sound_Category.GENERAL_SFX, volume := 1.0) -> *Sound_Player.Sound_Stream {
    stream := Sound_Player.make_stream(data, category);
    stream.user_volume_scale = volume;
    Sound_Player.start_playing(stream);
    return stream;
}

play_spatial_sound :: (data: *Sound_Player.Sound_Data, position: Vector3, category := Sound_Player.Sound_Category.GENERAL_SFX, volume := 1.0) -> *Sound_Player.Sound_Stream {
    stream := make_stream(data, category);
    stream.user_volume_scale = volume;
    stream.user_flags |= .SPATIALIZED;
    stream.position = position;
    stream.inner_radius = 2.0;
    stream.outer_radius = 50.0;
    Sound_Player.start_playing(stream);
    return stream;
}

play_sound_looping :: (data: *Sound_Player.Sound_Data, category := Sound_Player.Sound_Category.GENERAL_SFX, volume := 1.0) -> *Sound_Player.Sound_Stream {
    stream := Sound_Player.make_stream(data, category);
    stream.user_volume_scale = volume;
    set_repeating(stream, true);
    start_playing(stream);
    return stream;
}

play_spatial_sound_looping :: (data: *Sound_Player.Sound_Data, position: Vector3, category := Sound_Player.Sound_Category.GENERAL_SFX, volume := 1.0) -> *Sound_Player.Sound_Stream {
    stream := make_stream(data, category);
    stream.user_volume_scale = volume;
    stream.user_flags |= .SPATIALIZED;
    stream.position = position;
    stream.inner_radius = 2.0;
    stream.outer_radius = 50.0;
    set_repeating(stream, true);
    start_playing(stream);
    return stream;
}

// ============================================================
// Catalog playback (from Table(u8, Sound_Data) + sound type)
// ============================================================

play_sound :: (sc : *Table(u8, Sound_Player.Sound_Data), sound_type : u8, category := Sound_Player.Sound_Category.GENERAL_SFX, volume := 1.0) -> *Sound_Player.Sound_Stream {
    sound_data := table_find_pointer(sc, sound_type);
    if !sound_data return null;
    return play_sound(sound_data, category, volume);
}

play_spatial_sound :: (sc : *Table(u8, Sound_Player.Sound_Data), sound_type : u8, position: Vector3 = .{0, 0, 0}, category := Sound_Player.Sound_Category.GENERAL_SFX, volume := 1.0) -> *Sound_Player.Sound_Stream {
    sound_data := table_find_pointer(sc, sound_type);
    if !sound_data return null;
    return play_spatial_sound(sound_data, position, category, volume);
}

play_sound_looping :: (using sc: *Table(u8, Sound_Player.Sound_Data), sound_type: u8, category := Sound_Player.Sound_Category.GENERAL_SFX, volume := 1.0) -> *Sound_Player.Sound_Stream {
    sound_data := table_find_pointer(*sound_type_to_data, sound_type);
    if !sound_data return null;
    return play_sound_looping(sound_data, category, volume);
}

play_spatial_sound_looping :: (using sc: *Table(u8, Sound_Player.Sound_Data), sound_type: u8, position: Vector3 = .{0, 0, 0}, category := Sound_Player.Sound_Category.GENERAL_SFX, volume := 1.0) -> *Sound_Player.Sound_Stream {
    sound_data := table_find_pointer(*sound_type_to_data, sound_type);
    if !sound_data return null;
    return play_spatial_sound_looping(sound_data, position, category, volume);
}

// ============================================================
// Stopping
// ============================================================

stop_sound :: (stream: **Sound_Player.Sound_Stream) {
    if stream.* == null return;
    lock(*Sound_Player.sound_mutex);
    stream.*.internal_flags |= .FADING_OUT;
    unlock(*Sound_Player.sound_mutex);
    stream.* = null;
}
