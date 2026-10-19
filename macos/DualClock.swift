// DualClock for macOS v1.6 - Analog clock showing Local (primary) and UTC (secondary) time.
// Port of the Windows/WinForms DualClock v1.5. Same face, hands, colors, date windows, and readout.
// v1.6: One unified app. A 12 | 24 switch in the lower-right corner flips the dial mode
//       (replaces the separate "DualClock 12h" / "DualClock 24h" apps).
// Native Swift + AppKit, single file. Compile with: swiftc -O -o DualClock DualClock.swift
//
// Controls:
//   12 | 24 switch (lower right) .. click to change dial mode
//   Right-click (or Ctrl-click) ... menu (12/24-hour dial, second hand, digital readout, always on top, quit)
//   T ............................. toggle 12h / 24h
//   Double-click .................. toggle always on top
//   Drag anywhere ................. move the window
//   Esc / Cmd-W ................... close (quits the app);  Cmd-Q quits
//   Hidden test hook: DualClock --render out.png [12|24]  -> 420x520 PNG at a fixed time, no window.

import AppKit

// MARK: - Settings (UserDefaults; window frame is saved by AppKit's frame autosave)

final class Settings {
    private let d = UserDefaults.standard
    private func key(_ k: String) -> String { return k }
    private func bool(_ k: String, _ def: Bool) -> Bool { return d.object(forKey: key(k)) as? Bool ?? def }

    var use24Hour: Bool {
        get { return bool("Use24Hour", false) }
        set { d.set(newValue, forKey: key("Use24Hour")) }
    }
    var topMost: Bool {
        get { return bool("TopMost", false) }
        set { d.set(newValue, forKey: key("TopMost")) }
    }
    var showSeconds: Bool {
        get { return bool("ShowSeconds", true) }
        set { d.set(newValue, forKey: key("ShowSeconds")) }
    }
    var showDigital: Bool {
        get { return bool("ShowDigital", true) }
        set { d.set(newValue, forKey: key("ShowDigital")) }
    }
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

// MARK: - Renderer (flipped coordinates: y grows downward, same math as the Windows version)

enum ClockRenderer {
    static func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: Int = 255) -> NSColor {
        return NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
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

    // MARK: 12 | 24 switch (lower-right corner, in its own footer strip below the readout)

    static let switchW: CGFloat = 76, switchH: CGFloat = 22, switchMargin: CGFloat = 10
    static var footerH: CGFloat { return switchH + switchMargin }

    static func switchRect(in b: CGRect) -> CGRect {
        return CGRect(x: b.maxX - switchW - switchMargin, y: b.maxY - switchH - switchMargin,
                      width: switchW, height: switchH)
    }

    // nil = click missed the switch; false = "12" half; true = "24" half
    static func switchHit(_ p: CGPoint, in b: CGRect) -> Bool? {
        let r = switchRect(in: b).insetBy(dx: -4, dy: -4) // slightly forgiving hit area
        guard r.contains(p) else { return nil }
        return p.x >= r.midX
    }

    private static func drawSwitch(_ cg: CGContext, _ b: CGRect, _ is24: Bool) {
        let r = switchRect(in: b)
        let radius = r.height / 2
        let track = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
        cg.addPath(track)
        cg.setFillColor(faceFill.cgColor)
        cg.fillPath()

        // Selected half: dark pill
        let half = r.width / 2
        let sel = CGRect(x: is24 ? r.minX + half : r.minX, y: r.minY, width: half, height: r.height).insetBy(dx: 2, dy: 2)
        let selPath = CGPath(roundedRect: sel, cornerWidth: sel.height / 2, cornerHeight: sel.height / 2, transform: nil)
        cg.addPath(selPath)
        cg.setFillColor(ink.cgColor)
        cg.fillPath()

        cg.addPath(track)
        cg.setStrokeColor(tick.cgColor)
        cg.setLineWidth(1)
        cg.strokePath()

        let f = font(12, .semibold, mono: true)
        drawCentered("12h", f, is24 ? softNum : faceFill, CGPoint(x: r.minX + half / 2, y: r.midY))
        drawCentered("24h", f, is24 ? faceFill : softNum, CGPoint(x: r.minX + half * 1.5, y: r.midY))
    }

    static func draw(in full: CGRect, date: Date, localTZ: TimeZone, zone: String,
                     is24: Bool, showSeconds: Bool, showDigital: Bool) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        cg.setFillColor(background.cgColor)
        cg.fill(full)
        drawSwitch(cg, full, is24)

        // Clock and readout lay out in the space above the switch strip
        let b = CGRect(x: full.minX, y: full.minY, width: full.width, height: full.height - footerH)

        let digitalH: CGFloat = showDigital ? max(54, floor(b.height / 7)) : 0
        let pad = max(10, floor(min(b.width, b.height) / 30))
        let size = min(b.width - 2 * pad, b.height - digitalH - 2 * pad)
        if size < 50 { return }
        let R = size / 2
        let c = CGPoint(x: b.midX, y: b.minY + pad + R)

        let local = ClockTime(date, localTZ)
        let utc = ClockTime(date, TimeZone(identifier: "UTC")!)

        drawFace(cg, c, R, is24, zone)
        drawDate(cg, c, R, local)

        // UTC hands first (underneath). Seconds are identical in every zone, so UTC gets no second hand.
        drawHands(cg, c, R, utc, is24, utcHand, utcHand, false)
        drawHands(cg, c, R, local, is24, ink, secondRed, showSeconds)

        // Center cap
        let cap = R * 0.045
        cg.setFillColor(ink.cgColor)
        cg.fillEllipse(in: CGRect(x: c.x - cap, y: c.y - cap, width: cap * 2, height: cap * 2))
        if showSeconds {
            let cap2 = cap * 0.5
            cg.setFillColor(secondRed.cgColor)
            cg.fillEllipse(in: CGRect(x: c.x - cap2, y: c.y - cap2, width: cap2 * 2, height: cap2 * 2))
        }

        if showDigital {
            let area = CGRect(x: b.minX, y: c.y + R + pad * 0.5, width: b.width, height: digitalH)
            drawDigital(area, local, utc, zone, is24, showSeconds)
        }
    }

