import SwiftUI

/// Cool, quiet neutrals. The site is dark; on a phone the same coldness comes from
/// blue-grey paper, hairline strokes and one ink colour for the primary action.
enum DS {
    private static func dyn(_ light: String, _ dark: String) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
    static let bg = dyn("#F6F7F9", "#0A0B0D")
    static let card = dyn("#FFFFFF", "#121317")
    static let bar = dyn("#F6F7F9", "#0D0E11")
    static let stroke = dyn("#E4E7EC", "#1E2026")
    static let text = dyn("#111317", "#EDEFF3")
    static let secondary = dyn("#6B7280", "#9AA0AC")
    static let ink = dyn("#111317", "#EDEFF3")
    static let onInk = dyn("#F7F8FA", "#0A0B0D")
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
}

struct PrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(DS.onInk)
            .frame(minWidth: 104, minHeight: 44)
            .padding(.horizontal, 18)
            .background(DS.ink.opacity(configuration.isPressed || !enabled ? 0.55 : 1), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// The low-chroma palette from the site, used for the empty space around a photo.
/// One palette colour, ringed when it is the current choice.
struct PaletteDot: View {
    var hex: String
    var selected: Bool
    var size: CGFloat = 28

    var body: some View {
        Circle()
            .fill(Color(UIColor(hex: hex)))
            .frame(width: size, height: size)
            .overlay {
                Circle().strokeBorder(DS.ink, lineWidth: selected ? 2 : 0)
            }
    }
}

enum Palette {
    struct Swatch { let name: String; let hex: String }
    /// Low-chroma Pantone tones that sit next to ink without fighting the photo.
    /// Ordered by tone, so neighbours on the grid look related: neutrals, then
    /// greens through yellow, then the warm end and the purples.
    static let all: [Swatch] = [
        .init(name: "Stone", hex: "#969EA5"),   // Pantone 4151 C
        .init(name: "Slate", hex: "#9FAFBC"),   // Pantone 5445 C
        .init(name: "Deep",  hex: "#5E6C74"),   // Pantone 7546 C
        .init(name: "Teal",  hex: "#8FA6A3"),   // Pantone 5493 C
        .init(name: "Sage",  hex: "#A3AC9E"),   // Pantone 5665 C
        .init(name: "Olive", hex: "#A8A482"),   // muted olive
        .init(name: "Sand",  hex: "#D6D2C4"),   // Pantone 7527 C
        .init(name: "Clay",  hex: "#B49A8D"),   // warm clay
        .init(name: "Rose",  hex: "#C2A8AB"),   // dusty rose
        .init(name: "Mauve", hex: "#B3AACD"),   // Pantone 2645 C
    ]
}
