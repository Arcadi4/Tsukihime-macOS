import Foundation
import TsukiCore

// The script commands of the sound library and the deferred-SE queue (docs/formats/sound_runtime.md 3 and 5). Each handler is a
// line-by-line port of the Python model, which the research checked against the engine's handlers (VA 0x87250, 0x87940, 0x87660,
// 0x893F0, 0x89E40, 0x89B50, 0x996E1, 0x88160, 0x87D50, 0x87AF0) on the audio statements of every script.
extension SoundModel {
    /// True for the command names this model runs (`MPLY MVOL MFAD MSTP SEPL SEFI SEFD SEVL SESP VPLY VPL2 VCLR`).
    public static func handles(_ name: CommandName) -> Bool {
        isSoundName(name.description)
    }

    private static func isSoundName(_ n: String) -> Bool {
        switch n {
        case "MPLY", "MVOL", "MFAD", "MSTP", "SEPL", "SEFI", "SEFD", "SEVL", "SESP", "VPLY", "VPL2", "VCLR":
            return true
        default:
            return false
        }
    }

    /// Runs a sound statement of the script VM (`Statement.args` starts at the separator after the four name bytes).
    /// Returns the handler's wait value: 0 to go on, 1 to wait (`_MFAD`, see `wait16`).
    @discardableResult
    public func execute(_ statement: Statement) throws -> Int {
        try execute(statement.name.description, statement.args, 0)
    }

    /// Runs a statement given as text, for example `_SEPL(7,1,MOON_SE03028,,`001:8000,,`017:30);` (latin-1 bytes; the name is
    /// the four characters after the first underscore).
    @discardableResult
    public func run(_ statement: String) throws -> Int {
        let b = Array(statement.utf8)
        guard let us = b.firstIndex(of: UInt8(ascii: "_")), us + 5 <= b.count else {
            throw TsukiError.format("not a statement: \(statement)")
        }

        let start = statement.index(statement.startIndex, offsetBy: us + 1)
        let end = statement.index(start, offsetBy: 4)
        let name = String(statement[start..<end])
        return try execute(name, ByteSpan(b), us + 5)
    }

    private func execute(_ name: String, _ b: ByteSpan, _ sep: Int) throws -> Int {
        switch name {
        case "MPLY": return cmdMply(b, sep)
        case "MVOL": return cmdMvol(b, sep)
        case "MFAD": return cmdMfad(b, sep)
        case "MSTP": return cmdMstp()
        case "SEPL", "SEFI": return cmdSepl(b, sep)
        case "SEFD": return cmdSefd(b, sep)
        case "SEVL": return cmdSevl(b, sep)
        case "SESP": return cmdSesp(b, sep)
        case "VPLY": return cmdVply(b, sep, immediate: false)
        case "VPL2": return cmdVply(b, sep, immediate: true)
        case "VCLR": return cmdVclr()
        default: throw TsukiError.unsupported("unknown sound command: \(name)")
        }
    }

    var silent: Bool { fastForward || scan }

    /// `History_Push` (VA 0x7AF90), called by every sound handler: besides recording the SE state it copies the history ring
    /// record's bytes +0x36BC.. back into the script character array 0x1654330 (VA 0x7B3BA..0x7B3C3). No code ever writes those record
    /// bytes, so with a zeroed ring the array is cleared (sound_runtime.md 11.2).
    func historyPush() {
        _scrSeChar = [Int](repeating: 0, count: SoundModel.seChannels)
    }

    // -- BGM commands ----------------------------------------------------------------------------

