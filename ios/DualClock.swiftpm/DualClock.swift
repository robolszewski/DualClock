// DualClock for iOS / iPadOS v2.2 - Analog clock showing Local (primary) and UTC (secondary) time.
// Port of DualClock for macOS v1.9. Same face, hands, colors, date windows, readout, and 12h | 12/24 | 24h modes.
// v2.0: iPhone + iPad. Touch-sized mode switch, options sheet, landscape layout (readout beside the clock),
//       safe-area aware, readout auto-fits its width, optional "keep screen awake" for desk/nightstand use.
// v2.2: "Two Hands" app icon. 12/24 mode: the top 12 and 24 now swap too (at 13:00).
//       12h dial: sun (AM) / crescent moon (PM) beside the zone label, and beside UTC when it differs.
// SwiftUI app shell + UIKit/Core Graphics renderer. Open the .swiftpm in Swift Playgrounds (iPad or Mac) or Xcode.
//
// Controls:
//   12h | 12/24 | 24h switch ...... tap (lower right) to change dial mode
//   ••• button .................... options (dial mode, second hand, digital readout, keep screen awake)
//   Long-press anywhere ........... options
//   T (hardware keyboard) ......... cycle 12h -> 12/24 -> 24h

import SwiftUI
import UIKit

// MARK: - Dial modes

enum DialMode: Int {
    case twelve = 0      // 1-12 dial, 12-hour readout
    case dual = 1        // 1-12 dial with an inner 13-24 ring (railway style), 24-hour readout
    case twentyFour = 2  // 00-23 dial, hour hand turns once a day, 24-hour readout

    var handsUse24: Bool { return self == .twentyFour }
    var readoutUse24: Bool { return self != .twelve }
    var next: DialMode { return DialMode(rawValue: (rawValue + 1) % 3)! }
    var switchLabel: String {
        switch self {
        case .twelve: return "12h"
        case .dual: return "12/24"
        case .twentyFour: return "24h"
        }
    }
    static let all: [DialMode] = [.twelve, .dual, .twentyFour]
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

// MARK: - Renderer (UIKit contexts are flipped: y grows downward, same math as the Mac/Windows versions)

enum ClockRenderer {
    static func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: Int = 255) -> UIColor {
        return UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }

    static let background = rgb(244, 243, 239)
    static let faceFill   = rgb(255, 255, 255)
    static let rim        = rgb(40, 44, 52)
    static let ink        = rgb(28, 30, 36)        // local hands + numerals
    static let secondRed  = rgb(214, 48, 49)       // local second hand
    static let utcHand    = rgb(92, 150, 214, 150) // faded blue, ~60% opacity
    static let utcText    = rgb(92, 132, 190)
    static let tick       = rgb(120, 124, 132)
    static let softNum    = rgb(90, 94, 102)

    static let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

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

    // MARK: Footer controls: [•••] [12h | 12/24 | 24h] in the lower-right corner (finger-sized)

    static let segW: CGFloat = 58, switchH: CGFloat = 34, margin: CGFloat = 12, gap: CGFloat = 10
    static var switchW: CGFloat { return segW * CGFloat(DialMode.all.count) }
    static var footerH: CGFloat { return switchH + margin }

    static func switchRect(in s: CGRect) -> CGRect {
        return CGRect(x: s.maxX - switchW - margin, y: s.maxY - switchH - margin, width: switchW, height: switchH)
    }

    static func optionsRect(in s: CGRect) -> CGRect {
        let r = switchRect(in: s)
        return CGRect(x: r.minX - gap - switchH, y: r.minY, width: switchH, height: switchH)
    }

    // nil = tap missed the switch; otherwise the segment tapped
    static func switchHit(_ p: CGPoint, in s: CGRect) -> DialMode? {
        let r = switchRect(in: s)
        guard r.insetBy(dx: -4, dy: -10).contains(p) else { return nil } // forgiving, without reaching the ••• button
        let i = Int((p.x - r.minX) / segW)
        return DialMode.all[max(0, min(DialMode.all.count - 1, i))]
    }

