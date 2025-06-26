const std = @import("std");
const movy = @import("movy");
const movy_video = @import("movy_video");
const player = @import("movy_player.zig");
const flagz = @import("flagz");

const stdout = std.io.getStdOut().writer();

var target_width: usize = undefined;
var target_height: usize = undefined;

const SYNC_WINDOW_NS: i64 = 50_000_000;

pub fn printUsage() void {
    stdout.print(
        \\Usage:
        \\
        \\movycat -file <filename> 
        \\        [-s <startframe>] 
        \\        [-width <width> -height <height>]
        \\
    , .{}) catch {};
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        // .verbose_log = true,
    }){};

    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // -- Parse args
    const Args = struct {
        file: []const u8,
        width: ?usize,
        height: ?usize,
        s: ?usize,
    };

    const args = try flagz.parse(Args, allocator);
    defer flagz.deinit(args, allocator);

    if (args.file.len == 0) {
        return printUsage();
    }

    // -- Set output dimensions

    const term_dimensions = try movy.terminal.getSize();
    target_width = term_dimensions.width;
    target_height = term_dimensions.height * 2 - 2;

    if (args.width) |width| {
        if (width < target_width) target_width = width;
    }
    if (args.height) |height| {
        if (height < target_height) target_height = height;
    }

    var start_frame: usize = 0;
    if (args.s) |s| {
        start_frame = s;
    }

    // -- Setup movy screen
    try movy.terminal.beginRawMode();
    defer movy.terminal.endRawMode();

    // Looks cooler, when last video frame stays on screen, on exit
    // try movy.terminal.beginAlternateScreen();
    // defer movy.terminal.endAlternateScreen();

    var screen = try movy.Screen.init(
        allocator,
        target_width,
        target_height / 2,
    );
    defer screen.deinit(allocator);

    screen.setScreenMode(movy.Screen.Mode.bgcolor);

    // -- init render surface for output, and add to screen
    var surface = try movy.RenderSurface.init(
        allocator,
        target_width,
        target_height,
        movy.core.types.Rgb{ .r = 0xff, .g = 0, .b = 0 },
    );
    defer surface.deinit(allocator);

    // maybe center on screen
    surface.x = 0;
    surface.y = 0;

    try screen.addRenderSurface(surface);

    // -- Initialize the decoder
    const decoder =
        try movy_video.VideoDecoder.init(allocator, args.file, surface);
    defer decoder.deinit(allocator);

    var reached_end = false;
    var loop_ctr: usize = 0;

    var state = player.PlayerState{};

    while (!state.stop) {
        loop_ctr += 1;

        // esc input only works with raw terminal mode
        if (try movy.input.get()) |event| {
            if (event == .key and event.key.type == .Escape) {
                state.stop = true;
            }
            // Outta Space
            if (event == .key and event.key.type == .Char and
                event.key.sequence[0] == ' ')
            {
                state.togglePause(decoder);
            }
        }

        if (state.paused) {
            std.time.sleep(10_000_000);
            continue;
        }

        // FIRST: Chck if a frame is ready to render (even before decoding more)
        if (decoder.video.queue_count > 0) {
            if (decoder.video.peekFrame()) |head| {
                const playback_time_ns = decoder.getAudioClock();
                const head_pts_i64 = @as(i64, @intCast(head.pts_ns));
                const audio_i64 = @as(i64, @intCast(playback_time_ns));
                const diff = head_pts_i64 - audio_i64;

                decoder.video.pkt_ctr += 1;

                if (diff <= SYNC_WINDOW_NS and diff >= -SYNC_WINDOW_NS) {
                    if (decoder.video.popFrame()) |frame_ptr| {
                        decoder.video.frame_ctr += 1;

                        const t_before = std.time.nanoTimestamp();
                        decoder.video.renderFrameToSurface(frame_ptr, surface);
                        const t_after = std.time.nanoTimestamp();
                        const render_ns = t_after - t_before;

                        if (render_ns > 10_000_000) {
                            std.debug.print("Decoding frame took {} ns\n", .{render_ns});
                            return error.ScalingTooSlow;
                        }

                        screen.render();
                        try screen.output();

                        movy_video.VideoDecoder.freeAVFrame(frame_ptr);
                    }
                } else if (diff < -SYNC_WINDOW_NS) {
                    // Video is behind – drop the frame!
                    _ = decoder.video.popFrame();
                } else {
                    // Too early ->  just wait a bit
                    std.time.sleep(500_000);
                }
            }
        }

        // THEN: Decode only if queue is not full
        if (decoder.video.queue_count < movy_video.MAX_VIDEO_FRAMES) {
            const playback_time_ns = decoder.getAudioClock();
            switch (try decoder.processNextPacket(SYNC_WINDOW_NS, playback_time_ns)) {
                .eof => reached_end = true,
                else => {}, // any outcome advances state
            }
        }

        // All frames processed
        if (decoder.video.queue_count == 0 and reached_end) {
            state.stop = true;
        }

        std.time.sleep(1_000); // bit of breathing space for the cpu
    }

    // The End
}
