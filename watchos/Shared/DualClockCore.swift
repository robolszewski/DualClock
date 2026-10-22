// DualClock for Apple Watch v2.2 - shared core (watch app + complications).
// Port of the iOS v2.0 / macOS v1.9 renderer from Core Graphics to SwiftUI Canvas
// (watchOS has no UIKit drawing context). Geometry, colors, layering and the 12h | 12/24 | 24h modes
// are unchanged; only the drawing calls differ.
// v2.2: 12/24 mode: the top 12 and 24 now swap too (at 13:00). "Two Hands" app icon.
//       12h dial: sun (AM) / crescent moon (PM) beside the zone label, and beside UTC when it differs.

import SwiftUI

// MARK: - Dial modes

enum DialMode: Int, CaseIterable {
    case twelve = 0      // 1-12 dial, 12-hour readout
    case dual = 1        // 1-12 dial with an inner 13-24 ring (railway style), 24-hour readout
    case twentyFour = 2  // 00-23 dial, hour hand turns once a day, 24-hour readout

    var handsUse24: Bool { return self == .twentyFour }
    var readoutUse24: Bool { return self != .twelve }
    var next: DialMode { return DialMode(rawValue: (rawValue + 1) % 3)! }

    var label: String {
        switch self {
        case .twelve: return "12h"
        case .dual: return "12/24"
        case .twentyFour: return "24h"
        }
    }

    var longName: String {
        switch self {
        case .twelve: return "12-hour"
        case .dual: return "12-hour + 13–24 ring"
        case .twentyFour: return "24-hour"
        }
    }
}

extension TimeZone {
    static let utcZone = TimeZone(identifier: "UTC")!
}

// MARK: - Time components in a given zone

struct ClockTime {
    let year: Int, month: Int, day: Int
    let hour: Int, minute: Int, second: Int, nanos: Int

    init(_ date: Date, _ tz: TimeZone) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date)
        year = c.year ?? 2000; month = c.month ?? 1; day = c.day ?? 1
        hour = c.hour ?? 0; minute = c.minute ?? 0; second = c.second ?? 0; nanos = c.nanosecond ?? 0
    }

    var ymd: Int { return year * 10000 + month * 100 + day }
}

// MARK: - Text formatting

enum ClockFormat {
    static let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    static func monthAbbrev(_ t: ClockTime) -> String { return months[max(0, min(11, t.month - 1))] }

    static func time(_ t: ClockTime, _ is24: Bool, _ sec: Bool) -> String {
        if is24 {
            return sec ? String(format: "%02d:%02d:%02d", t.hour, t.minute, t.second)
                       : String(format: "%02d:%02d", t.hour, t.minute)
        }
        var h = t.hour % 12
        if h == 0 { h = 12 }
        let ap = t.hour < 12 ? "AM" : "PM"
        let core = sec ? String(format: "%d:%02d:%02d", h, t.minute, t.second)
                       : String(format: "%d:%02d", h, t.minute)
        return core + " " + ap
    }

    // "+1d" / "-1d" when the UTC date differs from the local date, else ""
    static func dayOffset(local: ClockTime, utc: ClockTime) -> String {
        if utc.ymd > local.ymd { return "+1d" }
        if utc.ymd < local.ymd { return "-1d" }
        return ""
    }

    // "EDT", "PST", "CEST"... Falls back to initials of the long name, then "Local".
    static func zoneAbbrev(_ tz: TimeZone, at date: Date) -> String {
        if let a = tz.abbreviation(for: date), (2...5).contains(a.count), a.allSatisfy({ $0.isLetter }) {
            return a
        }
        let style: NSTimeZone.NameStyle = tz.isDaylightSavingTime(for: date) ? .daylightSaving : .standard
        let name = tz.localizedName(for: style, locale: Locale(identifier: "en_US")) ?? ""
        var abbr = ""
        for w in name.split(separator: " ") {
            if let f = w.first, f.isLetter { abbr += String(f).uppercased() }
        }
        return (2...5).contains(abbr.count) ? abbr : "Local"
    }
}

// MARK: - Colors

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: Int = 255) -> Color {
    return Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
}

