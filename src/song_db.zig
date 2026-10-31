const std = @import("std");
const c = @import("std").c;
const sqlite3 = @import("sqlite3");
const taglib = @import("taglib");

//TODO: NEED TO ADD CHECKS FOR INCORRECT FILE TYPES AND NEED TO IMPLEMENT ERROR HANDLING
pub const songDbInfo = struct {
    db_path: [:0]const u8,
    num_songs: i32,

    //initialize database if the db does not exist
    pub fn initDatabase(self: *@This()) void {
        //?* to say a pointer to be nullable
        var conn: ?*sqlite3.sqlite3 = null;
        var conn_check: i32 = 0;
        conn_check = sqlite3.sqlite3_open(self.db_path, &conn);

        var error_message: [*c]u8 = null;

        const create_table = "CREATE TABLE IF NOT EXISTS songs(song_number INTEGER PRIMARY KEY AUTOINCREMENT, song_name varchar(255), file_address varchar(255));";
        var create_check: i32 = 0;

        create_check = sqlite3.sqlite3_exec(conn, create_table, null, null, &error_message);

        if (create_check != sqlite3.SQLITE_OK) {
            if (error_message != null) {
                _ = sqlite3.sqlite3_free(error_message);
            }
        }

        var insert_stmt: ?*sqlite3.sqlite3_stmt = null;
        const get_count = "SELECT COUNT(*) FROM songs;";
        const get_count_check = sqlite3.sqlite3_prepare_v2(conn, get_count, -1, &insert_stmt, null);
        if (get_count_check != sqlite3.SQLITE_OK) {
            return;
        }
        _ = sqlite3.sqlite3_step(insert_stmt);
        const count = sqlite3.sqlite3_column_int(insert_stmt, 0);
        self.num_songs = count;
        _ = sqlite3.sqlite3_finalize(insert_stmt);

        _ = sqlite3.sqlite3_close(conn);
    }

    //adds a song to the database: takes a file location
    //TODO: add checks for file type to ensure non mp3 and wav files cannot be added
    pub fn addSong(self: *@This(), song_address: [:0]const u8) void {
        var conn: ?*sqlite3.sqlite3 = null;
        var conn_check: i32 = 0;
        conn_check = sqlite3.sqlite3_open(self.db_path, &conn);

        const insert_song = "INSERT INTO songs(song_name, file_address) VALUES (?, ?);";
        var insert_stmt: ?*sqlite3.sqlite3_stmt = null;

        const insert_check = sqlite3.sqlite3_prepare_v2(conn, insert_song, -1, &insert_stmt, null);

        if (insert_check != sqlite3.SQLITE_OK) {
            return;
        }
        const song_file: [*c]taglib.TagLib_File = taglib.taglib_file_new(song_address);
        const song_tags: [*c]taglib.TagLib_Tag = taglib.taglib_file_tag(song_file);
        const song_title = taglib.taglib_tag_title(song_tags);

        _ = sqlite3.sqlite3_bind_text(insert_stmt, 1, song_title, -1, sqlite3.SQLITE_STATIC);
        _ = sqlite3.sqlite3_bind_text(insert_stmt, 2, song_address, -1, sqlite3.SQLITE_STATIC);

        _ = sqlite3.sqlite3_step(insert_stmt);
        _ = sqlite3.sqlite3_finalize(insert_stmt);

        const get_count = "SELECT COUNT(*) FROM songs;";
        const get_count_check = sqlite3.sqlite3_prepare_v2(conn, get_count, -1, &insert_stmt, null);
        if (get_count_check != sqlite3.SQLITE_OK) {
            return;
        }
        _ = sqlite3.sqlite3_step(insert_stmt);
        const count = sqlite3.sqlite3_column_int(insert_stmt, 0);
        self.num_songs = count;
        _ = sqlite3.sqlite3_finalize(insert_stmt);

        _ = sqlite3.sqlite3_close(conn);
        return;
    }

    //returns a song address from the database
    //TODO: add checks for a faulty return
    //also look at allocation and see if an alternative exists
    pub fn getSongAddress(self: *@This(), allocator: std.mem.Allocator, song_num: c_int) [:0]const u8 {
        var song_address: [*c]const u8 = null;
        var conn: ?*sqlite3.sqlite3 = null;
        var conn_check: i32 = 0;
        conn_check = sqlite3.sqlite3_open(self.db_path, &conn);

        const select_song = "SELECT file_address FROM songs WHERE song_number = ?;";
        var select_stmt: ?*sqlite3.sqlite3_stmt = null;
        const select_check = sqlite3.sqlite3_prepare_v2(conn, select_song, -1, &select_stmt, null);

        if (select_check == sqlite3.SQLITE_OK) {
            _ = sqlite3.sqlite3_bind_int(select_stmt, 1, song_num);
            const row_check = sqlite3.sqlite3_step(select_stmt);

            if (row_check == sqlite3.SQLITE_ROW) {
                song_address = sqlite3.sqlite3_column_text(select_stmt, 0);
            }
        }

        if (song_address == null) return "";

        //takes returned c pointer and dupes into an allocated block
        //for return so the string exists outside of function stack
        //dupeZ creates string with a null terminator to match a c string
        const slice = allocator.dupeZ(u8, std.mem.span(song_address)) catch return "";
        _ = sqlite3.sqlite3_finalize(select_stmt);
        _ = sqlite3.sqlite3_close(conn);

        return slice;
    }
};
