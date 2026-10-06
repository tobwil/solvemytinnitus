import SwiftData
import SwiftUI
import TinnitusCore

struct RootView: View {
    @Query private var settingsList: [AppSettings]
    @Environment(\.modelContext) private var ctx

    var body: some View {
        Group {
            if settingsList.first?.onboarded == true {
                MainTabs()
            } else {
                OnboardingView()
            }
        }
        .tint(Theme.sound)
        .onAppear { _ = ctx.settings() }
    }
}

struct MainTabs: View {
    @Environment(AppModel.self) private var model
    @State private var session = SessionController.shared
    @Namespace private var zoom

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            Tab("Fluss", systemImage: "water.waves", value: AppTab.today) {
                stack($model.todayPath) { TodayView() }
            }
            Tab("Üben", systemImage: "circle.hexagongrid", value: AppTab.practice) {
                stack($model.practicePath) { PracticeView() }
            }
            Tab("Ich", systemImage: "person.crop.circle", value: AppTab.me) {
                stack($model.mePath) { MeView() }
            }
        }
        .environment(\.zoomNamespace, zoom)
        .sheet(isPresented: $model.checkInPresented) {
            CheckInView().presentationDetents([.large])
        }
        .sheet(item: $session.ratingRequest) { req in
            SessionRatingSheet(request: req)
                .presentationDetents([.medium])
                .interactiveDismissDisabled(false)
        }
        .overlay(alignment: .top) {
            if let t = model.toast {
                ToastView(toast: t).padding(.top, 8).transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func stack<Root: View>(_ path: Binding<[AppRoute]>, @ViewBuilder root: () -> Root) -> some View {
        NavigationStack(path: path) {
            root()
                .navigationDestination(for: AppRoute.self) { RouteView(route: $0) }
                .safeAreaInset(edge: .bottom) { MiniPlayer() }
        }
    }
}

/// Destination for every in-app route.
struct RouteView: View {
    var route: AppRoute
    @Environment(\.zoomNamespace) private var zoom
    var body: some View {
        Group {
            switch route {
            case .checkin: CheckInView()
            case .headphones: HeadphonesCheckView()
            case .spectrum: SpectrumTestView()
            case .match(let start): MatchView(start: start)
            case .hearing: HearingView()
            case .somatic: SomaticView()
            case .ri: RILabView()
            case .sound(let mode):
                if let mode { PlayerView(mode: mode) } else { SoundListView() }
            case .play(let mode, _): PlayerView(mode: mode)
            case .mind: MindView()
            case .lesson(let id): LessonView(id: id)
            case .tool(let id): ToolView(id: id)
            case .body(let p):
                if let p { BodyProgramView(program: p) } else { BodyView() }
            case .progress(let tab): ProgressScreen(initialTab: tab)
            case .learn: KnowledgeView()
            case .settings: SettingsView()
            }
        }
        .safeAreaInset(edge: .bottom) { MiniPlayer() }
        .modifier(ZoomDestination(route: route, ns: zoom))
    }
}

/// Zoom out of the card the route was opened from.
private struct ZoomDestination: ViewModifier {
    var route: AppRoute
    var ns: Namespace.ID?
    func body(content: Content) -> some View {
        switch route {
        case .sound(let m?): content.zoomDestination("sound-\(m.rawValue)", in: ns)
        case .body(let p?): content.zoomDestination("body-\(p.rawValue)", in: ns)
        case .lesson(let id): content.zoomDestination("lesson-\(id)", in: ns)
        default: content
        }
    }
}

/// Compact bar while a session runs (sound continues across screens and in the background).
struct MiniPlayer: View {
    @State private var session = SessionController.shared
    @Environment(AppModel.self) private var model

    var body: some View {
        if session.isActive, let c = session.config, !isShowingPlayer(c.mode) {
            HStack(spacing: 12) {
                IconBadge(symbol: SoundContent.mode(c.mode).symbol, color: Theme.sound, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    Text(session.remaining.map { "noch \(Format.duration($0))" } ?? Format.duration(session.elapsed))
                        .font(.caption).monospacedDigit().foregroundStyle(Theme.text2)
                }
                Spacer()
                Button { session.toggle() } label: {
                    Image(systemName: session.state == .running ? "pause.fill" : "play.fill").font(.title3)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(session.state == .running ? "Pause" : "Weiter")
                Button { session.finish(auto: false) } label: {
                    Image(systemName: "stop.fill").font(.title3).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Beenden")
            }
            .foregroundStyle(Theme.sound)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke2))
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .contentShape(Rectangle())
            .onTapGesture { model.open(.sound(c.mode)) }
        }
    }

    private func isShowingPlayer(_ mode: TherapyMode) -> Bool {
        model.tab == .practice && model.practicePath.last == .sound(mode)
    }
}

struct SessionRatingSheet: View {
    var request: SessionController.RatingRequest
    @State private var value: Int?
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sitzung beendet").font(.titleL)
            Text("\(request.title) · \(Format.duration(request.durationS)) min. Wie laut ist dein Tinnitus jetzt?")
                .foregroundStyle(Theme.text2)
            Scale10(value: $value, labels: ("nicht hörbar", "extrem laut")) { v in
                SessionController.shared.rate(Double(v))
                if let pre = request.pre {
                    let d = Double(v) - pre
                    model.showToast("Gespeichert · \(d > 0 ? "+" : "")\(Int(d)) Punkte")
                } else {
                    model.showToast("Sitzung gespeichert")
                }
                dismiss()
            }
            TextLinkButton("Ohne Bewertung speichern") {
                SessionController.shared.rate(nil)
                dismiss()
            }
        }
        .padding(24)
        .presentationBackground(Theme.bgElevated)
    }
}
