const std = @import("std");
const movy = @import("movy");
const movy_video = @import("movy_video");
const flagz = @import("flagz");

const stdout = std.io.getStdOut().writer();

var target_width: usize = 140;
var target_height: usize = 100;

pub fn printUsage() void {
    stdout.print(
        \\Usage:
        \\
        \\movycat -file <filename> [-width <width> -height <height>]
        \\
    , .{}) catch {};
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .verbose_log = true,
    }){};

    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Parse args
    const Args = struct {
        file: []const u8,
        width: ?usize,
        height: ?usize,
    };

    const args = try flagz.parse(Args, allocator);
    defer flagz.deinit(args, allocator);

    if (args.file.len == 0) {
        return printUsage();
    }

    // set size

    const term_dimensions = try movy.terminal.getSize();
    target_width = term_dimensions.width;
    target_height = term_dimensions.height * 2 - 2;

    if (args.width) |width| {
        if (width < target_width) target_width = width;
    }
    if (args.height) |height| {
        if (height < target_height) target_height = height;
    }

    // -- Setup movy screen
    try movy.terminal.beginRawMode();
    defer movy.terminal.endRawMode();
    try movy.terminal.beginAlternateScreen();
    defer movy.terminal.endAlternateScreen();

    var screen = try movy.Screen.init(
        allocator,
        target_width,
        target_height / 2,
    );
    defer screen.deinit(allocator);

    screen.setScreenMode(movy.Screen.Mode.transparent);

    // -- init render surface for output, and add to screen
    var surface = try movy.RenderSurface.init(
        allocator,
        target_width,
        target_height,
        movy.core.types.Rgb{ .r = 0xff, .g = 0, .b = 0 },
    );
    defer surface.deinit(allocator);

    surface.x = 0;
    surface.y = 0;

    try screen.addRenderSurface(surface);

    // -- Open movie

    const decoder = try movy_video.VideoDecoder.init(
        allocator,
        args.file,
        surface,
    );
    defer decoder.deinit();

    // Play!
    while (true) {
        // Try reading input every frame
        if (try movy.input.get()) |event| {
            switch (event) {
                .key => |key| {
                    if (key.type == .Escape) {
                        break;
                    }
                },
                else => {},
            }
        }

        // Perform one decoding step
        // This plays audio or fills the RenderSurface
        const result = try decoder.update();
        if (result.eof) break;

        if (result.video_rendered) {
            screen.render();
            try screen.output();
        }
    }
}
