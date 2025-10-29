const std = @import("std");

// for SDL
const usr_include_path = "/usr/include/";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = std.builtin.OptimizeMode.Debug;

    const dep_movy = b.dependency("movy", .{ .video = true });
    const mod_movy = dep_movy.module("movy");
    const mod_movy_video = dep_movy.module("movy_video");

    const dep_flagz = b.dependency("flagz", .{});
    const mod_flagz = dep_flagz.module("flagz");

    const name = "movycat";

    const movycat_mod = b.addModule(name, .{
        .root_source_file = b.path("src/movycat.zig"),
        .target = target,
        .optimize = optimize,
    });
    movycat_mod.addIncludePath(.{ .cwd_relative = usr_include_path });
    movycat_mod.addImport("movy", mod_movy);
    movycat_mod.addImport("movy_video", mod_movy_video);
    movycat_mod.addImport("flagz", mod_flagz);
    movycat_mod.linkSystemLibrary("SDL2", .{});

    const movycat_exe = b.addExecutable(.{
        .name = name,
        .root_module = movycat_mod,
    });
    b.installArtifact(movycat_exe);

    // Add run step
    const run_movycat = b.addRunArtifact(movycat_exe);
    run_movycat.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_movycat.addArgs(args);
    b.step(
        b.fmt("run-{s}", .{name}),
        b.fmt("Run {s}", .{name}),
    ).dependOn(&run_movycat.step);
}