    /// VA 0x87250: `_MPLY(track, , `001 fade-in ms, `011 fade-out ms, `017 volume, `049 loop, `069 start sample)`.
    private func cmdMply(_ b: ByteSpan, _ sep: Int) -> Int {
        historyPush()
        let t = SoundTags.parse(b, sep)
        let vol: Int
        let loop: Int
        let fade: Int
        let t011: Int
        let start: Int
        if t.count <= 0 {
            vol = 100
            loop = 1
            fade = 0
            t011 = 0
            start = 0
        } else {
            let jv = t.find(SoundTags.volume)
            vol = jv >= 0 ? SoundMath.i16(SoundTags.int(b, sep, jv)) : 100
            let jl = t.find(SoundTags.loop)
            loop = jl >= 0 ? SoundMath.i16(SoundTags.int(b, sep, jl)) : 1
            let jf = t.find(SoundTags.fade)
            fade = jf >= 0 ? SoundMath.i16(SoundTags.int(b, sep, jf)) : 0
            let jw = t.find(SoundTags.wait)
            t011 = jw >= 0 ? SoundMath.i16(SoundTags.int(b, sep, jw)) : 0
            let js = t.find(SoundTags.start)
            start = js >= 0 ? SoundTags.int(b, sep, js, bits: 32) : 0
        }

        let track = SoundMath.i16(SoundTags.int(b, sep, 0))
        if track < 0 {
            if !fastForward && !scan {
                bgmStop()
            }

            _scrTrack = -1
            return 0
        }

        if !scan {
            if !fastForward && _track != track {
                let status = _isPlaying(_slot) ? 3 : 5
                if fade == 0 && status == 3 {
                    bgmStop()
                }

                bgmSetLoop(loop)
                emit(AudioCommand.setStartSample(_slot ^ 1, start))
                let fv = Float(vol)
                if fade != 0 {
                    let newRate = fv * SoundMath.msPerSecond / SoundMath.fps / Float(fade)
                    let old = Float(_scrBgmVol) * SoundMath.msPerSecond / SoundMath.fps
                    var oldRate = old / Float(t011 != 0 ? t011 : fade)
                    if !(oldRate > 0 || oldRate.isNaN) {
                        oldRate = 100.0
                    }

                    bgmFadeOut(oldRate)
                    bgmStartFade(track, vol, newRate)
                } else {
                    bgmStart(track, fv)
                }
            }

            if (track & 0xFFFF) <= 0x207 {
                let bit = track + 0xC80
                _musicBits[bit >> 3] = (_musicBits[bit >> 3] ?? 0) | (1 << (track & 7))
            }
        }

        _scrTrack = track
        _scrBgmVol = SoundMath.i16(vol)
        return 0
    }

    /// VA 0x87940: ramp the BGM to ``017` over ``001` ms (both default 0).
    private func cmdMvol(_ b: ByteSpan, _ sep: Int) -> Int {
        let t = SoundTags.parse(b, sep)
        let jf = t.find(SoundTags.fade)
        let ms = jf >= 0 ? SoundMath.i16(SoundTags.int(b, sep, jf)) : 0
        let jv = t.find(SoundTags.volume)
        let v = jv >= 0 ? SoundMath.i16(SoundTags.int(b, sep, jv)) : 0
        historyPush()
        if !silent {
            let rate = SoundMath.rate(Float(abs(v - _scrBgmVol)), Float(ms >= 2 ? ms : 1))
            let r = _bgm[_slot]
            if r.state != 0 { // VA 0x9F20
                r.volumeStep = rate
                r.volumeTarget = Float(v)
            }
        }

        _scrBgmVol = v
        return 0
    }

    /// VA 0x87660: `_MFAD(`001 ms)` fades the BGM out over ``001` ms and stops it; returns the wait in 16 ms units
    /// (`wait16`) unless ``011` is present and 0.
    private func cmdMfad(_ b: ByteSpan, _ sep: Int) -> Int {
        historyPush()
        let t = SoundTags.parse(b, sep)
        let jf = t.find(SoundTags.fade)
        let jw = t.find(SoundTags.wait)
        let ms = jf >= 0 ? SoundMath.i16(SoundTags.int(b, sep, jf)) : 0
        if !silent {
            if ms > 0 {
                bgmFadeOut(SoundMath.rate(Float(_scrBgmVol), Float(ms)))
            } else {
                bgmStop()
            }
        }

        _scrTrack = -1
        if jw >= 0 && SoundMath.i16(SoundTags.int(b, sep, jw)) == 0 {
            return 0
        }

        wait16 = (ms < 0 ? ms + 15 : ms) >> 4 // word 0x1653E08
        return 1
    }

    /// `_MSTP()` (VA 0x978BD; no script uses it): a BGM fade-out (state 2) and track -1. The engine passes the rate in xmm0 and the
    /// Python model leaves it open [H]; knife's Witch build uses 4.1666665 points per frame (0.4 s from full volume), taken here.
    private func cmdMstp() -> Int {
        historyPush()
        if !silent {
            bgmFadeOut(4.1666665)
        }

        _scrTrack = -1
        return 0
    }

    // -- SE primitives ---------------------------------------------------------------------------

    /// VA 0xAAB0.
    func seStop(_ ch: Int) {
        if ch > 0x13 {
            return
        }

        let r = _se[ch]
        r.state = 0
        if r.started != 0 {
            stopCall(ch + AudioStreams.firstSE)
        }
    }