    static func optionsHit(_ p: CGPoint, in s: CGRect) -> Bool {
        return optionsRect(in: s).insetBy(dx: -4, dy: -10).contains(p)
    }

    private static func drawSwitch(_ cg: CGContext, _ s: CGRect, _ mode: DialMode) {
        let r = switchRect(in: s)
        let radius = r.height / 2
        let track = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
        cg.addPath(track)
        cg.setFillColor(faceFill.cgColor)
        cg.fillPath()

        // Selected segment: dark pill
        let idx = DialMode.all.firstIndex(of: mode) ?? 0
        let sel = CGRect(x: r.minX + segW * CGFloat(idx), y: r.minY, width: segW, height: r.height).insetBy(dx: 3, dy: 3)
        let selPath = CGPath(roundedRect: sel, cornerWidth: sel.height / 2, cornerHeight: sel.height / 2, transform: nil)
        cg.addPath(selPath)
        cg.setFillColor(ink.cgColor)
        cg.fillPath()

        cg.addPath(track)
        cg.setStrokeColor(tick.cgColor)
        cg.setLineWidth(1)
        cg.strokePath()

        let f = font(13, .semibold, mono: true)
        for (i, m) in DialMode.all.enumerated() {
            let center = CGPoint(x: r.minX + segW * (CGFloat(i) + 0.5), y: r.midY)
            drawCentered(m.switchLabel, f, m == mode ? faceFill : softNum, center)
        }
    }

    private static func drawOptionsButton(_ cg: CGContext, _ s: CGRect) {
        let r = optionsRect(in: s)
        cg.setFillColor(faceFill.cgColor)
        cg.fillEllipse(in: r)
        cg.setStrokeColor(tick.cgColor)
        cg.setLineWidth(1)
        cg.strokeEllipse(in: r.insetBy(dx: 0.5, dy: 0.5))
        let d: CGFloat = 4
        cg.setFillColor(softNum.cgColor)
        for k in -1...1 {
            let x = r.midX + CGFloat(k) * 7
            cg.fillEllipse(in: CGRect(x: x - d / 2, y: r.midY - d / 2, width: d, height: d))
        }
    }

