import Foundation
import TsukiCore
extension TextBlock {
    public static let empty = TextBlock(
        n: 0, widthArg: 0, height: 0, flags: 0, spacing: 0, leading: 0, boxWidth: 0, sx: 1, sy: 1,
        nLines: 0, lastGlyphLine: 0, lineGlyphs: [], lineWidth: [], lineHeight: [], records: [],
        classes: [], wordLen: [], endCtr: 0, yField: 0, empty: true
    )
}


/// One message of the page: the text as the script gave it, its layout and the page variables it recorded.
public final class PageMessage {
    /// The copied argument (unexpanded, at most 0x300 bytes; grows with `_MSAD`).
    public var raw: [UInt8] = []

    /// The expanded text (with its markup).
    public var text: [UInt8] = []

    /// The laid-out block.
    public var block: TextBlock!

    /// The (flags, counter) pairs of the block's glyph records (the 0xCA070 reveal-done test).
    public var records: [(flags: Int, ctr: Int)] = []

    /// The end mode.
    public var end: MessageEnd = .click

    /// The RGB565 colour word the layout started with.
    public var colour: Int = 0

    /// The message was read before.
    public var read: Bool = false

    /// C846 as the message saw it: empty lines left before it (textbox.md 5.8).
    public var blank: Int = 0

    /// C835 / 24: the vertical text scale.
    public var scaleY: Double = 1.0

    /// The message counter F823 when the message started.
    public var index: Int = 0

    /// The window index F1105 (F1109 in English when positive) the message was laid out with.
    public var window: Int = 0

    /// Frames the message has been dimmed (-1: fully dimmed).
    public var dimTimer: Int = 0

    /// The dimming limit in frames: `(C870 + 128) * 1.2`.
    public var dimLimit: Float = 153.6

    /// The `@x` continue position the message was laid out with (`MessageWindow.continueX` of the message before it; 0 for the first of a page).
    public var savedX: Float = 0

    public init() {}
}

/// Which text-break mark the HUD draws (docs/formats/textbox.md 7.1).
public enum ClickIconKind: UInt8, Sendable {
    case none
    case line
    case page
    case bubble
}

/// The click-wait icon as the HUD drew it in the last frame (package K34).
public struct ClickIconDraw: Sendable {
    public let kind: ClickIconKind
    public let dispChild: Int
    public let frame: Int
    public let x: Double
    public let y: Double
    public let alpha: Double

    public init(kind: ClickIconKind, dispChild: Int, frame: Int, x: Double, y: Double, alpha: Double) {
        self.kind = kind
        self.dispChild = dispChild
        self.frame = frame
        self.x = x
        self.y = y
        self.alpha = alpha
    }
}

extension GameHost {
    static let maxMessageBytes = 0x300
    static let maxExpandedBytes = 0x2FC
    private static let fadeUnit: Float = 16.66666603088379

    /// Units per texel of the icon quads (float32 0.333 at VA 0x1A7094 / 0x1A7170): 1 px per texel in x, 1.0446 in y under list 0x1E.
    public static let clickIconScale: Float = 0.333
    public static let lineIconChild: Int = 4
    public static let pageIconChild: Int = 9
    public static let bubbleIconChild: Int = 53

    /// The player hid the message window (action 25); a new message shows it again.
    public var windowHidden: Bool { windowHiddenVal }

    func initMessages() {}

    func resetMessages() {
        page.removeAll()
        currentMsg = nil
        currentRaw.removeAll()
        for i in 0..<namePlateBytes.count {
            namePlateBytes[i] = 0
        }
        namePlateBlock = nil
        textFadeVal = 1.0
        windowQuick = false
        zmStartedVoice = false
        continueByte = false
        windowHiddenVal = false
        resetClickIcon()
    }

    /// The message currently being shown or waiting for a click, or nil.
    public var currentMessage: PageMessage? { currentMsg }

    /// The messages of the page, oldest first, the current one last.
    public var pageMessages: [PageMessage] { page }

    /// The text fade T (VA 0x86AA1C), 0..1.
    public var textFade: Float { textFadeVal }

    /// The text of the last message as plain bytes (the markup is kept), for traces.
    public var currentText: [UInt8] { currentMsg?.text ?? [] }

