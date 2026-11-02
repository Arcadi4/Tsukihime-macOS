import Foundation
import TsukiEngine

/// A string the port shows that the PS4 did not have.
public enum PortString: Int, CaseIterable, Sendable {
    /// The window and message-box title of the game program: "Tsukihime".
    case productName = 0
    /// The first run has no game folder: what the next dialog asks for ({0} is the folder name CUSA47999).
    case folderPrompt
    /// The caption of the folder dialog.
    case folderDialogTitle
    /// The chosen folder holds no eboot.bin.
    case folderNotTheGame
    /// The remembered folder is gone ({0} the folder).
    case folderGone
    /// The remembered folder lacks a file ({0} the file, {1} the folder).
    case folderIncomplete
    /// The remembered folder cannot be opened ({0} the folder, {1} the system's words).
    case folderUnreadable
    /// The second line under a folder error: choose the folder again.
    case chooseFolderAgain
    /// Another game runs on the same profile.
    case alreadyRunning
    /// The save file could not be written ({0} the path, {1} the system's words).
    case saveFailed
    /// The save file was damaged and the backup was used ({0} the backup's name, {1} where the damaged file went).
    case saveDamagedBackupUsed
    /// The save file was damaged and a new profile started ({0} the error, {1} where the damaged file went).
    case saveDamagedNewProfile
    /// The FFmpeg DLLs are missing ({0} the list).
    case ffmpegMissing
    /// The graphics driver gave no OpenGL 3.3 context.
    case noOpenGl
    /// The window could not be created.
    case noWindow
    /// The log file could not be opened ({0} the path, {1} the system's words).
    case logNotOpened
    /// "Details: {0}" under an error, naming crash.log.
    case details
    /// Dialog Yes.
    case dialogYes
    /// Dialog No.
    case dialogNo
    /// Screenshot saved.
    case screenshotSaved
    /// Screenshot failed.
    case screenshotFailed
    /// Text copied.
    case textCopied
    /// Text WebSocket listening.
    case textWebSocketListening
    /// Text WebSocket failed.
    case textWebSocketFailed
    /// Folder is pkg.
    case folderIsPkg
    /// Folder is update only.
    case folderIsUpdateOnly
    /// Folder holds several.
    case folderHoldsSeveral
    /// Folder has no game inside.
    case folderNoGameInside
    /// Build unsupported.
    case buildUnsupported
    /// Build other version.
    case buildOtherVersion
    /// Shared library FFmpeg missing.
    case sharedLibraryFfmpegMissing

    public static let ProductName = PortString.productName
    public static let DialogYes = PortString.dialogYes
    public static let DialogNo = PortString.dialogNo
}

