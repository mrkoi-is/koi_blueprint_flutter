# Synthetic runtime fixtures

These locally generated, tiny samples exercise actual image codecs, Player,
first-frame JPEG screenshots and persistent content stores. They contain no
remote or personal media. Total payload is 86,249 bytes. `manifest.json` records
SHA-256, byte counts and ffprobe codec evidence.

- `gradient.png` and `gradient.jpg`: 160x96 synthetic RGB gradient.
- `landscape.mp4`: 160x96, two seconds, H.264 Constrained Baseline, 8-bit yuv420p, AAC-LC.
- `portrait.mp4`: 96x160 with the same codec baseline.
- `中文资料.md`: UTF-8 text persistence sample.

The optional source generator is `tool/create_media_fixtures.py` and requires
ffmpeg/ffprobe only when regenerating checked-in fixtures. Generated applications
do not need either tool.

The integration adapter supplies real fixture byte streams instead of opening
the OS file picker. Its passing result is **not** picker acceptance.