    // full = whole view (background); safe = view minus notch/home-indicator insets (everything else)
    static func draw(_ cg: CGContext, full: CGRect, safe: CGRect, date: Date, localTZ: TimeZone, zone: String,
                     mode: DialMode, showSeconds: Bool, showDigital: Bool) {
        cg.setFillColor(background.cgColor)
        cg.fill(full)
        drawSwitch(cg, safe, mode)
        drawOptionsButton(cg, safe)

        // Layout. Tall (portrait, Mac-like): clock above readout, both above the footer strip, centered vertically.
        // Wide (landscape iPhone/iPad): clock on the left at full height, readout centered in the right column.
        let wide = safe.width > safe.height * 1.25
        let c: CGPoint
        let R: CGFloat
        var digitalArea: CGRect? = nil

        if wide {
            let cw = showDigital ? min(safe.width * 0.6, safe.height) : safe.width
            let colH = showDigital ? safe.height : safe.height - footerH
            let area = CGRect(x: safe.minX, y: safe.minY, width: cw, height: colH)
            let pad = max(10, floor(min(area.width, area.height) / 30))
            let size = min(area.width - 2 * pad, area.height - 2 * pad)
            if size < 50 { return }
            R = size / 2
            c = CGPoint(x: area.midX, y: area.midY)
            if showDigital {
                let right = CGRect(x: safe.minX + cw, y: safe.minY, width: safe.width - cw, height: safe.height - footerH)
                let h = min(right.height, max(60, right.width * 0.40))
                digitalArea = CGRect(x: right.minX + 8, y: right.midY - h / 2, width: right.width - 16 - margin, height: h)
            }
        } else {
            let b = CGRect(x: safe.minX, y: safe.minY, width: safe.width, height: safe.height - footerH)
            let digitalH: CGFloat = showDigital ? max(54, floor(b.height / 7)) : 0
            let pad = max(10, floor(min(b.width, b.height) / 30))
            let size = min(b.width - 2 * pad, b.height - digitalH - 2 * pad)
            if size < 50 { return }
            R = size / 2
            let slack = max(0, b.height - (size + 2 * pad + digitalH))
            c = CGPoint(x: b.midX, y: b.minY + slack / 2 + pad + R)
            if showDigital {
                digitalArea = CGRect(x: b.minX + pad, y: c.y + R + pad * 0.5, width: b.width - 2 * pad, height: digitalH)
            }
        }

        let local = ClockTime(date, localTZ)
        let utc = ClockTime(date, TimeZone(identifier: "UTC")!)

        drawFace(cg, c, R, mode, zone, local.hour)
        if mode == .twelve { drawMeridiem(cg, c, R, zone, local.hour, utc.hour) }
        drawDate(cg, c, R, local, mode == .dual ? R * 0.33 : R * 0.38) // pulled in a bit to clear the inner ring

        // UTC hands first (underneath). Seconds are identical in every zone, so UTC gets no second hand.
        drawHands(cg, c, R, utc, mode.handsUse24, utcHand, utcHand, false)
        drawHands(cg, c, R, local, mode.handsUse24, ink, secondRed, showSeconds)

        // Center cap
        let cap = R * 0.045
        cg.setFillColor(ink.cgColor)
        cg.fillEllipse(in: CGRect(x: c.x - cap, y: c.y - cap, width: cap * 2, height: cap * 2))
        if showSeconds {
            let cap2 = cap * 0.5
            cg.setFillColor(secondRed.cgColor)
            cg.fillEllipse(in: CGRect(x: c.x - cap2, y: c.y - cap2, width: cap2 * 2, height: cap2 * 2))
        }

        if let area = digitalArea {
            drawDigital(area, local, utc, zone, mode.readoutUse24, showSeconds)
        }
    }

    // MARK: Face

    private static func drawFace(_ cg: CGContext, _ c: CGPoint, _ R: CGFloat, _ mode: DialMode, _ zone: String, _ hour: Int) {
        // 12/24 dial: 1-11 swap with 13-23 at noon; the top pair (12 / 24) swaps at 13:00, so the outer
        // ring reads 12 while the hour hand is there (12:00-12:59) and 24 after that.
        let pm = hour >= 12, topSwap = hour >= 13
        let is24 = mode == .twentyFour // the 12/24 dial uses the 12-hour face plus an inner ring
        let disc = CGRect(x: c.x - R, y: c.y - R, width: 2 * R, height: 2 * R)
        cg.setFillColor(faceFill.cgColor)
        cg.fillEllipse(in: disc)
        cg.setStrokeColor(rim.cgColor)
        cg.setLineWidth(max(2, R * 0.035))
        cg.strokeEllipse(in: disc)

        // Minute ticks (60)
        for i in 0..<60 {
            let five = !is24 && i % 5 == 0 // on the 24h dial, hour marks come from the loop below
            let len = five ? R * 0.09 : R * 0.04
            let w = five ? max(2, R * 0.018) : max(1, R * 0.007)
            let a = CGFloat(i) * 6
            line(cg, polar(c, a, R * 0.94 - len), polar(c, a, R * 0.94), tick, w, round: false)
        }

        if is24 {
            for h in 0..<24 {
                let major = h % 6 == 0
                let len = major ? R * 0.10 : R * 0.065
                let w = major ? max(2.5, R * 0.022) : max(1.5, R * 0.012)
                let a = CGFloat(h) * 15
                line(cg, polar(c, a, R * 0.94 - len), polar(c, a, R * 0.94), major ? ink : tick, w, round: false)
            }
        }

        // Numerals
        let count = is24 ? 24 : 12
        let dual = mode == .dual
        let px = is24 ? R * 0.105 : (dual ? R * 0.14 : R * 0.16)
        let f = font(px, .regular)
        let fb = font(px, .bold)
        let rr = is24 ? R * 0.72 : (dual ? R * 0.745 : R * 0.73)
        for i in 0..<count {
            // 12/24 dial after noon: the 13-23 numbers take the big outer ring; 24 joins them from 13:00.
            let label = is24 ? i : (i == 0 ? (dual && topSwap ? 24 : 12) : (dual && pm ? i + 12 : i))
            let txt = is24 ? String(format: "%02d", label) : String(label)
            let major = is24 ? i % 6 == 0 : i % 3 == 0
            let pt = polar(c, CGFloat(i) * 360 / CGFloat(count), rr)
            drawCentered(txt, major ? fb : f, major ? ink : softNum, pt)
        }

        // 12/24 dial: inner ring, smaller and faded, just inside each main numeral (railway-station style).
        if dual {
            let fi = font(R * 0.08, .regular)
            let faded = rgb(90, 94, 102, 150)
            let ri = R * 0.58
            for i in 0..<12 {
                // 13-23 in the morning, 1-11 after noon; 24 on top until 13:00, then 12.
                let txt = String(i == 0 ? (topSwap ? 12 : 24) : (pm ? i : i + 12))
                drawCentered(txt, fi, faded, polar(c, CGFloat(i) * 30, ri))
            }
        }

        // Legend on the dial
        let lf = font(R * 0.08, .bold)
        drawTop(zone, lf, ink, c.x, c.y - R * 0.40)
        drawTop("UTC", lf, utcText, c.x, c.y + R * 0.30)
    }