/// The port's own strings in ja, en, zc and zt.
public enum PortText {
    /// Every string, in the order of `PortString`; each row is ja, en, zc, zt.
    private static let table: [[String]] = [
        // ProductName
        ["Tsukihime", "Tsukihime", "Tsukihime", "Tsukihime"],
        // FolderPrompt
        [
            "Tsukihime を遊ぶには、お手持ちの PS4 版のゲームデータが必要です。\n\n次のウィンドウで、展開した {0} フォルダ（eboot.bin と image\\ が入っているフォルダ）を選んでください。フォルダの中身は読み込むだけで、変更されることはありません。",
            "Tsukihime needs your own copy of the PS4 game.\n\nIn the next window, choose the extracted {0} folder (the one that holds eboot.bin and image\\). The folder is only read; nothing in it is ever changed.",
            "运行 Tsukihime 需要您自己的 PS4 版游戏数据。\n\n请在下一个窗口中选择解压后的 {0} 文件夹（其中包含 eboot.bin 和 image\\）。该文件夹只会被读取，不会被修改。",
            "執行 Tsukihime 需要您自己的 PS4 版遊戲資料。\n\n請在下一個視窗中選擇解壓後的 {0} 資料夾（其中包含 eboot.bin 和 image\\）。該資料夾只會被讀取，不會被修改。",
        ],
        // FolderDialogTitle
        ["Tsukihime: CUSA47999 フォルダを選んでください", "Tsukihime: choose the CUSA47999 folder", "Tsukihime: 请选择 CUSA47999 文件夹", "Tsukihime: 請選擇 CUSA47999 資料夾"],
        // FolderNotTheGame
        [
            "そのフォルダには eboot.bin がありません。ゲームの CUSA47999 フォルダを選んでください。",
            "That folder does not contain eboot.bin. Choose the CUSA47999 folder of the game.",
            "该文件夹中没有 eboot.bin。请选择游戏的 CUSA47999 文件夹。",
            "該資料夾中沒有 eboot.bin。請選擇遊戲的 CUSA47999 資料夾。",
        ],
        // FolderGone
        [
            "ゲームフォルダ {0} が見つかりません。",
            "The game folder {0} no longer exists.",
            "找不到游戏文件夹 {0}。",
            "找不到遊戲資料夾 {0}。",
        ],
        // FolderIncomplete
        [
            "ゲームフォルダが不完全です: {1} に {0} がありません。",
            "The game folder is incomplete: {0} is missing from {1}.",
            "游戏文件夹不完整: {1} 中缺少 {0}。",
            "遊戲資料夾不完整: {1} 中缺少 {0}。",
        ],
        // FolderUnreadable
        [
            "ゲームフォルダ {0} を開けませんでした: {1}",
            "The game folder {0} could not be opened: {1}",
            "无法打开游戏文件夹 {0}: {1}",
            "無法開啟遊戲資料夾 {0}: {1}",
        ],
        // ChooseFolderAgain
        [
            "ランチャーで CUSA47999 フォルダをもう一度選んでください。",
            "Choose the CUSA47999 folder again in the launcher.",
            "请在启动器中重新选择 CUSA47999 文件夹。",
            "請在啟動器中重新選擇 CUSA47999 資料夾。",
        ],
        // AlreadyRunning
        ["Tsukihime はすでに起動しています。", "Tsukihime is already running.", "Tsukihime 已经在运行。", "Tsukihime 已經在執行。"],
        // SaveFailed
        [
            "セーブファイルを書き込めませんでした:\n{0}\n\n{1}\n\n今回のセーブはゲームを閉じるまでしか残りません。フォルダの空き容量や権限を確認するか、ランチャーで別のフォルダを選んでください。",
            "The save file could not be written:\n{0}\n\n{1}\n\nSaves made now are kept until the game closes only. Free the folder or choose another one in the launcher.",
            "无法写入存档文件:\n{0}\n\n{1}\n\n现在的存档只会保留到游戏关闭为止。请检查该文件夹的空间和权限，或在启动器中选择另一个文件夹。",
            "無法寫入存檔檔案:\n{0}\n\n{1}\n\n現在的存檔只會保留到遊戲關閉為止。請檢查該資料夾的空間和權限，或在啟動器中選擇另一個資料夾。",
        ],
        // SaveDamagedBackupUsed
        [
            "セーブファイルが壊れていたため、ひとつ前の世代 ({0}) を使いました。その後に作ったセーブは失われているかもしれません。\n\n壊れたファイルは次の場所に移しました:\n{1}",
            "Your save file was damaged, so the previous generation ({0}) was used instead; the saves made after it may be gone.\n\nThe damaged file was moved to\n{1}",
            "存档文件已损坏，因此改用了上一代存档 ({0})；在那之后的存档可能已经丢失。\n\n损坏的文件已移至\n{1}",
            "存檔檔案已損壞，因此改用了上一代存檔 ({0})；在那之後的存檔可能已經遺失。\n\n損壞的檔案已移至\n{1}",
        ],
        // SaveDamagedNewProfile
        [
            "セーブファイルが壊れていました ({0})。\n\nファイルは次の場所に移し、\n{1}\n新しいプロファイルを始めました。ランチャーの「Saves」ページからバックアップを復元できます。",
            "Your save file was damaged ({0}).\n\nIt was moved to\n{1}\nand a new profile was started. The launcher's Saves page can restore a backup.",
            "存档文件已损坏 ({0})。\n\n文件已移至\n{1}\n并已开始新的配置文件。启动器的 Saves 页面可以恢复备份。",
            "存檔檔案已損壞 ({0})。\n\n檔案已移至\n{1}\n並已開始新的設定檔。啟動器的 Saves 頁面可以還原備份。",
        ],
        // FfmpegMissing
        [
            "Tsukihime.exe と同じフォルダに FFmpeg のライブラリがありません ({0})。ポートを入れ直すか、ファイルを戻してください。",
            "The FFmpeg libraries are missing next to Tsukihime.exe ({0}). Reinstall the port or copy them back.",
            "Tsukihime.exe 旁边缺少 FFmpeg 库 ({0})。请重新安装移植版或把文件复制回来。",
            "Tsukihime.exe 旁邊缺少 FFmpeg 程式庫 ({0})。請重新安裝移植版或把檔案複製回來。",
        ],
        // NoOpenGl
        [
            "グラフィックドライバーが OpenGL 3.3 に対応していません。ドライバーを更新するか、専用 GPU でゲームを起動してください。",
            "Your graphics driver does not provide OpenGL 3.3. Update the driver or run the game on the dedicated GPU.",
            "您的显卡驱动不支持 OpenGL 3.3。请更新驱动，或在独立显卡上运行游戏。",
            "您的顯示卡驅動程式不支援 OpenGL 3.3。請更新驅動程式，或在獨立顯示卡上執行遊戲。",
        ],
        // NoWindow
        [
            "ゲームウィンドウを作成できませんでした。グラフィックドライバーを更新するか、専用 GPU でゲームを起動してください。",
            "The game window could not be created. Update your graphics driver or run the game on the dedicated GPU.",
            "无法创建游戏窗口。请更新显卡驱动，或在独立显卡上运行游戏。",
            "無法建立遊戲視窗。請更新顯示卡驅動程式，或在獨立顯示卡上執行遊戲。",
        ],
        // LogNotOpened
        [
            "ログファイル {0} を開けませんでした: {1}\n\nログなしでゲームを続けます。",
            "The log file {0} could not be opened: {1}\n\nThe game goes on without a log file.",
            "无法打开日志文件 {0}: {1}\n\n游戏将在没有日志文件的情况下继续。",
            "無法開啟記錄檔 {0}: {1}\n\n遊戲將在沒有記錄檔的情況下繼續。",
        ],
        // Details
        ["詳細: {0}", "Details: {0}", "详情: {0}", "詳情: {0}"],
        // DialogYes
        ["はい", "Yes", "是", "是"],
        // DialogNo
        ["いいえ", "No", "否", "否"],
        // ScreenshotSaved
        ["スクリーンショットを保存しました", "Screenshot saved", "已保存截图", "已儲存螢幕截圖"],
        // ScreenshotFailed
        ["スクリーンショットを保存できませんでした", "The screenshot could not be saved", "无法保存截图", "無法儲存螢幕截圖"],
        // TextCopied
        ["テキストをクリップボードにコピーしました", "Text copied to the clipboard", "已将文本复制到剪贴板", "已將文字複製到剪貼簿"],
        // TextWebSocketListening
        ["テキスト WebSocket: ws://127.0.0.1:{0}", "Text WebSocket: ws://127.0.0.1:{0}", "文本 WebSocket: ws://127.0.0.1:{0}", "文字 WebSocket: ws://127.0.0.1:{0}"],
        // TextWebSocketFailed
        [
            "テキスト WebSocket をポート {0} で開始できませんでした: {1}",
            "The text WebSocket could not start on port {0}: {1}",
            "无法在端口 {0} 启动文本 WebSocket: {1}",
            "無法在連接埠 {0} 啟動文字 WebSocket: {1}",
        ],
        // FolderIsPkg
        [
            "{0} は PS4 のパッケージファイル (.pkg) です。先に shadPS4 や PKG 展開ツールで展開し、展開された {1} フォルダ（eboot.bin と image\\ が入っているフォルダ）を選んでください。",
            "{0} is a PS4 package file (.pkg). Extract it first (shadPS4, or a PKG extractor), then choose the extracted {1} folder (the one that holds eboot.bin and image\\).",
            "{0} 是 PS4 的安装包文件 (.pkg)。请先用 shadPS4 或 PKG 解包工具解压，然后选择解压后的 {1} 文件夹（其中包含 eboot.bin 和 image\\）。",
            "{0} 是 PS4 的安裝包檔案 (.pkg)。請先用 shadPS4 或 PKG 解包工具解壓，然後選擇解壓後的 {1} 資料夾（其中包含 eboot.bin 和 image\\）。",
        ],
        // FolderIsUpdateOnly
        [
            "{0} にはアップデート（パッチ）しか入っていません。ゲーム本体のフォルダ（image\\allpac0.mrg などのアーカイブが入っているフォルダ）を、そのフォルダの隣に置いてください。",
            "{0} holds only the game's update (patch). The base game folder (the one with image\\allpac0.mrg and the other archives) must be beside it.",
            "{0} 中只有游戏的更新（补丁）。游戏本体的文件夹（含 image\\allpac0.mrg 等档案的文件夹）必须放在它旁边。",
            "{0} 中只有遊戲的更新（修補程式）。遊戲本體的資料夾（含 image\\allpac0.mrg 等檔案的資料夾）必須放在它旁邊。",
        ],
        // FolderHoldsSeveral
        [
            "{0} には複数のゲームフォルダがあります ({1})。そのうちのひとつを選んでください。",
            "{0} holds several game folders ({1}). Choose one of them.",
            "{0} 中有多个游戏文件夹 ({1})。请选择其中一个。",
            "{0} 中有多個遊戲資料夾 ({1})。請選擇其中一個。",
        ],
        // FolderNoGameInside
        [
            "{0} にはゲームがありません: eboot.bin と image\\ を含むフォルダが、その中にも見つかりませんでした。",
            "{0} holds no game: no folder with eboot.bin and image\\ was found in it, not even one or two levels down.",
            "{0} 中没有游戏: 其中（包括下一两级子文件夹）没有同时包含 eboot.bin 和 image\\ 的文件夹。",
            "{0} 中沒有遊戲: 其中（包括下一兩級子資料夾）沒有同時包含 eboot.bin 和 image\\ 的資料夾。",
        ],
        // BuildUnsupported
        [
            "このゲームデータ ({0}、eboot.bin SHA-256 {1}...) は、このポートが知らないビルドです。ゲーム本体の中にあるべきテーブルのうち、次のものが見つかりませんでした: {2}。\n\nログファイルを添えて報告してください。",
            "This copy of the game ({0}, eboot.bin SHA-256 {1}...) is a build the port does not know, and these tables could not be found in its program: {2}.\n\nPlease report it together with the log file.",
            "这份游戏数据 ({0}，eboot.bin SHA-256 {1}...) 是本移植版未知的版本，其程序中有下列表未能找到: {2}。\n\n请连同日志文件一起报告。",
            "這份遊戲資料 ({0}，eboot.bin SHA-256 {1}...) 是本移植版未知的版本，其程式中有下列表未能找到: {2}。\n\n請連同記錄檔一起回報。",
        ],
        // BuildOtherVersion
        [
            "検証済みのビルドではありません: {0}。テーブルは内容から探し出されました。",
            "Not the verified build: {0}. The tables were located by their content.",
            "不是经过验证的版本: {0}。表已按内容定位。",
            "不是經過驗證的版本: {0}。表已按內容定位。",
        ],
        // SharedLibraryFfmpegMissing
        [
            "FFmpeg 9 の共有ライブラリがありません ({0})。FFmpeg 9 の共有ライブラリをインストールするか、Tsukihime と同じフォルダに配置してください。",
            "FFmpeg 9 shared libraries are missing ({0}). Install the FFmpeg 9 shared libraries or place them next to Tsukihime.",
            "缺少 FFmpeg 9 共享库 ({0})。请安装 FFmpeg 9 共享库，或将其放在 Tsukihime 旁边。",
            "缺少 FFmpeg 9 共用程式庫 ({0})。請安裝 FFmpeg 9 共用程式庫，或將其放在 Tsukihime 旁邊。",
        ],
    ]

