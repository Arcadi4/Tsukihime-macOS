import SwiftUI

/// The Help & About page: overview, setup guide, essential keys, troubleshooting, and licenses.
public struct HelpPageView: View {
    @ObservedObject var model: LauncherModel

    public init(model: LauncherModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeaderView(
                    overline: "HELP & ABOUT",
                    title: "About this port",
                    description: "A fan-made, native macOS version of the PS4 game that runs on the files of your own copy."
                )

                // What this is Card
                LauncherCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader("WHAT THIS IS")
                        GoldDivider()

                        Text("TSUKIHIME macOS Native Port is a clean reimplementation of the game's engine. Every time it starts it reads the game files of your own copy, the extracted CUSA47999 folder, and plays them with sound, movies, menus and saves. Nothing from the game is included in the port, and nothing in your game folder is ever changed.")
                            .font(.system(size: 13))
                            .foregroundColor(Color(red: 0xB9 / 255.0, green: 0xC3 / 255.0, blue: 0xE3 / 255.0))
                            .lineSpacing(4)

                        Text("Tsukihime macOS port is an unofficial fan project. It is not affiliated with, endorsed by or supported by TYPE-MOON, Aniplex, HuneX or Sony. TSUKIHIME and all of its art, music, text and characters belong to their rights holders. This program contains no game data: it only plays the files of a copy of TSUKIHIME -A piece of blue glass moon- (PS4) that you own. You must supply those files yourself; this project does not provide the files or link to any source of them.")
                            .font(.system(size: 12.5))
                            .foregroundColor(LauncherTheme.muted)
                            .lineSpacing(3)
                            .padding(.top, 4)
                    }
                }

                // Setup Guide Card
                LauncherCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader("SETUP GUIDE")
                        GoldDivider()

                        Text("SETUP_GUIDE.md is the player's guide: what you need, how your own game files must be laid out (the game folder, the update folder beside it), the first start, every key, and what each message of the launcher and the game means.")
                            .font(.system(size: 13))
                            .foregroundColor(Color(red: 0xB9 / 255.0, green: 0xC3 / 255.0, blue: 0xE3 / 255.0))
                            .lineSpacing(3)

                        Button("Open the setup guide") {
                            model.openGuide()
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 4)
                    }
                }

                // Essential Keys Card
                LauncherCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader("THE KEYS YOU NEED")
                        GoldDivider()

                        VStack(spacing: 8) {
                            ForEach(model.essentialKeys) { row in
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

                        Text("The Controls page lists every key.")
                            .font(.system(size: 12))
                            .foregroundColor(LauncherTheme.muted)
                            .padding(.top, 4)
                    }
                }

                // Troubleshooting Card
                LauncherCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader("IF SOMETHING GOES WRONG")
                        GoldDivider()

                        Text("The game writes last_run.log next to your saves each time it runs, and crash.log when it fails. The ready check on the Play page says what is missing.")
                            .font(.system(size: 13))
                            .foregroundColor(Color(red: 0xB9 / 255.0, green: 0xC3 / 255.0, blue: 0xE3 / 255.0))
                            .lineSpacing(3)

                        HStack(spacing: 10) {
                            Button("Open the log") {
                                model.openLog()
                            }
                            .buttonStyle(.bordered)

                            Button("Open the saves folder") {
                                model.openSavesFolder()
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.top, 4)
                    }
                }

                // Licenses Card
                LauncherCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader("LICENSES")
                        GoldDivider()

                        LicenseRow(name: "knife", license: "MPL-2.0", description: "Parts of the menu and story code are translations of AuroraWright's knife (github.com/AuroraWright/knife). Those files stay under the Mozilla Public License 2.0.")
                        LicenseRow(name: "FFmpeg", license: "LGPL v3", description: "Movies and sound are decoded by FFmpeg's shared libraries (avcodec, avformat, avutil, swresample).")
                        LicenseRow(name: "SDL3", license: "zlib", description: "Windowing, input devices and controllers.")
                        LicenseRow(name: "Swift / Native Port", license: "MPL-2.0", description: "The port's own Swift implementation is under the Mozilla Public License 2.0.")
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }
}

struct LicenseRow: View {
    let name: String
    let license: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(LauncherTheme.text)
                Text(license)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(LauncherTheme.gold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(LauncherTheme.gold.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(LauncherTheme.gold.opacity(0.3), lineWidth: 1)
                    )
            }
            Text(description)
                .font(.system(size: 12))
                .foregroundColor(LauncherTheme.muted)
                .lineSpacing(2)
        }
    }
}
