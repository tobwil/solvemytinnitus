import SwiftUI
import TinnitusCore
import UIKit

/// One colour story instead of one colour per area:
/// teal = calm and everything you do (sound, mind, body, measuring), amber = the tinnitus itself.
/// The background warms up towards amber when the last check-in was loud (see `Ambient`).
enum Theme {
    static let bg = Color(light: 0xF3F5F8, dark: 0x07090D)
    static let bgElevated = Color(light: 0xFFFFFF, dark: 0x0D1118)
    static let surface = Color(lightRGBA: (1, 1, 1, 0.78), darkRGBA: (1, 1, 1, 0.045))
    static let surface2 = Color(lightRGBA: (15 / 255, 23 / 255, 42 / 255, 0.05), darkRGBA: (1, 1, 1, 0.075))
    static let surface3 = Color(lightRGBA: (15 / 255, 23 / 255, 42 / 255, 0.09), darkRGBA: (1, 1, 1, 0.11))
    static let stroke = Color(lightRGBA: (15 / 255, 23 / 255, 42 / 255, 0.08), darkRGBA: (1, 1, 1, 0.08))
    static let stroke2 = Color(lightRGBA: (15 / 255, 23 / 255, 42 / 255, 0.14), darkRGBA: (1, 1, 1, 0.14))
    static let text = Color(light: 0x0B1220, dark: 0xEEF2F7)
    static let text2 = text.opacity(0.68)
    static let text3 = text.opacity(0.42)

    static let sound = Color(light: 0x0D9488, dark: 0x5EEAD4)
    static let accent = sound
    // former per-area colours: all areas share the calm accent now
    static let mind = sound
    static let lab = sound
    static let body = sound
    static let tin = Color(light: 0xD97706, dark: 0xFBBF24)
    /// Second data series next to loudness (distress, right ear): a quiet slate.
    static let distress = Color(light: 0x52627A, dark: 0xAEBBD0)
    static let good = Color(light: 0x16A34A, dark: 0x4ADE80)
    static let warn = Color(light: 0xEA580C, dark: 0xFB923C)
    static let bad = Color(light: 0xDC2626, dark: 0xF87171)
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x04130F)

    static let radiusSmall: CGFloat = 10
    static let radius: CGFloat = 18
    static let radiusLarge: CGFloat = 26

    static func color(_ kind: DayTask.Kind) -> Color {
        switch kind {
        case .lab: lab
        case .sound: sound
        case .mind: mind
        case .tin: tin
        case .body: body
        }
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    init(lightRGBA l: (CGFloat, CGFloat, CGFloat, CGFloat), darkRGBA d: (CGFloat, CGFloat, CGFloat, CGFloat)) {
        self.init(uiColor: UIColor { t in
            let c = t.userInterfaceStyle == .dark ? d : l
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: c.3)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Font {
    /// Rounded display face for big numbers and titles (SF Pro Rounded).
    /// Scales with the user's text size (Dynamic Type), capped so big numbers still fit.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        let scaled = min(UIFontMetrics(forTextStyle: .largeTitle).scaledValue(for: size), size * 1.6)
        return .system(size: scaled, weight: weight, design: .rounded)
    }
    static let titleXL = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let titleL = Font.system(.title2, design: .rounded).weight(.bold)
    static let titleM = Font.system(.headline, design: .default).weight(.semibold)
    static let eyebrow = Font.system(.caption, design: .default).weight(.semibold)
}
