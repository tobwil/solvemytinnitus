import Observation
import SwiftUI
import TinnitusCore

enum AppEnv {
    static let isUITest = ProcessInfo.processInfo.arguments.contains("-uitest") && !ProcessInfo.processInfo.arguments.contains("-animate")
}

/// Three rooms instead of five feature tabs: the day as it flows, practising, and you (profile, measurements, history).
enum AppTab: String, Hashable, CaseIterable {
    case today, practice, me
}

/// Navigation state for the three tabs plus global sheets and toasts.
@MainActor
@Observable
final class AppModel {
    var tab: AppTab = .today
    var todayPath: [AppRoute] = []
    var practicePath: [AppRoute] = []
    var mePath: [AppRoute] = []
    var checkInPresented = false
    var toast: ToastMessage?
    /// Starts a session for `.play` deep links (set by the app).
    @ObservationIgnored var onPlay: ((TherapyMode, Int) -> Void)?

    func open(_ route: AppRoute) {
        switch route {
        case .checkin:
            checkInPresented = true
        case .headphones, .spectrum, .match, .hearing, .somatic, .ri, .progress, .learn, .settings:
            tab = .me
            mePath = [route]
        case .sound(let mode):
            tab = .practice
            practicePath = [.sound(mode)]
        case .play(let mode, let minutes):
            tab = .practice
            practicePath = [.sound(mode)]
            onPlay?(mode, minutes)
        case .mind, .lesson, .tool, .body:
            tab = .practice
            practicePath = [route]
        }
    }

    /// Push within the current tab.
    func push(_ route: AppRoute) {
        switch tab {
        case .today: todayPath.append(route)
        case .practice: practicePath.append(route)
        case .me: mePath.append(route)
        }
    }

    func pop() {
        switch tab {
        case .today: _ = todayPath.popLast()
        case .practice: _ = practicePath.popLast()
        case .me: _ = mePath.popLast()
        }
    }

    /// Replace the top screen of the current tab (e.g. lesson → its exercise, measurement → next step).
    func replaceTop(with route: AppRoute) {
        pop()
        push(route)
    }

    func showToast(_ text: String, kind: ToastMessage.Kind = .success) {
        let t = ToastMessage(text: text, kind: kind)
        withAnimation(.spring(duration: 0.35)) { toast = t }
        if kind == .success { Haptics.success() }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            if self.toast?.id == t.id { withAnimation(.easeOut) { self.toast = nil } }
        }
    }
}
