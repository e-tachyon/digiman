const std = @import("std");

//adds executable with options
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //adds a c header file to be translated and compiled in zig
    const miniaudio = b.addTranslateC(.{
        .root_source_file = b.path("third-party/miniaudio/mini_imp.h"),
        .target = target,
        .optimize = optimize,
    });

    const sqlite3 = b.addTranslateC(.{
        .root_source_file = b.path("third-party/sqlite/sqlite3.h"),
        .target = target,
        .optimize = optimize,
    });

    const taglib = b.addTranslateC(.{
        .root_source_file = b.path("third-party/taglib_wrapper/taglib_wrapper.h"),
        .target = target,
        .optimize = optimize,
    });

    const song_db = b.createModule(.{
        .root_source_file = b.path("src/song_db.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{
                .name = "sqlite3",
                .module = sqlite3.createModule(),
            },
            .{
                .name = "taglib",
                .module = taglib.createModule(),
            },
        },
    });

    const audio_engine = b.createModule(.{
        .root_source_file = b.path("src/audio_engine.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{
                .name = "miniaudio",
                .module = miniaudio.createModule(),
            },
        },
    });

    //adds executable and allows you to select options like optimizations and libc
    //imports lets you add modules (added c files there)
    const exe = b.addExecutable(.{
        .name = "digiman",
        .root_module = b.createModule(.{ //defines moudule variables (target, optimizaton)
            .root_source_file = b.path("src/digiman.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    exe.root_module.addImport("song_db", song_db);
    exe.root_module.addImport("audio_engine", audio_engine);

    //adds c source file to go to be compiled with exe module
    exe.root_module.addCSourceFile(.{
        .file = b.path("third-party/miniaudio/mini_imp.c"),
        .flags = &.{"-std=c99"},
    });

    song_db.addCSourceFile(.{
        .file = b.path("third-party/sqlite/sqlite3.c"),
        .flags = &.{"-std=c99"},
    });

    song_db.addCSourceFile(.{
        .file = b.path("third-party/taglib_wrapper/taglib_wrapper.c"),
        .flags = &.{"-std=c99"},
    });

    //adds required includes and system libraries for c files (need to look up some for ones like mini)
    audio_engine.addIncludePath(b.path("third-party/miniaudio/"));
    song_db.addIncludePath(b.path("third-party/sqlite/"));
    song_db.addIncludePath(b.path("third-party/taglib/"));
    exe.root_module.linkSystemLibrary("m", .{});
    exe.root_module.linkSystemLibrary("pthread", .{});
    exe.root_module.linkSystemLibrary("tag_c", .{});
    exe.root_module.linkSystemLibrary("taglib", .{});

    //creates executable
    b.installArtifact(exe);

    //allows for running in main
    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);
}
