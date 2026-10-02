# Platform capability host

This runnable lab validates optional recipes. It is not a third application
template. Generated minimal and workbench apps receive only selected capability
sources, dependencies, localizations, native changes and behavior tests.

The `system-media` recipe offers two independent playback implementations:

- **MediaKit** uses its bundled mpv backend.
- **Audioplayers 6.8.1** uses Android MediaPlayer, Apple AVPlayer, Windows Media
  Foundation, Linux GStreamer, or browser audio.

Selection is explicit. Both factories create a real player to probe platform
initialization and dispose that probe. Availability does not assert that every
codec can decode, browser autoplay is permitted, or audible output is present.
The unselected second engine remains unprobed. On switch, the candidate opens
the current source and receives its position, volume and playing state before
the old engine is released. A failed candidate leaves the old owner active.
The main view, OS transport and mini player retain the same owner facade.

The application supplies audio-session policy and owns OS transport. A workbench
ordinary media preview remains a separate pause-on-leave feature. Windows
installations add the required CMake 3.15 / CMP0091 configuration through the
transactional native planner. Linux builds require the GStreamer development
libraries and runtime plugins suitable for the selected media formats.

```sh
flutter test --no-pub test/features/system_media
flutter test --no-pub --platform chrome test/features/system_media
```

These tests use the real Audioplayers Dart implementation with a platform
interface fixture. They verify plugin commands, lifecycle and error behavior;
they do not prove native playback. Device acceptance must separately exercise
both actual backends with the same local audio file, paused and playing switches,
seek/volume, candidate failure, system controls and exit. Current evidence lives
in `docs/validation/2026-10-02-spotube-upgrade/` at the workspace root.
