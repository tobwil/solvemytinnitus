import SwiftUI
import TinnitusCore
import WidgetKit

/// Watch complication: "Wie laut ist er gerade?" as entry point plus today's check-ins.
@main
struct TinnitusComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "watch.checkin", provider: Provider()) { e in
            ComplicationView(entry: e)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Tinnitus-Check-in")
        .description("Check-ins heute, Tippen öffnet den Check-in.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let checkins: Int
    let tasksDone: Int
    let tasksTotal: Int
}

struct Provider: TimelineProvider {
    private var defaults: UserDefaults { UserDefaults(suiteName: TinnitusSchema.appGroup) ?? .standard }

    private func current() -> Entry {
        let d = defaults
        let today = d.string(forKey: "watch.day") == Day.key()
        return Entry(date: .now, checkins: today ? d.integer(forKey: "watch.checkins") : 0, tasksDone: today ? d.integer(forKey: "watch.tasksDone") : 0, tasksTotal: d.integer(forKey: "watch.tasksTotal"))
    }

    func placeholder(in context: Context) -> Entry { Entry(date: .now, checkins: 1, tasksDone: 2, tasksTotal: 6) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(current()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let midnight = Calendar.current.startOfDay(for: Date.now.addingTimeInterval(86400))
        completion(Timeline(entries: [current()], policy: .after(midnight)))
    }
}

struct ComplicationView: View {
    var entry: Entry
    @Environment(\.widgetFamily) private var family
    private let tin = Color(red: 0.98, green: 0.75, blue: 0.14)

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Label("Wie laut gerade?", systemImage: "waveform.path.ecg").font(.headline).widgetAccentable()
                Text("Check-ins \(entry.checkins)/3 · Aufgaben \(entry.tasksDone)/\(entry.tasksTotal)").font(.caption2)
            }
        case .accessoryInline:
            Label("Check-in \(entry.checkins)/3", systemImage: "waveform.path.ecg")
        case .accessoryCorner:
            Image(systemName: "waveform.path.ecg").font(.title3).foregroundStyle(tin)
                .widgetLabel { Gauge(value: Double(min(entry.checkins, 3)), in: 0...3) { Text("") }.tint(tin) }
        default:
            Gauge(value: Double(min(entry.checkins, 3)), in: 0...3) {
                Image(systemName: "waveform.path.ecg")
            } currentValueLabel: {
                Text("\(entry.checkins)")
            }
            .gaugeStyle(.accessoryCircular)
            .tint(tin)
        }
    }
}
