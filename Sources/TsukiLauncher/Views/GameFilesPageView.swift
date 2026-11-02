import SwiftUI

/// The Game Files page: folder selection, verification facts, and problem details.
public struct GameFilesPageView: View {
    @ObservedObject var model: LauncherModel

    public init(model: LauncherModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeaderView(
                    overline: "GAME FILES",
                    title: "Your copy of the game",
                    description: "The port reads the PS4 game you own, the extracted CUSA47999 folder. The launcher only looks inside it; nothing in that folder is ever changed."
                )

                // Folder Selection Card
                LauncherCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader("GAME FOLDER")
                        GoldDivider()

                        HStack(spacing: 10) {
                            TextField("Path of the CUSA47999 folder", text: $model.folderText)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    model.applyFolderText()
                                }

                            Button("Browse…") {
                                model.browseFolder()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(LauncherTheme.moonBlue)

                            Button("Open") {
                                model.openGameFolder()
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.folder.state == .notSet || model.folder.state == .missing)
                        }

                        if !model.folderMessage.isEmpty {
                            Text(model.folderMessage)
                                .font(.system(size: 12))
                                .foregroundColor(LauncherTheme.warning)
                        }

                        Text("Choose the folder that holds eboot.bin and image/, or the folder above it. A base game with its update in a second folder beside it (CUSA47999 and CUSA47999-patch, or CUSA47999-UPDATE) is read as one game: the update's files take precedence. A .pkg must be extracted first. Press Return in the box to check a typed path.")
                            .font(.system(size: 12))
                            .foregroundColor(LauncherTheme.muted)
                            .lineSpacing(3)
                    }
                }

                // Verification Facts Card
                LauncherCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            SectionHeader("VERIFICATION")
                            Spacer()
                            Button("Check again") {
                                model.refresh()
                            }
                            .buttonStyle(.link)
                            .foregroundColor(LauncherTheme.moonPale)
                        }
                        GoldDivider()

                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                            GridRow {
                                Text("Status")
                                    .font(.system(size: 13))
                                    .foregroundColor(LauncherTheme.muted)
                                    .frame(width: 140, alignment: .leading)
                                Text(model.statusText)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(model.folder.isReady ? LauncherTheme.text : LauncherTheme.warning)
                            }
                            GridRow {
                                Text("Title and version")
                                    .font(.system(size: 13))
                                    .foregroundColor(LauncherTheme.muted)
                                Text(model.titleText)
                                    .font(.system(size: 13))
                                    .foregroundColor(LauncherTheme.text)
                            }
                            GridRow {
                                Text("Build")
                                    .font(.system(size: 13))
                                    .foregroundColor(LauncherTheme.muted)
                                Text(model.buildDetail)
                                    .font(.system(size: 13))
                                    .foregroundColor(LauncherTheme.text)
                            }
                            GridRow {
                                Text("Languages")
                                    .font(.system(size: 13))
                                    .foregroundColor(LauncherTheme.muted)
                                Text(model.languagesDetail)
                                    .font(.system(size: 13))
                                    .foregroundColor(LauncherTheme.text)
                            }
                            GridRow {
                                Text("Size on disk")
                                    .font(.system(size: 13))
                                    .foregroundColor(LauncherTheme.muted)
                                Text(model.folderSize)
                                    .font(.system(size: 13))
                                    .foregroundColor(LauncherTheme.text)
                            }
                            GridRow {
                                Text("Build checks")
                                    .font(.system(size: 13))
                                    .foregroundColor(LauncherTheme.muted)
                                Text(model.checksText)
                                    .font(.system(size: 13))
                                    .foregroundColor(LauncherTheme.text)
                            }
                            GridRow {
                                Text("Contents")
                                    .font(.system(size: 13))
                                    .foregroundColor(LauncherTheme.muted)
                                Text(model.contentsText)
                                    .font(.system(size: 13))
                                    .foregroundColor(LauncherTheme.text)
                            }
                        }

                        if !model.folder.problemList.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(model.folder.problemList, id: \.self) { prob in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(LauncherTheme.warning)
                                            .font(.system(size: 12))
                                            .padding(.top, 2)
                                        Text(prob)
                                            .font(.system(size: 12))
                                            .foregroundColor(Color(red: 0xE8 / 255.0, green: 0xD9 / 255.0, blue: 0xA6 / 255.0))
                                    }
                                }
                            }
                            .padding(.top, 10)
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }
}
