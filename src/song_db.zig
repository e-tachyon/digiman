const std = @import("std");
const c = @import("std").c;
const sqlite3 = @import("sqlite3");

const songDb = struct {
    db_path: [*c]const u8,
    conn: [*c]sqlite3,
};

pub fn initDatabase(db_path: [*c]const u8, conn: [*c]sqlite3) void {
    var conn_check: i32 = 0;
    conn_check = sqlite3.sqlite3_open(db_path, conn);

    var error_message: [*c]u8 = undefined;

    const create_table: [*c]u8 = "CREATE TABLE IF NOT EXISTS songs(song_number INTEGER PRIMARY KEY AUTOINCREMENT, song_name varchar(255), file_address varchar(255));";
    var create_check: i32 = 0;

    create_check = sqlite3.sqlite3_exec(conn, create_table, null, 0, &error_message);

    if (create_check != sqlite3.SQLITE_OK) {
        sqlite3.sqlite3_free(error_message);
    }

    sqlite3.sqlite3_close(conn);
}

pub fn addSong(db_path: [*c]const u8, conn: [*c]sqlite3, song_address: [*c]const u8) void {
    var conn_check: i32 = 0;
    conn_check = sqlite3.sqlite3_open(db_path, conn);

    if (conn_check) {
        return;
    }

    const insert_song: [*c]u8 = "INSERT INTO songs(song_name, file_address) VALUES (?, ?);";
    var insert_stmt: [*c]sqlite3.sqlite3_stmt = null;
    var insert_check: u32 = undefined;

    insert_check = sqlite3.sqlite3_prepare_v2(conn, insert_song, -1, &insert_stmt, null);

    if (insert_check != sqlite3.SQLITE_OK) {
        return;
    }

    const song_title = "song title";

    sqlite3.sqlite3_bind_text(insert_stmt, 1, song_title, -1, sqlite3.SQLITE_STATIC);
    sqlite3.sqlite3_bind_text(insert_stmt, 2, song_address, -1, sqlite3.SQLITE_STATIC);

    sqlite3.sqlite3_step(insert_stmt);
    sqlite3.sqlite3_finalize(insert_stmt);

    sqlite3.sqlite3_close(conn);
    return;
}