    // MARK: AM/PM symbols (12h dial only): sun = AM, crescent moon = PM, just right of the zone and UTC labels.
    // The UTC symbol only appears when UTC is on the other side of noon from local time.

    private static func drawMeridiem(_ cg: CGContext, _ c: CGPoint, _ R: CGFloat, _ zone: String, _ localHour: Int, _ utcHour: Int) {
        let localPM = localHour >= 12, utcPM = utcHour >= 12
        let lf = font(R * 0.08, .bold)
        let s = lf.pointSize * 1.15                       // symbol box, a little larger than the label font
        let midOff = lf.ascender - lf.capHeight / 2       // label top -> cap-height center
        let wZone = (zone as NSString).size(withAttributes: [.font: lf]).width
        symbol(cg, CGPoint(x: c.x + wZone / 2 + s * 0.62, y: c.y - R * 0.40 + midOff), s, localPM, ink)
        if utcPM != localPM {
            let wUtc = ("UTC" as NSString).size(withAttributes: [.font: lf]).width
            symbol(cg, CGPoint(x: c.x + wUtc / 2 + s * 0.62, y: c.y + R * 0.30 + midOff), s, utcPM, utcText)
        }
    }

    private static func symbol(_ cg: CGContext, _ p: CGPoint, _ s: CGFloat, _ moon: Bool, _ col: UIColor) {
        cg.setFillColor(col.cgColor)
        if moon {
            // Crescent: a disc with an offset disc cut out, horns pointing right
            let r = s * 0.42, rc = s * 0.36
            let cut = CGRect(x: p.x - rc + s * 0.22, y: p.y - rc - s * 0.12, width: 2 * rc, height: 2 * rc)
            cg.saveGState()
            cg.addRect(CGRect(x: p.x - s, y: p.y - s, width: 2 * s, height: 2 * s))
            cg.addEllipse(in: cut)
            cg.clip(using: .evenOdd)
            cg.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            cg.restoreGState()
        } else {
            // Sun: small disc with 8 short rays
            let core = s * 0.21
            cg.fillEllipse(in: CGRect(x: p.x - core, y: p.y - core, width: 2 * core, height: 2 * core))
            for i in 0..<8 {
                line(cg, polar(p, CGFloat(i) * 45, s * 0.33), polar(p, CGFloat(i) * 45, s * 0.48), col, max(1, s * 0.09), round: true)
            }
        }
    }