    // -- variable access helpers --------------------------------------------------------------------------------------------------

    /// Signed value of F word `n`.
    public func f(_ n: Int) -> Int {
        Int(Int16(bitPattern: vars.getF(n)))
    }

    func setF(_ n: Int, _ value: Int) {
        vars.setF(n, UInt16(truncatingIfNeeded: value))
    }

    /// Loads the F words the wait functions read into `wait`.
    func syncWaitFromVars() {
        wait.f799 = f(799)
        wait.f823 = f(823)
        wait.f988 = f(988)
        wait.f1103 = f(1103)
        wait.f1123 = f(1123)
    }

    // -- text -----------------------------------------------------------------------------------------------------------------------

    static func copyMessage(_ args: ByteSpan, start: Int) -> (raw: [UInt8], terminator: Character) {
        var raw: [UInt8] = []
        raw.reserveCapacity(64)
        var term: Character = ")"
        var i = start
        while i < args.count && raw.count < maxMessageBytes - 1 {
            let c = args[i]
            if c == UInt8(ascii: ")") {
                break
            }
            if c == UInt8(ascii: "@") && i + 1 < args.count && (args[i + 1] == UInt8(ascii: "n") || args[i + 1] == UInt8(ascii: "e")) {
                term = Character(UnicodeScalar(args[i + 1]))
                break
            }
            if c == UInt8(ascii: ";") && i + 1 >= args.count {
                break
            }
            raw.append(c)
            i += 1
        }
        return (raw, term)
    }

