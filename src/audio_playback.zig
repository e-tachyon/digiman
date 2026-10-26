//imports
const std = @import("std");
const c = @import("std").c;
const mini = @import("miniaudio");
const sqlite3 = @import("miniaudio");

//consts to shorten things
const Io = std.Io;
const print = std.debug.print;
var song_finish: bool = false;

fn song_link(
    song_player: songPlayer,
) void {
    var song_s0 = song_player.;
    const song_s1 = song_source_next;
    while (true) {
        if (song_finish) {
            _ = mini.ma_device_stop(device);
            const temp = song_s0;
            song_s0 = song_s1;
            _ = mini.ma_resource_manager_data_source_uninit(temp);
            _ = mini.ma_resource_manager_data_source_init(resource_manager, song_queue.popFront().?, 0, 0, song_s1);
            _ = mini.ma_data_source_set_next(song_s0, song_s1);
            _ = mini.ma_device_start(device);
        }
    }
}

const songPlayer = struct {
    mutex: std.IO.mutex = .{},
    io: std.io,
    device: *mini.ma_device,
    song_queue: *std.Deque([*c]const u8),
    song_source: *mini.ma_resource_manager_data_source,
    song_source_next: *mini.ma_resource_manager_data_source,
    resource_manager: *mini.ma_resource_manager,
};

//StaticStringMap(varibale type) -> creates a optimized map for string to value lut
//underlying optimization mapas strings to length and only searches strings that have same length as input
const MusicMenuLut = std.StaticStringMap(u32).initComptime(.{
    .{ "play", 1 },
    .{ "pause", 2 },
    .{ "exit", 3 },
    .{ "zip", 4 },
    .{ "volume", 5 },
});

//main
pub fn main(init: std.process.Init) !void {
    //const io = init.io;

    const allocator = init.arena.allocator();

    //buffer for io reader
    var buffer: [1024]u8 = undefined;

    //vars are variables that are not static
    //const are unchanging variables
    var input_command: []u8 = undefined;
    var input_value: u32 = 0;

    var song_queue = try std.Deque([*c]const u8).initCapacity(allocator, 10);
    defer song_queue.deinit(allocator);

    try song_queue.pushBack(allocator, "");
    try song_queue.pushBack(allocator, "");
    try song_queue.pushBack(allocator, "");

    //connection to terminal -> treated like reading a file
    var stdin_reader = std.Io.File.stdin().reader(init.io, &buffer);
    const stdin = &stdin_reader.interface;

    //miniaudio
    var song_source: mini.ma_resource_manager_data_source = undefined;
    var song_source_next: mini.ma_resource_manager_data_source = undefined;
    var device_config: mini.ma_device_config = undefined;
    var device: mini.ma_device = undefined;
    var resource_manager: mini.ma_resource_manager = undefined;
    var resource_manager_config: mini.ma_resource_manager_config = undefined;
    //var total_frames: mini.ma_uint64 = undefined;

    //miniaudio defined funcions being used in zig
    //use mini.[function, struct, ect] to use c code from another lib
    device_config = mini.ma_device_config_init(mini.ma_device_type_playback);
    device_config.playback.format = mini.ma_format_f32;
    device_config.playback.channels = 2;
    device_config.sampleRate = 44100;
    device_config.dataCallback = dataCallback;
    device_config.pUserData = &song_source;
    _ = mini.ma_device_init(null, &device_config, &device);
    _ = mini.ma_device_set_master_volume(&device, 0.1);
    resource_manager_config = mini.ma_resource_manager_config_init();
    resource_manager_config.decodedFormat = device.playback.format;
    resource_manager_config.decodedChannels = device.playback.channels;
    resource_manager_config.decodedSampleRate = device.sampleRate;
    _ = mini.ma_resource_manager_init(&resource_manager_config, &resource_manager);

    //? says value could be null, temp .? to force non ? value for testing
    _ = mini.ma_resource_manager_data_source_init(&resource_manager, song_queue.popFront().?, 0, 0, &song_source);
    _ = mini.ma_resource_manager_data_source_init(&resource_manager, song_queue.popFront().?, 0, 0, &song_source_next);

    _ = mini.ma_data_source_set_next(&song_source, &song_source_next);
    _ = mini.ma_device_start(&device);

    var total_frames: mini.ma_uint64 = 0;

    const thread = try std.Thread.spawn(.{}, song_link, .{ &device, &song_queue, &song_source, &song_source_next, &resource_manager });

    print("Digiman Menu:\n", .{});
    print("Commands: play, pause, exit, zip\n", .{});
    while (input_value != 3) {
        //read from commandline up to a delimiter you set and then advances the cursor past it
        input_command = try stdin.takeDelimiter('\n') orelse break;
        print("\x1B[1A\x1B[2K\r", .{});
        input_value = MusicMenuLut.get(input_command) orelse break;

        switch (input_value) {
            1 => {
                _ = mini.ma_device_start(&device);
            },
            2 => {
                _ = mini.ma_device_stop(&device);
            },
            3 => {
                input_value = 3;
            },
            4 => {
                _ = mini.ma_device_stop(&device);
                _ = mini.ma_data_source_get_length_in_pcm_frames(&song_source, &total_frames);
                _ = mini.ma_data_source_seek_to_pcm_frame(&song_source, total_frames);
                _ = mini.ma_device_start(&device);
            },
            else => {
                input_value = 0;
                print("Not a Command\n", .{});
            },
        }
    }

    thread.join();
    _ = mini.ma_resource_manager_data_source_uninit(&song_source);
    _ = mini.ma_resource_manager_data_source_uninit(&song_source_next);
    _ = mini.ma_device_stop(&device);
    _ = mini.ma_device_uninit(&device);
    _ = mini.ma_resource_manager_uninit(&resource_manager);

    print("Exiting Digiman\n", .{});
}

//defining c function in zig
//use compatable variable types -> do this for all c code included in zig
pub fn dataCallback(
    pDevice: [*c]mini.ma_device,
    pOutput: ?*anyopaque,
    pInput: ?*const anyopaque,
    frameCount: mini.ma_uint32,
) callconv(.c) void {
    _ = pInput;
    var frames_read: mini.ma_uint64 = 0;
    _ = mini.ma_data_source_read_pcm_frames(@ptrCast(pDevice.*.pUserData), pOutput, frameCount, &frames_read);
    if (frames_read < frameCount) {
        song_finish = true;
    }
    song_finish = false;
}