    // MARK: Date windows (local date; drawn before the hands so the hands sweep over them)

    private static func drawDate(_ cg: CGContext, _ c: CGPoint, _ R: CGFloat, _ t: ClockTime, _ off: CGFloat) {
        let mon = months[max(0, min(11, t.month - 1))]
        let day = String(format: "%02d", t.day)
        let f = font(R * 0.085, .bold, mono: true)
        let attrs: [NSAttributedString.Key: Any] = [.font: f]
        // Fixed-size windows (sized for "MMM" / "00") so the boxes never change size
        let wMon = ("MMM" as NSString).size(withAttributes: attrs).width
        let wDay = ("00" as NSString).size(withAttributes: attrs).width
        let h = f.pointSize * 1.35
        let padX = R * 0.04
        let rMon = CGRect(x: c.x - off - wMon / 2 - padX, y: c.y - h / 2, width: wMon + 2 * padX, height: h)
        let rDay = CGRect(x: c.x + off - wDay / 2 - padX, y: c.y - h / 2, width: wDay + 2 * padX, height: h)
        cg.setStrokeColor(ink.cgColor)
        cg.setLineWidth(max(1, R * 0.008))
        cg.stroke(rMon)
        cg.stroke(rDay)
        drawCentered(mon, f, ink, CGPoint(x: rMon.midX, y: rMon.midY))
        drawCentered(day, f, ink, CGPoint(x: rDay.midX, y: rDay.midY))
    }

    // MARK: Hands

    private static func drawHands(_ cg: CGContext, _ c: CGPoint, _ R: CGFloat, _ t: ClockTime, _ is24: Bool,
                                  _ handColor: UIColor, _ secColor: UIColor, _ showSec: Bool) {
        let sec = Double(t.second) + Double(t.nanos) / 1e9
        let mins = Double(t.minute) + sec / 60
        let hrs = Double(t.hour) + mins / 60

        let hourAngle = CGFloat(is24 ? hrs * 15 : hrs.truncatingRemainder(dividingBy: 12) * 30)
        let minAngle = CGFloat(mins * 6)

        hand(cg, c, hourAngle, R * 0.52, R * 0.09, max(3, R * 0.055), handColor)
        // Identical geometry for local and UTC, so the local hand fully covers the UTC one in whole-hour zones.
        hand(cg, c, minAngle, R * 0.80, R * 0.11, max(2, R * 0.034), handColor)

        if showSec {
            let sa = CGFloat(floor(sec) * 6) // ticking second hand
            hand(cg, c, sa, R * 0.86, R * 0.18, max(1, R * 0.012), secColor)
        }
    }

    private static func hand(_ cg: CGContext, _ c: CGPoint, _ deg: CGFloat, _ length: CGFloat,
                             _ tail: CGFloat, _ width: CGFloat, _ col: UIColor) {
        line(cg, polar(c, deg, -tail), polar(c, deg, length), col, width, round: true)
    }

    // MARK: Digital readout