    // MARK: Face

    private static func drawFace(_ cg: CGContext, _ c: CGPoint, _ R: CGFloat, _ is24: Bool, _ zone: String) {
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
        let px = is24 ? R * 0.105 : R * 0.16
        let f = font(px, .regular)
        let fb = font(px, .bold)
        let rr = is24 ? R * 0.72 : R * 0.73
        for i in 0..<count {
            let label = is24 ? i : (i == 0 ? 12 : i)
            let txt = is24 ? String(format: "%02d", label) : String(label)
            let major = is24 ? i % 6 == 0 : i % 3 == 0
            let pt = polar(c, CGFloat(i) * 360 / CGFloat(count), rr)
            drawCentered(txt, major ? fb : f, major ? ink : softNum, pt)
        }

        // Legend on the dial
        let lf = font(R * 0.08, .bold)
        drawTop(zone, lf, ink, c.x, c.y - R * 0.40)
        drawTop("UTC", lf, utcText, c.x, c.y + R * 0.30)
    }

    // MARK: Date windows (local date; drawn before the hands so the hands sweep over them)

    private static func drawDate(_ cg: CGContext, _ c: CGPoint, _ R: CGFloat, _ t: ClockTime) {
        let mon = months[max(0, min(11, t.month - 1))]
        let day = String(format: "%02d", t.day)
        let off = R * 0.38
        let f = font(R * 0.085, .bold, mono: true)
        let attrs: [NSAttributedString.Key: Any] = [.font: f]
        // Fixed-size windows (sized for "MMM" / "00") so the boxes never change size
        let wMon = ("MMM" as NSString).size(withAttributes: attrs).width
        let wDay = ("00" as NSString).size(withAttributes: attrs).width
        let h = f.pointSize * 1.35
        let padX = R * 0.04 // a touch more than Windows: AppKit measures text tighter than GDI+
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
                                  _ handColor: NSColor, _ secColor: NSColor, _ showSec: Bool) {
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
                             _ tail: CGFloat, _ width: CGFloat, _ col: NSColor) {
        line(cg, polar(c, deg, -tail), polar(c, deg, length), col, width, round: true)
    }

    // MARK: Digital readout

