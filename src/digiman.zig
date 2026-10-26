//imports
const std = @import("std");
const c = @import("std").c;
const mini = @import("miniaudio");

const print = std.debug.print;

const songPlayer = struct {
    device: [*c]mini.ma_device,
    song_queue: *std.Deque([*c]const u8),
    song_source: [*c]mini.ma_resource_manager_data_source,
    song_source_next: [*c]mini.ma_resource_manager_data_source,
    resource_manager: [*c]mini.ma_resource_manager,
};

fn thread_test(mutex: *std.Io.Mutex, io: std.Io, allocator: std.mem.Allocator, song_player: *songPlayer) !void {
    //need to change the check from true to a flag triggered by the main thread when program is closed
    while (true) {
        //sleep to lower polling rate (should change to better way)
        io.sleep(.fromMilliseconds(100), .awake) catch {};
        //checks for end of song and changes next song link
        //will probbably move to audio thead
        var total_frames: mini.ma_uint64 = 0;
        var current_frame: mini.ma_uint64 = 0;
        _ = mini.ma_data_source_get_length_in_pcm_frames(song_player.song_source, &total_frames);
        _ = mini.ma_data_source_get_cursor_in_pcm_frames(song_player.song_source, &current_frame);

        //TODO: add error handling
        if (current_frame >= total_frames) {
            //lock mutex to edit mulit thread variables
            mutex.lock(io) catch return;
            defer mutex.unlock(io);

            //deallocate original song memory and set source to current
            const temp = song_player.song_source;
            song_player.song_source = song_player.song_source_next;
            _ = mini.ma_resource_manager_data_source_uninit(temp);

            //set next to next from queue
            const song_loc = song_player.song_queue.popFront().?;
            song_player.song_source_next = try allocator.create(mini.ma_resource_manager_data_source);
            _ = mini.ma_resource_manager_data_source_init(song_player.resource_manager, song_loc, 0, 0, song_player.song_source_next);
            _ = mini.ma_data_source_set_next(song_player.song_source, song_player.song_source_next);
        }
    }
}

//StaticStringMap(varibale type) -> creates a optimized map for string to value lut
//underlying optimization mapas strings to length and only searches strings that have same length as input
const MusicMenuLut = std.StaticStringMap(u32).initComptime(.{
    .{ "play", 1 },
    .{ "pause", 2 },
    .{ "volume", 3 },
    .{ "zip", 4 },
    .{ "exit", 5 },
});