    /// VA 0xAC50: from the record's current volume to 0 over `ms`.
    func seFadeOut(_ ch: Int, _ ms: Int) {
        let r = _se[ch]
        let rate: Float = ms > 0 ? r.volume * SoundMath.msPerSecond / SoundMath.fps / Float(ms) : 100.0
        if r.state != 0 {
            r.state = 2
            r.volumeStep = rate
            r.volumeTarget = 0
        }
    }

    /// VA 0xAC20.
    func seFadeOutRate(_ ch: Int, _ rate: Float) {
        let r = _se[ch]
        if r.state != 0 {
            r.state = 2
            r.volumeStep = rate
            r.volumeTarget = 0
        }
    }

    /// VA 0xACC0: ramp to `target`; a rate of 100 points in one frame or more jumps.
    func seRamp(_ ch: Int, _ target: Int, _ rate: Float) {
        let r = _se[ch]
        if r.state != 0 {
            r.volumeStep = rate
            r.volumeTarget = Float(target)
            if rate >= SoundMath.seJumpRate {
                r.volume = Float(target)
            }
        }
    }

    func seGain(_ ch: Int, _ vol: Float) -> Float {
        let r = _se[ch]
        let c = Int(r.character)
        var x: Float
        if c - 1 >= 0 && c - 1 <= 0x12 {
            if (config.charEnable & (UInt32(1) << (c - 1))) == 0 {
                return 0
            }

            x = vol / 100.0 * Float(SoundMath.i16(config.charVol[c - 1]))
            x *= Float(SoundMath.i16(config.voice))
            x /= 100.0
        } else {
            x = Float(SoundMath.i8(Int(_vol[0xE]))) * vol / 100.0
        }

        x = SoundMath.maxSs(0, x)
        return SoundMath.minSs(100.0, x)
    }

    /// VA 0xA300: start vse `entry` on channel `ch` at `vol` (0..100).
    func sePlayNow(_ ch: Int, _ entry: Int, _ vol: Float) {
        let g = seGain(ch, vol)
        let s = ch + AudioStreams.firstSE
        emit(AudioCommand.openHandle(s, .se))
        let gv = g * 0.01
        emit(AudioCommand.setVolume0(s, gv))
        playCall(s, .se, entry, _seLoop[ch] != 0 ? 1 : 0, gv)
        let r = _se[ch]
        r.state = 1
        r.volumeClass = 1
        r.entry = UInt16(truncatingIfNeeded: entry)
        r.volume = vol
        r.volumeTarget = vol
        r.volumeStep = 100.0
        clearPans(r)
        r.started = 1
    }

    /// VA 0xA770: start at volume 0 (the ramp is set up by the caller).
    func sePlayFade(_ ch: Int, _ entry: Int, _ rate: Float, _ target: Int) {
        let s = ch + AudioStreams.firstSE
        emit(AudioCommand.openHandle(s, .se))
        emit(AudioCommand.setVolume(s, 0, time: 0))
        playCall(s, .se, entry, _seLoop[ch] != 0 ? 1 : 0, 0)
        let r = _se[ch]
        r.state = 1
        r.volumeClass = 1
        r.entry = UInt16(truncatingIfNeeded: entry)
        r.volume = 0
        r.volumeStep = rate
        r.volumeTarget = Float(target)
        clearPans(r)
        r.started = 1
    }

    /// VA 0xA9E0: an immediate pan (only on an SE-kind record).
    func seSetPan(_ ch: Int, _ pan: Int) {
        if ch > 0x13 {
            return
        }

        let r = _se[ch]
        if r.volumeClass != 1 {
            return
        }

        clearPans(r)
        emit(AudioCommand.setPan(ch + AudioStreams.firstSE, Float(pan) * 0.001))
    }

    private static func channel(_ b: ByteSpan, _ sep: Int) -> Int {
        SoundMath.i16(SoundMath.i16(SoundTags.int(b, sep, 0)) % 20)
    }

    private static func channelRange(_ ch: Int) -> ClosedRange<Int> {
        let lo = ch > 0 ? ch : 0
        let hi = ch >= 0 ? ch : 0x13
        return lo <= hi ? lo...hi : 0...(-1)
    }

    /// The index Python gives a possibly negative channel (a negative list index counts from the end).
    private static func wrap(_ ch: Int) -> Int {
        ch < 0 ? ch + SoundModel.seChannels : ch
    }

