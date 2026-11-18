# First Golden baseline

Three scenarios use real koi_ui states and AppTheme: error light, error dark,
and a 320 logical-pixel empty state at 200% text size. Fixed DPR 1, height 480,
no animation, test font KoiGoldenSans, Material locale en-US with Koi's existing
Chinese fallback labels. The font is a reproducible test-only Noto Sans SC subset.

Reviewed baselines use Flutter 3.47.2, macOS arm64 and flutter_tester:

- `baselines/macos-arm64` is the original macOS 27.0.1 baseline.
- `baselines/macos-26-arm64` records the actual macOS 26.7.2 CI render after
  explicit approval. Four independent CI runs produced matching image hashes.

The test selects the baseline using the actual `sw_vers -productVersion` major
version. Other macOS arm64 versions fail explicitly until reviewed; non-macOS
and non-arm64 hosts skip and are not verified. Other minor releases within a
supported major still must match pixel-for-pixel. There is no tolerance or
automatic baseline regeneration. CI outcome for the new baseline remains pending
until a new run actually executes it.

From packages/koi_ui using the workspace SDK:

```sh
../../.fvm/flutter_sdk/bin/flutter test --no-pub --update-goldens test/golden/status_golden_test.dart
../../.fvm/flutter_sdk/bin/flutter test --no-pub test/golden/status_golden_test.dart
```

Use the configured pinned SDK path in generated projects if .fvm is elsewhere.
Inspect every PNG before accepting a baseline. Intentional layout mutations must
fail comparison; Flutter writes failure images under test/golden/failures.
Those diagnostics are generated output and are not template inputs. Only the
reviewed baselines and font fixture should be versioned. Normal validate still
runs the existing test, browser and coverage phases separately.
