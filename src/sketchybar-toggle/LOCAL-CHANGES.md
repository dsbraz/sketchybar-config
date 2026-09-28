Based on malpern/sketchybar-toggle v0.5.0 (MIT; see LICENSE).

Local change: animate y_offset to -34 over 9 frames before hiding after 180 ms.
Cancel the delayed hide on show, including quick pointer reversals. The original
mouse monitoring and debounce remain unchanged. No additional periodic timer.
Commands are ordered so a delayed animation command cannot overtake a hide.

Build from the configuration directory with `bash build-toggle.sh`.
Tests: `swift test --package-path src/sketchybar-toggle`.
The Homebrew binary remains unchanged; sketchybarrc prefers the local binary.
