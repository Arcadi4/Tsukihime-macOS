import SwiftUI
import TsukiEngine

/// The Language & Sound page: language switcher tiles and audio notes.
public struct LanguagePageView: View {
    @ObservedObject var model: LauncherModel

    public init(model: LauncherModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeaderView(
                    overline: "LANGUAGE & SOUND",
                    title: "Voice and text",
                    description: "The language of the story, the menus and the pictures that carry text. The voices stay Japanese in every language, as in the original game."
                )

                // Language Tiles Card
                LauncherCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader("GAME LANGUAGE")
                        GoldDivider()

                        HStack(spacing: 12) {
                            LanguageTile(
                                nativeName: "日本語",
                                englishName: "Japanese",
                                isSelected: model.languageIndex == 0
                            ) {
                                model.setLanguage(0)
                            }

                            LanguageTile(
                                nativeName: "English",
                                englishName: "English",
                                isSelected: model.languageIndex == 1
                            ) {
                                model.setLanguage(1)
                            }

                            LanguageTile(
                                nativeName: "简体中文",
                                englishName: "Simplified Chinese",
                                isSelected: model.languageIndex == 2
                            ) {
                                model.setLanguage(2)
                            }

                            LanguageTile(
                                nativeName: "繁體中文",
                                englishName: "Traditional Chinese",
                                isSelected: model.languageIndex == 3
                            ) {
                                model.setLanguage(3)
                            }
                        }

                        Text("Takes effect the next time the game starts. Inside the game, Config also switches the language at once. A language your copy of the game does not carry is not offered.")
                            .font(.system(size: 12))
                            .foregroundColor(LauncherTheme.muted)
                            .lineSpacing(2)
                            .padding(.top, 4)
                    }
                }

                // Sound Card
                LauncherCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader("SOUND")
                        GoldDivider()

                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 22))
                                .foregroundColor(LauncherTheme.moonPale)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Change volumes in the game's Config")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundColor(LauncherTheme.text)
                                Text("Music, sound effects, system sounds and voices are saved with your progress, so they are set in the game itself: open the system menu (Esc), then Config.")
                                    .font(.system(size: 12))
                                    .foregroundColor(LauncherTheme.muted)
                                    .lineSpacing(2)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }
}

/// A card tile for selecting a language.
struct LanguageTile: View {
    let nativeName: String
    let englishName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(nativeName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isSelected ? .white : LauncherTheme.text)
                Text(englishName)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? LauncherTheme.moonPale : LauncherTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(isSelected ? LauncherTheme.moonBlue.opacity(0.3) : Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? LauncherTheme.moonBlue : LauncherTheme.panelBorder, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
