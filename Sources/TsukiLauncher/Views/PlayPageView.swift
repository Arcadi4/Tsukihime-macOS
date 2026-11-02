import SwiftUI
import TsukiEngine

/// The main Play page.
public struct PlayPageView: View {
    @ObservedObject var model: LauncherModel

    public init(model: LauncherModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HeroView(model: model)

                HStack(alignment: .top, spacing: 18) {
                    // Ready Check Card
                    LauncherCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                SectionHeader("READY CHECK")
                                Spacer()
                                Text(model.readySummary)
                                    .font(.system(size: 12))
                                    .foregroundColor(LauncherTheme.muted)
                            }
                            GoldDivider()

                            VStack(spacing: 12) {
                                ForEach(model.readyRows) { row in
                                    ReadyRowView(row: row) { fixPage in
                                        model.page = fixPage
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // Quick Settings Card
                    LauncherCard {
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeader("QUICK SETTINGS")
                            GoldDivider()

                            // Language
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Game language")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundColor(LauncherTheme.text)

                                Picker("Game Language", selection: Binding(
                                    get: { model.languageIndex },
                                    set: { model.setLanguage($0) }
                                )) {
                                    Text("日本語").tag(0)
                                    Text("English").tag(1)
                                    Text("简体中文").tag(2)
                                    Text("繁體中文").tag(3)
                                }
                                .pickerStyle(.segmented)
                            }

                            // Fullscreen
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Fullscreen")
                                        .font(.system(size: 13.5, weight: .semibold))
                                        .foregroundColor(LauncherTheme.text)
                                    Text("Borderless, on the monitor you pick.")
                                        .font(.system(size: 12))
                                        .foregroundColor(LauncherTheme.muted)
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { model.fullscreen },
                                    set: { model.setFullscreen($0) }
                                ))
                                .toggleStyle(.switch)
                                .labelsHidden()
                            }
                            .padding(.top, 4)

                            // Button Prompts
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Button prompts")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundColor(LauncherTheme.text)

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
                            }
                            .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 24)
        }
    }
}

/// A row inside the Ready Check card.
struct ReadyRowView: View {
    let row: ReadyRow
    let onFix: (LauncherPage) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // State badge
            ZStack {
                Circle()
                    .fill(row.state == .ok ? LauncherTheme.success.opacity(0.15) : LauncherTheme.warning.opacity(0.15))
                    .frame(width: 26, height: 26)
                    .overlay(
                        Circle().stroke(row.state == .ok ? LauncherTheme.success.opacity(0.4) : LauncherTheme.warning.opacity(0.4), lineWidth: 1)
                    )

                Image(systemName: row.state == .ok ? "checkmark" : "exclamationmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(row.state == .ok ? LauncherTheme.success : LauncherTheme.warning)
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(LauncherTheme.text)
                Text(row.detail)
                    .font(.system(size: 12))
                    .foregroundColor(LauncherTheme.muted)
                    .lineLimit(2)
            }

            Spacer()

            if let fix = row.fix {
                Button("Fix") {
                    onFix(fix)
                }
                .buttonStyle(.link)
                .foregroundColor(LauncherTheme.moonPale)
                .font(.system(size: 12, weight: .medium))
                .padding(.top, 2)
            }
        }
    }
}
