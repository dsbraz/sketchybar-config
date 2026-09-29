Based on malpern/sketchybar-toggle v0.5.0 (MIT; see LICENSE).

The local helper owns visibility, front application name and window title,
native menu coverage and Space discovery. Hammerspoon is not used.

- NativeBridge implements SketchyBar's Mach helper wire protocol with bounded
  send/receive waits, fresh bootstrap lookup and NUL-separated arguments.
  Protocol reference: https://github.com/FelixKratz/SketchyBarHelper
- A registered mach_helper receives Space/display/wake notifications and reads SkyLight's SLSCopyManagedDisplaySpaces, a private
  read-only API, preserving Mission Control index slots and ignoring fullscreen
  items. No SIP changes. Failed snapshots preserve the current layout.
- AppKit supplies the localized app name; AX supplies the focused window title.
  AppLabelRenderer displays "App — window title", fitting only the title into
  the remaining width when the app name fits. Empty/duplicate titles and dangling
  separators are omitted. A leading Braille spinner is ignored. Only the current
  name/title/width measurement is retained; unchanged output causes no redraw.
  Focus events refresh immediately; internal title changes coalesce for 1 s using
  one event-triggered task, canceled on app/window changes. No periodic polling.
  The presentation gate holds both name and title until geometry is committed.
  AX menu/window messaging is bounded; missing notifications may leave text or
  geometry stale until another app/Space/reveal event.
- Mouse movement/clicks use passive NSEvent monitors with no periodic timer.
- App names fit the available display geometry with a 16 pt gap before the notch
  or measured surface edge, using grapheme-safe pixel truncation and no text scrolling.
- CompactBarLayout configures one opaque surface per display: x=6, y=2,
  height=30, radius=10, color=0xff242426, no blur. The right edge follows that
  display's last measured menu plus 12 points (minimum end 320, clamped to screen).
  Each display keeps its current measurement independently; disconnected displays
  are dropped. Unmeasured displays use the compact notch/center fallback until focus.
  Growth is immediate; shrink uses one cancelable 250 ms delayed commit, preserving
  old coverage while macOS replaces its menu. New targets replace pending shrink;
  there is no polling or sequence of intermediate widths. The app name keeps the
  applied width during that wait; surface geometry and the newly fitted name
  are committed in one Mach transaction, with state advanced only on IPC success.
  A presentation gate also holds app name/icon updates during pending layout,
  including naturally shorter names. Generations reject stale commits; unchanged
  geometry still flushes the new presentation. A later event retries failed sends. Unchanged surfaces are
  not resent. All surfaces are drawn by SketchyBar, with no extra NSPanel windows.
- MenuMeasurement reads top-level AX menu item rectangles on app/window, Space,
  wake, reveal and supported menu events. No recursive submenu walk, polling or
  app-width cache. Title-only notifications never measure menus. Per-item AX timeout
  is 20 ms, and the item walk stops after a 100 ms budget. Stale PID results are
  rejected. AX layout/resize notifications on the menu bar are optional; apps
  may not support them. NSMenu notifications are in-process, not global hooks.
  AX coordinates associate each measurement with its own display. Other monitors
  retain their current measured state, not a cache indexed by applications. Delivery
  is not synchronized with WindowServer drawing; the shrink delay is a heuristic.
- Clock/date and CPU/GPU widgets are absent from the active configuration.
- smooth-slide moves 32 points over 16 sin frames (~267 ms); hiding completes
  after that duration plus 30 ms. Reversals continue at the current offset.
  Revealing the surface does not resend item styles or reload app images.
  NativeBackdrop remains as an unused experimental implementation; the executable
  does not instantiate it. Its additional windows/materials are absent at runtime.
  Experimental fade uses 18 sin frames; default upstream-style slide is retained.
- Signal sources restore visibility on orderly exit without unsafe work in a
  POSIX signal handler.
- build-toggle.sh creates a locally signed SketchyBar Helper.app, launched by
  LaunchServices with its own Accessibility identity. Missing AX permission does
  not disable the background, Spaces or mouse monitoring.

Build: bash build-toggle.sh
Test: swift test --package-path src/sketchybar-toggle
The Homebrew toggle binary is unchanged and is not used as a fallback.
