//imports
const std = @import("std");
const c = @import("std").c;
const audio = @import("audio_engine");
const song_db = @import("song_db");

//easy print
const print = std.debug.print;

const songInfo = struct {
    file_path: [:0]const u8,
};

//function for thread that handles background tasks like
fn player_logic(
    mutex: *std.Io.Mutex,
    io: std.Io,
    allocator: std.mem.Allocator,
    audio_engine: *audio.audioEngine,
    song_db_data: *song_db.songDbInfo,
    song_queue: *std.Deque(songInfo),
) !void {
    //need to change the check from true to a flag triggered by the main thread when program is closed
    var song_num: c_int = 1;
    var song_info: songInfo = undefined;
    while (audio_engine.engine_on) {
        if (audio_engine.song_source != null) {
            //sleep to lower polling rate (should change to better way)
            io.sleep(.fromMilliseconds(100), .awake) catch {};
            //checks for end of song and changes next song link
            //will probbably move to audio thead
            var total_frames: audio.mini.ma_uint64 = 0;
            var current_frame: audio.mini.ma_uint64 = 0;
            _ = audio.mini.ma_data_source_get_length_in_pcm_frames(audio_engine.song_source, &total_frames);
            _ = audio.mini.ma_data_source_get_cursor_in_pcm_frames(audio_engine.song_source, &current_frame);

            //TODO: add error handling
            if (current_frame >= total_frames) {
                //lock mutex to edit mulit thread variables
                mutex.lock(io) catch return;
                defer mutex.unlock(io);

                //deallocate original song memory and set source to current
                const temp = audio_engine.song_source.?;
                audio_engine.song_source = audio_engine.song_source_next;
                _ = audio.mini.ma_resource_manager_data_source_uninit(temp);
                allocator.destroy(temp);

                //set next to next from queue
                audio_engine.song_source_next = try allocator.create(audio.mini.ma_resource_manager_data_source);
                const song_data = song_queue.popFront().?;
                defer allocator.free(song_data.file_path);
                _ = audio.mini.ma_resource_manager_data_source_init(&audio_engine.resource_manager, song_data.file_path, 0, 0, audio_engine.song_source_next);
                _ = audio.mini.ma_data_source_set_next(audio_engine.song_source, audio_engine.song_source_next);
                song_info.file_path = song_db_data.getSongAddress(allocator, song_num);
                try song_queue.pushBack(allocator, song_info);
                song_num += 1;
                if (song_num > song_db_data.num_songs) {
                    song_num = 1;
                }
            }
        } else if (song_db_data.num_songs >= 1) {
            //lock mutex to edit mulit thread variables
            mutex.lock(io) catch return;
            defer mutex.unlock(io);
            const song1 = song_db_data.getSongAddress(allocator, song_num);
            defer allocator.free(song1);
            song_num += 1;
            if (song_num > song_db_data.num_songs) {
                song_num = 1;
            }

            const song2 = song_db_data.getSongAddress(allocator, song_num);
            defer allocator.free(song1);
            song_num += 1;
            if (song_num > song_db_data.num_songs) {
                song_num = 1;
            }

            try audio_engine.songInit(allocator, song1, song2);

            song_info.file_path = song_db_data.getSongAddress(allocator, song_num);

            try song_queue.pushBack(allocator, song_info);
            song_num += 1;
            if (song_num > song_db_data.num_songs) {
                song_num = 1;
            }
        }
    }
}

//StaticStringMap(varibale type) -> creates a optimized map for string to value lut
//underlying optimization mapas strings to length and only searches strings that have same length as input
const MusicMenuLut = std.StaticStringMap(u32).initComptime(.{
    .{ "play", 1 },
    .{ "volume", 2 },
    .{ "zip", 3 },
    .{ "add song", 4 },
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
    var add_song_path: []u8 = undefined;
    var vol_string: []u8 = undefined;
    var input_value: u32 = 0;
    var vol: i32 = 0;

    var song_queue = try std.Deque(songInfo).initCapacity(allocator, 10);
    defer song_queue.deinit(allocator);

    //TEMP: replace db_path with absolute path
    //will make relative path work eventually
    var song_db_data = song_db.songDbInfo{
        .db_path = "",
        .num_songs = 0,
    };

    song_db_data.initDatabase();

    //miniaudio
    var audio_engine: audio.audioEngine = undefined;
    try audio_engine.init();

    const player_logic_thread = try std.Thread.spawn(.{}, player_logic, .{
        &mutex,
        io,
        allocator,
        &audio_engine,
        &song_db_data,
        &song_queue,
    });

    print("Digiman Menu:\n", .{});
    print("Commands: play, volume, zip, add song, exit\n", .{});
    while (input_value != 5) {
        //read from command line up to a delimiter you set and then advances the cursor past it
        input_command = try stdin.takeDelimiter('\n') orelse break;
        print("\x1B[1A\x1B[2K\r", .{}); //clears line
        input_value = MusicMenuLut.get(input_command) orelse break;

        switch (input_value) {
            1 => {
                mutex.lock(io) catch return;
                defer mutex.unlock(io);
                audio_engine.playButton();
            },
            2 => {
                mutex.lock(io) catch return;
                defer mutex.unlock(io);
                vol_string = try stdin.takeDelimiter('\n') orelse break;
                print("\x1B[1A\x1B[2K\r", .{}); //clears line
                vol = try std.fmt.parseInt(i32, vol_string, 10);
                audio.set_volume(&audio_engine.device, vol);
            },
            3 => {
                mutex.lock(io) catch return;
                defer mutex.unlock(io);
                audio.skip(&audio_engine.device, audio_engine.song_source);
            },
            4 => {
                mutex.lock(io) catch return;
                defer mutex.unlock(io);
                add_song_path = try stdin.takeDelimiter('\n') orelse break;

                //adds a null terminator for sqlite3 compatability
                const end_index = add_song_path.len;
                add_song_path.ptr[end_index] = 0;
                const song_path = add_song_path.ptr[0..end_index :0];
                print("\x1B[1A\x1B[2K\r", .{}); //clears line
                song_db_data.addSong(song_path);
            },
            5 => {
                mutex.lock(io) catch return;
                defer mutex.unlock(io);
                audio_engine.engine_on = false;
                _ = audio.mini.ma_device_stop(&audio_engine.device);
            },
            else => {
                input_value = 0;
            },
        }
    }

    player_logic_thread.join();

    audio_engine.deinit(allocator);

    print("Exiting Digiman\n", .{});
}
