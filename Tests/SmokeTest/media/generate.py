"""Generate the media fixtures for the tvOS simulator smoke test.

Usage: python -I generate.py <output-dir> [--font <ttf-or-otf>]

Writes, into <output-dir>:
  sample.mp4            30 s, 640x360, 24 fps, H.264 (main, 2 s GOP) + AAC stereo
  sample.mkv            the same streams in Matroska
  sample.zh.ass         Chinese ASS sidecar (bold / colour / italic), timed to the video
  sample.en.srt         English SRT sidecar, timed to the video
  hls/sample.m3u8       HLS rendition of sample.mp4, 2 s TS segments

Every frame carries a burnt-in timecode, frame number and progress bar, so a
screenshot of playback shows which instant is on screen. Needs ffmpeg on PATH.
The picture is drawn here with Pillow; ffmpeg only encodes.
"""
import math
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

WIDTH, HEIGHT, FPS, SECONDS = 640, 360, 24, 30
TOTAL_FRAMES = FPS * SECONDS
BAR_H = 40
TC_H = 44


def frame(index, fonts):
    """One video frame for frame number `index`."""
    t = index / FPS
    ys, xs = np.mgrid[0:HEIGHT, 0:WIDTH]

    # sweeping diagonal bands over a vertical gradient
    base = 26 + 34 * ys // HEIGHT
    offset = (60 * np.sin((ys + t * 90) / 46.0)).astype(np.int32)
    phase = ((xs + offset) // 80) % 3
    arr = np.empty((HEIGHT, WIDTH, 3), dtype=np.uint8)
    arr[..., 0] = base + np.select([phase == 0, phase == 1], [70, 10], 0)
    arr[..., 1] = base + np.select([phase == 0, phase == 1], [14, 60], 6)
    arr[..., 2] = base + np.select([phase == 0, phase == 1], [90, 100], 30)
    img = Image.fromarray(arr, "RGB")

    draw = ImageDraw.Draw(img)

    # bouncing marker, so motion is visible even in a still
    bx = int(40 + (WIDTH - 80) * (0.5 - 0.5 * math.cos(2 * math.pi * t / 10)))
    by = int(HEIGHT / 2 + 70 * math.sin(2 * math.pi * t / 3))
    draw.ellipse((bx - 26, by - 26, bx + 26, by + 26), fill=(255, 210, 40), outline=(0, 0, 0), width=3)

    # burnt-in timecode + frame number
    draw.rectangle((0, 0, WIDTH, TC_H), fill=(0, 0, 0))
    draw.text((14, 5), "%02d:%05.2f   FRAME %04d" % (int(t // 60), t % 60, index), font=fonts["tc"], fill=(255, 255, 255))

    # progress bar along the bottom edge, labels just above it: filled up to the current instant
    draw.rectangle((0, HEIGHT - BAR_H, WIDTH, HEIGHT), fill=(0, 0, 0))
    draw.text((22, HEIGHT - BAR_H + 2), "AETHERTV SMOKE TEST", font=fonts["bar"], fill=(255, 220, 0))
    draw.text((WIDTH - 150, HEIGHT - BAR_H + 2), "of %02d:%02d" % (SECONDS // 60, SECONDS % 60), font=fonts["bar"], fill=(255, 220, 0))
    draw.rectangle((20, HEIGHT - 12, WIDTH - 20, HEIGHT - 6), fill=(70, 70, 70))
    filled = int((WIDTH - 40) * t / SECONDS)
    draw.rectangle((20, HEIGHT - 12, 20 + filled, HEIGHT - 6), fill=(250, 250, 250))
    return img


def cue_times():
    """(start, end) of every subtitle cue: one every 3.5 s starting half a second in."""
    start = 0.5
    while start + 3.0 <= SECONDS:
        yield start, start + 3.0
        start += 3.5


def ass_timestamp(seconds):
    h = int(seconds // 3600)
    m = int(seconds % 3600 // 60)
    s = seconds % 60
    return "%d:%02d:%05.2f" % (h, m, s)


def srt_timestamp(seconds):
    ms = int(round(seconds * 1000))
    return "%02d:%02d:%02d,%03d" % (ms // 3600000, ms % 3600000 // 60000, ms % 60000 // 1000, ms % 1000)


def write_subtitles(out_dir):
    zh = [
        "[Script Info]",
        "Title: AetherTV smoke test",
        "ScriptType: v4.00+",
        "PlayResX: 3840",
        "PlayResY: 2160",
        "WrapStyle: 0",
        "ScaledBorderAndShadow: yes",
        "",
        "[V4+ Styles]",
        "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, "
        "Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, "
        "Alignment, MarginL, MarginR, MarginV, Encoding",
        "Style: Default,Source Han Sans SC,120,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,-1,0,0,0,100,100,0,0,1,6,2,2,60,60,120,1",
        "Style: Accent,Source Han Sans SC,140,&H0000FFFF,&H000000FF,&H00000000,&H80000000,-1,0,0,0,100,100,0,0,1,6,2,2,60,60,120,1",
        "",
        "[Events]",
        "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text",
    ]
    en = []
    for number, (start, end) in enumerate(cue_times(), 1):
        span = "第 %d-%d 秒" % (int(math.floor(start)), int(end))
        zh.append("Dialogue: 0,%s,%s,Default,,0,0,0,,{\\pos(1920,1560)}冒烟字幕 %d（%s）" % (ass_timestamp(start), ass_timestamp(end), number, span))
        if number % 3 == 1:
            zh.append("Dialogue: 1,%s,%s,Accent,,0,0,0,,{\\b1\\c&H00E5FF&\\pos(1920,1320)}加粗黄色 · 第 %d 条" % (ass_timestamp(start + 0.2), ass_timestamp(end - 0.2), number))
        elif number % 3 == 2:
            zh.append("Dialogue: 1,%s,%s,Accent,,0,0,0,,{\\i1\\c&HE5E5FF&\\pos(1920,1320)}斜体粉色 · 第 %d 条" % (ass_timestamp(start + 0.2), ass_timestamp(end - 0.2), number))
        en.append("%d\n%s --> %s\nCue %d, second %d\n" % (number, srt_timestamp(start), srt_timestamp(end), number, int(math.floor(start))))
    with open(os.path.join(out_dir, "sample.zh.ass"), "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(zh) + "\n")
    with open(os.path.join(out_dir, "sample.en.srt"), "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(en))


def run(*args, **stdin):
    result = subprocess.run(args, stdin=stdin.get("stdin"), stdout=subprocess.DEVNULL,
                            stderr=subprocess.PIPE)
    if result.returncode != 0:
        raise SystemExit("command failed (%d): %s\n%s" % (result.returncode, " ".join(args[:4]), result.stderr.decode("utf-8", "replace")[-800:]))


def main(argv):
    out_dir = argv[1]
    font_path = argv[argv.index("--font") + 1] if "--font" in argv else None
    os.makedirs(os.path.join(out_dir, "hls"), exist_ok=True)
    fonts = {
        "tc": ImageFont.truetype(font_path, 28) if font_path else ImageFont.load_default(28),
        "bar": ImageFont.truetype(font_path, 20) if font_path else ImageFont.load_default(20),
    }

    mp4 = os.path.join(out_dir, "sample.mp4")
    audio = "aevalsrc=exprs=0.3*sin(2*PI*(330+30*floor(mod(t\\,10)))*t):s=48000:d=%d" % SECONDS
    encoder = subprocess.Popen([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "%dx%d" % (WIDTH, HEIGHT), "-r", str(FPS), "-i", "-",
        "-f", "lavfi", "-i", audio,
        "-map", "0:v", "-map", "1:a",
        "-c:v", "libx264", "-preset", "veryfast", "-crf", "27", "-profile:v", "main",
        "-g", str(FPS * 2), "-keyint_min", str(FPS * 2), "-sc_threshold", "0",
        "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "64k", "-ac", "2",
        "-t", str(SECONDS), "-movflags", "+faststart", mp4,
    ], stdin=subprocess.PIPE, stderr=subprocess.PIPE)
    for index in range(TOTAL_FRAMES):
        encoder.stdin.write(frame(index, fonts).tobytes())
    encoder.stdin.close()
    if encoder.wait() != 0:
        raise SystemExit("ffmpeg failed:\n" + encoder.stderr.read().decode("utf-8", "replace")[-800:])

    run("ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", mp4, "-c", "copy",
        os.path.join(out_dir, "sample.mkv"))
    hls_dir = os.path.join(out_dir, "hls")
    for name in os.listdir(hls_dir):
        os.remove(os.path.join(hls_dir, name))
    run("ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", mp4, "-c", "copy",
        "-f", "hls", "-hls_time", "2", "-hls_playlist_type", "vod",
        "-hls_segment_filename", os.path.join(hls_dir, "seg_%03d.ts"),
        os.path.join(hls_dir, "sample.m3u8"))
    write_subtitles(out_dir)

    for name in sorted(os.listdir(out_dir) + ["hls/" + n for n in os.listdir(hls_dir)]):
        path = os.path.join(out_dir, name)
        if os.path.isfile(path):
            print("%9d  %s" % (os.path.getsize(path), name))
    print("segments:", len([n for n in os.listdir(hls_dir) if n.endswith(".ts")]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
