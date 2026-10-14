#!/usr/bin/env python3
"""Rebuild tiny synthetic Koi runtime fixtures. Not required to run generated apps."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import zlib

ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / 'examples' / 'workbench_app' / 'assets' / 'fixtures'


def png_chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))


def main() -> None:
    ffmpeg = shutil.which('ffmpeg')
    ffprobe = shutil.which('ffprobe')
    if not ffmpeg or not ffprobe:
        raise SystemExit('Fixture regeneration requires ffmpeg and ffprobe; checked-in fixtures do not.')
    DESTINATION.mkdir(parents=True, exist_ok=True)
    width, height = 160, 96
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        for x in range(width):
            rows.extend((x * 255 // (width - 1), y * 255 // (height - 1), (x + y) * 255 // (width + height - 2)))
    png = (b'\x89PNG\r\n\x1a\n' + png_chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
           + png_chunk(b'IDAT', zlib.compress(rows, 9)) + png_chunk(b'IEND', b''))
    (DESTINATION / 'gradient.png').write_bytes(png)
    subprocess.run([ffmpeg, '-v', 'error', '-y', '-i', str(DESTINATION / 'gradient.png'),
                    '-frames:v', '1', '-q:v', '3', str(DESTINATION / 'gradient.jpg')], check=True)
    for name, size in [('landscape', '160x96'), ('portrait', '96x160')]:
        subprocess.run([ffmpeg, '-v', 'error', '-y', '-f', 'lavfi', '-i', f'testsrc2=size={size}:rate=15',
                        '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000',
                        '-t', '2', '-af', 'volume=0.05', '-c:v', 'libx264', '-threads', '1',
                        '-profile:v', 'baseline', '-pix_fmt', 'yuv420p', '-crf', '32', '-preset', 'medium',
                        '-c:a', 'aac', '-profile:a', 'aac_low', '-b:a', '24k', '-ac', '1',
                        '-movflags', '+faststart', '-metadata', 'comment=Koi synthetic runtime fixture',
                        str(DESTINATION / f'{name}.mp4')], check=True)
    (DESTINATION / '中文资料.md').write_text('# 本地工作区\n\n这是用于验证真实持久化与重开恢复的中文资料。\n', encoding='utf-8')
    records = []
    total = 0
    fixture_names = {'gradient.png', 'gradient.jpg', 'landscape.mp4',
                     'portrait.mp4', '中文资料.md'}
    for path in sorted(DESTINATION.iterdir()):
        if path.name not in fixture_names:
            continue
        data = path.read_bytes()
        total += len(data)
        item = {'name': path.name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
        if path.suffix == '.mp4':
            probe = subprocess.run([ffprobe, '-v', 'error', '-show_entries',
                                    'stream=codec_name,profile,pix_fmt,width,height,sample_rate,channels',
                                    '-of', 'json', str(path)], check=True, capture_output=True, text=True)
            item['streams'] = json.loads(probe.stdout)['streams']
        records.append(item)
    if total >= 300 * 1024:
        raise SystemExit(f'Fixture total {total} exceeds 300 KiB')
    (DESTINATION / 'manifest.json').write_text(json.dumps({'total_bytes': total, 'fixtures': records},
                                                         ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'total_bytes': total, 'files': len(records), 'directory': str(DESTINATION)}))


if __name__ == '__main__':
    main()