    static func fmt(_ t: ClockTime, _ is24: Bool, _ sec: Bool) -> String {
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

    private static func drawDigital(_ area: CGRect, _ local: ClockTime, _ utc: ClockTime,
                                    _ zone: String, _ is24: Bool, _ sec: Bool) {
        var dayNote = ""
        if utc.ymd > local.ymd { dayNote = "  +1d" } else if utc.ymd < local.ymd { dayNote = "  -1d" }
        let top = zone + "  " + fmt(local, is24, sec)
        let bot = "UTC  " + fmt(utc, is24, sec) + dayNote

        // Size to the area's height, then shrink if either line would overflow its width (narrow iPhones).
        var px = max(10, area.height * 0.36)
        let wTop = (top as NSString).size(withAttributes: [.font: font(px, .bold, mono: true)]).width
        let wBot = (bot as NSString).size(withAttributes: [.font: font(px * 0.78, .regular, mono: true)]).width
        let widest = max(wTop, wBot)
        if widest > area.width, widest > 0 { px = max(8, px * area.width / widest) }

        let big = font(px, .bold, mono: true)
        let small = font(px * 0.78, .regular, mono: true)
        let topC = CGPoint(x: area.midX, y: area.minY + area.height * 0.55 / 2)
        let botC = CGPoint(x: area.midX, y: area.minY + area.height * 0.52 + area.height * 0.45 / 2)
        drawCentered(top, big, ink, topC)
        drawCentered(bot, small, utcText, botC)
    }

    // MARK: Helpers

    private static func polar(_ c: CGPoint, _ deg: CGFloat, _ r: CGFloat) -> CGPoint {
        let a = (deg - 90) * .pi / 180
        return CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
    }

    private static func line(_ cg: CGContext, _ p1: CGPoint, _ p2: CGPoint, _ col: UIColor, _ w: CGFloat, round: Bool) {
        cg.setStrokeColor(col.cgColor)
        cg.setLineWidth(w)
        cg.setLineCap(round ? .round : .butt)
        cg.beginPath()
        cg.move(to: p1)
        cg.addLine(to: p2)
        cg.strokePath()
    }

    private static func font(_ size: CGFloat, _ weight: UIFont.Weight, mono: Bool = false) -> UIFont {
        let s = max(6, size)
        return mono ? UIFont.monospacedDigitSystemFont(ofSize: s, weight: weight)
                    : UIFont.systemFont(ofSize: s, weight: weight)
    }

    // Centers the text horizontally and centers its cap height vertically on the point.
    private static func drawCentered(_ s: String, _ f: UIFont, _ col: UIColor, _ center: CGPoint) {
        let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: col]
        let w = (s as NSString).size(withAttributes: attrs).width
        let y = center.y + f.capHeight / 2 - f.ascender
        (s as NSString).draw(at: CGPoint(x: center.x - w / 2, y: y), withAttributes: attrs)
    }

    // Centers horizontally with the top of the text at `top`.
    private static func drawTop(_ s: String, _ f: UIFont, _ col: UIColor, _ cx: CGFloat, _ top: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: col]
        let w = (s as NSString).size(withAttributes: attrs).width
        (s as NSString).draw(at: CGPoint(x: cx - w / 2, y: top), withAttributes: attrs)
    }
}

// MARK: - Clock view (UIKit)

final class ClockUIView: UIView {
    var mode: DialMode = .twelve
    var showSeconds = true
    var showDigital = true
    var onMode: ((DialMode) -> Void)?
    var onOptions: (() -> Void)?
    private var timer: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = ClockRenderer.background
        isOpaque = true
        contentMode = .redraw // redraw (not stretch) on rotation and resize
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:))))
        isAccessibilityElement = true
        accessibilityTraits = [.updatesFrequently]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var safeRect: CGRect { return bounds.inset(by: safeAreaInsets) }

    override func draw(_ rect: CGRect) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        let now = Date()
        let tz = TimeZone.autoupdatingCurrent
        ClockRenderer.draw(cg, full: bounds, safe: safeRect, date: now, localTZ: tz,
                           zone: ClockRenderer.zoneAbbrev(tz, at: now),
                           mode: mode, showSeconds: showSeconds, showDigital: showDigital)
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsDisplay()
    }

    // Redraw just after each whole second so the ticking second hand lands on time (1 redraw/sec: easy on battery).
    override func didMoveToWindow() {
        super.didMoveToWindow()
        timer?.invalidate()
        timer = nil
        guard window != nil else { return }
        let next = Date(timeIntervalSinceReferenceDate: floor(Date().timeIntervalSinceReferenceDate) + 1.02)
        let t = Timer(fire: next, interval: 1.0, repeats: true) { [weak self] _ in self?.setNeedsDisplay() }
        t.tolerance = 0.05
        RunLoop.main.add(t, forMode: .common)
        timer = t
        becomeFirstResponder()
    }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        let p = g.location(in: self)
        if ClockRenderer.optionsHit(p, in: safeRect) {
            onOptions?()
        } else if let m = ClockRenderer.switchHit(p, in: safeRect) {
            onMode?(m)
        }
        becomeFirstResponder()
    }

    @objc private func longPressed(_ g: UILongPressGestureRecognizer) {
        if g.state == .began { onOptions?() }
    }

    // Hardware keyboard (iPad): T cycles the dial mode, as on the Mac.
    override var canBecomeFirstResponder: Bool { return true }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if let key = press.key, !key.modifierFlags.contains(.command),
               key.charactersIgnoringModifiers.lowercased() == "t" {
                onMode?(mode.next)
                return
            }
        }
        super.pressesBegan(presses, with: event)
    }

    // VoiceOver reads both times.
    override var accessibilityLabel: String? {
        get {
            let now = Date()
            let tz = TimeZone.autoupdatingCurrent
            let local = ClockTime(now, tz)
            let utc = ClockTime(now, TimeZone(identifier: "UTC")!)
            return "Local " + ClockRenderer.fmt(local, mode.readoutUse24, false) +
                   ", UTC " + ClockRenderer.fmt(utc, mode.readoutUse24, false)
        }
        set { }
    }
}

