import SwiftUI

/// Warm dark palette and type scale, taken from the approved mockups.
enum Theme {
    static let background = Color(hex: 0x161514)
    static let rail = Color(hex: 0x1B1A19)
    static let surface = Color(hex: 0x211F1E)
    static let surface2 = Color(hex: 0x282624)
    static let surface3 = Color(hex: 0x312E2B)
    static let well = Color(hex: 0x121110)
    static let hairline = Color(red: 1, green: 245 / 255, blue: 235 / 255).opacity(0.06)
    static let hairline2 = Color(red: 1, green: 245 / 255, blue: 235 / 255).opacity(0.10)

    static let text = Color(hex: 0xEDEBE8)
    /// Secondary and tertiary text brighten over a background photo so they stay readable.
    static var text2: Color { backdrop ? Color(hex: 0xBBB6B0) : Color(hex: 0x9C9893) }
    static var text3: Color { backdrop ? Color(hex: 0x99948E) : Color(hex: 0x6B6763) }
    /// Set by `AppModel` when a background photo is shown.
    static var backdrop = false
    static let ink = Color(hex: 0x161514)

    static let accent = Color(hex: 0xC9A27E)
    static let busy = Color(hex: 0xE3B568)
    static let done = Color(hex: 0x8FBF9F)
    static let needs = Color(hex: 0xE07A6B)
    static let needsText = Color(hex: 0xEAA294)
    static let claude = Color(hex: 0xD97757)

    static let cardRadius: CGFloat = 14
    static let panelRadius: CGFloat = 22
    static let sectionGap: CGFloat = 40
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension Font {
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension EnvironmentValues {
    /// True when a background photo sits behind the content, so surfaces turn translucent.
    @Entry var hasBackdrop = false
}

extension View {
    /// Card: surface fill with a hairline border. Over a background photo it becomes frosted glass.
    func card(radius: CGFloat = Theme.cardRadius, fill: Color = Theme.surface, translucent: Bool = true) -> some View {
        modifier(CardStyle(radius: radius, fill: fill, translucent: translucent))
    }
}

private struct CardStyle: ViewModifier {
    @Environment(\.hasBackdrop) private var hasBackdrop
    let radius: CGFloat
    let fill: Color
    let translucent: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                if hasBackdrop && translucent {
                    ZStack {
                        shape.fill(.ultraThinMaterial)
                        shape.fill(fill.opacity(0.72))
                    }
                } else {
                    shape.fill(fill)
                }
            }
            .overlay(shape.strokeBorder(hasBackdrop ? Theme.hairline2 : Theme.hairline, lineWidth: 1))
    }
}
