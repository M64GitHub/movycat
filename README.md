
![License](https://img.shields.io/badge/License-MIT-85adf2?style=flat)
![Version](https://img.shields.io/badge/Version-0.0.2-85adf2?style=flat)
![Zig](https://img.shields.io/badge/Zig-0.15.2-orange?style=flat)

![get_movycat5](https://github.com/user-attachments/assets/d07e6ecd-2ee4-41f2-a82c-66096de14aed)

# movycat

**movycat** plays videos directly in your terminal — in full RGB color. It renders frames as ANSI half block characters, using the [movy](https://github.com/M64GitHub/movy) rendering engine, with synced audio playback powered by SDL2.

It supports all formats that **FFmpeg** can decode — including `.mp4`, `.h264`, `.avi`, `.mkv`, `.webm`, and more.  

```
Usage:

movycat -f|-file <filename> 
        [-w|-width <width>]
        [-h |-height <height>]
        [-a]

movycat -help

Options:
       -f ............ File to play

       -w, -h ........ Optional: dimensions of video output in pixels.
                       The resulting output size always preserves the 
                       aspect ratio, and is truncated to the terminal
                       size.

       -a ............ Optional: show video on alternate screen.
                       This preserves your current terminal state.

       -help ......... Help. Show this help along with the movycat
                       logo.
```

- Press `ESC` to quit.

- Press `SPACE` to pause.

- Press `CURSOR RIGHT` to skip forward 5 seconds.

- Press `CURSOR LEFT` to skip backwards 5 seconds.

- Of course you can use vim keys instead of the cursor keys!  
  `l` to skip forwards, and `h` to skip backwards 5 seconds.

- Press `i` to toggle the info overlay.

https://github.com/user-attachments/assets/e01ab36e-25d4-4228-bf79-36196637f125

(Excerpt from the 64k Demo "Universal Sequence" from the amazing demo group "Conspiracy")

![image](https://github.com/user-attachments/assets/f03fadeb-8812-4bb5-9aca-c94bcd1cdb84)

![image](https://github.com/user-attachments/assets/fcfcb9a5-1b3a-43dc-8c30-15574aeda9fb)

## Why movycat?
**movycat** is both a demo and a showcase of what [movy](https://github.com/M64GitHub/movy) can do: an RGBA-based rendering engine for composing, transforming, and displaying visuals with real-time effects.
If movy can render anything to a surface, why not video frames?

## ZIG
**movycat** is entirely written in Zig. This offers us to seamlessly import libffmpeg. And libsdl2. And call it directly from the code.

## Requirements

  - FFmpeg (shared libraries)
  - SDL2
  - Zig 0.15.2 or newer

### Tested Platforms

**movycat** has been tested and confirmed working on:
- **macOS 15.5** with FFmpeg 8.0 (via Homebrew)
- **Ubuntu 25.10** with FFmpeg 7.1.1 (via apt)

### Installation

**On macOS:**
```bash
brew install ffmpeg sdl2
```

**On Ubuntu:**
```bash
sudo apt install libavformat-dev libavcodec-dev libavutil-dev libswscale-dev libswresample-dev libsdl2-dev
```

## Build

```bash
zig build -Drelease-fast
```
