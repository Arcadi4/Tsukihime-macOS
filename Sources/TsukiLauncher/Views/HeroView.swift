import SwiftUI

/// Top banner view showing game art or drawn moonlight fallback.
public struct HeroView: View {
    @ObservedObject var model: LauncherModel

    public init(model: LauncherModel) {
        self.model = model
    }

    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background: loaded art or drawn moon canvas
            if let hero = model.heroArt {
                Image(nsImage: hero)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 270)
                    .clipped()
            } else {
                MoonFallbackCanvas()
                    .frame(height: 270)
            }

            // Darkening gradients for legibility
            LinearGradient(
                colors: [
                    LauncherTheme.nightTop.opacity(0.92),
                    LauncherTheme.nightTop.opacity(0.70),
                    LauncherTheme.nightTop.opacity(0.25),
                    Color.clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            LinearGradient(
                colors: [
                    Color.clear,
                    LauncherTheme.nightTop.opacity(0.85)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 100)

            // Content text and chips
            VStack(alignment: .leading, spacing: 6) {
                Text("NATIVE PORT  ·  macOS")
                    .font(.system(size: 11.5, weight: .semibold))
                    .tracking(2.5)
                    .foregroundColor(LauncherTheme.gold)

                if let logo = model.heroLogo {
                    Image(nsImage: logo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 380, maxHeight: 90, alignment: .leading)
                        .shadow(color: LauncherTheme.moonBlue.opacity(0.6), radius: 15)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TSUKIHIME")
                            .font(.system(size: 48, weight: .bold, design: .serif))
                            .tracking(4)
                            .foregroundColor(LauncherTheme.text)
                            .shadow(color: LauncherTheme.moonBlue.opacity(0.7), radius: 20)

                        Text("-A piece of blue glass moon-")
                            .font(.system(size: 16, weight: .medium, design: .serif))
                            .italic()
                            .foregroundColor(Color(red: 0xC4 / 255.0, green: 0xD2 / 255.0, blue: 0xF5 / 255.0))
                    }
                }

                HStack(spacing: 8) {
                    ChipView(text: model.gameChip)
                    ChipView(text: model.launcherVersion)
                }
                .padding(.top, 10)
            }
            .padding(.leading, 32)
            .padding(.bottom, 24)
        }
        .frame(height: 270)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(LauncherTheme.panelBorder, lineWidth: 1)
        )
    }
}

/// Fallback drawn blue moon canvas when art is not loaded.
struct MoonFallbackCanvas: View {
    var body: some View {
        Canvas { context, size in
            // Night sky gradient
            let rect = CGRect(origin: .zero, size: size)
            let skyGradient = Gradient(colors: [
                Color(red: 0x0A / 255.0, green: 0x0F / 255.0, blue: 0x24 / 255.0),
                Color(red: 0x16 / 255.0, green: 0x22 / 255.0, blue: 0x5A / 255.0),
                Color(red: 0x0E / 255.0, green: 0x15 / 255.0, blue: 0x32 / 255.0)
            ])
            context.fill(Path(rect), with: .linearGradient(skyGradient, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))

            // Moon glow
            let moonCenter = CGPoint(x: size.width * 0.72, y: size.height * 0.45)
            let outerGlowRect = CGRect(x: moonCenter.x - 200, y: moonCenter.y - 200, width: 400, height: 400)
            let glowGrad = Gradient(colors: [
                Color(red: 0x5E / 255.0, green: 0x8B / 255.0, blue: 1.0, opacity: 0.4),
                Color(red: 0x5E / 255.0, green: 0x8B / 255.0, blue: 1.0, opacity: 0.1),
                Color.clear
            ])
            context.fill(Path(ellipseIn: outerGlowRect), with: .radialGradient(glowGrad, center: moonCenter, startRadius: 20, endRadius: 200))

            // Thin orbit ring
            let ringRect = CGRect(x: moonCenter.x - 120, y: moonCenter.y - 120, width: 240, height: 240)
            context.stroke(Path(ellipseIn: ringRect), with: .color(Color(red: 0x9C / 255.0, green: 0xD2 / 255.0, blue: 1.0, opacity: 0.2)), lineWidth: 1)

            // Moon body
            let moonRect = CGRect(x: moonCenter.x - 75, y: moonCenter.y - 75, width: 150, height: 150)
            let moonGrad = Gradient(colors: [
                Color(red: 0xF7 / 255.0, green: 0xFB / 255.0, blue: 1.0),
                Color(red: 0xC4 / 255.0, green: 0xE3 / 255.0, blue: 1.0),
                Color(red: 0x7D / 255.0, green: 0xA8 / 255.0, blue: 1.0),
                Color(red: 0x3A / 255.0, green: 0x55 / 255.0, blue: 0xB5 / 255.0)
            ])
            context.fill(Path(ellipseIn: moonRect), with: .radialGradient(moonGrad, center: CGPoint(x: moonCenter.x - 20, y: moonCenter.y - 25), startRadius: 10, endRadius: 75))

            // Subtle inner ring
            let innerRing = CGRect(x: moonCenter.x - 70, y: moonCenter.y - 70, width: 140, height: 140)
            context.stroke(Path(ellipseIn: innerRing), with: .color(Color.white.opacity(0.25)), lineWidth: 1)

            // Stars / sparkles
            let stars: [(x: CGFloat, y: CGFloat, r: CGFloat, alpha: Double)] = [
                (size.width * 0.55, size.height * 0.2, 1.8, 0.8),
                (size.width * 0.88, size.height * 0.35, 2.0, 0.7),
                (size.width * 0.82, size.height * 0.15, 1.5, 0.6),
                (size.width * 0.94, size.height * 0.45, 1.5, 0.5),
                (size.width * 0.48, size.height * 0.60, 1.2, 0.5),
                (size.width * 0.65, size.height * 0.85, 1.5, 0.6),
                (size.width * 0.85, size.height * 0.80, 1.8, 0.6)
            ]
            for star in stars {
                let starRect = CGRect(x: star.x - star.r, y: star.y - star.r, width: star.r * 2, height: star.r * 2)
                context.fill(Path(ellipseIn: starRect), with: .color(Color.white.opacity(star.alpha)))
            }
        }
    }
}

/// Small rounded chip badge.
struct ChipView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundColor(Color(red: 0xC4 / 255.0, green: 0xD2 / 255.0, blue: 0xF5 / 255.0))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(red: 0x12 / 255.0, green: 0x1A / 255.0, blue: 0x3A / 255.0, opacity: 0.6))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color(red: 0xBF / 255.0, green: 0xD2 / 255.0, blue: 1.0, opacity: 0.25), lineWidth: 1)
            )
    }
}