struct ClockPalette {
    var background, face, rim, ink, soft, tick, second, utcHand, utcText: Color

    // Same colors as Windows/macOS/iOS. The window background is black on the watch so the face
    // blends into the bezel (the paper tone would light up the whole OLED).
    static let day = ClockPalette(
        background: .black,
        face: rgb(255, 255, 255),
        rim: rgb(40, 44, 52),
        ink: rgb(28, 30, 36),
        soft: rgb(90, 94, 102),
        tick: rgb(120, 124, 132),
        second: rgb(214, 48, 49),
        utcHand: rgb(92, 150, 214, 150),
        utcText: rgb(92, 132, 190))

    // Always-on (wrist down): dark face, light hands, no second hand.
    static let dim = ClockPalette(
        background: .black,
        face: rgb(16, 16, 18),
        rim: rgb(64, 68, 76),
        ink: rgb(196, 198, 204),
        soft: rgb(120, 124, 132),
        tick: rgb(84, 88, 96),
        second: rgb(150, 40, 40),
        utcHand: rgb(92, 150, 214, 150),
        utcText: rgb(92, 132, 190))

    // Complications: solid blue so the UTC hand reads on dark watch faces.
    static let complicationUTC = rgb(92, 150, 214)
}

// MARK: - Drawing helpers

enum Draw {
    static func polar(_ c: CGPoint, _ deg: CGFloat, _ r: CGFloat) -> CGPoint {
        let a = (deg - 90) * .pi / 180
        return CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
    }

    static func line(_ ctx: inout GraphicsContext, _ p1: CGPoint, _ p2: CGPoint, _ col: Color, _ w: CGFloat, round: Bool) {
        var p = Path()
        p.move(to: p1)
        p.addLine(to: p2)
        ctx.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: w, lineCap: round ? .round : .butt))
    }

    // Straight hand with round caps and a short tail behind the center
    static func hand(_ ctx: inout GraphicsContext, _ c: CGPoint, _ deg: CGFloat, _ length: CGFloat,
                     _ tail: CGFloat, _ width: CGFloat, _ col: Color) {
        line(&ctx, polar(c, deg, -tail), polar(c, deg, length), col, width, round: true)
    }

    static func dot(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ col: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(col))
    }

    static func font(_ size: CGFloat, _ weight: Font.Weight, mono: Bool = false) -> Font {
        let f = Font.system(size: max(6, size), weight: weight)
        return mono ? f.monospacedDigit() : f
    }

    static func text(_ ctx: inout GraphicsContext, _ s: String, _ f: Font, _ col: Color,
                     at p: CGPoint, anchor: UnitPoint = .center) {
        ctx.draw(Text(verbatim: s).font(f).foregroundStyle(col), at: p, anchor: anchor)
    }

    static func size(_ ctx: inout GraphicsContext, _ s: String, _ f: Font) -> CGSize {
        return ctx.resolve(Text(verbatim: s).font(f)).measure(in: CGSize(width: 10_000, height: 10_000))
    }

    static func hourAngle(_ t: ClockTime, is24: Bool) -> CGFloat {
        let sec = Double(t.second) + Double(t.nanos) / 1e9
        let hrs = Double(t.hour) + (Double(t.minute) + sec / 60) / 60
        return CGFloat(is24 ? hrs * 15 : hrs.truncatingRemainder(dividingBy: 12) * 30)
    }

    static func minuteAngle(_ t: ClockTime) -> CGFloat {
        let sec = Double(t.second) + Double(t.nanos) / 1e9
        return CGFloat((Double(t.minute) + sec / 60) * 6)
    }
}

// MARK: - Full dial (watch app). Same proportions as every other DualClock.