    /// The selectable languages, in the order of the table's columns.
    public static let languages: [Language] = [.ja, .en, .zc, .zt]
    public static let Languages: [Language] = languages

    /// The string in `language` (English for Korean and any value outside the four).
    public static func get(_ id: PortString, _ language: Language) -> String {
        let row = id.rawValue
        guard row >= 0 && row < table.count else {
            return ""
        }
        return table[row][column(language)]
    }
    public static func Get(_ id: PortString, _ language: Language) -> String {
        get(id, language)
    }

    /// The string with its placeholders filled (invariant culture).
    public static func format(_ id: PortString, _ language: Language, _ args: Any...) -> String {
        var str = get(id, language)
        for (i, arg) in args.enumerated() {
            str = str.replacingOccurrences(of: "{\(i)}", with: String(describing: arg))
        }
        return str
    }
    public static func Format(_ id: PortString, _ language: Language, _ args: Any...) -> String {
        var str = get(id, language)
        for (i, arg) in args.enumerated() {
            str = str.replacingOccurrences(of: "{\(i)}", with: String(describing: arg))
        }
        return str
    }

    public static func fromCultureName(_ cultureName: String?) -> Language {
        guard let name = cultureName, !name.isEmpty else {
            return .en
        }
        let lower = name.lowercased()
        if lower.hasPrefix("ja") {
            return .ja
        }
        if lower.hasPrefix("zh") {
            if lower.contains("hant") || lower.hasSuffix("-tw") || lower.hasSuffix("-hk") || lower.hasSuffix("-mo") {
                return .zt
            }
            return .zc
        }
        return .en
    }
    public static func FromCultureName(_ cultureName: String?) -> Language {
        fromCultureName(cultureName)
    }

    private static func column(_ language: Language) -> Int {
        switch language {
        case .ja: return 0
        case .zc: return 2
        case .zt: return 3
        default: return 1
        }
    }
}
