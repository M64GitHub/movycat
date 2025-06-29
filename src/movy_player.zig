const std = @import("std");
const movy = @import("movy");
const movy_video = @import("movy_video");

const c = @cImport({
    @cInclude("libavformat/avformat.h");
    @cInclude("libavcodec/avcodec.h");
    @cInclude("libswscale/swscale.h");
    @cInclude("libavutil/imgutils.h");
    @cInclude("libswresample/swresample.h"); // audio
});

// SDL2 for audio
const SDL = @cImport({
    @cInclude("SDL2/SDL.h");
});

pub const PlayBackState = enum {
    playing,
    stopped,
    paused,
};

pub const PlayerController = struct {
    playback_state: PlayBackState = .stopped,
    pause_start_ns: i128 = 0,
    total_paused_ns: i128 = 0,

    frame_ctr: usize = 0,
    pkt_ctr: usize = 0,

    pub fn togglePause(
        self: *PlayerController,
        decoder: *movy_video.VideoDecoder,
    ) void {
        if (self.isPaused()) {
            self.playback_state = .playing;
        } else {
            self.playback_state = .paused;
        }

        if (self.isPaused()) {
            // Pause audio and measure pause time
            self.pause_start_ns = decoder.getPlaybackClock();

            if (decoder.audio) |*a| {
                a.pauseAudioPlayback(true);
            }
        } else {
            // Continue audio and update clocks for av sync
            const pause_end_ns = decoder.getPlaybackClock();
            self.total_paused_ns += pause_end_ns - self.pause_start_ns;

            decoder.video.start_time_ns +=
                pause_end_ns - self.pause_start_ns;
            decoder.clock_start_ns +=
                pause_end_ns - self.pause_start_ns;
            if (decoder.audio) |*a| {
                a.start_time_ns += pause_end_ns - self.pause_start_ns;

                a.pauseAudioPlayback(false);
            }
        }
    }

    pub fn play(self: *PlayerController) void {
        self.playback_state = .playing;
    }

    pub fn stop(self: *PlayerController) void {
        self.playback_state = .stopped;
    }

    pub fn isStopped(self: *PlayerController) bool {
        return self.playback_state == .stopped;
    }

    pub fn isPaused(self: *PlayerController) bool {
        return self.playback_state == .paused;
    }

    pub fn getCurrentTime(
        self: *PlayerController,
        decoder: *movy_video.VideoDecoder,
    ) i128 {
        _ = self;
        return std.time.nanoTimestamp() - decoder.clock_start_ns;
    }

    pub fn skipTime(
        self: *PlayerController,
        decoder: *movy_video.VideoDecoder,
        offset_ns: i64,
    ) !void {
        if (self.isPaused()) return;

        const current_pos: i64 =
            @intCast(std.time.nanoTimestamp() - decoder.clock_start_ns);
        const requested_pos = @max(current_pos + offset_ns, 0);

        if (requested_pos >= decoder.video.fmt_ctx.duration * 1000) return;

        // Perform seeking
        if (offset_ns < 0) {
            const safe_seek_pos = @max(requested_pos - @as(i64, 5_000_000_000), 0);
            try decoder.seekToTimestamp(safe_seek_pos, .backward);
        } else {
            try decoder.seekToTimestamp(requested_pos, .forward);
        }

        // Flush
        if (decoder.audio) |*audio| {
            _ = SDL.SDL_ClearQueuedAudio(audio.audio_device);
        }
        decoder.video.resetQueue();
        decoder.flushAndDrainCodecs();

        // Decode 100 packets or until we see a valid video frame
        var warmup_attempts: usize = 0;
        var found_video = false;
        while (warmup_attempts < 100 and
            !found_video) : (warmup_attempts += 1)
        {
            const result = decoder.processNextPacket(0, requested_pos, true);
            if (result catch null == .handled_video) {
                found_video = true;
            }
        }

        // Warmup decoding to get accurate video timestamp
        const actual_video_pts_ns =
            try seekAndWarmupToFrame(decoder, requested_pos);

        // Feed a few packets to warm up audio decoder too (FFmpeg may need this)
        var warm_audio_attempts: usize = 0;
        while (warm_audio_attempts < 3000) : (warm_audio_attempts += 1) {
            const r = decoder.processNextPacket(
                0,
                @intCast(actual_video_pts_ns),
                false,
            );
            if (r catch null == .handled_audio) break;
        }

        // Realign clocks
        const now = std.time.nanoTimestamp();
        const new_start_time = now - @as(i128, @intCast(actual_video_pts_ns));
        decoder.clock_start_ns = new_start_time;
        decoder.video.start_time_ns = new_start_time;

        // Try syncing audio to video

        if (decoder.audio) |*audio| {
            _ = SDL.SDL_ClearQueuedAudio(audio.audio_device);

            const deadline = std.time.nanoTimestamp() + 250_000_000;
            var rebased = false;

            while (std.time.nanoTimestamp() < deadline) {
                const result = decoder.processNextPacket(
                    0,
                    @intCast(actual_video_pts_ns),
                    false,
                );
                if (result catch null == .handled_audio) {
                    if (audio.frame.*.pts != c.AV_NOPTS_VALUE) {
                        const audio_pts_ns =
                            try audio.getAudioPtsNS(audio.frame);
                        // Always rebase to audio_pts_ns,
                        // even if not within leeway
                        audio.start_time_ns = std.time.nanoTimestamp() -
                            @as(i128, @intCast(audio_pts_ns));
                        try audio.convertAndQueueAudio(audio.frame);
                        rebased = true;
                        break;
                    }
                }
            }

            if (!rebased) {
                // fallback
                audio.start_time_ns = new_start_time;
            }

            if (!self.isPaused()) {
                SDL.SDL_PauseAudioDevice(audio.audio_device, 0);
            }
        }

        self.total_paused_ns = 0;
    }
};

fn seekAndWarmupToFrame(
    decoder: *movy_video.VideoDecoder,
    target_ns: i64,
) !u64 {
    const warmup_limit = 150;

    decoder.video.resetQueue();

    movy.terminal.setColor(movy.color.WHITE);

    var tries: usize = 0;
    var last_err: ?anyerror = null;

    while (tries < warmup_limit) : (tries += 1) {
        const result = decoder.processNextPacket(0, target_ns, true);

        if (result) |status| {
            if (status == .handled_video) {
                if (decoder.video.popFrame()) |frame| {
                    const pts_ns = try decoder.video.getFramePtsNS(frame);
                    movy_video.VideoDecoder.freeAVFrame(frame);
                    return pts_ns;
                }
            }
        } else |e| {
            last_err = e;
        }

        std.time.sleep(200_000);
    }

    return last_err orelse error.SeekFailed;
}