enum DialRenderer {
    static func drawDial(_ ctx: inout GraphicsContext, center c: CGPoint, radius R: CGFloat,
                         date: Date, localTZ: TimeZone, zone: String, mode: DialMode,
                         showSeconds: Bool, palette p: ClockPalette) {
        let local = ClockTime(date, localTZ)
        let utc = ClockTime(date, .utcZone)

        drawFace(&ctx, c, R, mode, zone, local.hour, p)
        if mode == .twelve { drawMeridiem(&ctx, c, R, zone, local.hour, utc.hour, p) }
        drawDate(&ctx, c, R, local, mode == .dual ? R * 0.33 : R * 0.38, p) // pulled in to clear the inner ring

        // UTC hands first (underneath). Seconds are identical in every zone, so UTC gets no second hand.
        drawHands(&ctx, c, R, utc, mode.handsUse24, p.utcHand, p.utcHand, false)
        drawHands(&ctx, c, R, local, mode.handsUse24, p.ink, p.second, showSeconds)

        // Center cap
        let cap = R * 0.045
        Draw.dot(&ctx, c, cap, p.ink)
        if showSeconds { Draw.dot(&ctx, c, cap * 0.5, p.second) }
    }

    private static func drawFace(_ ctx: inout GraphicsContext, _ c: CGPoint, _ R: CGFloat,
                                 _ mode: DialMode, _ zone: String, _ hour: Int, _ p: ClockPalette) {
        // 12/24 dial: 1-11 swap with 13-23 at noon; the top pair (12 / 24) swaps at 13:00, so the outer
        // ring reads 12 while the hour hand is there (12:00-12:59) and 24 after that.
        let pm = hour >= 12, topSwap = hour >= 13
        let is24 = mode == .twentyFour // the 12/24 dial uses the 12-hour face plus an inner ring
        let disc = Path(ellipseIn: CGRect(x: c.x - R, y: c.y - R, width: 2 * R, height: 2 * R))
        ctx.fill(disc, with: .color(p.face))
        ctx.stroke(disc, with: .color(p.rim), lineWidth: max(2, R * 0.035))

        // Minute ticks (60)
        for i in 0..<60 {
            let five = !is24 && i % 5 == 0 // on the 24h dial, hour marks come from the loop below
            let len = five ? R * 0.09 : R * 0.04
            let w = five ? max(2, R * 0.018) : max(1, R * 0.007)
            let a = CGFloat(i) * 6
            Draw.line(&ctx, Draw.polar(c, a, R * 0.94 - len), Draw.polar(c, a, R * 0.94), p.tick, w, round: false)
        }

        if is24 {
            for h in 0..<24 {
                let major = h % 6 == 0
                let len = major ? R * 0.10 : R * 0.065
                let w = major ? max(2.5, R * 0.022) : max(1.5, R * 0.012)
                let a = CGFloat(h) * 15
                Draw.line(&ctx, Draw.polar(c, a, R * 0.94 - len), Draw.polar(c, a, R * 0.94),
                          major ? p.ink : p.tick, w, round: false)
            }
        }

        // Numerals
        let count = is24 ? 24 : 12
        let dual = mode == .dual
        let px = is24 ? R * 0.105 : (dual ? R * 0.14 : R * 0.16)
        let f = Draw.font(px, .regular)
        let fb = Draw.font(px, .bold)
        let rr = is24 ? R * 0.72 : (dual ? R * 0.745 : R * 0.73)
        for i in 0..<count {
            // 12/24 dial after noon: the 13-23 numbers take the big outer ring; 24 joins them from 13:00.
            let label = is24 ? i : (i == 0 ? (dual && topSwap ? 24 : 12) : (dual && pm ? i + 12 : i))
            let txt = is24 ? String(format: "%02d", label) : String(label)
            let major = is24 ? i % 6 == 0 : i % 3 == 0
            let pt = Draw.polar(c, CGFloat(i) * 360 / CGFloat(count), rr)
            Draw.text(&ctx, txt, major ? fb : f, major ? p.ink : p.soft, at: pt)
        }

        // 12/24 dial: inner ring, smaller and faded, just inside each main numeral (railway-station style).
        if dual {
            let fi = Draw.font(R * 0.08, .regular)
            let ri = R * 0.58
            for i in 0..<12 {
                // 13-23 in the morning, 1-11 after noon; 24 on top until 13:00, then 12.
                let txt = String(i == 0 ? (topSwap ? 12 : 24) : (pm ? i : i + 12))
                Draw.text(&ctx, txt, fi, p.soft.opacity(0.6), at: Draw.polar(c, CGFloat(i) * 30, ri))
            }
        }

        // Legend on the dial
        let lf = Draw.font(R * 0.08, .bold)
        Draw.text(&ctx, zone, lf, p.ink, at: CGPoint(x: c.x, y: c.y - R * 0.40), anchor: .top)
        Draw.text(&ctx, "UTC", lf, p.utcText, at: CGPoint(x: c.x, y: c.y + R * 0.30), anchor: .top)
    }