    // -- SE commands -----------------------------------------------------------------------------

    /// VA 0x893F0: `_SEPL(ch, loop, name, , `001 fade, `017 volume, `018 pan, `068 delay, `070 character)` (also `_SEFI`).
    private func cmdSepl(_ b: ByteSpan, _ sep: Int) -> Int {
        let t = SoundTags.parse(b, sep)
        if t.count > 0 {
            let jd = t.find(SoundTags.delay)
            if jd > 0 && !fastForward && !scan {
                deferCommand(b, sep, 1)
                return 0
            }
        }

        let name = SoundTags.argText(b, sep, 2)
        let ch = Self.wrap(Self.channel(b, sep))
        _defer[ch].timer = 0
        var vol = 100
        var rawVol = -1
        var pan = 0
        var fade = 0
        if t.count > 0 {
            let jf = t.find(SoundTags.fade)
            if jf >= 0 {
                let v = SoundMath.i16(SoundTags.int(b, sep, jf))
                fade = _se[ch].state == 2 ? v + 1000 : v
            }

            let jv = t.find(SoundTags.volume)
            if jv >= 0 {
                rawVol = SoundMath.i16(SoundTags.int(b, sep, jv))
                vol = min(max(rawVol, 0), 100)
            }

            let jp = t.find(SoundTags.pan)
            if jp >= 0 {
                pan = SoundMath.panFromTag(SoundMath.i16(SoundTags.int(b, sep, jp)))
            }
        }

        if name.isEmpty {
            historyPush()
            if !silent {
                seStop(ch)
            }

            _scrSeLoopId[ch] = -1
            return 0
        }

        let loopArg = SoundTags.present(b, sep, 1) ? SoundTags.int(b, sep, 1) : 0
        let bx = SoundMath.i16(loopArg) != 0 ? 1 : 0
        let flags = rawVol < 0 ? (2 * bx) + 1 : 3
        let seId = seLookup(name, flags) ?? -1
        _scrSeId[ch] = SoundMath.i16(seId)
        let r14 = SoundMath.i16(SoundTags.int(b, sep, 1))
        if r14 == 1 {
            historyPush()
            if _scrSeLoopId[ch] == SoundMath.i16(seId) && _scrSeLoop[ch] == 1 && _scrSeVol[ch] > 0 {
                return 0
            }

            _scrSeLoopId[ch] = SoundMath.i16(seId)
            _scrSeLoop[ch] = 1
        } else {
            _scrSeLoop[ch] = 0
            if skip {
                if _scrSeLoopId[ch] >= 0 {
                    seStop(ch)
                }

                _scrSeLoopId[ch] = -1
                return 0
            }

            _scrSeLoopId[ch] = -1
        }

        let loop = bx != 0 ? r14 : 0
        _seLoop[ch] = loop
        let jc = t.find(SoundTags.character)
        let chr = jc >= 0 ? SoundMath.i8(SoundTags.int(b, sep, jc)) : 0
        _scrSeChar[ch] = chr & 0xFF
        _se[ch].character = UInt8(truncatingIfNeeded: chr & 0xFF)
        if !silent {
            if fade >= 0x11 {
                sePlayFade(ch, seId, 2000.0, 0)
                seRamp(ch, vol, SoundMath.rate(Float(vol), Float(fade)))
            } else {
                sePlayNow(ch, seId, Float(vol))
            }

            seSetPan(ch, pan)
            _scrSePan[ch] = pan
            if config.seCaption != 0 {
                seStarted?(ch, seId)
            }
        } else {
            _scrSePan[ch] = pan
        }

        _scrSeVol[ch] = rawVol >= 0 ? rawVol : 100
        return 0
    }

    /// VA 0x89E40: `_SEFD(ch, , `001 ms)` fades channel ch (or all for a negative ch) out over `001 ms.
    private func cmdSefd(_ b: ByteSpan, _ sep: Int) -> Int {
        let t = SoundTags.parse(b, sep)
        if t.count > 0 {
            let jd = t.find(SoundTags.delay)
            if jd > 0 && !fastForward && !scan {
                deferCommand(b, sep, 2)
                return 0
            }
        }

        let j = t.find(SoundTags.fade)
        let ms = j >= 0 ? SoundMath.i16(SoundTags.int(b, sep, j)) : 0
        let ch = Self.channel(b, sep)
        historyPush()
        for c in Self.channelRange(ch) {
            let d = _defer[c]
            if d.kind == 1 && d.timer > 0 { // a pending deferred _SEPL is cancelled
                d.timer = 0
                d.kind = 0
            }

            if !silent {
                if ms > 0 {
                    seFadeOut(c, ms)
                } else {
                    seStop(c)
                }
            }

            _scrSeLoopId[c] = -1
        }

        return 0
    }

