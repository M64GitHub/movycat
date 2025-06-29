const std = @import("std");
const movy = @import("movy");
const movy_video = @import("movy_video");
const player = @import("movy_player.zig");
const flagz = @import("flagz");

// SDL2 for audio
const SDL = @cImport({
    @cInclude("SDL2/SDL.h");
});

const stdout = std.io.getStdOut().writer();

var target_width: usize = undefined;
var target_height: usize = undefined;

var SYNC_WINDOW_NS: i64 = 10_000_000;

pub fn printUsage() void {
    stdout.print(
        \\Usage:
        \\
        \\movycat -f|-file <filename> 
        \\        [-w|-width <width>]
        \\        [-h |-height <height>]
        \\        [-a] 
        \\
        \\movycat -help
        \\
        \\Options:
        \\       -f ............ File to play
        \\
        \\       -w, -h ........ Optional: dimensions of video output in pixels.
        \\                       The resulting output size always preserves the 
        \\                       aspect ratio, and is truncated to the terminal
        \\                       size.
        \\
        \\       -a ............ Optional: show video on alternate screen.
        \\                       This preserves your current terminal state.
        \\
        \\       -help ......... Help. Show this help along with the movycat
        \\                       logo.
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
        help: bool,
        a: bool,
    };

    const args = flagz.parse(Args, allocator) catch {
        return printUsage();
    };
    defer flagz.deinit(args, allocator);

    if (args.file.len == 0) {
        return printUsage();
    }

    if (args.help) {
        return printUsage();
    }

    // -- init Audio

    // init SDL audio
    if (SDL.SDL_Init(SDL.SDL_INIT_AUDIO) != 0) return error.SDLInitFailed;
    defer SDL.SDL_Quit();

    // -- Init output dimensions to screen dimensions
    const term_dimensions = try movy.terminal.getSize();
    target_width = term_dimensions.width;
    target_height = term_dimensions.height * 2 - 2;

    // override with cmdline parameters
    if (args.width) |width| {
        if (width < target_width) target_width = width;
    }
    if (args.height) |height| {
        if (height < target_height) target_height = height;
    }

    // -- Initialize the decoder
    const decoder =
        try movy_video.VideoDecoder.init(allocator, args.file);
    defer decoder.deinit(allocator);

    if (decoder.audio) |*a| {
        a.pauseAudioPlayback(false);
    }

    // -- Get video dimensions, resize and setup scaling
    const vid_w = decoder.getVideoDimensions().w;
    const vid_h = decoder.getVideoDimensions().h;

    const resized = try resize(vid_w, vid_h, target_width, target_height);
    target_width = resized.w;
    target_height = resized.h;

    if (target_width < 20) target_width = 20;
    if (target_height < 20) target_height = 20;

    try decoder.video.setDimensions(allocator, target_width, target_height);

    // -- Setup movy screen
    try movy.terminal.beginRawMode();
    defer movy.terminal.endRawMode();

    // Looks cooler, when last video frame stays on screen, on exit
    if (args.a) try movy.terminal.beginAlternateScreen();

    var screen = try movy.Screen.init(
        allocator,
        target_width,
        target_height / 2,
    );
    defer screen.deinit(allocator);

    screen.setScreenMode(movy.Screen.Mode.bgcolor);

    // -- Init render surface for output, and add to screen
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

    var reached_end = false;
    var loop_ctr: usize = 0;

    var controller = player.PlayerController{};

    controller.play();

    var info_display_on = true;

    while (!controller.isStopped()) {
        loop_ctr += 1;

        // esc input only works with raw terminal mode
        if (try movy.input.get()) |event| {
            if (event == .key and event.key.type == .Escape) {
                controller.stop();
            }
            // Outta Space
            if (event == .key and event.key.type == .Char and
                event.key.sequence[0] == ' ')
            {
                controller.togglePause(decoder);
            }
            // fast forward +5s
            if (event == .key and event.key.type == .Right) {
                try controller.skipTime(decoder, 5 * std.time.ns_per_s);
            }
            // fast backward +5s
            if (event == .key and event.key.type == .Left) {
                try controller.skipTime(decoder, -5 * std.time.ns_per_s);
            }
            // vim style
            if (event == .key and event.key.type == .Char and
                event.key.sequence[0] == 'l')
            {
                try controller.skipTime(decoder, 5 * std.time.ns_per_s);
            }
            if (event == .key and event.key.type == .Char and
                event.key.sequence[0] == 'h')
            {
                try controller.skipTime(decoder, -5 * std.time.ns_per_s);
            }
            // info toggle
            if (event == .key and event.key.type == .Char and
                event.key.sequence[0] == 'i')
            {
                info_display_on = !info_display_on;
                if (!info_display_on) clearStats(surface);
            }
        }

        if (controller.isPaused()) {
            std.time.sleep(10_000_000);
            continue;
        }

        // FIRST: Chck if a frame is ready to render (even before decoding more)
        if (decoder.video.queue_count > 0) {
            if (decoder.video.peekFrame()) |head| {
                const playback_time_ns = decoder.getPlaybackClock();
                const head_pts_i64 = @as(i64, @intCast(head.pts_ns));
                const audio_i64 = @as(i64, @intCast(playback_time_ns));
                const diff = head_pts_i64 - audio_i64;

                controller.pkt_ctr += 1;

                if (diff <= SYNC_WINDOW_NS and diff >= -SYNC_WINDOW_NS) {
                    if (decoder.video.popFrame()) |frame_ptr| {
                        controller.frame_ctr += 1;

                        const t_before = std.time.nanoTimestamp();
                        decoder.video.renderFrameToSurface(frame_ptr, surface);
                        const t_after = std.time.nanoTimestamp();
                        const render_ns = t_after - t_before;

                        if (render_ns > 20_000_000) {
                            movy.terminal.setColor(movy.color.WHITE);
                            std.debug.print(
                                "Scaling / rendering frame took {} ns\n",
                                .{render_ns},
                            );
                            return error.ScalingTooSlow;
                        }

                        if (info_display_on)
                            try renderStats(allocator, decoder, surface);

                        movy_video.VideoDecoder.freeAVFrame(frame_ptr);

                        screen.render();
                        try screen.output();
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
        if (decoder.video.queue_count < movy_video.VideoState.MAX_VIDEO_FRAMES) {
            const playback_time_ns = decoder.getPlaybackClock();
            switch (try decoder.processNextPacket(
                SYNC_WINDOW_NS,
                playback_time_ns,
                false,
            )) {
                .eof => reached_end = true,
                else => {}, // any outcome advances state
            }
        }

        // All frames processed
        if (decoder.video.queue_count == 0 and reached_end) {
            controller.stop();
        }

        std.time.sleep(1_000); // bit of breathing space for the cpu
    }

    if (args.a) movy.terminal.endAlternateScreen();

    // The End
}

fn resize(vid_w: usize, vid_h: usize, scrn_w: usize, scrn_h: usize) !struct {
    w: usize,
    h: usize,
} {
    const ratio = @as(f64, @floatFromInt(vid_w)) /
        @as(f64, @floatFromInt(vid_h));

    // Try to fit by width
    const new_h_f = @as(f64, @floatFromInt(scrn_w)) / ratio;
    const new_h = @as(usize, @intFromFloat(new_h_f));
    if (new_h <= scrn_h)
        return .{ .w = scrn_w, .h = new_h };

    // Else, fit by height
    const new_w_f = @as(f64, @floatFromInt(scrn_h)) * ratio;
    const new_w = @as(usize, @intFromFloat(new_w_f));
    if (new_w <= scrn_w)
        return .{ .w = new_w, .h = scrn_h };

    return error.ResizeError;
}

fn renderStats(
    allocator: std.mem.Allocator,
    decoder: *movy_video.VideoDecoder,
    surface: *movy.RenderSurface,
) !void {
    const time_str = try decoder.getPlaybackTimestampStr(allocator);
    const total_str = try decoder.getTotalDurationStr(allocator);
    const percent = decoder.getPlaybackProgressPercent();

    const stat_str = try std.fmt.allocPrint(
        allocator,
        " {s} ({s}) | {d}% ",
        .{ time_str, total_str, percent },
    );

    if (stat_str.len + 2 > surface.w) {
        allocator.free(time_str);
        allocator.free(total_str);
        allocator.free(stat_str);
        return;
    }

    const x = surface.w - stat_str.len - 1;
    const y = surface.h / 2 - 1;

    _ = surface.putStrXY(
        stat_str,
        x,
        y,
        movy.color.LIGHT_GRAY,
        movy.color.DARKER_GRAY,
    );

    allocator.free(time_str);
    allocator.free(total_str);
    allocator.free(stat_str);
}

fn clearStats(surface: *movy.RenderSurface) void {
    surface.clearColored(movy.color.BLACK);
}
