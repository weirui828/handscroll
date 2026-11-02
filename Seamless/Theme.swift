import SwiftUI

enum Theme: String, CaseIterable, Identifiable {
    case violet, cyan, gold, rose, emerald, custom
    var id: String { rawValue }

    /// The accent and the text color that reads on it.
    var hex: String? {
        switch self {
        case .violet: "#A78BFA"
        case .cyan: "#22D3EE"
        case .gold: "#FBBF24"
        case .rose: "#F472B6"
        case .emerald: "#34D399"
        case .custom: nil
        }
    }
}

extension UIColor {
    convenience init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let n = UInt32(s, radix: 16) ?? 0x1A1A1A
        self.init(red: CGFloat((n >> 16) & 255) / 255, green: CGFloat((n >> 8) & 255) / 255, blue: CGFloat(n & 255) / 255, alpha: 1)
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    /// Dark text on light colors, white on dark ones.
    var ink: UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let L = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        return L > 0.18 ? UIColor(hex: "#111114") : .white
    }
}

/// The user's accent, saved on the device.
struct Accent {
    var themeRaw: String
    var customHex: String

    var theme: Theme { Theme(rawValue: themeRaw) ?? .violet }
    var ui: UIColor { UIColor(hex: theme.hex ?? customHex) }
    var color: Color { Color(ui) }
    var ink: Color { Color(ui.ink) }
}

/// Cool, quiet neutrals. The site is dark; on a phone the same coldness comes from
/// blue-grey paper, hairline strokes and one accent that only marks a choice.
enum DS {
    private static func dyn(_ light: String, _ dark: String) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
    static let bg = dyn("#F6F7F9", "#0A0B0D")
    static let canvas = dyn("#ECEEF2", "#050608")
    static let card = dyn("#FFFFFF", "#121317")
    static let bar = dyn("#F6F7F9", "#0D0E11")
    static let stroke = dyn("#E4E7EC", "#1E2026")
    static let text = dyn("#111317", "#EDEFF3")
    static let secondary = dyn("#6B7280", "#9AA0AC")
    static let ink = dyn("#111317", "#EDEFF3")
    static let onInk = dyn("#F7F8FA", "#0A0B0D")
}

/// A bare 44 pt tap target for the one or two secondary actions in a bar.
struct QuietBarButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(enabled ? DS.secondary : DS.secondary.opacity(0.35))
            .opacity(configuration.isPressed ? 0.5 : 1)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

struct PrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var accent: Accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(DS.onInk)
            .frame(minWidth: 104, minHeight: 44)
            .padding(.horizontal, 18)
            .background(DS.ink.opacity(configuration.isPressed || !enabled ? 0.55 : 1), in: RoundedRectangle(cornerRadius: 12))
    }
}
