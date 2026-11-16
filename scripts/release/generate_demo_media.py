#!/usr/bin/env python3
"""Generate original bundled review clips. Requires ffmpeg with libx264/drawtext.

Usage: python3 scripts/release/generate_demo_media.py [path/to/ffmpeg]
No downloaded artwork, fonts, audio, or video is included in the app.
"""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]

def main():
    ffmpeg = sys.argv[1] if len(sys.argv) > 1 else shutil.which('ffmpeg')
    if not ffmpeg:
        raise SystemExit('Install ffmpeg or pass its path as the first argument.')
    output = ROOT / 'PlinxApp/Resources/DemoMedia'
    output.mkdir(parents=True, exist_ok=True)
    for name, color, frequency in [('movie', '0x163f46', 330), ('episode', '0x343059', 440)]:
        filters = (
            "[0:v][2:v]overlay=x='mod(t*60,576)':y='140+40*sin(t)'[motion];"
            "[motion]drawtext=fontfile=/System/Library/Fonts/Monaco.ttf:"
            f"text='Plinx {name} sample %{{pts\\:hms}}':fontcolor=white:fontsize=22:x=24:y=40[v]"
        )
        with tempfile.TemporaryDirectory(prefix='plinx-demo-') as temporary:
            captions = Path(temporary) / 'captions.srt'
            captions.write_text('1\n00:00:00,000 --> 00:00:10,000\nPlinx original sample. Try pause, seeking, and captions.\n\n2\n00:00:30,000 --> 00:00:40,000\nThis caption is thirty seconds into the sample.\n\n3\n00:01:10,000 --> 00:01:25,000\nDownload this sample to try offline playback.\n')
            generate(ffmpeg, name, color, frequency, filters, captions, output)


def generate(ffmpeg, name, color, frequency, filters, captions, output):
    subprocess.run([
            ffmpeg, '-y', '-f', 'lavfi', '-i', f'color=c={color}:s=640x360:r=24:d=90',
            '-f', 'lavfi', '-i', f'sine=frequency={frequency}:sample_rate=44100:duration=90',
            '-f', 'lavfi', '-i', 'color=c=0xa5d56d:s=64x64:r=24:d=90',
            '-f', 'lavfi', '-i', f'sine=frequency={frequency + 220}:sample_rate=44100:duration=90',
            '-i', str(captions),
            '-filter_complex', filters, '-map', '[v]', '-map', '1:a', '-map', '3:a', '-map', '4:s',
            '-af', 'volume=0.06', '-metadata:s:a:0', 'title=Low sample tone',
            '-metadata:s:a:1', 'title=High sample tone', '-metadata:s:s:0', 'language=eng',
            '-metadata:s:s:0', 'title=Sample captions', '-c:s', 'mov_text',
            '-c:v', 'libx264', '-preset', 'slow', '-crf', '30', '-pix_fmt', 'yuv420p',
            '-c:a', 'aac', '-b:a', '32k', '-movflags', '+faststart', '-map_metadata', '-1',
            str(output / f'{name}.mp4')
        ], check=True)

if __name__ == '__main__':
    main()
