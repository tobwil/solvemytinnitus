import ActivityKit
import AppIntents
import SwiftUI
import TinnitusCore
import WidgetKit

@main
struct TinnitusLabWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        SpikePlanWidget()
        SessionLiveActivity()
    }
}

// MARK: - Palette (widgets can't use the app's design system file)

private enum W {
    static let sound = Color(red: 0.37, green: 0.92, blue: 0.83)
    static let tin = Color(red: 0.98, green: 0.75, blue: 0.14)
    static let mind = sound // one calm accent, as in the app
    static let bg = Color(red: 0.03, green: 0.035, blue: 0.05)
}

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snap: WidgetSnapshot(day: Day.key(), checkinsToday: 2, lastLoudness: 5, tasksDone: 3, tasksTotal: 6, soundMinutesToday: 25, programDay: 12, programWeek: 2, spikePlan: MindContent.spikePlanTemplate, tinnitusHz: 7600, updatedAt: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : SnapshotEntry(date: .now, snap: SharedStore.snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date.now
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86400))
        // reload at midnight so the daily counters reset even if the app is not opened
        completion(Timeline(entries: [SnapshotEntry(date: now, snap: SharedStore.snapshot)], policy: .after(midnight)))
    }
}

// MARK: - Today widget (home + lock screen)

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "today", provider: SnapshotProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(for: .widget) { W.bg }
        }
        .configurationDisplayName("Check-in & Tag")
        .description("Check-in mit einem Tipp und dein Tagesfortschritt.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct TodayWidgetView: View {
    var entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var progress: Double { entry.snap.tasksTotal > 0 ? Double(entry.snap.tasksDone) / Double(entry.snap.tasksTotal) : 0 }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(min(entry.snap.checkinsToday, 3)), in: 0...3) {
                Image(systemName: "waveform.path.ecg")
            } currentValueLabel: {
                Text("\(entry.snap.checkinsToday)")
            }
            .gaugeStyle(.accessoryCircular)
            .widgetURL(AppRoute.checkin.url)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("Wie laut gerade?", systemImage: "waveform.path.ecg").font(.headline)
                Text("Heute \(entry.snap.checkinsToday)/3 · \(entry.snap.tasksDone)/\(entry.snap.tasksTotal) Aufgaben").font(.caption)
            }
            .widgetURL(AppRoute.checkin.url)
        case .accessoryInline:
            Label("Check-in \(entry.snap.checkinsToday)/3", systemImage: "waveform.path.ecg")
                .widgetURL(AppRoute.checkin.url)
        case .systemMedium:
            HStack(spacing: 14) {
                ring
                VStack(alignment: .leading, spacing: 8) {
                    Link(destination: AppRoute.checkin.url) { pill("Check-in", "waveform.path.ecg", W.tin) }
                    Link(destination: AppRoute.sound(.enrichment).url) { pill("Klang", "cloud.rain", W.sound) }
                    Link(destination: AppRoute.tool("breath").url) { pill("Atmen", "wind", W.mind) }
                }
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                Text("Wie laut ist er gerade?").font(.headline).foregroundStyle(.white)
                Spacer(minLength: 0)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(entry.snap.checkinsToday)/3").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(W.tin)
                        Text("Check-ins heute").font(.caption2).foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    Image(systemName: "plus.circle.fill").font(.title).foregroundStyle(W.tin)
                }
            }
            .widgetURL(AppRoute.checkin.url)
        }
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.12), lineWidth: 9)
            Circle().trim(from: 0, to: progress).stroke(W.sound, style: StrokeStyle(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(entry.snap.tasksDone)/\(entry.snap.tasksTotal)").font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Text("Tag \(entry.snap.programDay)").font(.caption2).foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: 96, height: 96)
    }

    private func pill(_ title: String, _ symbol: String, _ color: Color) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}

// MARK: - Spike plan widget

struct SpikePlanWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "spikeplan", provider: SnapshotProvider()) { entry in
            VStack(alignment: .leading, spacing: 6) {
                Label("Notfallplan", systemImage: "shield").font(.headline).foregroundStyle(W.mind)
                Text(entry.snap.spikePlan.isEmpty ? "Noch kein Plan. Schreib ihn an einem guten Tag." : entry.snap.spikePlan)
                    .font(.caption).foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: 0)
            }
            .widgetURL(AppRoute.tool("plan").url)
            .containerBackground(for: .widget) { W.bg }
        }
        .configurationDisplayName("Notfallplan")
        .description("Für Tage, an denen er laut ist.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Live Activity

struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { ctx in
            HStack(spacing: 14) {
                Image(systemName: ctx.attributes.symbol).font(.title2).foregroundStyle(W.sound)
                    .frame(width: 44, height: 44).background(Circle().fill(W.sound.opacity(0.15)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(ctx.attributes.title).font(.headline)
                    Text(ctx.state.phase).font(.caption).foregroundStyle(ctx.state.silence ? W.tin : .secondary).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    timer(ctx.state, stale: ctx.isStale).font(.title3.monospacedDigit().weight(.semibold))
                    Button(intent: StopSessionLiveIntent()) { Image(systemName: "stop.fill") }
                        .tint(W.sound)
                }
            }
            .padding(16)
            .activityBackgroundTint(W.bg)
            .activitySystemActionForegroundColor(W.sound)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: ctx.attributes.symbol).font(.title2).foregroundStyle(W.sound)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    timer(ctx.state, stale: ctx.isStale).font(.title3.monospacedDigit()).foregroundStyle(W.sound)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(ctx.attributes.title).font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(ctx.state.phase).font(.caption).foregroundStyle(ctx.state.silence ? W.tin : .secondary).lineLimit(1)
                        Spacer()
                        Button(intent: StopSessionLiveIntent()) { Label("Beenden", systemImage: "stop.fill") }.tint(W.sound)
                    }
                }
            } compactLeading: {
                Image(systemName: ctx.state.silence ? "speaker.slash" : ctx.attributes.symbol).foregroundStyle(ctx.state.silence ? W.tin : W.sound)
            } compactTrailing: {
                timer(ctx.state, stale: ctx.isStale).monospacedDigit().foregroundStyle(W.sound).frame(maxWidth: 52)
            } minimal: {
                Image(systemName: ctx.attributes.symbol).foregroundStyle(W.sound)
            }
            .widgetURL(AppRoute.sound(nil).url)
        }
    }

    @ViewBuilder
    private func timer(_ s: SessionActivityAttributes.ContentState, stale: Bool) -> some View {
        if stale {
            Text("Beendet")
        } else if s.paused {
            Text(s.remainingWhenPaused.map { Format.duration($0) } ?? "Pause")
        } else if let end = s.endDate, end > .now {
            Text(timerInterval: Date.now...end, countsDown: true)
        } else {
            Text(s.startDate, style: .timer)
        }
    }
}
