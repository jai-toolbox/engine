#scope_file
Sound_Player :: #import "Sound_Player";
#import "Thread";
#scope_export

#import "Hash_Table";
#import "tbx/assets";

load_sound :: (path : string) -> Sound_Player.Sound_Data {
    asset_loaded, asset_data := load_asset_copy(path);
    if !asset_loaded exit(1);

    data := Sound_Player.load_audio_data(path, asset_data);
    if !data.loaded exit(1);
    return data;
}


play_sound :: (data: *Sound_Player.Sound_Data, category := Sound_Player.Sound_Category.GENERAL_SFX, volume := 1.0) -> *Sound_Player.Sound_Stream {
    stream := Sound_Player.make_stream(data, category);
    stream.user_volume_scale = volume;
    Sound_Player.start_playing(stream);
    return stream;
}

play_spatial_sound :: (data: *Sound_Player.Sound_Data, position: Vector3, category := Sound_Player.Sound_Category.GENERAL_SFX, volume := 1.0) -> *Sound_Player.Sound_Stream {
    stream := Sound_Player.make_stream(data, category);
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
    Sound_Player.set_repeating(stream, true);
    Sound_Player.start_playing(stream);
    return stream;
}

play_spatial_sound_looping :: (data: *Sound_Player.Sound_Data, position: Vector3, category := Sound_Player.Sound_Category.GENERAL_SFX, volume := 1.0) -> *Sound_Player.Sound_Stream {
    stream := Sound_Player.make_stream(data, category);
    stream.user_volume_scale = volume;
    stream.user_flags |= .SPATIALIZED;
    stream.position = position;
    stream.inner_radius = 2.0;
    stream.outer_radius = 50.0;
    set_repeating(stream, true);
    start_playing(stream);
    return stream;
}

// catalog playback (from table(u8, sound_data) + sound type)

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

play_sound_looping :: (using sound_catalog: *Table(u8, Sound_Player.Sound_Data), sound_type: u8, category := Sound_Player.Sound_Category.GENERAL_SFX, volume := 1.0) -> *Sound_Player.Sound_Stream {
    sound_data := table_find_pointer(sound_catalog, sound_type);
    if !sound_data return null;
    return play_sound_looping(sound_data, category, volume);
}

play_spatial_sound_looping :: (using sc: *Table(u8, Sound_Player.Sound_Data), sound_type: u8, position: Vector3 = .{0, 0, 0}, category := Sound_Player.Sound_Category.GENERAL_SFX, volume := 1.0) -> *Sound_Player.Sound_Stream {
    sound_data := table_find_pointer(*sound_type_to_data, sound_type);
    if !sound_data return null;
    return play_spatial_sound_looping(sound_data, position, category, volume);
}


stop_sound :: (stream: **Sound_Player.Sound_Stream) {
    if stream.* == null return;
    lock(*Sound_Player.sound_mutex);
    stream.*.internal_flags |= .FADING_OUT;
    unlock(*Sound_Player.sound_mutex);
    stream.* = null;
}

set_sound_volume :: (stream: *Sound_Player.Sound_Stream, volume: float) {
    if stream == null return;

    if volume < 0.0 volume = 0.0;

    lock(*Sound_Player.sound_mutex);
    stream.user_volume_scale = volume;
    unlock(*Sound_Player.sound_mutex);
}


update_listener_orientation :: (position: Vector3, yaw: float) {
    yaw_quat: Quaternion;
    set_from_axis_and_angle(*yaw_quat, 0, 0, 1, -yaw);

    rotation_y: Quaternion;
    set_from_axis_and_angle(*rotation_y, 0, 1, 0, PI/2);

    rotation_z: Quaternion;
    set_from_axis_and_angle(*rotation_z, 0, 0, 1, PI/2);

    correction_quat := rotation_z * rotation_y;
    listener_orientation := yaw_quat * correction_quat;

    Sound_Player.update_listener(position, listener_orientation);
}
