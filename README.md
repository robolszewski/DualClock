# DualClock

An analog desk clock that shows **local time** (ink hands) and **UTC** (translucent blue hands) on a single face, with the local date in two small windows and an optional digital readout.

The local and UTC hands share identical geometry, so in whole-hour time zones the UTC minute hand hides under the local one. It only appears in half- and quarter-hour zones (India, Newfoundland, Nepal).

## Platforms

| Folder | Platform | Version | Tech |
|---|---|---|---|
| `windows/` | Windows 10/11 | 1.5 | C# 5 / WinForms, no install needed |
| `macos/` | macOS 11+ | 1.9 | Swift / AppKit, single file |
| `ios/DualClock.swiftpm` | iPhone + iPad, iOS 17+ | 2.0 | SwiftUI shell + Core Graphics |

## Building

**Windows** — double-click `windows/Build.bat`. It compiles with the `csc.exe` built into Windows, creates "DualClock 12h" and "DualClock 24h" shortcuts, and launches both.

**macOS** — in Terminal: `bash macos/Build.command`. Needs Apple's Command Line Tools (the script offers to install them). Produces `DualClock.app` with its "Two Hands" icon.

**iPhone / iPad** — open `ios/DualClock.swiftpm` in Swift Playgrounds (iPad or Mac) or Xcode 15+, then run. The `AppIcon` asset is an empty placeholder; drop in a 1024×1024 PNG to set the icon.

## Dial modes

- **12h** — standard 1–12 dial
- **12/24** (macOS, iOS) — 12-hour dial with a faded inner 13–24 ring that swaps places after noon; 24-hour readout
- **24h** — 00–23 dial, hour hand turns once a day

## Controls

| | Windows | macOS | iOS |
|---|---|---|---|
| Change dial | Right-click menu, **T** | Corner switch, menu, **T** | Corner switch, options |
| Options | Right-click | Right-click | ••• or long-press |
| Always on top | Double-click | Double-click | — |
| Quit | Esc | Esc, ⌘Q | — |

## Versions

Releases are tagged (`windows-v1.5`, `macos-v1.5`, `macos-v1.9`, `ios-v2.0`). `docs/Windows-RebuildPrompt.md` contains the full Windows v1.5 spec.

## License

MIT — see [LICENSE](LICENSE).