//main
pub fn main(init: std.process.Init) !void {
    //mutex and io for communication between threads and tasks
    const io = init.io;
    var mutex: std.Io.Mutex = .init;

    //allocator -- can chose multiple types, should look at that later
    const allocator = init.arena.allocator();

    var buffer: [1024]u8 = undefined;
    //connection to terminal -> treated like reading a file
    var stdin_reader = std.Io.File.stdin().reader(init.io, &buffer);
    const stdin = &stdin_reader.interface;

    //vars are variables that are not static
    //const are unchanging variables
    var input_command: []u8 = undefined;
    var input_value: u32 = 0;

    var song_queue = try std.Deque([*c]const u8).initCapacity(allocator, 10);
    defer song_queue.deinit(allocator);

    try song_queue.pushBack(allocator, "/home/gogurt/Music/songs/me_&_u.mp3");
    try song_queue.pushBack(allocator, "/home/gogurt/Music/songs/not_for_sale_fossil.mp3");
    try song_queue.pushBack(allocator, "/home/gogurt/Music/songs/worst_regret_sped_up.mp3");
    try song_queue.pushBack(allocator, "/home/gogurt/Music/songs/TAIDADA.mp3");
    try song_queue.pushBack(allocator, "/home/gogurt/Music/songs/summer_fever.mp3");

    //miniaudio
    var device_config: mini.ma_device_config = undefined;
    var resource_manager_config: mini.ma_resource_manager_config = undefined;

    const song_player = try allocator.create(songPlayer);
    song_player.* = songPlayer{
        .device = try allocator.create(mini.ma_device),
        .song_queue = &song_queue,
        .song_source = try allocator.create(mini.ma_resource_manager_data_source),
        .song_source_next = try allocator.create(mini.ma_resource_manager_data_source),
        .resource_manager = try allocator.create(mini.ma_resource_manager),
    };

    //miniaudio defined funcions being used in zig
    //use mini.[function, struct, ect] to use c code from another lib
    device_config = mini.ma_device_config_init(mini.ma_device_type_playback);
    device_config.playback.format = mini.ma_format_f32;
    device_config.playback.channels = 2;
    device_config.sampleRate = 44100;
    device_config.dataCallback = dataCallback;
    device_config.pUserData = song_player;
    _ = mini.ma_device_init(null, &device_config, song_player.device);
    _ = mini.ma_device_set_master_volume(song_player.device, 0.1);
    resource_manager_config = mini.ma_resource_manager_config_init();
    resource_manager_config.decodedFormat = song_player.device.*.playback.format;
    resource_manager_config.decodedChannels = song_player.device.*.playback.channels;
    resource_manager_config.decodedSampleRate = song_player.device.*.sampleRate;
    _ = mini.ma_resource_manager_init(&resource_manager_config, song_player.resource_manager);

    //? says value could be null, temp .? to force non ? value for testing
    _ = mini.ma_resource_manager_data_source_init(song_player.resource_manager, song_queue.popFront().?, 0, 0, song_player.song_source);
    _ = mini.ma_resource_manager_data_source_init(song_player.resource_manager, song_queue.popFront().?, 0, 0, song_player.song_source_next);

    var total_frames: mini.ma_uint64 = 0;

    _ = mini.ma_data_source_set_next(song_player.song_source, song_player.song_source_next);
    _ = mini.ma_device_start(song_player.device);

    const thread = try std.Thread.spawn(.{}, thread_test, .{ &mutex, io, allocator, song_player });

    print("Digiman Menu:\n", .{});
    print("Commands: play, pause, exit, zip\n", .{});
    while (input_value != 5) {
        //read from command line up to a delimiter you set and then advances the cursor past it
        input_command = try stdin.takeDelimiter('\n') orelse break;
        print("\x1B[1A\x1B[2K\r", .{});
        input_value = MusicMenuLut.get(input_command) orelse break;

        switch (input_value) {
            1 => {
                _ = mini.ma_device_start(song_player.device);
            },
            2 => {
                _ = mini.ma_device_stop(song_player.device);
            },
            3 => {},
            4 => {
                _ = mini.ma_data_source_get_length_in_pcm_frames(song_player.song_source, &total_frames);
                _ = mini.ma_device_stop(song_player.device);
                _ = mini.ma_data_source_get_length_in_pcm_frames(song_player.song_source, &total_frames);
                _ = mini.ma_device_start(song_player.device);
            },
            5 => {
                input_value = 5;
                _ = mini.ma_device_stop(song_player.device);
            },
            else => {
                input_value = 0;
                print("Not a Command\n", .{});
            },
        }
    }

    thread.join();
    _ = mini.ma_resource_manager_data_source_uninit(song_player.song_source);
    _ = mini.ma_resource_manager_data_source_uninit(song_player.song_source);
    _ = mini.ma_device_stop(song_player.device);
    _ = mini.ma_device_uninit(song_player.device);
    _ = mini.ma_resource_manager_uninit(song_player.resource_manager);

    _ = allocator.destroy(song_player);

    //allocator.destroy(song_player.song_source);
    //allocator.destroy(song_player.song_source);

    print("Exiting Digiman\n", .{});
}

pub fn dataCallback(
    pDevice: [*c]mini.ma_device,
    pOutput: ?*anyopaque,
    pInput: ?*const anyopaque,
    frameCount: mini.ma_uint32,
) callconv(.c) void {
    _ = pInput;

    //need to understand this section more
    const user_data = pDevice.*.pUserData orelse return;
    const aligned_opaque: *align(@alignOf(songPlayer)) anyopaque = @alignCast(user_data);
    const song_player: *songPlayer = @ptrCast(aligned_opaque);
    //end section

    var frames_read: mini.ma_uint64 = 0;
    _ = mini.ma_data_source_read_pcm_frames(song_player.song_source, pOutput, frameCount, &frames_read);
}
