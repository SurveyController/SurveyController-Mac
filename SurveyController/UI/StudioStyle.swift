import SwiftUI

enum StudioStyle {
    static let canvas = adaptive(0xF3F4F7, 0x15171C)
    static let panel = adaptive(0xFFFFFF, 0x202329)
    static let raised = adaptive(0xEBEDF2, 0x2A2D35)
    static let border = adaptive(0xDBE0E9, 0x383D49)
    static let accent = adaptive(0x2D50CB, 0xA7BBFF)
    static let onAccent = adaptive(0xFFFFFF, 0x131D3A)
    static let accentFill = adaptive(0xE9EEFC, 0x303952)
    static let ink = adaptive(0x1B2230, 0xEDF0F6)
    static let muted = adaptive(0x545E70, 0xADB7CA)
    static let warning = adaptive(0x8A4A10, 0xF0BB7D)
    static let danger = adaptive(0xAD3349, 0xFFA5B3)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
}

extension View {
    func studioPanel(radius: CGFloat = 19) -> some View {
        background(StudioStyle.panel, in: RoundedRectangle(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(StudioStyle.border)
                    .allowsHitTesting(false)
            }
    }
}

struct StudioMark: View {
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: size * 0.47, weight: .semibold))
            .foregroundStyle(StudioStyle.accent)
            .frame(width: size, height: size)
            .background(StudioStyle.accentFill, in: RoundedRectangle(cornerRadius: size * 0.28))
            .accessibilityHidden(true)
    }
}

struct StudioHeading: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(StudioStyle.accent)
                    .frame(width: 44, height: 44)
                    .background(StudioStyle.accentFill, in: RoundedRectangle(cornerRadius: 13))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 28, weight: .bold))
                    .foregroundStyle(StudioStyle.ink)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(StudioStyle.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StudioMetric: View {
    let title: String
    let value: String
    let icon: String
    var color = StudioStyle.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(StudioStyle.muted)
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .contentTransition(.numericText())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioPanel(radius: 15)
        .accessibilityElement(children: .combine)
    }
}
