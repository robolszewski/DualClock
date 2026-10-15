# DualClock — Rebuild Prompt (matches source v1.5)

Copy everything below the line into a new Claude conversation.

---

Build me a native Windows analog desk clock called **DualClock** that shows **local time (primary)** and **UTC (secondary)** on a single analog face. Deliver a single C# source file and a one-click build batch file. Name all files `YYYY-MM-DD_vX.X_FileName`, using today's date.

## Platform and build
- Use C# **WinForms** and write it in **C# 5 syntax**: no string interpolation, no `=>` members, no `?.`, no `nameof`. That way it compiles with the `csc.exe` built into Windows (`%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe`, falling back to `Framework\`), with nothing to install.
- Reference only `System.Windows.Forms.dll` and `System.Drawing.dll`, and use `/target:winexe /optimize+`. Output is `DualClock.exe`.
- **Build.bat** (CRLF line endings) should:
  - find csc and compile the source in its own folder;
  - use PowerShell + `WScript.Shell` to create two shortcuts in that folder: **"DualClock 12h"** (target `DualClock.exe /12`) and **"DualClock 24h"** (target `DualClock.exe /24`);
  - launch both.
- If possible, test-compile with Mono `mcs -langversion:5` and render preview PNGs before delivering.

## Command line and settings
- `/12` or `/24` (also accept `-12`/`-24`) forces that dial mode and uses a **separate settings file** (`%APPDATA%\DualClock\settings-12.ini` / `settings-24.ini`). With no argument, use `settings.ini`.
- Settings to save: `Use24Hour`, `TopMost`, `ShowSeconds`, `ShowDigital`, `X`, `Y`, `W`, `H`.
  - Simple key=value INI. Save on every change and on close; read and write errors are ignored silently.
  - Restore the saved position only if it is on a visible screen.
  - Otherwise place the window at the top-right of the primary work area. On first run the 24h window is shifted left by its width + 10 px so the two clocks sit side by side.
- Hidden test hook: `DualClock.exe --render out.png [12|24]` renders a 420×520 PNG.
  - Fixed time: UTC 2026-10-15 15:28:42, local = UTC−4, zone label "EDT", seconds and digital readout on.
  - Exits without showing a window.

## Window and controls
- Title: "Dual Clock - Local / UTC". Default size 380×470, minimum 220×260, resizable; the clock scales with the window.
- Double-buffered; repaint every 200 ms.
- **Right-click menu:**
  - 12-hour dial / 24-hour dial (radio-style checks)
  - separator
  - Show second hand
  - Show digital readout
  - Always on top
  - separator
  - Exit
- Keys: **T** toggles 12/24, **Esc** exits. **Double-click** toggles always-on-top.

## Visual design (all sizes scale off dial radius R)
- **Colors:**
  - window background `#F4F3EF`; face white; rim `#282C34`
  - ink (local hands, numerals, local labels) `#1C1E24`
  - local second hand red `#D63031`
  - UTC hands `ARGB(150, 92,150,214)`, a translucent soft blue
  - UTC text `#5C84BE`
  - ticks `#787C84`
- **Layout:** padding = max(10, min(w,h)/30). The digital readout area height is max(54, h/7) when shown. The dial is centered horizontally near the top.
- **Face:** white fill, rim width max(2, 0.035R). Ticks run inward from 0.94R.
  - **12h:** 60 minute ticks; every 5th is longer (0.09R) and thicker.
  - **24h:** 60 thin minute ticks, plus 24 hour ticks. Hours 0/6/12/18 are major (0.10R, ink color); the rest are 0.065R in tick color.
- **Numerals** use Segoe UI. Major numerals are bold ink; the others are gray `#5A5E66`.
  - **12h:** 1–12, with 12 at the top, at radius 0.73R, size 0.16R. 12/3/6/9 are major.
  - **24h:** 00–23 (two digits), with 00 at the top and 12 at the bottom, at radius 0.72R, size 0.105R. 00/06/12/18 are major.
- **On-dial labels** (Segoe UI Semibold, bold):
  - local zone abbreviation (e.g. "EDT") in **black** at center − 0.40R, size 0.08R;
  - **"UTC"** in UTC blue at center + 0.30R.
  - Get the zone abbreviation from the initials of the current Windows zone name (standard or daylight as appropriate, e.g. "Eastern Daylight Time" → EDT). Fall back to "Local" if the result isn't 2–5 letters.
- **Date windows** show the **local** date, drawn before the hands so the hands sweep over them.
  - Left of center at −0.38R: 3-letter month in caps ("OCT"). Right at +0.38R: 2-digit day ("15").
  - Text: Segoe UI Semibold bold, size 0.085R, ink.
  - Each sits in a **thin black-outlined rectangle** (pen max(1, 0.008R)). The box is a fixed size: the measured width of "MMM" for the month and "00" for the day, + 0.025R padding on each side, height = font size × 1.35.

## Hands
- **12h dial:** hour hand = (hour mod 12) × 30°. **24h dial:** hour hand = hour × 15°, one revolution per day, 00 at the top. On both dials, minute = 6°/min. All hands move smoothly except the second hand, which ticks in whole seconds.
- **Hand geometry, identical for local and UTC** (round caps, with a short tail behind center):
  - hour: length 0.52R, tail 0.09R, width max(3, 0.055R)
  - minute: length 0.80R, tail 0.11R, width max(2, 0.034R)
  - second (local only): length 0.86R, tail 0.18R, width max(1, 0.012R), red
- **Layering:** draw the UTC hour and minute hands first (blue), then the local hands on top (ink), then the second hand.
  - Because the geometry is identical, the UTC minute hand stays fully hidden under the local one in whole-hour offset zones. It only shows in half- and quarter-hour zones (India, Newfoundland, Nepal, etc.).
  - There is **no UTC second hand**.
- **Center cap:** ink circle of radius 0.045R, plus a small red dot when the second hand is on.

## Digital readout (below the dial, toggleable)
- Top line, bold ink: `<ZONE>  <local time>`.
- Second line, smaller (0.78×), in UTC blue: `UTC  <utc time>`, followed by `  +1d` or `  -1d` when the UTC date differs from the local date.
- Format: 24h `HH:mm:ss`, 12h `h:mm:ss tt` (invariant culture). Drop the seconds when the second hand is off.

## Design history (for context)
- An earlier version removed the UTC minute hand. That was reverted, because it's needed in non-whole-hour zones.
- If the faded blue hour hand on the 24-hour dial is mistaken for a minute hand, the option discussed was to give hour hands a broader, tapered shape.
