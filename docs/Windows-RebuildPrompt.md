# DualClock — Windows Rebuild Prompt (matches source v2.2)

Copy everything below the line into a new Claude conversation. The exact source is `windows/DualClock.cs`. This prompt is for rebuilding the app if that file is lost.

---

Build me a native Windows analog desk clock called **DualClock** that shows **local time (primary)** and **UTC (secondary)** on a single analog face. Deliver a single C# source file and a one-click build batch file. Name all files `YYYY-MM-DD_vX.X_FileName`, using today's date.

## Platform and build
- Use C# **WinForms** and write it in **C# 5 syntax**: no string interpolation, no `=>` members, no `?.`, no `nameof`. That way it compiles with the `csc.exe` built into Windows (`%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe`, falling back to `Framework\`), with nothing to install.
- Reference only `System.Windows.Forms.dll` and `System.Drawing.dll`, and use `/target:winexe /optimize+`. Output is `DualClock.exe`.
- **Build.bat** (CRLF line endings) should:
  - find csc, `taskkill` any running DualClock.exe, then compile twice:
    - Pass 1 is a plain build. Run `DualClock.exe --make-icon DualClock.ico`.
    - Pass 2 builds again with `/win32icon:DualClock.ico`.
  - delete the old "DualClock 12h.lnk" / "DualClock 24h.lnk" shortcuts and create a single **"DualClock"** shortcut using PowerShell + `WScript.Shell`;
  - launch the app.
- If possible, test-compile with Mono `mcs -langversion:5` and render preview PNGs before delivering.

## Dial modes
Three modes, stored as `DialMode` 0/1/2:
- **12h:** a 1–12 dial with a 12-hour readout.
- **12/24 ("dual"):** a 1–12 dial with a faded inner 13–24 ring, railway-station style.
  - Hands run as on the 12-hour dial; the readout is 24-hour.
  - **After noon the rings swap.** 13–23 take the big outer ring and the inner ring shows 1–11. The top pair swaps at 13:00 instead: the outer ring shows 12 (inner 24) through 12:59, then 24 (inner 12) from 13:00 to midnight.
- **24h:** a 00–23 dial. The hour hand turns once a day and the readout is 24-hour.

## Command line and settings
- `/12`, `/dual`, or `/24` (`-` also accepted) sets the starting mode. These switches are optional.
- Settings live in `%APPDATA%\DualClock\settings.ini` (simple key=value): `DialMode`, `TopMost`, `ShowSeconds`, `ShowDigital`, `X`, `Y`, `W`, `H`.
  - Save on every change and on close; read and write errors are ignored silently.
  - **Migration:** if `settings.ini` is missing, read `settings-12.ini` (from v1.5). If there is no `DialMode` key, map `Use24Hour=1` to 24h and anything else to 12h.
  - Restore the saved position only if it is on a visible screen. Otherwise use the top-right of the primary work area.
- Hidden hooks (exit without showing a window):
  - `--render out.png [12|dual|24] [pm]`: renders a 420×520 PNG. Fixed time is UTC 2026-10-15 15:28:42 (or 19:28:42 with `pm`), local = UTC−4, zone "EDT", seconds and readout on.
  - `--render-icon out.png SIZE [tile|full]`: renders the "Two Hands" icon.
  - `--make-icon file.ico`: writes a multi-size ICO.

## Window and controls
- Title: "Dual Clock - Local / UTC". Default size 380×480, minimum 220×270, resizable; the clock scales with the window.
- Double-buffered; repaint every 200 ms.
- **Mode switch:** a pill-shaped `12h | 12/24 | 24h` segmented control in a footer strip at the lower right.
  - Size: segments 44 px wide, 22 px tall, 10 px margin.
  - Look: white track with a tick-gray outline. The selected segment is an ink pill with white text; the others use gray text. Font is Segoe UI Semibold, 12 px.
  - Clicking a segment sets the mode. The hand cursor shows over it, and the hit area is forgiving by 4 px.
- **Right-click menu:**
  - 12-hour dial / 12-hour dial with 13-24 ring / 24-hour dial
  - separator
  - Show second hand
  - Show digital readout
  - Always on top
  - separator
  - Exit
- **Keys:** **T** cycles 12h → 12/24 → 24h; **Esc** exits.
- **Mouse:** double-click (not on the switch) toggles always-on-top. **Dragging anywhere** moves the window, but only once the mouse moves past the system drag threshold (ReleaseCapture + WM_NCLBUTTONDOWN/HTCAPTION), so clicks still work.
- **Taskbar icon:** a live "Two Hands" clock, redrawn once a second as a 64 px bitmap. Use GetHicon, and DestroyIcon the previous handle.
- **Screen readers:** set AccessibleName to "Local h:mm AM, UTC h:mm PM", in 24-hour form for 12/24 and 24h.

