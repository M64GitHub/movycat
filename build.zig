const std = @import("std");

// for SDL
const usr_include_path = "/usr/include/";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = std.builtin.OptimizeMode.ReleaseFast;

    const dep_movy = b.dependency("movy", .{});
    const mod_movy = dep_movy.module("movy");

    const dep_movy_video = b.dependency("movy_video", .{});
    const mod_movy_video = dep_movy_video.module("movy_video");

    const dep_flagz = b.dependency("flagz", .{});
    const mod_flagz = dep_flagz.module("flagz");

    const name = "movycat";

    const movycat_exe = b.addExecutable(.{
        .name = name,
        .root_source_file = b.path("src/movycat.zig"),
        .target = target,
        .optimize = optimize,
    });
    movycat_exe.addIncludePath(.{ .cwd_relative = usr_include_path });
    movycat_exe.root_module.addImport("movy", mod_movy);
    movycat_exe.root_module.addImport("movy_video", mod_movy_video);
    movycat_exe.root_module.addImport("flagz", mod_flagz);
    movycat_exe.linkSystemLibrary("SDL2");
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