    private static func fmt(_ t: ClockTime, _ is24: Bool, _ sec: Bool) -> String {
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
        let px = max(10, area.height * 0.36)
        let big = font(px, .bold, mono: true)
        let small = font(px * 0.78, .regular, mono: true)
        var dayNote = ""
        if utc.ymd > local.ymd { dayNote = "  +1d" } else if utc.ymd < local.ymd { dayNote = "  -1d" }

        let topC = CGPoint(x: area.midX, y: area.minY + area.height * 0.55 / 2)
        let botC = CGPoint(x: area.midX, y: area.minY + area.height * 0.52 + area.height * 0.45 / 2)
        drawCentered(zone + "  " + fmt(local, is24, sec), big, ink, topC)
        drawCentered("UTC  " + fmt(utc, is24, sec) + dayNote, small, utcText, botC)
    }

    // MARK: Helpers

    private static func polar(_ c: CGPoint, _ deg: CGFloat, _ r: CGFloat) -> CGPoint {
        let a = (deg - 90) * .pi / 180
        return CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
    }

    private static func line(_ cg: CGContext, _ p1: CGPoint, _ p2: CGPoint, _ col: NSColor, _ w: CGFloat, round: Bool) {
        cg.setStrokeColor(col.cgColor)
        cg.setLineWidth(w)
        cg.setLineCap(round ? .round : .butt)
        cg.beginPath()
        cg.move(to: p1)
        cg.addLine(to: p2)
        cg.strokePath()
    }

    private static func font(_ size: CGFloat, _ weight: NSFont.Weight, mono: Bool = false) -> NSFont {
        let s = max(6, size)
        return mono ? NSFont.monospacedDigitSystemFont(ofSize: s, weight: weight)
                    : NSFont.systemFont(ofSize: s, weight: weight)
    }

    // Centers the text horizontally and centers its cap height vertically on the point.
    private static func drawCentered(_ s: String, _ f: NSFont, _ col: NSColor, _ center: CGPoint) {
        let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: col]
        let w = (s as NSString).size(withAttributes: attrs).width
        let y = center.y + f.capHeight / 2 - f.ascender
        (s as NSString).draw(at: CGPoint(x: center.x - w / 2, y: y), withAttributes: attrs)
    }

    // Centers horizontally with the top of the text at `top` (like GDI+ near-alignment).
    private static func drawTop(_ s: String, _ f: NSFont, _ col: NSColor, _ cx: CGFloat, _ top: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: col]
        let w = (s as NSString).size(withAttributes: attrs).width
        (s as NSString).draw(at: CGPoint(x: cx - w / 2, y: top), withAttributes: attrs)
    }
}

// MARK: - View

final class ClockView: NSView {
    weak var controller: ClockController?

    override var isFlipped: Bool { return true }
    override var acceptsFirstResponder: Bool { return true }

    override func draw(_ dirtyRect: NSRect) {
        guard let s = controller?.settings else { return }
        let now = Date()
        let tz = TimeZone.autoupdatingCurrent
        ClockRenderer.draw(in: bounds, date: now, localTZ: tz, zone: ClockRenderer.zoneAbbrev(tz, at: now),
                           is24: s.use24Hour, showSeconds: s.showSeconds, showDigital: s.showDigital)
    }

    override func keyDown(with e: NSEvent) {
        if e.keyCode == 53 { window?.performClose(nil); return } // Esc
        if !e.modifierFlags.contains(.command), e.charactersIgnoringModifiers?.lowercased() == "t" {
            controller?.toggleFormat(nil)
            return
        }
        super.keyDown(with: e)
    }

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if let want24 = ClockRenderer.switchHit(p, in: bounds) {
            // Clicking either half selects it; clicking the already-selected half flips it.
            let s = controller?.settings
            if let s = s, s.use24Hour == want24 { controller?.toggleFormat(nil) }
            else if want24 { controller?.set24(nil) } else { controller?.set12(nil) }
            return
        }
        if e.clickCount == 2 { controller?.toggleTopMost(nil) }
        else { window?.performDrag(with: e) }
    }

    override func resetCursorRects() {
        addCursorRect(ClockRenderer.switchRect(in: bounds), cursor: .pointingHand)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        window?.invalidateCursorRects(for: self)
    }
}

// MARK: - Window controller