struct ClockRepresentable: UIViewRepresentable {
    var mode: DialMode
    var showSeconds: Bool
    var showDigital: Bool
    var onMode: (DialMode) -> Void
    var onOptions: () -> Void

    func makeUIView(context: Context) -> ClockUIView { return ClockUIView() }

    func updateUIView(_ v: ClockUIView, context: Context) {
        v.mode = mode
        v.showSeconds = showSeconds
        v.showDigital = showDigital
        v.onMode = onMode
        v.onOptions = onOptions
        v.setNeedsDisplay()
    }
}

// MARK: - App (SwiftUI shell)

@main
struct DualClockApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @AppStorage("DialMode") private var modeRaw = DialMode.twelve.rawValue
    @AppStorage("ShowSeconds") private var showSeconds = true
    @AppStorage("ShowDigital") private var showDigital = true
    @AppStorage("KeepAwake") private var keepAwake = false
    @State private var showOptions = false
    @Environment(\.scenePhase) private var scenePhase

    private var mode: DialMode { return DialMode(rawValue: modeRaw) ?? .twelve }

    var body: some View {
        ClockRepresentable(mode: mode, showSeconds: showSeconds, showDigital: showDigital,
                           onMode: { modeRaw = $0.rawValue },
                           onOptions: { showOptions = true })
            .ignoresSafeArea()
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden) // dims the home indicator
            .sheet(isPresented: $showOptions) {
                OptionsView(modeRaw: $modeRaw, showSeconds: $showSeconds,
                            showDigital: $showDigital, keepAwake: $keepAwake)
                    .presentationDetents([.medium, .large])
            }
            .onAppear { applyKeepAwake() }
            .onChange(of: keepAwake) { applyKeepAwake() }
            .onChange(of: scenePhase) { applyKeepAwake() }
    }

    private func applyKeepAwake() {
        UIApplication.shared.isIdleTimerDisabled = keepAwake && scenePhase == .active
    }
}

struct OptionsView: View {
    @Binding var modeRaw: Int
    @Binding var showSeconds: Bool
    @Binding var showDigital: Bool
    @Binding var keepAwake: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Dial") {
                    Picker("Dial", selection: $modeRaw) {
                        Text("12-hour dial").tag(DialMode.twelve.rawValue)
                        Text("12-hour dial with 13–24 ring").tag(DialMode.dual.rawValue)
                        Text("24-hour dial").tag(DialMode.twentyFour.rawValue)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Display") {
                    Toggle("Second hand", isOn: $showSeconds)
                    Toggle("Digital readout", isOn: $showDigital)
                    Toggle("Keep screen awake", isOn: $keepAwake)
                }
                Section {
                    Text("Tap the switch in the corner to change dials. Long-press anywhere, or tap •••, for these options.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("DualClock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