    // AM/PM symbols (12h dial only): sun = AM, crescent moon = PM, just right of the zone and UTC labels.
    // The UTC symbol only appears when UTC is on the other side of noon from local time.
    private static func drawMeridiem(_ ctx: inout GraphicsContext, _ c: CGPoint, _ R: CGFloat, _ zone: String,
                                     _ localHour: Int, _ utcHour: Int, _ p: ClockPalette) {
        let localPM = localHour >= 12, utcPM = utcHour >= 12
        let lf = Draw.font(R * 0.08, .bold)
        let fs = max(6, R * 0.08)
        let s = fs * 1.15                                  // symbol box, a little larger than the label font
        let zoneSize = Draw.size(&ctx, zone, lf)
        let midOff = zoneSize.height * 0.5                 // label top -> middle of the text line
        symbol(&ctx, CGPoint(x: c.x + zoneSize.width / 2 + s * 0.62, y: c.y - R * 0.40 + midOff), s, localPM, p.ink)
        if utcPM != localPM {
            let wUtc = Draw.size(&ctx, "UTC", lf).width
            symbol(&ctx, CGPoint(x: c.x + wUtc / 2 + s * 0.62, y: c.y + R * 0.30 + midOff), s, utcPM, p.utcText)
        }
    }

    private static func symbol(_ ctx: inout GraphicsContext, _ pt: CGPoint, _ s: CGFloat, _ moon: Bool, _ col: Color) {
        if moon {
            // Crescent: a disc with an offset disc cut out, horns pointing right
            let r = s * 0.42, rc = s * 0.36
            let disc = Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: 2 * r, height: 2 * r))
            let cut = Path(ellipseIn: CGRect(x: pt.x - rc + s * 0.22, y: pt.y - rc - s * 0.12, width: 2 * rc, height: 2 * rc))
            ctx.fill(disc.subtracting(cut), with: .color(col))
        } else {
            // Sun: small disc with 8 short rays
            Draw.dot(&ctx, pt, s * 0.21, col)
            for i in 0..<8 {
                Draw.line(&ctx, Draw.polar(pt, CGFloat(i) * 45, s * 0.33), Draw.polar(pt, CGFloat(i) * 45, s * 0.48),
                          col, max(1, s * 0.09), round: true)
            }
        }
    }

    // Local date in fixed-size windows (sized for "MMM" / "00"); drawn before the hands so they sweep over it.
    private static func drawDate(_ ctx: inout GraphicsContext, _ c: CGPoint, _ R: CGFloat,
                                 _ t: ClockTime, _ off: CGFloat, _ p: ClockPalette) {
        let mon = ClockFormat.monthAbbrev(t)
        let day = String(format: "%02d", t.day)
        let f = Draw.font(R * 0.085, .bold, mono: true)
        let wMon = Draw.size(&ctx, "MMM", f).width
        let wDay = Draw.size(&ctx, "00", f).width
        let h = max(6, R * 0.085) * 1.35
        let padX = R * 0.04
        let rMon = CGRect(x: c.x - off - wMon / 2 - padX, y: c.y - h / 2, width: wMon + 2 * padX, height: h)
        let rDay = CGRect(x: c.x + off - wDay / 2 - padX, y: c.y - h / 2, width: wDay + 2 * padX, height: h)
        let lw = max(1, R * 0.008)
        ctx.stroke(Path(rMon), with: .color(p.ink), lineWidth: lw)
        ctx.stroke(Path(rDay), with: .color(p.ink), lineWidth: lw)
        Draw.text(&ctx, mon, f, p.ink, at: CGPoint(x: rMon.midX, y: rMon.midY))
        Draw.text(&ctx, day, f, p.ink, at: CGPoint(x: rDay.midX, y: rDay.midY))
    }

    private static func drawHands(_ ctx: inout GraphicsContext, _ c: CGPoint, _ R: CGFloat, _ t: ClockTime,
                                  _ is24: Bool, _ handColor: Color, _ secColor: Color, _ showSec: Bool) {
        Draw.hand(&ctx, c, Draw.hourAngle(t, is24: is24), R * 0.52, R * 0.09, max(3, R * 0.055), handColor)
        // Identical geometry for local and UTC, so the local hand fully covers the UTC one in whole-hour zones.
        Draw.hand(&ctx, c, Draw.minuteAngle(t), R * 0.80, R * 0.11, max(2, R * 0.034), handColor)
        if showSec {
            Draw.hand(&ctx, c, CGFloat(t.second) * 6, R * 0.86, R * 0.18, max(1, R * 0.012), secColor) // ticking
        }
    }

    // Two-line readout; shrinks to fit the width.
    static func drawReadout(_ ctx: inout GraphicsContext, in area: CGRect, date: Date, localTZ: TimeZone,
                            zone: String, use24: Bool, seconds: Bool, palette p: ClockPalette) {
        let local = ClockTime(date, localTZ)
        let utc = ClockTime(date, .utcZone)
        let off = ClockFormat.dayOffset(local: local, utc: utc)
        let top = zone + "  " + ClockFormat.time(local, use24, seconds)
        let bot = "UTC  " + ClockFormat.time(utc, use24, seconds) + (off.isEmpty ? "" : "  " + off)

        var px = max(9, area.height * 0.36)
        let widest = max(Draw.size(&ctx, top, Draw.font(px, .bold, mono: true)).width,
                         Draw.size(&ctx, bot, Draw.font(px * 0.78, .regular, mono: true)).width)
        if widest > area.width, widest > 0 { px = max(7, px * area.width / widest) }

        let topColor = p.face == ClockPalette.day.face ? Color.white : p.ink // light text on the black background
        Draw.text(&ctx, top, Draw.font(px, .bold, mono: true), topColor,
                  at: CGPoint(x: area.midX, y: area.minY + area.height * 0.275))
        Draw.text(&ctx, bot, Draw.font(px * 0.78, .regular, mono: true), p.utcText,
                  at: CGPoint(x: area.midX, y: area.minY + area.height * 0.745))
    }
}