    /// VA 0x89B50: `_SEVL(ch, , `001 ms, `017 volume)` ramps channel ch to `017 over `001 ms (from the script volume).
    private func cmdSevl(_ b: ByteSpan, _ sep: Int) -> Int {
        let t = SoundTags.parse(b, sep)
        if t.count > 0 {
            let jd = t.find(SoundTags.delay)
            if jd > 0 && !fastForward && !scan {
                deferCommand(b, sep, 3)
                return 0
            }
        }

        let j = t.find(SoundTags.fade)
        let ms = j >= 0 ? SoundMath.i16(SoundTags.int(b, sep, j)) : 0
        let jv = t.find(SoundTags.volume)
        let v = jv >= 0 ? SoundMath.i16(SoundTags.int(b, sep, jv)) : 0
        historyPush()
        if !silent {
            let ch = Self.wrap(Self.channel(b, sep))
            let rate = ms > 0 ? SoundMath.rate(Float(abs(v - _scrSeVol[ch])), Float(ms)) : 2000.0
            seRamp(ch, v, rate)
            _scrSeVol[ch] = v
        }

        return 0
    }

    /// VA 0x996E1: `_SESP(ch)` stops channel ch (or all) and cancels its deferred command.
    private func cmdSesp(_ b: ByteSpan, _ sep: Int) -> Int {
        let ch = SoundMath.i16(SoundMath.i16(SoundTags.int(b, sep, 0)) % 20)
        historyPush()
        for c in Self.channelRange(ch) {
            if !fastForward {
                seStop(c)
            }

            _defer[c].clear()
            _defer[c].fade = -1
            _scrSeLoopId[c] = -1
            _scrSeId[c] = -1
        }

        return 0
    }

    // -- deferred (`068) commands ----------------------------------------------------------------

    /// VA 0x88160: queue SEPL (1) / SEFD (2) / SEVL (3) for channel ch (all channels for a negative SEFD channel); a pending command of
    /// the channel is executed first. Timer = max(1, trunc(delay ms * 3 / 50)) frames.
    private func deferCommand(_ b: ByteSpan, _ sep: Int, _ kind: Int) {
        let t = SoundTags.parse(b, sep)
        let jd = t.find(SoundTags.delay)
        let delay = SoundMath.i16(SoundTags.int(b, sep, jd))
        let timer = (delay * 3) + 0x31 >= 0x63 ? (delay * 3) / 50 : 1
        historyPush()
        let ch = SoundMath.i16(SoundTags.int(b, sep, 0)) % 20
        let lo = ch > 0 ? ch : 0
        let hi = ch >= 0 ? ch : 0x13
        if hi < lo {
            return
        }

        var seId = -1
        if kind == 1 {
            let name = SoundTags.argText(b, sep, 2)
            let loopArg = SoundTags.present(b, sep, 1) ? SoundTags.int(b, sep, 1) : 0
            let jv = t.find(SoundTags.volume)
            let flags = jv >= 0 ? 3 : (2 * (SoundMath.i16(loopArg) != 0 ? 1 : 0)) + 1
            seId = !name.isEmpty ? seLookup(name, flags) ?? -1 : -1
        }

        for c in lo...hi {
            if _defer[c].kind != 0 {
                runDeferred(c)
            }

            let d = DeferredSe(timer: timer, kind: kind, seId: -1, fade: -1, vol: 0xFF, vol2: 0xFF, pan: 0xFF, pan2: 0xFF, loop: 0xFF, char: 0)
            let j = t.find(SoundTags.fade)
            if j >= 0 {
                d.fade = Int64(SoundMath.i16(SoundTags.int(b, sep, j)))
            }

            if kind == 1 {
                d.seId = seId
                let jv = t.find(SoundTags.volume)
                if jv >= 0 {
                    d.vol = SoundTags.int(b, sep, jv) & 0xFF
                }

                let jp = t.find(SoundTags.pan)
                if jp >= 0 {
                    d.pan = SoundTags.int(b, sep, jp) & 0xFF
                }

                d.loop = SoundTags.present(b, sep, 1) ? SoundTags.int(b, sep, 1) & 0xFF : 0
                let jc = t.find(SoundTags.character)
                d.char = jc >= 0 ? SoundTags.int(b, sep, jc) & 0xFF : 0
            } else if kind == 3 {
                let jv = t.find(SoundTags.volume)
                if jv >= 0 {
                    d.vol = SoundTags.int(b, sep, jv) & 0xFF
                }
            }

            _defer[c] = d
        }
    }

