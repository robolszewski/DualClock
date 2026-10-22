# DualClock

An analog desk clock that shows **local time** (ink hands) and **UTC** (translucent blue hands) on a single face, with the local date in two small windows and an optional digital readout.

The local and UTC hands share identical geometry, so in whole-hour time zones the UTC minute hand hides under the local one. It only appears in half- and quarter-hour zones (India, Newfoundland, Nepal).

## Platforms

| Folder | Platform | Version | Tech |
|---|---|---|---|
| `windows/` | Windows 10/11 | 2.2 | C# 5 / WinForms, no install needed |
| `macos/` | macOS 11+ | 2.2 | Swift / AppKit, single file |
| `ios/DualClock.swiftpm` | iPhone + iPad, iOS 17+ | 2.2 | SwiftUI shell + Core Graphics |
| `watchos/` | Apple Watch, watchOS 10+ | 2.2 | SwiftUI Canvas app + WidgetKit complications |

Every platform has the same face, all three dial modes, and the "Two Hands" app icon.

## Building

**Windows**: double-click `windows/Build.bat`. It compiles with the `csc.exe` built into Windows, embeds the "Two Hands" icon, replaces the old "DualClock 12h"/"DualClock 24h" shortcuts with a single "DualClock" shortcut, and launches the app.

**macOS**: in Terminal, run `bash macos/Build.command`. It needs Apple's Command Line Tools (the script offers to install them) and produces `DualClock.app` with its "Two Hands" icon.

**iPhone / iPad**: open `ios/DualClock.swiftpm` in Swift Playgrounds (iPad or Mac) or Xcode 15+, then run.

**Apple Watch**: open `watchos/DualClockWatch.xcodeproj` in Xcode 16+ (Swift Playgrounds can't build watch apps).
1. For both targets, *DualClock* and *DualClockComplications*, pick your team under Signing & Capabilities.
2. Choose the **DualClock** scheme with your watch as the destination, and run.
3. To add a complication, long-press the watch face → Edit → Complications → DualClock (12h, 12/24 or 24h).

A free Apple ID works, but the app expires after 7 days.

Apple doesn't allow third-party watch faces, so the watch version comes in two parts:
- **App**: the full DualClock face. Set Settings → General → Return to Clock → *After 1 hour* and it stays up after a wrist raise, like a face. In always-on mode it switches to a dark face, drops the second hand, and updates once a minute.
- **Complications** on Apple's own faces (hands step once a minute, with no second hand, because WidgetKit can't animate):
  - circular / corner: a mini dial
  - rectangular: mini dial + both times + date
  - inline: UTC time

## Dial modes

- **12h**: standard 1–12 dial, with a sun (AM) or crescent moon (PM) beside the zone label, and beside "UTC" when UTC is on the other side of noon
- **12/24**: 12-hour dial with a faded inner 13–24 ring that swaps places after noon (12 and 24 swap at 13:00, while the hour hand is away from the top); 24-hour readout
- **24h**: 00–23 dial; the hour hand turns once a day

## Controls

| | Windows | macOS | iOS | watchOS |
|---|---|---|---|---|
| Change dial | Corner switch, menu, **T** | Corner switch, menu, **T** | Corner switch, options | Digital Crown, options |
| Options | Right-click | Right-click | ••• or long-press | Long-press |
| Digital readout | Menu | Menu | Options | Tap, options |
| Always on top | Double-click | Double-click | — | — |
| Move window | Drag anywhere | Drag anywhere | — | — |
| Quit | Esc | Esc, ⌘Q | — | — |

Wide windows on Windows and macOS (and landscape on iPhone/iPad) put the readout beside the clock, and the readout shrinks to fit narrow windows. The Windows taskbar icon and the macOS Dock icon are a live clock. Screen readers (Narrator, VoiceOver) read both times.

## Versions

Each release is its own commit: Windows v1.5 → macOS v1.5 → macOS v1.9 → iOS v2.0 → watchOS v2.1 → v2.2. `git log` shows the history and diffs.

v2.2 brought every platform to parity:
- **Windows** caught up with the 12/24 mode, corner switch, single app, wide layout, readout fitting, icon, live taskbar clock and drag-to-move.
- **macOS** gained the wide layout, readout fitting and VoiceOver.
- **iOS and watchOS** got the app icon.

`docs/Windows-RebuildPrompt.md` contains the full Windows v2.2 spec.

## License

MIT; see [LICENSE](LICENSE).