## Layout
Let footerH = 32 (switch height + margin).
- **Wide** (width > 1.25 × height):
  - The clock sits in a left column of width min(0.6W, H) when the readout is on (full width when it's off), using the full height, or H − footerH when the readout is off.
  - The readout is centered vertically in the right column (height min(colH, max(60, 0.40 × colWidth))), inset 8 px from the left and 8 + 10 px from the right.
- **Tall:** the clock sits above the readout, and both sit above the footer strip.
  - padding = max(10, min(w,h)/30); readout height = max(54, h/7).
  - Center the clock + readout block vertically in the leftover space.
  - The readout area is inset by the padding on both sides.

## Visual design (all sizes scale off dial radius R)
- **Colors:**
  - background `#F4F3EF`; face white; rim `#282C34`
  - ink `#1C1E24`; second hand red `#D63031`
  - UTC hands `ARGB(150, 92,150,214)`; UTC text `#5C84BE`
  - ticks `#787C84`; soft numerals `#5A5E66`
  - 12/24 inner ring `ARGB(150, 90,94,102)`
- **Face:** white fill, rim width max(2, 0.035R). Ticks run inward from 0.94R.
  - **12h and 12/24:** 60 minute ticks; every 5th is longer (0.09R) and thicker.
  - **24h:** 60 thin minute ticks, plus 24 hour ticks. Hours 0/6/12/18 are major (0.10R, ink color); the rest are 0.065R in tick color.
- **Numerals** use Segoe UI. Major numerals are bold ink; the others are soft gray.
  - **12h:** at radius 0.73R, size 0.16R. **12/24:** at 0.745R, size 0.14R. In both, 12/3/6/9 are major.
  - **24h:** 00–23 at 0.72R, size 0.105R. 00/06/12/18 are major.
  - **12/24 inner ring:** at 0.58R, size 0.08R, in the faded color.
- **On-dial labels** (Segoe UI Semibold bold, 0.08R):
  - the local zone in ink, top edge at center − 0.40R;
  - "UTC" in UTC blue at center + 0.30R.
  - The zone abbreviation is the initials of the Windows zone name (e.g. "Eastern Daylight Time" → EDT). Fall back to "Local" if the result isn't 2–5 letters.
- **AM/PM symbols (12h dial only):** a sun for AM or a crescent moon for PM, just right of each label. Use the label's color.
  - Size: the symbol box s is 1.15 × the label font size. Center it at the label's right edge + 0.62s, at the label's cap-height center (top + 0.72 × font size).
  - The UTC symbol is drawn only when UTC is on the other side of noon from local time.
  - **Sun:** a disc of radius 0.21s, plus 8 round-capped rays from 0.33s to 0.48s, width max(1, 0.09s).
  - **Moon:** a disc of radius 0.42s, minus a disc of radius 0.36s offset by (+0.22s, −0.12s), using Region.Exclude.
- **Date windows:** show the local date, drawn before the hands.
  - Month (3 letters, caps) on the left and the 2-digit day on the right, at ±0.38R from center (±0.33R in 12/24, to clear the inner ring).
  - Text: Segoe UI Semibold bold, 0.085R.
  - Each sits in a fixed-size black-outlined box: the width of "MMM" or "00" + 0.025R padding on each side, height = font size × 1.35, pen max(1, 0.008R).

## Hands
- **12h and 12/24:** hour angle = (hour mod 12) × 30°. **24h:** hour × 15°. On all dials, minute = 6°/min. All hands move smoothly except the second hand, which ticks in whole seconds.
- **Geometry, identical for local and UTC** (round caps, with a tail behind center):
  - hour: length 0.52R, tail 0.09R, width max(3, 0.055R)
  - minute: length 0.80R, tail 0.11R, width max(2, 0.034R)
  - second (local only, red): length 0.86R, tail 0.18R, width max(1, 0.012R)
- **Layering:** draw the UTC hands first (blue), then the local hands on top, then the second hand. The UTC minute hand only shows in half- and quarter-hour zones. There is no UTC second hand.
- **Center cap:** ink circle of radius 0.045R, plus a red dot (half that size) when the second hand is on.

## Digital readout
- Top line, Segoe UI Semibold bold, ink: `<ZONE>  <local time>`. Second line, Segoe UI at 0.78× size, UTC blue: `UTC  <utc time>`, followed by `  +1d` or `  -1d` when the UTC date differs.
- Font size starts at max(10, 0.36 × area height). **Shrink it to fit** if either line is wider than the area (minimum 8 px). Use NoWrap.
- Format: 24h `HH:mm:ss`, 12h `h:mm:ss tt` (invariant culture). Drop the seconds when the second hand is off.

## "Two Hands" icon
- A slate gradient from `#343A46` at the top to `#16181E`.
  - **Tile** variant: superellipse (exponent 5) covering 88% of the canvas (96% at ≤48 px), transparent outside.
  - **Full** variant: an opaque square, for iOS and watchOS.
- White face, radius 0.41 × the tile size.
- 12 hour ticks running from 0.74R/0.82R out to 0.92R: 12/3/6/9 in bold ink, the others light gray `#969AA2`.
- Hands:
  - UTC hour: `ARGB(170, 92,150,214)`, length 0.52R, width 0.10R
  - local hour: ink, 0.50R, width 0.11R
  - minute: ink, 0.80R, width 0.065R
  - second: red, 0.86R, width 0.025R, only at sizes ≥ 64 px
- Center cap: ink, 0.07R, with a red dot.
- The static icon time is 10:10:33 local, with UTC five hours ahead.
- The ICO holds PNG entries at 16, 24, 32, 48, 64, 128 and 256 px.

## Design history (for context)
- An earlier version removed the UTC minute hand. That was reverted, because it's needed in non-whole-hour zones.
- v1.5 shipped separate 12h/24h shortcuts. v2.2 replaced them with one app and a corner switch, matching macOS, iOS and watchOS.