    /// VA 0x87D50: executes the channel's deferred command and clears the entry.
    func runDeferred(_ ch: Int) {
        let d = _defer[ch]
        switch d.kind {
        case 1:
            deferredPlay(ch)
        case 2:
            if !silent {
                let fade = Int(Int32(truncatingIfNeeded: d.fade))
                if fade > 0 && _scrSeVol[ch] > 0 {
                    seFadeOutRate(ch, SoundMath.rate(Float(_scrSeVol[ch]), Float(fade)))
                } else {
                    seStop(ch)
                }
            }

            _scrSeLoopId[ch] = -1
        case 3:
            if !silent && SoundMath.i8(d.vol) >= 0 {
                let tgt = SoundMath.i8(d.vol)
                var fade = Int(Int32(truncatingIfNeeded: d.fade))
                fade = fade >= 2 ? fade : 1
                var cur = _scrSeVol[ch]
                cur = cur < 0 ? 100 : min(cur, 100)
                seRamp(ch, tgt, SoundMath.rate(Float(abs(tgt - cur)), Float(fade)))
                _scrSeVol[ch] = tgt & 0xFF
            }
        case 4:
            // Deferred kind 4 (_SEAC) is not used by the scripts
            break
        default:
            break
        }

        _defer[ch].clear()
    }

    /// VA 0x87AF0.
    func deferredPlay(_ ch: Int) {
        let d = _defer[ch]
        let fadeRaw = d.fade
        let fade: Int
        if fadeRaw > 0 {
            fade = _se[ch].state == 2 ? Int(Int32(truncatingIfNeeded: fadeRaw)) + 1000 : Int(Int32(truncatingIfNeeded: fadeRaw))
        } else {
            fade = 0
        }

        _scrSeId[ch] = SoundMath.i16(d.seId)
        if d.loop == 1 {
            _scrSeLoopId[ch] = SoundMath.i16(d.seId)
            _scrSeLoop[ch] = 1
            _seLoop[ch] = 1
        } else {
            _scrSeLoop[ch] = 0
            if skip {
                if _scrSeLoopId[ch] >= 0 {
                    seStop(ch)
                }

                _scrSeLoopId[ch] = -1
                return
            }

            _scrSeLoopId[ch] = -1
            _seLoop[ch] = 0
        }

        _se[ch].character = UInt8(truncatingIfNeeded: d.char)
        _scrSeChar[ch] = d.char
        if silent {
            return
        }

        var effFade = fade
        if d.kind == 4 {
            effFade = 0
        }

        _scrSeVol[ch] = 100
        var vol = 100
        if SoundMath.i8(d.vol) >= 0 {
            vol = d.vol
            _scrSeVol[ch] = vol
        }

        if effFade >= 0x11 {
            sePlayNow(ch, SoundMath.i16(d.seId), 0)
            seRamp(ch, vol, SoundMath.rate(Float(vol), Float(effFade)))
        } else {
            sePlayNow(ch, SoundMath.i16(d.seId), Float(vol))
        }

        let pan = d.pan != 0xFF ? SoundMath.panFromTag(abs(SoundMath.i8(d.pan))) : 0
        seSetPan(ch, pan)
        _scrSePan[ch] = pan
        if config.seCaption != 0 {
            seStarted?(ch, SoundMath.i16(d.seId))
        }
    }

    func scriptSeIdAt(_ ch: Int) -> Int { _scrSeId[ch] }
    func scriptSeLoopIdAt(_ ch: Int) -> Int { _scrSeLoopId[ch] }
    func scriptSeVolAt(_ ch: Int) -> Int { _scrSeVol[ch] }
    func scriptSeLoopAt(_ ch: Int) -> Int { _scrSeLoop[ch] }
    func scriptSePanAt(_ ch: Int) -> Int { _scrSePan[ch] }
    func scriptSeCharAt(_ ch: Int) -> Int { _scrSeChar[ch] }
}
