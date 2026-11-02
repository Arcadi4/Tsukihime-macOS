import SwiftUI

/// The Saves page: backups, restore, and PS4 image import.
public struct SavesPageView: View {
    @ObservedObject var model: LauncherModel
    @State private var showingFileImporter = false

    public init(model: LauncherModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeaderView(
                    overline: "SAVES",
                    title: "Keep your progress safe",
                    description: "All 140 slots, the system data and the config are in one file, save.dat. Back it up before you try anything new, and restore it whenever you like."
                )

                // Save Data Status Card
                LauncherCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader("SAVE DATA")
                        GoldDivider()

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.saveText)
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundColor(LauncherTheme.text)
                                Text(model.dataDirectory)
                                    .font(.system(size: 12))
                                    .foregroundColor(LauncherTheme.muted)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Button("Open folder") {
                                model.openSavesFolder()
                            }
                            .buttonStyle(.bordered)

                            Button("Back up now") {
                                model.backupNow()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(LauncherTheme.moonBlue)
                        }
                    }
                }

                // Backups List Card
                LauncherCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            SectionHeader("BACKUPS")
                            Spacer()
                            Button("Open backups folder") {
                                model.openBackupsFolder()
                            }
                            .buttonStyle(.link)
                            .foregroundColor(LauncherTheme.moonPale)
                        }
                        GoldDivider()

                        if model.noBackups {
                            Text("No backups yet. Press 'Back up now' to make the first one.")
                                .font(.system(size: 12.5))
                                .foregroundColor(LauncherTheme.muted)
                                .padding(.vertical, 8)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(model.backups) { backup in
                                    HStack {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .font(.system(size: 16))
                                            .foregroundColor(LauncherTheme.moonPale)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(backup.name)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundColor(LauncherTheme.text)
                                            Text("\(backup.save.describe()) · \(GameFolderCheck.formatSize(backup.bytes))")
                                                .font(.system(size: 11.5))
                                                .foregroundColor(LauncherTheme.muted)
                                        }

                                        Spacer()

                                        Button("Restore") {
                                            model.askRestore(backup)
                                        }
                                        .buttonStyle(.bordered)
                                        .font(.system(size: 12))
                                    }
                                    .padding(.vertical, 6)
                                    Divider().background(LauncherTheme.divider)
                                }
                            }
                        }
                    }
                }

                // Import PS4 Save Card
                LauncherCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader("IMPORT A PS4 SAVE")
                        GoldDivider()

                        Text("Bring your progress over from a PS4 or from shadPS4: the 4 MiB save image (savedata000). The file is only read, never changed. It replaces save.dat after your current save has been backed up.")
                            .font(.system(size: 12.5))
                            .foregroundColor(LauncherTheme.muted)
                            .lineSpacing(2)

                        HStack {
                            if let shad = model.shadImage {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Found under shadPS4")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(LauncherTheme.text)
                                    Text(shad)
                                        .font(.system(size: 11.5))
                                        .foregroundColor(LauncherTheme.muted)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Button("Import it") {
                                    model.importFoundShadImage()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(LauncherTheme.moonBlue)
                            } else {
                                Spacer()
                            }

                            Button("Choose a file…") {
                                showingFileImporter = true
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.top, 6)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.data, .item],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                model.importPs4File(url: url)
            }
        }
    }
}
