# Test-only Chinese font

KoiGoldenSans.ttf is a 45 KB subset of Noto Sans SC, used only by Golden tests.
It does not change application typography or add an application asset. Original
source, exact commit and source/subset SHA-256 are in source.json. OFL.txt is
retained from the upstream font. The subset keeps the variable weight axis.

To reproduce in a temporary Python environment with fonttools==4.60.1, download
the exact source.json URL, verify sourceSha256, then run from this directory:

```sh
pyftsubset /tmp/noto-source.ttf --text-file=characters.txt --output-file=KoiGoldenSans.ttf
```

Verify subsetSha256 after generation. characters.txt contains ASCII plus every
Chinese/punctuation character used by the three scenarios. New scenario text
requires updating the subset and reviewing resulting baselines explicitly.
