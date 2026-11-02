import SwiftUI

/// Palette and styles for the Tsukihime launcher ("blue glass moon").
public enum LauncherTheme {
    public static let nightTop = Color(red: 0x0A / 255.0, green: 0x0F / 255.0, blue: 0x24 / 255.0)
    public static let nightBottom = Color(red: 0x0E / 255.0, green: 0x15 / 255.0, blue: 0x32 / 255.0)
    public static let panelColor = Color(red: 0x12 / 255.0, green: 0x1A / 255.0, blue: 0x3A / 255.0)
    public static let panelBorder = Color(red: 0x8F / 255.0, green: 0xA6 / 255.0, blue: 1.0, opacity: 0.15)
    public static let moonBlue = Color(red: 0x5E / 255.0, green: 0x8B / 255.0, blue: 1.0)
    public static let moonPale = Color(red: 0x9C / 255.0, green: 0xD2 / 255.0, blue: 1.0)
    public static let gold = Color(red: 0xD9 / 255.0, green: 0xC5 / 255.0, blue: 0x8E / 255.0)
    public static let success = Color(red: 0x7E / 255.0, green: 0xD6 / 255.0, blue: 0xA8 / 255.0)
    public static let warning = Color(red: 0xE8 / 255.0, green: 0xC8 / 255.0, blue: 0x77 / 255.0)
    public static let text = Color(red: 0xE9 / 255.0, green: 0xED / 255.0, blue: 0xF8 / 255.0)
    public static let muted = Color(red: 0x98 / 255.0, green: 0xA2 / 255.0, blue: 0xC8 / 255.0)
    public static let divider = Color.white.opacity(0.08)

    public static let nightGradient = LinearGradient(
        colors: [nightTop, nightBottom],
        startPoint: .top,
        endPoint: .bottom
    )

    public static let accentGradient = LinearGradient(
        colors: [moonBlue, moonPale],
        startPoint: .leading,
        endPoint: .trailing
    )

    public static let playGradient = LinearGradient(
        colors: [Color(red: 0x3A / 255.0, green: 0x6E / 255.0, blue: 0xF5 / 255.0), moonBlue],
        startPoint: .top,
        endPoint: .bottom
    )
}

/// A standard card container used throughout the launcher.
public struct LauncherCard<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(20)
        .background(LauncherTheme.panelColor.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(LauncherTheme.panelBorder, lineWidth: 1)
        )
    }
}

/// Gold thin separator.
public struct GoldDivider: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(LauncherTheme.gold.opacity(0.25))
            .frame(height: 1)
    }
}

/// Small caps header style.
public struct SectionHeader: View {
    let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11.5, weight: .semibold, design: .default))
            .tracking(2.0)
            .foregroundColor(LauncherTheme.gold)
    }
}

/// Standard page header at the top of secondary pages.
public struct PageHeaderView: View {
    let overline: String
    let title: String
    let description: String

    public init(overline: String, title: String, description: String) {
        self.overline = overline
        self.title = title
        self.description = description
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(overline)
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(LauncherTheme.text)
            Text(description)
                .font(.system(size: 13))
                .foregroundColor(LauncherTheme.muted)
                .lineSpacing(3)
        }
        .padding(.bottom, 16)
    }
}
