import SwiftUI

/// The Controls page: button prompt style, keyboard/mouse table, controller detection.
public struct ControlsPageView: View {
    @ObservedObject var model: LauncherModel

    public init(model: LauncherModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeaderView(
                    overline: "CONTROLS",
                    title: "Keyboard, mouse and pad",
                    description: "Play with the keyboard and mouse, or with a pad. The game switches between them as you go, and the on-screen button hints follow."
                )

                // Button Prompts Card
                LauncherCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader("BUTTON PROMPTS")
                        GoldDivider()

                        Picker("Button Prompts", selection: Binding(
                            get: { model.promptsIndex },
                            set: { model.setPrompts($0) }
                        )) {
                            Text("Auto").tag(0)
                            Text("Keyboard").tag(1)
                            Text("PlayStation").tag(2)
                            Text("Xbox").tag(3)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 480)

                        Text("Auto shows key caps for the keyboard and mouse, the game's own PlayStation icons for a PlayStation pad and Xbox glyphs for any other pad, and follows the device you used last. The other three keep one style.")
                            .font(.system(size: 12))
                            .foregroundColor(LauncherTheme.muted)
                            .lineSpacing(2)
                    }
                }

                // Keyboard and Mouse Card
                LauncherCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader("KEYBOARD AND MOUSE")
                        GoldDivider()

                        VStack(spacing: 8) {
                            ForEach(model.keys) { row in
                                HStack(alignment: .top, spacing: 14) {
                                    Text(row.keys)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(LauncherTheme.text)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.white.opacity(0.08))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(LauncherTheme.panelBorder, lineWidth: 1)
                                        )
                                        .frame(width: 250, alignment: .leading)

                                    Text(row.action)
                                        .font(.system(size: 12.5))
                                        .foregroundColor(Color(red: 0xB9 / 255.0, green: 0xC3 / 255.0, blue: 0xE3 / 255.0))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.top, 4)
                                }
                            }
                        }
                    }
                }

                // Game Controllers Card
                LauncherCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader("GAME CONTROLLERS")
                        GoldDivider()

                        Text(model.controllersText)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundColor(LauncherTheme.text)

                        Text("Pads are detected at any time, also while the game runs. South button = decide, east = cancel, west = system menu, north = backlog, shoulders = auto and skip, triggers = rewind and fast-forward, start = quick save.")
                            .font(.system(size: 12))
                            .foregroundColor(LauncherTheme.muted)
                            .lineSpacing(2)
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }
}