final class ClockController: NSObject, NSWindowDelegate, NSMenuItemValidation {
    let settings = Settings()
    let window: NSWindow
    let view = ClockView()
    private var timer: Timer?

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 480),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        super.init()

        window.title = "Dual Clock - Local / UTC"
        window.backgroundColor = ClockRenderer.background
        window.contentMinSize = NSSize(width: 220, height: 270)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.delegate = self
        view.controller = self

        // Restore saved frame; otherwise top-right of the primary screen.
        let name = "DualClockMainWindow"
        if !window.setFrameUsingName(name), let vf = (NSScreen.screens.first ?? NSScreen.main)?.visibleFrame {
            let fw = window.frame.width, fh = window.frame.height
            window.setFrameOrigin(NSPoint(x: vf.maxX - fw - 20, y: vf.maxY - fh - 20))
        }
        window.setFrameAutosaveName(name)
        window.level = settings.topMost ? .floating : .normal

        view.menu = ClockController.makeOptionsMenu(target: self, includeQuit: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)

        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.view.needsDisplay = true }
        RunLoop.main.add(t, forMode: .common) // keeps ticking while a menu is open
        timer = t
    }

    static func makeOptionsMenu(target: AnyObject, includeQuit: Bool) -> NSMenu {
        let m = NSMenu()
        func add(_ title: String, _ sel: Selector) {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            i.target = target
            m.addItem(i)
        }
        add("12-hour dial", #selector(ClockController.set12(_:)))
        add("24-hour dial", #selector(ClockController.set24(_:)))
        m.addItem(.separator())
        add("Show second hand", #selector(ClockController.toggleSeconds(_:)))
        add("Show digital readout", #selector(ClockController.toggleDigital(_:)))
        add("Always on top", #selector(ClockController.toggleTopMost(_:)))
        if includeQuit {
            m.addItem(.separator())
            m.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        }
        return m
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let a = item.action
        if a == #selector(set12(_:)) { item.state = settings.use24Hour ? .off : .on }
        else if a == #selector(set24(_:)) { item.state = settings.use24Hour ? .on : .off }
        else if a == #selector(toggleSeconds(_:)) { item.state = settings.showSeconds ? .on : .off }
        else if a == #selector(toggleDigital(_:)) { item.state = settings.showDigital ? .on : .off }
        else if a == #selector(toggleTopMost(_:)) { item.state = settings.topMost ? .on : .off }
        return true
    }

    @objc func set12(_ sender: Any?) { settings.use24Hour = false; changed() }
    @objc func set24(_ sender: Any?) { settings.use24Hour = true; changed() }
    @objc func toggleFormat(_ sender: Any?) { settings.use24Hour.toggle(); changed() }
    @objc func toggleSeconds(_ sender: Any?) { settings.showSeconds.toggle(); changed() }
    @objc func toggleDigital(_ sender: Any?) { settings.showDigital.toggle(); changed() }
    @objc func toggleTopMost(_ sender: Any?) {
        settings.topMost.toggle()
        window.level = settings.topMost ? .floating : .normal
        changed()
    }

    private func changed() { view.needsDisplay = true }

    func windowWillClose(_ notification: Notification) { timer?.invalidate() }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: ClockController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let ctl = ClockController()
        controller = ctl

        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About DualClock", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide DualClock", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit DualClock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let clockItem = NSMenuItem()
        main.addItem(clockItem)
        let clockMenu = ClockController.makeOptionsMenu(target: ctl, includeQuit: false)
        clockMenu.title = "Clock"
        clockMenu.addItem(.separator())
        clockMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        clockItem.submenu = clockMenu

        NSApp.mainMenu = main
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { return true }
}

// MARK: - Test render hook

func renderPNG(path: String, is24: Bool) {
    let w = 420, h = 520
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let base = NSGraphicsContext(bitmapImageRep: rep) else { return }
    let cg = base.cgContext
    cg.translateBy(x: 0, y: CGFloat(h))
    cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)

    var comps = DateComponents()
    comps.year = 2026; comps.month = 10; comps.day = 15
    comps.hour = 15; comps.minute = 28; comps.second = 42
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let date = cal.date(from: comps)!
    ClockRenderer.draw(in: CGRect(x: 0, y: 0, width: w, height: h), date: date,
                       localTZ: TimeZone(secondsFromGMT: -4 * 3600)!, zone: "EDT",
                       is24: is24, showSeconds: true, showDigital: true)

    NSGraphicsContext.restoreGraphicsState()
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: path))
    }
}

// MARK: - Entry point

let args = CommandLine.arguments
_ = NSApplication.shared

if args.count >= 3 && args[1] == "--render" {
    renderPNG(path: args[2], is24: args.count >= 4 && args[3] == "24")
    exit(0)
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.setActivationPolicy(.regular)
NSApplication.shared.run()
