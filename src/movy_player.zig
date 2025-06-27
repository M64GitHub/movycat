const std = @import("std");
const movy = @import("movy");
const movy_video = @import("movy_video");

pub const PlayerState = struct {
    paused: bool = false,
    stop: bool = false,

    pause_start_ns: i128 = 0,
    total_paused_ns: i128 = 0,

    frame_ctr: usize = 0,
    pkt_ctr: usize = 0,

    pub fn togglePause(
        self: *PlayerState,
        decoder: *movy_video.VideoDecoder,
    ) void {
        self.paused = !self.paused;
        if (decoder.audio) |*a| {
            if (self.paused) {
                // Pause audio and measure pause time
                self.pause_start_ns = a.getAudioClock();
                a.pauseAudioPlayback(true);
            } else {
                // Continue audio and update clocks for av sync
                const pause_end_ns = a.getAudioClock();
                self.total_paused_ns += pause_end_ns - self.pause_start_ns;

                decoder.video.start_time_ns += pause_end_ns - self.pause_start_ns;
                a.start_time_ns += pause_end_ns - self.pause_start_ns;

                a.pauseAudioPlayback(false);
            }
        }
    }

    pub fn getEffectiveAudioClock(
        self: *const PlayerState,
        audio: *movy_video.AudioState,
    ) i128 {
        return audio.getAudioClock() - self.total_paused_ns;
    }
};
