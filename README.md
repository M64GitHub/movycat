![get_movycat5](https://github.com/user-attachments/assets/d07e6ecd-2ee4-41f2-a82c-66096de14aed)

# movycat

**movycat** plays videos directly in your terminal. It renders the video to ANSI half block characters in full RGB, using the [movy](https://github.com/M64GitHub/movy) rendering engine, and supports synced audio playback using SDL2.

All formats that ffmpeg can decode are supported. This includes h64, mp4, avi, mkv, webm files, ...

```bash
Usage:
movycat -file <filename> [-width <width> -height <height>]
```

Press `ESC` to quit playback anytime.

Press `SPACE` to pause.

Press `CURSOR RIGHT` to skip forward 5 seconds.

Press `CURSOR LEFT` to skip backwards 5 seconds.

Of course you can use vim keys instead of the cursor keys! `l` to skip forwards, and `h` to skip backwards 5 seconds.

https://github.com/user-attachments/assets/e01ab36e-25d4-4228-bf79-36196637f125

(part of the 64k Demo "Universal Sequence" from the amazing demo group "Conspiracy")

![image](https://github.com/user-attachments/assets/f03fadeb-8812-4bb5-9aca-c94bcd1cdb84)

![image](https://github.com/user-attachments/assets/fcfcb9a5-1b3a-43dc-8c30-15574aeda9fb)

## Why
This is just a demo for movy, that basically provides rgba rendersurfaces, ways to manipulate and combine them, and functions to blast them to the terminal. You can render anything on those, so why not movie-frames?

## ZIG
**movycat** is entirely written in Zig. This offers us to seamlessly import libffmpeg. And libsdl2. And call it directly from the code. 