// MARK: - Mini dial (complications): ticks + hands only, in three layers so WidgetKit can tint the UTC layer.

enum MiniDial {
    static func ticks(_ ctx: inout GraphicsContext, _ c: CGPoint, _ R: CGFloat, _ mode: DialMode, _ col: Color) {
        let n = mode == .twentyFour ? 24 : 12
        for i in 0..<n {
            let major = mode == .twentyFour ? i % 6 == 0 : i % 3 == 0
            let a = CGFloat(i) * 360 / CGFloat(n)
            Draw.line(&ctx, Draw.polar(c, a, R * (major ? 0.74 : 0.84)), Draw.polar(c, a, R * 0.96),
                      col.opacity(major ? 1 : 0.5), max(1, R * (major ? 0.09 : 0.05)), round: false)
        }
    }

    // Same proportions as the full dial's hands, a bit bolder so they read at complication size.
    static func hands(_ ctx: inout GraphicsContext, _ c: CGPoint, _ R: CGFloat, _ t: ClockTime,
                      _ mode: DialMode, _ col: Color) {
        Draw.hand(&ctx, c, Draw.hourAngle(t, is24: mode.handsUse24), R * 0.52, R * 0.08, max(1.5, R * 0.12), col)
        Draw.hand(&ctx, c, Draw.minuteAngle(t), R * 0.82, R * 0.10, max(1, R * 0.075), col)
    }

    static func geometry(_ size: CGSize) -> (CGPoint, CGFloat) {
        return (CGPoint(x: size.width / 2, y: size.height / 2), min(size.width, size.height) / 2)
    }
}
