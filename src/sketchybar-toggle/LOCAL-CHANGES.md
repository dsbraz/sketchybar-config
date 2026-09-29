Based on malpern/sketchybar-toggle v0.5.0 (MIT; see LICENSE).

The local helper owns visibility, front application/window title, native menu
coverage and native desktop discovery. Hammerspoon is not used.

- NativeBridge implements SketchyBar's Mach helper wire protocol. Requests have
  bounded send/receive waits, fresh bootstrap lookup and independently owned
  replies. Arguments are NUL separated, with no shell/string quote parsing.
  Protocol reference: https://github.com/FelixKratz/SketchyBarHelper
- A registered mach_helper receives Space/display/wake notifications. A two
  second reconciliation reads SkyLight's SLSCopyManagedDisplaySpaces, a private
  read-only API, preserving Mission Control index slots and ignoring fullscreen
  items. No SIP changes. Failed snapshots preserve the current layout.
- AppKit and AX observe app, focused window and title changes. A 250 ms fallback
  handles missed notifications. AX has a 50 ms messaging timeout. Only the current
  state is retained: there is no per-application menu cache.
- Native-menu growth is immediate. Shrinking waits 400 ms for a stable PID/width;
  title and cover update together. Prepare layout before revealing the bar.
- smooth-slide moves 32 points over 16 sin frames (~267 ms); hiding completes
  after that duration plus 30 ms. Reversals continue at the current offset.
  Experimental fade uses 18 sin frames; default upstream-style slide is retained.
- Signal sources restore visibility on orderly exit without async-signal-unsafe
  work in a POSIX signal handler.
- build-toggle.sh creates a locally signed SketchyBar Helper.app, launched by
  LaunchServices with its own Accessibility identity. Missing AX permission does
  not disable Spaces or mouse monitoring; granting it enables menu reads live.

Build: bash build-toggle.sh
Test: swift test --package-path src/sketchybar-toggle
The Homebrew toggle binary is unchanged and is not used as a fallback because it
cannot provide the native menu/Spaces integration.
