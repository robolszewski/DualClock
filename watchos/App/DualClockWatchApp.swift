// DualClock for Apple Watch v2.1 - Analog clock showing Local (primary) and UTC (secondary) time.
// Port of DualClock for iOS v2.0. Same face, hands, colors, date windows, readout, and 12h | 12/24 | 24h modes.
// v2.1: watchOS app + WidgetKit complications (see Complications/). Renderer ported to SwiftUI Canvas.
//       Always-on: switches to a dark face, drops the second hand, updates once a minute.
//
// Controls:
//   Digital Crown ......... turn to change dial mode (12h -> 12/24 -> 24h), with a click at each step
//   Tap ................... show / hide the digital readout
//   Long-press ............ options (dial mode, second hand, digital readout)
// Tip: Settings > General > Return to Clock > "After 1 hour" keeps DualClock up after a wrist raise.

import SwiftUI

@main
struct DualClockWatchApp: App {
    var body: some Scene {
        WindowGroup { WatchClockView() }
    }
}

struct WatchClockView: View {
    @AppStorage("DialMode") private var modeRaw = DialMode.twelve.rawValue
    @AppStorage("ShowSeconds") private var showSeconds = true
    @AppStorage("ShowDigital") private var showDigital = true
    @Environment(\.isLuminanceReduced) private var dimmed

    @State private var crown: Double = 0
    @State private var showOptions = false
    @State private var badgeVisible = false
    @State private var badgeToken = 0

    private var mode: DialMode { return DialMode(rawValue: modeRaw) ?? .twelve }

    // Ticks on whole seconds (whole minutes when dimmed) so the second hand lands on time.
    private var schedule: PeriodicTimelineSchedule {
        let now = Date().timeIntervalSinceReferenceDate
        let step: TimeInterval = dimmed ? 60 : 1
        return .periodic(from: Date(timeIntervalSinceReferenceDate: floor(now / step) * step), by: step)
    }

    var body: some View {
        TimelineView(schedule) { timeline in
            let date = timeline.date
            Canvas { ctx, size in
                WatchLayout.draw(&ctx, size: size, date: date, mode: mode,
                                 showSeconds: showSeconds && !dimmed, showDigital: showDigital,
                                 palette: dimmed ? .dim : .day)
            }
            .accessibilityElement()
            .accessibilityLabel(WatchLayout.spoken(date, mode))
        }
        .background(Color.black)
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            if badgeVisible {
                Text(mode.label)
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(rgb(28, 30, 36).opacity(0.9)))
                    .padding(.top, 2)
                    .transition(.opacity)
            }
        }
        .persistentSystemOverlays(.hidden)
        .contentShape(Rectangle())
        .onTapGesture { showDigital.toggle() }
        .onLongPressGesture { showOptions = true }
        .focusable()
        .focusEffectDisabled()
        .digitalCrownRotation($crown, from: 0, through: Double(DialMode.allCases.count - 1), by: 1,
                              sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
        .onAppear { crown = Double(modeRaw) }
        .onChange(of: crown) { _, value in
            let m = DialMode(rawValue: Int(value.rounded())) ?? .twelve
            if m.rawValue != modeRaw {
                modeRaw = m.rawValue
                flashBadge()
            }
        }
        .onChange(of: modeRaw) { _, value in crown = Double(value) } // keep the crown in step with the options sheet
        .sheet(isPresented: $showOptions) {
            WatchOptionsView(modeRaw: $modeRaw, showSeconds: $showSeconds, showDigital: $showDigital)
        }
    }

    private func flashBadge() {
        badgeToken += 1
        let token = badgeToken
        withAnimation(.easeOut(duration: 0.15)) { badgeVisible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if token == badgeToken { withAnimation(.easeIn(duration: 0.3)) { badgeVisible = false } }
        }
    }
}

// MARK: - Layout: dial centered, readout below. The watch screen is taller than wide,
// so the readout costs the dial almost nothing.

enum WatchLayout {
    static func draw(_ ctx: inout GraphicsContext, size: CGSize, date: Date, mode: DialMode,
                     showSeconds: Bool, showDigital: Bool, palette: ClockPalette) {
        let tz = TimeZone.autoupdatingCurrent
        let zone = ClockFormat.zoneAbbrev(tz, at: date)
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.background))

        let digitalH: CGFloat = showDigital ? max(34, floor(size.height * 0.19)) : 0
        let pad = max(3, floor(size.width * 0.02))
        let d = min(size.width - 2 * pad, size.height - digitalH - 2 * pad)
        if d < 40 { return }
        let R = d / 2
        let slack = max(0, size.height - (d + 2 * pad + digitalH))
        let c = CGPoint(x: size.width / 2, y: slack / 2 + pad + R)

        DialRenderer.drawDial(&ctx, center: c, radius: R, date: date, localTZ: tz, zone: zone,
                              mode: mode, showSeconds: showSeconds, palette: palette)

        if showDigital {
            let area = CGRect(x: pad + 4, y: c.y + R + pad * 0.5, width: size.width - 2 * pad - 8, height: digitalH)
            DialRenderer.drawReadout(&ctx, in: area, date: date, localTZ: tz, zone: zone,
                                     use24: mode.readoutUse24, seconds: showSeconds, palette: palette)
        }
    }

    // VoiceOver reads both times.
    static func spoken(_ date: Date, _ mode: DialMode) -> String {
        let local = ClockTime(date, .autoupdatingCurrent)
        let utc = ClockTime(date, .utcZone)
        return "Local " + ClockFormat.time(local, mode.readoutUse24, false) +
               ", UTC " + ClockFormat.time(utc, mode.readoutUse24, false)
    }
}

// MARK: - Options

struct WatchOptionsView: View {
    @Binding var modeRaw: Int
    @Binding var showSeconds: Bool
    @Binding var showDigital: Bool

    var body: some View {
        List {
            Picker("Dial", selection: $modeRaw) {
                ForEach(DialMode.allCases, id: \.rawValue) { m in
                    Text(m.longName).tag(m.rawValue)
                }
            }
            Toggle("Second hand", isOn: $showSeconds)
            Toggle("Digital readout", isOn: $showDigital)
            Text("Turn the Digital Crown to change dials. Tap the clock to show or hide the readout.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
        }
        .navigationTitle("DualClock")
    }
}