    func expandMessage(_ message: [UInt8]) -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity(message.count + 32)
        var i = 0
        while i < message.count && output.count < Self.maxExpandedBytes {
            let c = message[i]
            if c == 0 {
                break
            }
            if c == UInt8(ascii: "$") {
                var value: Int64 = 0
                for k in 1...6 {
                    let b = (i + k < message.count) ? Int64(message[i + k]) : 0
                    value = (value * 10) + b
                }
                value -= 0x30 * 111111
                i += 7
                if value >= 0 && value < Int64(data.textLineCount) {
                    let line = data.textLine(language, Int(value))
                    let room = max(Self.maxExpandedBytes - output.count, 0)
                    let take = min(room, line.count)
                    let slice = line.slice(0, take)
                    let nul = slice.firstIndex(of: 0) ?? slice.count
                    for idx in 0..<nul {
                        output.append(slice[idx])
                    }
                }
                continue
            }

            output.append(c)
            i += 1
        }
        return output
    }

    func windowIndex() -> Int {
        var w = f(1105)
        if language == .en && f(1109) > 0 {
            w = f(1109)
        }
        return w
    }

    var isPageMode: Bool { f(822) == 1 }

    func layoutText(_ text: [UInt8], read: Bool, savedX: Float = 0) -> (block: TextBlock, colour: Int) {
        let window = windowIndex()
        let f31 = f(31)
        let f32 = f(32)
        let bp = MessageWindow.mainBoxParams(language, window: window, read: read, readColorMode: Int(config.textColourMode), f31: f31, f32: f32)
        let block = (try? TextLayout.layout(text, language, fonts, bp.toLayoutParams(savedX: Double(savedX)))) ?? TextBlock.empty
        return (block, bp.color)
    }

    static func recordsOf(_ block: TextBlock) -> [(flags: Int, ctr: Int)] {
        block.records.map { (Int($0.flags), Int($0.ctr)) }
    }

    func revealDoneValue(_ block: Int) -> Int {
        if block != 4 || currentMsg == nil || currentMsg!.block.empty {
            return 1
        }
        return WaitModel.revealDone(currentMsg!.records, head: wait.head, tail: wait.tail) ? 1 : 0
    }

    func newMessageSlot() {
        wait.newPage = 0
        wait.flags = 0
        wait.head = 0
        wait.tail = 0
    }

    func cmdMessage(_ st: Statement) -> StepResult {
        commitLayerChange(st)
        windowHiddenVal = false
        push(.message, st)
        if wait.newPage != 0 {
            newMessageSlot()
        }

        if !(wait.textFadeStep > 0) {
            if textFadeVal < 1.0 || f(1103) != 0 {
                textFadeVal = 0
                wait.textFadeStep = 1.0 / 18.0
            } else {
                textFadeVal = 1.0
                wait.textFadeStep = 0
            }
        }

        setF(1103, 0)
        wait.f1103 = 0

        let (raw, term) = Self.copyMessage(st.args, start: ArgumentList.startIn(st))
        let text = expandMessage(raw)
        let read = markers.isRead
        if skipScene && (f(998) != 0 || (!read && config.fastForwardReadOnly != 0)) {
            endSceneSkip()
        }

        let f823 = f(823)
        if f823 <= 1 {
            wait.pageLatch = (read ? config.pageEndInstantSeen : config.pageEndInstantUnseen) == 1
        }

        let mode: MessageEnd
        switch term {
        case "n": mode = .continue
        case "e": mode = .noWait
        default: mode = wait.pageLatch && f(799) != 1 ? .noWait : .click
        }

        if f823 <= 1 || !isPageMode {
            page.removeAll()
        }

        let savedX = page.count > 0 ? MessageWindow.continueX(page.last!.block) : Float(0)
        let (block, colour) = layoutText(text, read: read, savedX: savedX)
        layoutNamePlate()
        if isPageMode {
            let k = min(max(f823, 0), 11)
            setF(799 + k, colour >> 8)
            setF(810 + k, colour & 0xFF)
            setF(824 + k, f(31))
            setF(835 + k, f(32))
        }

        let f32 = f(32)
        let msg = PageMessage()
        msg.raw = raw
        msg.text = text
        msg.block = block
        msg.records = Self.recordsOf(block)
        msg.end = mode
        msg.colour = colour
        msg.read = read
        msg.blank = f(846 + f823)
        msg.scaleY = f32 > 0 ? Double(f32) / 24.0 : 1.0
        msg.index = f823
        msg.window = windowIndex()
        msg.dimLimit = Float(f(870 + f823) + 128) * 1.2
        msg.savedX = savedX

        page.append(msg)
        currentMsg = msg
        currentRaw = raw

        wait.readSel = read ? 1 : 0
        wait.head = 0
        wait.tail = 0
        continueByte = false
        zmStartedVoice = sound.startVoiceAtMessage()
        wait.voiceState = sound.voiceState
        sink.onMessageShown()
        sink.setMessageText(text)
        if zmStartedVoice {
            let character = sound.pendingVoiceCharacter
            sink.onVoiceStarted(voiceId: sound.lastVoice, character: Int16(character), speakerRow: Int8(VoiceGroups.slotOf(character)))
        }

        sink.updateStaging()
        if zmStartedVoice && mode != .continue {
            wait.flags |= WaitBits.voice
        }

        wait.flags |= WaitBits.reveal
        if mode == .continue {
            continueByte = true
        }

        wait.bits |= (mode == .click ? WaitBits.click : 0) | WaitBits.message
        if wait.flags != 0 {
            wait.bits |= wait.flags
        }

        messageStarted?(st.script, st.offset, read)
        return StepResult.yield
    }

    func cmdMsad(_ st: Statement) -> StepResult {
        commitLayerChange(st)
        setF(1103, 0)
        wait.f1103 = 0
        let (add, term) = Self.copyMessage(st.args, start: ArgumentList.startIn(st))
        let cur: PageMessage
        if let existing = currentMsg {
            cur = existing
        } else {
            cur = PageMessage()
            cur.index = f(823)
            cur.window = windowIndex()
            page.append(cur)
            currentMsg = cur
        }

        let room = max(0, Self.maxMessageBytes - cur.raw.count)
        var raw = cur.raw
        raw.append(contentsOf: add.prefix(room))
        let text = expandMessage(raw)

        let mode: MessageEnd
        switch term {
        case "n": mode = .continue
        case "e": mode = .noWait
        default: mode = wait.pageLatch && f(799) != 1 ? .noWait : .click
        }

        var oldEnd: Float = 0
        if let old = cur.block, !old.records.isEmpty {
            var maxCtr: Int = 0
            let start = max(0, old.records.count - 8)
            for i in start..<old.records.count {
                maxCtr = max(maxCtr, Int(old.records[i].ctr))
            }
            oldEnd = Float(maxCtr + 1)
        }

        let (block, colour) = layoutText(text, read: cur.read, savedX: cur.savedX)
        cur.raw = raw
        cur.text = text
        cur.block = block
        cur.records = Self.recordsOf(block)
        cur.colour = colour
        cur.end = mode
        currentRaw = raw
        sink.setMessageText(text)
        sink.updateStaging()

        wait.head = oldEnd
        wait.tail = oldEnd
        continueByte = false
        var started = false
        if sound.pendingVoice >= 0 {
            started = sound.startVoiceAtMessage()
            wait.voiceState = sound.voiceState
        }

        if mode != .continue && (started || zmStartedVoice) {
            wait.flags |= WaitBits.voice
        }

        wait.flags |= WaitBits.reveal
        if mode == .continue {
            continueByte = true
        }

        wait.bits |= (mode == .click ? WaitBits.click : 0) | WaitBits.message
        if wait.flags != 0 {
            wait.bits |= wait.flags
        }

        return StepResult.yield
    }

    func cmdWnty(_ st: Statement) -> StepResult {
        setF(799, InlineReader.readInt16(st, 0) != 0 ? 1 : 0)
        return StepResult.continue
    }

    func cmdPgst(_ st: Statement) -> StepResult {
        setF(1122, InlineReader.readInt16(st, 0))
        return StepResult.continue
    }

    func cmdClo2() -> StepResult {
        newMessageSlot()
        page.removeAll()
        currentMsg = nil
        wait.windowTarget = 0
        wait.windowAlpha = 0
        setF(1103, 1)
        return StepResult.yield
    }

    func cmdClo3() -> StepResult {
        if wait.windowTarget != 0 {
            wait.windowTarget = 0
            windowQuick = true
            setF(1103, 1)
        }
        return StepResult.yield
    }

    func cmdClo4(_ st: Statement) -> StepResult {
        let a = StageArgs(st)
        let ms = a.has(0) ? a.expr(0) : 0
        if ms > 0 && mode.skipActive == 0 {
            if wait.textFadeStep > 0 {
                textFadeVal = 1.0
                wait.textFadeStep = -Self.fadeUnit / Float(ms)
            } else if textFadeVal == 1.0 {
                wait.textFadeStep = -Self.fadeUnit / Float(ms)
            } else {
                textFadeVal = 0
                wait.textFadeStep = 0
            }
        } else {
            textFadeVal = 0
            wait.textFadeStep = 0
        }
        return StepResult.yield
    }

    func cmdClo5(_ st: Statement) -> StepResult {
        let a = StageArgs(st)
        let ms = a.has(0) ? a.expr(0) : 0
        if ms > 0 && mode.skipActive == 0 && (wait.textFadeStep < 0 || textFadeVal == 0 || f(1103) == 1) {
            textFadeVal = 0
            wait.textFadeStep = Self.fadeUnit / Float(ms)
        } else {
            textFadeVal = 1.0
            wait.textFadeStep = 0
        }
        setF(1103, 0)
        wait.windowAlpha = 1.0
        wait.windowTarget = 1
        return StepResult.yield
    }

    func cmdWttm(_ st: Statement) -> StepResult {
        commitLayerChange(st)
        let ms = InlineReader.readInt32(st, 0)
        wait.timer = Int(Int16(truncatingIfNeeded: WaitModel.waitFrames(ms)))
        wait.timerNoClick = InlineReader.isPresent(st, 1) && InlineReader.readInt16(st, 1) != 0 ? 1 : 0
        waitStarted?("WTTM", ms)
        return StepResult.yield
    }

    func cmdWtsv(_ st: Statement) -> StepResult {
        let a = StageArgs(st)
        wait.timer = a.has(0) ? Int(Int16(truncatingIfNeeded: WaitModel.waitFrames(a.expr(0)))) : 6
        wait.timerNoClick = a.has(1) ? (a.expr(1) != 0 ? 1 : 0) : 1
        waitStarted?("WTSV", wait.timer)
        return StepResult.yield
    }

    func updateWindowFades(_ k: Int) {
        var a = wait.windowAlpha
        let kf = Float(k)
        if windowQuick && wait.windowTarget == 0 {
            if a > 0 {
                a = (kf * -0.2604166567325592) + a
                if a <= 0 {
                    a = 0
                    windowQuick = false
                }
            } else {
                windowQuick = false
            }
        } else {
            if wait.windowTarget != 0 && mode.logShown == 0 {
                if 1.0 > a {
                    a = (kf * 0.06) + a
                    if a > 1.0 {
                        a = 1.0
                    }
                }
            } else if a > 0 {
                a -= kf * 0.06
                if a < 0 {
                    a = 0
                }
            }
            windowQuick = false
        }

        wait.windowAlpha = a
        if wait.textFadeStep != 0 {
            var t = (wait.textFadeStep * kf) + textFadeVal
            if t < 0 {
                t = 0
                wait.textFadeStep = 0
            } else if t > 1.0 {
                t = 1.0
                wait.textFadeStep = 0
            }
            textFadeVal = t
        }

        if textFadeVal >= 1.0 && page.count > 1 {
            for j in 0..<(page.count - 1) {
                let m = page[j]
                if m.dimTimer >= 0 {
                    m.dimTimer += k
                    if Float(m.dimTimer) >= m.dimLimit || config.seenTextAnimations == 1 {
                        m.dimTimer = -1
                    }
                }
            }
        }
    }

    // MARK: - Name Plate

    public var namePlateText: [UInt8] {
        let n = namePlateBytes.firstIndex(of: 0) ?? namePlateBytes.count
        return Array(namePlateBytes.prefix(n))
    }

    public var namePlateShown: Bool { namePlateBlock != nil }

    public func setNamePlate(_ text: [UInt8]) {
        for i in 0..<namePlateBytes.count {
            namePlateBytes[i] = 0
        }
        let take = min(text.count, namePlateBytes.count - 1)
        for i in 0..<take {
            namePlateBytes[i] = text[i]
        }
        layoutNamePlate()
    }

    func layoutNamePlate() {
        let text = namePlateText
        if text.isEmpty {
            namePlateBlock = nil
            return
        }

        let window = windowIndex()
        let p = LayoutParams(
            width: 150,
            height: 20,
            spacing: 2,
            leading: 0,
            color: 0xF6FD,
            flags: window < 3 ? 0 : 1 << 20,
            sx: 0.5,
            sy: 0.5,
            block: 14,
            window: window
        )
        let block = (try? TextLayout.layout(text, language, fonts, p)) ?? TextBlock.empty
        namePlateBlock = block.empty ? nil : block
    }

    var activeNamePlate: TextBlock? {
        if let b = namePlateBlock, f(1103) == 0 && f(822) != 0 {
            return b
        }
        return nil
    }

    func namePlateShift() -> Double {
        if let b = activeNamePlate {
            return Double(MessageWindow.lastLineOffset(b) + 14)
        }
        return 0.0
    }

    func drawNamePlate(_ list: DisplayList, offX: Double, offY: Double) {
        guard let block = activeNamePlate, !page.isEmpty else { return }
        let pos = pageOrigins()
        addBlock(list, block: block, x: pos[pos.count - 1].x, y: pos[pos.count - 1].y - namePlateShift(), alpha: Double(wait.windowAlpha), head: BlockDraw.revealAll, tail: BlockDraw.revealAll, scaleY: Self.pageScaleY, offsetXPx: offX, offsetYPx: offY)
    }

    // MARK: - Click Icon

    public var clickIconAlpha: Float { iconAlphaVal }
    public var clickIconTick: Int { iconTickVal }
    public var clickIconAnchor: ClickAnchor { iconAnchorVal }
    public var clickIconStored: (x: Float, y: Float) { (iconStoredXVal, iconStoredYVal) }

    public static func clickIconCells(_ dispChild: Int) -> (cells: Int, cellW: Int, cellH: Int) {
        dispChild == bubbleIconChild ? (59, 43, 46) : (105, 39, 39)
    }

    public static func clickIconCell(_ dispChild: Int, row: Int) -> Int {
        dispChild == pageIconChild && row == 104 ? 103 : row
    }

    func resetClickIcon() {
        iconAlphaVal = 0
        iconAnchorVal = ClickAnchor(x: 0, y: 0, complete: false)
        lastClickIcon = ClickIconDraw(kind: .none, dispChild: 0, frame: 0, x: 0, y: 0, alpha: 0)
    }

    func updateClickIcon() {
        guard wait.windowAlpha > 0 else { return }

        var complete = false
        if let m = currentMsg, let blk = m.block, !blk.empty {
            iconAnchorVal = MessageWindow.clickIconAnchor(blk, head: Double(wait.head), tail: Double(wait.tail), lang: language)
            complete = iconAnchorVal.complete
        } else {
            iconAnchorVal = ClickAnchor(x: 0, y: 0, complete: false)
        }

        if complete && (wait.bits & WaitBits.click) != 0 {
            let a = iconAlphaVal + 0.1
            iconAlphaVal = a > 1.0 ? 1.0 : a
        } else {
            iconAlphaVal = 0
        }
    }

    func drawClickIcon(_ list: DisplayList, origin: (x: Double, y: Double), offX: Double, offY: Double) {
        let window = windowIndex()
        let baseX: Float = language == .en ? 30.0 : 87.0
        let subtract: Float = (window >= 3 || f(1111) >= 3) ? 87.0 : baseX
        let shift: Float = Float(origin.x) - subtract
        let xInt = f(822) == 1 ? Int(shift + Float(iconAnchorVal.x)) : iconAnchorVal.x
        let yInt = iconAnchorVal.y
        let msgY = Float(origin.y)
        iconStoredXVal = Float(xInt)
        iconStoredYVal = Float(yInt) + msgY
        lastClickIcon = ClickIconDraw(kind: .none, dispChild: 0, frame: 0, x: 0, y: 0, alpha: 0)
        if !(iconAlphaVal > 0) || !(xInt >= 0 || yInt > 0) {
            return
        }

        let fade = wait.windowAlpha
        let kind: ClickIconKind
        let child: Int
        let x: Float
        let y: Float
        let factor: Float
        if window > 2 {
            if autoMode { return }
            kind = .bubble
            child = Self.bubbleIconChild
            x = Float(xInt) - 2.0
            y = Float(yInt) + msgY + 2.0
            factor = 1.0
        } else if f(822) == 1 {
            x = ((language == .en ? -57.0 : 0.0) + Float(xInt)) - 3.7
            y = Float(yInt) + msgY + 4.3
            if autoMode { return }
            if f(799) == 1 {
                kind = .page
                child = Self.pageIconChild
                factor = 0.5
            } else {
                kind = .line
                child = Self.lineIconChild
                factor = 1.0
            }
        } else {
            if autoMode { return }
            kind = .page
            child = Self.pageIconChild
            x = Float(xInt) + 115.0
            y = Float(yInt) + msgY + 2.0
            factor = 0.5
        }

        let (cells, cellW, cellH) = Self.clickIconCells(child)
        iconTickVal = (iconTickVal + 1) % (2 * cells)
        let cell = Self.clickIconCell(child, row: iconTickVal / 2)
        let alpha = iconAlphaVal * fade * factor
        let listAlpha = Double(fade) * min(max(2.0 * (Double(textFadeVal) - 0.5), 0.0), 1.0)
        let (sw, sh) = sheetSize(child)
        let cx = cell * cellW
        let x0 = (Double(x) * Self.textScale) + offX
        let y0 = (Double(y) * Self.pageScaleY) + offY
        let w = Double(cellW) * Double(Self.clickIconScale) * Self.textScale
        let h = Double(cellH) * Double(Self.clickIconScale) * Self.pageScaleY
        addQuad(
            list: list,
            tex: TextureRef.uiTile(set: UiSet.dispParts.rawValue, language: Int(language.rawValue), child: child, tile: Self.wholeSheet),
            x0: x0,
            y0: y0,
            x1: x0 + w,
            y1: y0 + h,
            u0: Float(cx) / Float(sw),
            v0: 0,
            u1: Float(cx + cellW) / Float(sw),
            v1: Float(cellH) / Float(sh),
            rgba: pack(255, 255, 255, alpha: Double(alpha) * listAlpha)
        )
        lastClickIcon = ClickIconDraw(kind: kind, dispChild: child, frame: cell, x: Double(x), y: Double(y), alpha: Double(alpha))
    }
}
