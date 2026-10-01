# Actual platform runtime smoke

`workbench_runtime_test.dart` uses real Native/IndexedDB stores, real image
codecs, a real media_kit Player/Video surface, MP4 playback/pause/seek/volume,
first-frame JPEG screenshots, persisted PNG thumbnails, lease release and
workspace reopen. No playback or store implementation is replaced by a fake.
Source images, first-frame screenshots and persisted thumbnails must decode to
the fixture dimensions and contain real image pixels. The synthetic gradients
and test patterns must have more than 16 distinct colors; an allocated but blank
surface cannot pass. Conditional Web probes record the actual video element's
readiness, position and direct canvas pixels when diagnosing a failure.

Only the input adapter is test-specific: checked-in rootBundle fixtures provide
actual byte streams instead of selecting a file through an OS dialog. A passing
result does **not** accept the native/browser file picker.

The Native test owns a temporary directory. The Web test owns a unique IndexedDB
and verifies that released Blob URLs cannot be fetched. Cleanup closes playback,
leases, workspace and storage before removing the sandbox.

Generate a workbench host with macOS/Web runners outside this source workspace;
these runner directories are intentionally absent here. Run from its app member:

```sh
flutter test --no-pub -d macos integration_test/workbench_runtime_test.dart
chromedriver --port=4445
flutter drive --no-pub -d web-server --headless --driver-port=4445 \
  --driver=integration_test/support/runtime_driver.dart \
  --target=integration_test/workbench_runtime_test.dart \
  --web-browser-flag=--autoplay-policy=no-user-gesture-required
```

The Chrome command explicitly permits automated autoplay. The test also plays
muted and confirms genuine time advancement. Normal product playback remains
subject to the browser's user-interaction policy.

Safari requires a permitted WebDriver session. Do not change user settings while
running acceptance; record `NOT_RUN` with Safari's exact refusal if remote
automation is disabled. Other platforms likewise require their actual runner and
device. Native/Web build success alone does not prove this runtime smoke passed.

The driver writes structured runtime evidence to
`build/integration_response_data.json`; successful target tests also print a
`KOI_RUNTIME_EVIDENCE` JSON record. Keep command stdout/stderr as acceptance logs.
