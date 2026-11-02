import SwiftUI

/// The Display page: fullscreen, window size presets, monitors.
public struct DisplayPageView: View {
    @ObservedObject var model: LauncherModel

    public init(model: LauncherModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeaderView(
                    overline: "DISPLAY",
                    title: "Window and picture",
                    description: "The game draws a 1920 × 1080 picture and fits it into the window with black bars where the shapes differ. These choices are read when the game starts."
                )

                // Mode Card
                LauncherCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader("MODE")
                        GoldDivider()

                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Fullscreen")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundColor(LauncherTheme.text)
                                Text("Borderless fullscreen on the chosen monitor; off, the game opens as a window. In the game, Command+Return or F11 switches it at any time.")
                                    .font(.system(size: 12))
                                    .foregroundColor(LauncherTheme.muted)
                                    .lineSpacing(2)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { model.fullscreen },
                                set: { model.setFullscreen($0) }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                        }

                        Divider().background(LauncherTheme.divider)

                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("VSync")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundColor(LauncherTheme.text)
                                Text("Wait for the monitor's refresh when showing a frame. Turn it off only if the picture stutters.")
                                    .font(.system(size: 12))
                                    .foregroundColor(LauncherTheme.muted)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { model.vsync },
                                set: { model.setVsync($0) }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                        }
                    }
                }

                // Window Size Card
                LauncherCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader("WINDOW SIZE")
                        GoldDivider()

                        HStack(spacing: 10) {
                            ForEach(model.windowSizes) { choice in
                                Button(action: {
                                    model.setWindowSize(choice)
                                }) {
                                    Text(choice.label)
                                        .font(.system(size: 12.5, weight: .medium))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(model.selectedWindowSize == choice ? LauncherTheme.moonBlue : LauncherTheme.panelColor)
                                        .foregroundColor(model.selectedWindowSize == choice ? .white : LauncherTheme.text)
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .stroke(model.selectedWindowSize == choice ? LauncherTheme.moonPale : LauncherTheme.panelBorder, lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Text(model.windowSizeNote)
                            .font(.system(size: 12))
                            .foregroundColor(LauncherTheme.muted)
                            .lineSpacing(2)
                            .padding(.top, 4)

                        Text("Only the presets that fit the chosen monitor are offered; the game's Config › System › Window Size row offers the same ones.")
                            .font(.system(size: 12))
                            .foregroundColor(LauncherTheme.muted)
                    }
                }

                // Monitor Card
                LauncherCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader("MONITOR")
                        GoldDivider()

                        VStack(spacing: 8) {
                            ForEach(model.monitors) { m in
                                HStack {
                                    Image(systemName: "display")
                                        .foregroundColor(model.selectedMonitor == m ? LauncherTheme.moonPale : LauncherTheme.muted)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(m.label)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(LauncherTheme.text)
                                        Text(m.name)
                                            .font(.system(size: 11.5))
                                            .foregroundColor(LauncherTheme.muted)
                                    }
                                    Spacer()
                                    if model.selectedMonitor == m {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(LauncherTheme.moonBlue)
                                    }
                                }
                                .padding(10)
                                .background(model.selectedMonitor == m ? LauncherTheme.moonBlue.opacity(0.15) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    model.setMonitor(m)
                                }
                            }
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "cpu")
                                .font(.system(size: 13))
                                .foregroundColor(LauncherTheme.muted)
                            Text(model.graphicsName)
                                .font(.system(size: 12.5))
                                .foregroundColor(LauncherTheme.muted)
                        }
                        .padding(.top, 6)
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }
}
