const std = @import("std");
const c = @import("std").c;
pub const mini = @import("miniaudio");

//miniaudios playback function
//takes pointer to audio engine
pub fn dataCallback(
    pDevice: [*c]mini.ma_device,
    pOutput: ?*anyopaque,
    pInput: ?*const anyopaque,
    frameCount: mini.ma_uint32,
) callconv(.c) void {
    _ = pInput;

    //need to understand this section more
    const user_data = pDevice.*.pUserData orelse return;
    const aligned_opaque: *align(@alignOf(audioEngine)) anyopaque = @alignCast(user_data);
    const audio_engine: *audioEngine = @ptrCast(aligned_opaque);
    //end section

    var frames_read: mini.ma_uint64 = 0;
    _ = mini.ma_data_source_read_pcm_frames(audio_engine.song_source, pOutput, frameCount, &frames_read);
}

//struct for backend of audio
//holds all nessecary info for audio playback from miniaudio
//has methods: init, songInit, playbutton, deinit
//may change to be 2 structs to lessen data passed to places and functions
pub const audioEngine = struct {
    device: mini.ma_device,
    song_source: ?*mini.ma_resource_manager_data_source,
    song_source_next: ?*mini.ma_resource_manager_data_source,
    resource_manager: mini.ma_resource_manager,
    device_config: mini.ma_device_config,
    resource_manager_config: mini.ma_resource_manager_config,
    playing: bool,
    engine_on: bool,

    //inits all variables in audioEngine
    //keeps song_source, song_source_next null in the case of no songs in db
    //READD ALLOCATOR AND CHANGE POINTERS TO *?
    pub fn init(self: *@This()) !void {
        self.playing = false;
        self.engine_on = true;
        self.song_source = null;
        self.song_source_next = null;
        self.device_config = mini.ma_device_config_init(mini.ma_device_type_playback);
        self.device_config.playback.format = mini.ma_format_f32;
        self.device_config.playback.channels = 2;
        self.device_config.sampleRate = 44100;
        self.device_config.dataCallback = dataCallback;
        self.device_config.pUserData = self;
        _ = mini.ma_device_init(null, &self.device_config, &self.device);
        _ = mini.ma_device_set_master_volume(&self.device, 0.1);
        self.resource_manager_config = mini.ma_resource_manager_config_init();
        self.resource_manager_config.decodedFormat = self.device.playback.format;
        self.resource_manager_config.decodedChannels = self.device.playback.channels;
        self.resource_manager_config.decodedSampleRate = self.device.sampleRate;
        _ = mini.ma_resource_manager_init(&self.resource_manager_config, &self.resource_manager);
        return;
    }

    //inits songs when there is 1 avalible
    pub fn songInit(self: *@This(), allocator: std.mem.Allocator, song1: [:0]const u8, song2: [:0]const u8) !void {
        self.song_source = try allocator.create(mini.ma_resource_manager_data_source);
        self.song_source_next = try allocator.create(mini.ma_resource_manager_data_source);
        _ = mini.ma_resource_manager_data_source_init(&self.resource_manager, song1, 0, 0, self.song_source);
        _ = mini.ma_resource_manager_data_source_init(&self.resource_manager, song2, 0, 0, self.song_source_next);
        _ = mini.ma_data_source_set_next(self.song_source, self.song_source_next);
        return;
    }

    //plays and pauses, checks for no song (null)
    pub fn playButton(self: *@This()) void {
        if (self.playing) {
            _ = mini.ma_device_stop(&self.device);
            self.playing = false;
        } else if (self.song_source != null) {
            _ = mini.ma_device_start(&self.device);
            self.playing = true;
        }
        return;
    }

    //deinits and unallocates audioEngine
    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        const source = self.song_source;
        const source_next = self.song_source_next;
        _ = mini.ma_device_stop(&self.device);

        //checks for null
        if (source) |src| _ = mini.ma_resource_manager_data_source_uninit(src);
        if (source_next) |src| _ = mini.ma_resource_manager_data_source_uninit(src);
        if (source) |src| allocator.destroy(src);
        if (source_next) |src| allocator.destroy(src);
        _ = mini.ma_resource_manager_uninit(&self.resource_manager);
        _ = mini.ma_device_uninit(&self.device);
        return;
    }
};

//set volume, 0 to 100
pub fn set_volume(device: ?*mini.ma_device, vol_level: i32) void {
    var vol: i32 = vol_level;
    if (vol < 0) {
        vol = 0;
    } else if (vol_level > 100) {
        vol = 100;
    }

    const volume: f32 = @as(f32, @floatFromInt(vol)) * 0.01;
    _ = mini.ma_device_set_master_volume(device, volume);

    return;
}

//skips song
//TODO: find way to make it a smooth transistion
pub fn skip(device: ?*mini.ma_device, song_playing: ?*mini.ma_resource_manager_data_source) void {
    var total_frames: mini.ma_uint64 = undefined;
    _ = mini.ma_data_source_get_length_in_pcm_frames(song_playing, &total_frames);
    _ = mini.ma_device_stop(device);
    _ = mini.ma_data_source_seek_to_pcm_frame(song_playing, total_frames);
    _ = mini.ma_device_start(device);
}
