// DualClock for Apple Watch v2.1 - complications (WidgetKit) for Apple's own watch faces.
//   Circular / corner ..... mini dial: white local hands over blue UTC hands; "UTC 13:10" on the bezel where the face allows
//   Rectangular ........... mini dial + local time, UTC time, and the local date
//   Inline ................ "UTC 13:10" (the face already shows local time)
// Each comes in 12h, 12/24 and 24h variants, picked in the watch face editor.
// WidgetKit can't animate, so the timeline holds one entry per minute: hands step once a minute, no second hand.

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Configuration (dial mode per complication)

enum DialModeOption: String, AppEnum {
    case twelve, dual, twentyFour

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Dial"
    static var caseDisplayRepresentations: [DialModeOption: DisplayRepresentation] = [
        .twelve: "12-hour",
        .dual: "12/24",
        .twentyFour: "24-hour"
    ]

    var mode: DialMode {
        switch self {
        case .twelve: return .twelve
        case .dual: return .dual
        case .twentyFour: return .twentyFour
        }
    }
}

struct DialConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "DualClock"
    static var description = IntentDescription("Local time with UTC.")

    @Parameter(title: "Dial", default: .twelve)
    var dial: DialModeOption

    init() {}
    init(dial: DialModeOption) { self.dial = dial }
}

// MARK: - Timeline

struct DualClockEntry: TimelineEntry {
    let date: Date
    let mode: DialMode
}

struct DualClockProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DualClockEntry {
        return DualClockEntry(date: Date(), mode: .twelve)
    }

    func snapshot(for configuration: DialConfigIntent, in context: Context) async -> DualClockEntry {
        return DualClockEntry(date: Date(), mode: configuration.dial.mode)
    }

    // Two hours of per-minute entries, then ask for a fresh timeline (~12 reloads a day, well within budget).
    func timeline(for configuration: DialConfigIntent, in context: Context) async -> Timeline<DualClockEntry> {
        let now = Date().timeIntervalSinceReferenceDate
        let start = Date(timeIntervalSinceReferenceDate: floor(now / 60) * 60)
        let entries = (0..<120).map { i in
            DualClockEntry(date: start.addingTimeInterval(Double(i) * 60), mode: configuration.dial.mode)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    // watchOS lists these as ready-made choices in the face editor.
    func recommendations() -> [AppIntentRecommendation<DialConfigIntent>] {
        return [
            AppIntentRecommendation(intent: DialConfigIntent(dial: .twelve), description: "DualClock 12h"),
            AppIntentRecommendation(intent: DialConfigIntent(dial: .dual), description: "DualClock 12/24"),
            AppIntentRecommendation(intent: DialConfigIntent(dial: .twentyFour), description: "DualClock 24h")
        ]
    }
}

// MARK: - Views

// Three stacked layers: ticks, UTC hands (tinted with the face's accent color in tinted modes), local hands.
struct MiniDialView: View {
    let date: Date
    let mode: DialMode

    var body: some View {
        let local = ClockTime(date, .autoupdatingCurrent)
        let utc = ClockTime(date, .utcZone)
        ZStack {
            Canvas { ctx, size in
                let (c, R) = MiniDial.geometry(size)
                MiniDial.ticks(&ctx, c, R, mode, .white)
            }
            Canvas { ctx, size in
                let (c, R) = MiniDial.geometry(size)
                MiniDial.hands(&ctx, c, R, utc, mode, ClockPalette.complicationUTC)
            }
            .widgetAccentable()
            Canvas { ctx, size in
                let (c, R) = MiniDial.geometry(size)
                MiniDial.hands(&ctx, c, R, local, mode, .white)
                Draw.dot(&ctx, c, max(1.5, R * 0.09), .white)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct DualClockComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DualClockEntry

    var body: some View {
        let tz = TimeZone.autoupdatingCurrent
        let local = ClockTime(entry.date, tz)
        let utc = ClockTime(entry.date, .utcZone)
        let use24 = entry.mode.readoutUse24
        let off = ClockFormat.dayOffset(local: local, utc: utc)
        let utcLine = "UTC " + ClockFormat.time(utc, use24, false) + (off.isEmpty ? "" : " " + off)

        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                MiniDialView(date: entry.date, mode: entry.mode).padding(4)
            }
            .widgetLabel { Text(verbatim: utcLine) }

        case .accessoryCorner:
            MiniDialView(date: entry.date, mode: entry.mode)
                .widgetLabel { Text(verbatim: utcLine) }

        case .accessoryRectangular:
            HStack(spacing: 6) {
                MiniDialView(date: entry.date, mode: entry.mode)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: ClockFormat.zoneAbbrev(tz, at: entry.date) + " " + ClockFormat.time(local, use24, false))
                        .font(.headline.monospacedDigit())
                    Text(verbatim: utcLine)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(ClockPalette.complicationUTC)
                        .widgetAccentable()
                    Text(verbatim: ClockFormat.monthAbbrev(local) + " " + String(format: "%02d", local.day))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }

        default: // .accessoryInline
            Text(verbatim: utcLine)
        }
    }
}

// MARK: - Widget

@main
struct DualClockComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "DualClockComplication", intent: DialConfigIntent.self,
                               provider: DualClockProvider()) { entry in
            DualClockComplicationView(entry: entry)
                .containerBackground(Color.clear, for: .widget)
        }
        .configurationDisplayName("DualClock")
        .description("Local time with UTC hands.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}
