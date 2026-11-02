import SwiftUI

/// The main window for the Tsukihime macOS launcher.
public struct MainLauncherWindow: View {
    @StateObject var model: LauncherModel

    public init(model: LauncherModel? = nil) {
        _model = StateObject(wrappedValue: model ?? LauncherModel())
    }

    public var body: some View {
        ZStack {
            // Background
            LauncherTheme.nightGradient
                .ignoresSafeArea()

            // Upper right moonlight ambient glow
            GeometryReader { geo in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                LauncherTheme.moonBlue.opacity(0.18),
                                LauncherTheme.moonBlue.opacity(0.06),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 50,
                            endRadius: 400
                        )
                    )
                    .frame(width: 800, height: 800)
                    .position(x: geo.size.width - 50, y: -50)
                    .allowsHitTesting(false)
            }

            // Main Layout: Sidebar + Content Column
            HStack(spacing: 0) {
                // Sidebar
                VStack(alignment: .leading, spacing: 0) {
                    // Logo brand header
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(LauncherTheme.accentGradient)
                                .frame(width: 36, height: 36)
                                .mask(
                                    ZStack {
                                        Circle().frame(width: 36, height: 36)
                                        Circle().frame(width: 32, height: 32)
                                            .offset(x: 7, y: -4)
                                            .blendMode(.destinationOut)
                                    }
                                )
                                .shadow(color: LauncherTheme.moonBlue.opacity(0.8), radius: 8)

                            Image(systemName: "sparkle")
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                                .offset(x: 10, y: 10)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text("TSUKIHIME")
                                .font(.system(size: 17, weight: .bold, design: .serif))
                                .tracking(1.8)
                                .foregroundColor(LauncherTheme.text)
                            Text("macOS PORT")
                                .font(.system(size: 9.5, weight: .semibold))
                                .tracking(2.5)
                                .foregroundColor(LauncherTheme.gold)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 28)
                    .padding(.bottom, 24)

                    // Navigation List
                    VStack(spacing: 4) {
                        ForEach(LauncherPage.allCases) { p in
                            SidebarItemView(
                                page: p,
                                isSelected: model.page == p
                            ) {
                                model.page = p
                            }
                        }
                    }
                    .padding(.horizontal, 14)

                    Spacer()

                    // Sidebar Footer
                    VStack(alignment: .leading, spacing: 6) {
                        GoldDivider()
                            .padding(.bottom, 8)
                        Text(model.launcherVersion)
                            .font(.system(size: 11.5))
                            .foregroundColor(LauncherTheme.muted)
                        Text("Fan-made. Not affiliated with TYPE-MOON.")
                            .font(.system(size: 10.5))
                            .foregroundColor(Color(red: 0x6C / 255.0, green: 0x76 / 255.0, blue: 0x99 / 255.0))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 20)
                }
                .frame(width: 240)
                .background(Color(red: 0x0B / 255.0, green: 0x11 / 255.0, blue: 0x29 / 255.0, opacity: 0.95))
                .overlay(
                    Rectangle()
                        .fill(LauncherTheme.divider)
                        .frame(width: 1),
                    alignment: .trailing
                )

                // Content Column
                VStack(spacing: 0) {
                    // Page Content
                    ZStack {
                        switch model.page {
                        case .play:
                            PlayPageView(model: model)
                        case .gameFiles:
                            GameFilesPageView(model: model)
                        case .display:
                            DisplayPageView(model: model)
                        case .language:
                            LanguagePageView(model: model)
                        case .controls:
                            ControlsPageView(model: model)
                        case .saves:
                            SavesPageView(model: model)
                        case .help:
                            HelpPageView(model: model)
                        }

                        // Floating Toast
                        if model.toastVisible {
                            VStack {
                                Spacer()
                                Text(model.toast)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(Color(red: 0x16 / 255.0, green: 0x1F / 255.0, blue: 0x45 / 255.0, opacity: 0.95))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(LauncherTheme.moonPale.opacity(0.4), lineWidth: 1)
                                    )
                                    .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
                                    .padding(.bottom, 16)
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                            .animation(.easeInOut(duration: 0.25), value: model.toastVisible)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 20)

                    // Footer Bar
                    HStack(spacing: 16) {
                        // Status dot + line
                        HStack(spacing: 10) {
                            Circle()
                                .fill(LauncherTheme.moonPale)
                                .frame(width: 7, height: 7)
                                .shadow(color: LauncherTheme.moonPale, radius: 5)

                            Text(model.statusLine)
                                .font(.system(size: 12.5))
                                .foregroundColor(LauncherTheme.muted)
                                .lineLimit(1)
                        }

                        Spacer()

                        // Log Button
                        Button("Log") {
                            model.openLog()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)

                        // Big PLAY Button
                        Button(action: {
                            model.play()
                        }) {
                            Text(model.playLabel)
                                .font(.system(size: 14, weight: .bold))
                                .tracking(1.5)
                                .foregroundColor(.white)
                                .frame(minWidth: 120, minHeight: 38)
                                .background(LauncherTheme.playGradient)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(LauncherTheme.moonPale.opacity(0.4), lineWidth: 1)
                                )
                                .shadow(color: LauncherTheme.moonBlue.opacity(model.canPlay ? 0.6 : 0), radius: 10)
                        }
                        .buttonStyle(.plain)
                        .disabled(!model.canPlay || model.gameRunning)
                        .opacity(model.canPlay ? 1.0 : 0.5)
                    }
                    .padding(.horizontal, 28)
                    .frame(height: 72)
                    .background(Color(red: 0x0A / 255.0, green: 0x0F / 255.0, blue: 0x24 / 255.0, opacity: 0.8))
                    .overlay(
                        Rectangle().fill(LauncherTheme.divider).frame(height: 1),
                        alignment: .top
                    )
                }
            }

            // Confirmation Modal Overlay
            if model.confirmVisible, let req = model.confirm {
                ZStack {
                    Color.black.opacity(0.65)
                        .ignoresSafeArea()

                    VStack(alignment: .leading, spacing: 14) {
                        Text(req.title)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(LauncherTheme.text)

                        GoldDivider()

                        Text(req.body)
                            .font(.system(size: 13))
                            .foregroundColor(Color(red: 0xB9 / 255.0, green: 0xC3 / 255.0, blue: 0xE3 / 255.0))
                            .lineSpacing(3)
                            .padding(.vertical, 4)

                        HStack(spacing: 12) {
                            Spacer()

                            Button("Cancel") {
                                model.answerConfirm(false)
                            }
                            .buttonStyle(.bordered)

                            Button(req.confirmLabel) {
                                model.answerConfirm(true)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(LauncherTheme.moonBlue)
                        }
                        .padding(.top, 8)
                    }
                    .padding(24)
                    .frame(width: 460)
                    .background(Color(red: 0x12 / 255.0, green: 0x1A / 255.0, blue: 0x3A / 255.0))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(LauncherTheme.panelBorder, lineWidth: 1)
                    )
                    .shadow(color: LauncherTheme.moonBlue.opacity(0.3), radius: 25)
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: model.confirmVisible)
            }
        }
        .frame(minWidth: 960, minHeight: 640)
    }
}

/// A sidebar navigation item.
struct SidebarItemView: View {
    let page: LauncherPage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: page.systemImage)
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? LauncherTheme.moonPale : LauncherTheme.muted)
                    .frame(width: 20)

                Text(page.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : LauncherTheme.text.opacity(0.85))

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isSelected ? LauncherTheme.moonBlue.opacity(0.2) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isSelected ? LauncherTheme.moonBlue.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
