import Foundation
import TsukiCore
import TsukiEngine
import TsukiData

public enum ReferenceCensus {
    private static let textLineCount = TextRules.retailLineCount
    private static let imageArgument: [String: Int] = [
        "SPFC": 1, "SPRD": 1, "STCG": 0
    ]
    private static let labelJumps: [String: Int] = [
        "GOTO": 0, "IF__": 3, "IFNX": 1, "IFP4": 1, "IFSC": 1, "IFUR": 2
    ]
    private static let textCommands: Set<String> = ["ZM", "ZD", "MSAD", "SELR"]

    public static func run(_ source: GameFolderSource, options: CensusOptions = CensusOptions()) -> CensusReport {
        let watch = Date()
        let scripts = source.scriptCount
        let context = Context(source: source)

        var references: [CensusReference] = []
        var findings: [CensusFinding] = []
        var statements = 0

        for k in 0..<scripts {
            let scan = scanScript(context, k)
            references.append(contentsOf: scan.references)
            findings.append(contentsOf: scan.findings)
            statements += scan.statements
        }

        var checks: [CensusCheck] = []
        if options.checkTargets {
            checkTargets(context, references, options, &findings, &checks)
        }

        var glyphs: [GlyphCensusLanguage] = []
        if options.checkGlyphs {
            glyphs = GlyphCensus.run(source: source, ids: textIds(references), findings: &findings)
        }

        var totals: [CensusKindTotals] = []
        for kind in ReferenceKind.allCases {
            let name = kind.rawValue
            let of = references.filter { $0.kind == kind }
            let distinct = Set(of.map(\.key)).count
            let resolved = of.filter(\.resolved).count
            let allowed = findings.filter { $0.check == name && $0.allowed }.count
            let unexpected = findings.filter { $0.check == name && !$0.allowed }.count
            totals.append(CensusKindTotals(kind: kind, references: of.count, distinct: distinct, resolved: resolved, allowed: allowed, unexpected: unexpected))
        }

        let elapsed = Date().timeIntervalSince(watch)
        return CensusReport(scripts: scripts, statements: statements, references: references, totals: totals, findings: findings, checks: checks, glyphs: glyphs, elapsed: elapsed)
    }

    private final class Context {
        let source: GameFolderSource
        let resolver: ScriptImageResolver
        let voiceNames: [String]
        let bgmCount: Int
        let movieCount: Int
        let scenes: SceneTable
        let allpac3Names: [String]
        let maskBase: Int

        init(source: GameFolderSource) {
            self.source = source
            self.resolver = source.catalog.resolver
            self.voiceNames = (try? source.archive("voice").index.nam?.names) ?? []
            self.bgmCount = (try? source.audioCount(.bgm)) ?? 0
            self.movieCount = source.tables.movies.count
            self.scenes = (try? source.tables.sceneIds) ?? (try! SceneTable.fromIds([]))
            self.allpac3Names = source.catalog.nams[.allpac3]?.names ?? []
            let found = try? source.catalog.nameIndex.find("mask_top.mzp")
            self.maskBase = (found?.archive == .allpac3) ? found!.index : 0
        }
    }

    private final class ScriptScan {
        var references: [CensusReference] = []
        var findings: [CensusFinding] = []
        var statements: Int = 0
    }

    private static func scanScript(_ cx: Context, _ k: Int) -> ScriptScan {
        let scan = ScriptScan()
        let image = cx.source.script(k)
        let span = ByteSpan(image.bytes)
        let tracker = LayerNameTracker()
        let ownLabels = (try? cx.source.scripts.labelLookup(k)) ?? LabelTable(records: [])

        for start in image.segmentStarts {
            guard let segment = try? ScriptSegmenter.read(span, start),
                  let statement = ScriptSegmenter.statement(k, span, segment) else {
                continue
            }

            scan.statements += 1
            let s = StatementView(statement)
            let n = s.name
            var pictureKey: String? = nil

            if n == "STCH" || n == "SCH2" {
                var aa = 0
                var bb = 0
                if let name = LayerNameTracker.pictureName(s, sourceName: tracker.sourceName(s), aa: &aa, bb: &bb) {
                    if let r = try? cx.resolver.resolve(ByteSpan(name), aa: aa, bb: bb) {
                        pictureKey = r.key
                        if !isNumber(r.key) {
                            addImage(scan, k, s, r)
                        }
                    }
                }
            } else if let arg = imageArgument[n] {
                if arg < s.textCount {
                    let val = s.textValue(arg)
                    if val.count > 0 && !isNumber(latin1(val.toArray())) {
                        if let r = try? cx.resolver.resolve(val) {
                            addImage(scan, k, s, r)
                        }
                    }
                }
            } else if n == "VPLY" || n == "VPL2" {
                addVoice(cx, scan, k, s)
            } else if (n == "SEPL" || n == "SEFI") && s.textCount > 2 {
                let name = s.textString(2)
                let idx = (try? cx.source.soundEffectNames.vseIndex(name)) ?? -1
                add(scan, .se, k, s, seKey(name), idx < 0 ? "-" : "\(idx)", idx >= 0)
            } else if n == "MPLY" && s.textCount > 0 {
                let track = s.inline16(0)
                let ok = track >= 0 && track < cx.bgmCount
                add(scan, .bgm, k, s, "\(track)", ok ? "\(track)" : "-", ok)
            } else if n == "TOMP" && s.textCount > 0 {
                let id = s.inline16(0)
                let ok = id >= 0 && id < cx.movieCount
                let fName = ok ? cx.source.tables.movies[id].fileName : "-"
                add(scan, .movie, k, s, "\(id)", fName, ok)
            } else if n.hasPrefix("J") && s.textCount > 0 {
                addJump(cx, scan, k, s)
            } else if let labelArg = labelJumps[n], s.textCount > labelArg {
                let lStr = s.textString(labelArg)
                let found = ownLabels.find(s.textValue(labelArg)) >= 0
                addLabel(scan, k, s, lStr, found)
            } else if n == "GOTS" {
                for i in 1..<s.textCount {
                    let lStr = s.textString(i)
                    let found = ownLabels.find(s.textValue(i)) >= 0
                    addLabel(scan, k, s, lStr, found)
                }
            }

            if n == "STMA" || n == "SGMA" {
                let m = s.expr(1)
                let state: String
                if let m = m {
                    state = m == 0 ? "zero" : (m >= 1 && m <= MotionTables.motionCount ? "ok" : "out")
                } else {
                    state = "none"
                }
                add(scan, .motion, k, s, m != nil ? "\(m!)" : "-", state, state == "ok")
            }

            if n == "FADS" && s.expr(0) == 2, let rule = s.expr(2) {
                let at = cx.maskBase + rule
                let file = (at >= 0 && at < cx.allpac3Names.count) ? cx.allpac3Names[at] : "-"
                let ok = (rule == 0 && file == "MASK_TOP.MZP") || (rule >= 1 && file == String(format: "RULE_%02d.MZP", rule))
                add(scan, .rule, k, s, "\(rule)", file, ok)
            }

            if textCommands.contains(n) {
                for i in 0..<s.textCount {
                    let refs = TextReferences.scanRefs(latin1(s.textValue(i).toArray()))
                    for id in refs {
                        let ok = id >= 0 && id < textLineCount
                        add(scan, .text, k, s, "\(id)", ok ? "ok" : "range", ok)
                    }
                }
            }

            tracker.update(s, pictureKey: pictureKey)
        }

        return scan
    }

    private static func addImage(_ scan: ScriptScan, _ k: Int, _ s: StatementView, _ r: ResolvedImage) {
        var layers: [String] = []
        var missing = 0
        if r.found {
            if let f = r.fileId {
                layers.append("\(f)")
            } else {
                missing += 1
            }
            if r.overlay != nil {
                if let o = r.overlayId {
                    layers.append("\(o)")
                } else {
                    missing += 1
                }
            }
        }

        let res = (layers.isEmpty ? "-" : layers.joined(separator: "+")) + ";m=\(missing)"
        let resolved = r.found && missing == 0
        let allowed = resolved ? nil : CensusAllowList.imageReason(r)
        add(scan, .image, k, s, r.key, res, resolved, allowed: allowed)
    }

    private static func addVoice(_ cx: Context, _ scan: ScriptScan, _ k: Int, _ s: StatementView) {
        let name = s.textCount > 0 ? s.textString(0) : ""
        var index = -1
        var ok = false
        if s.textCount > 1 {
            let str = s.textString(1).trimmingCharacters(in: .whitespaces)
            if let idx = Int(str, radix: 16) {
                index = idx
                ok = idx < cx.voiceNames.count && name.hasPrefix(cx.voiceNames[idx])
            }
        }
        let res = (index < 0 ? "-" : "\(index)") + "|" + (ok ? "1" : "0")
        add(scan, .voice, k, s, name, res, ok)
    }

    private static func addJump(_ cx: Context, _ scan: ScriptScan, _ k: Int, _ s: StatementView) {
        let sceneId = s.inline16(0)
        let target = cx.scenes.indexOf(sceneId)
        add(scan, .scene, k, s, "\(sceneId)", target != nil ? "\(target!)" : "-", target != nil)
        if s.textCount > 1 && s.textValue(1).count > 0 {
            let label = s.textString(1)
            let key = "\(sceneId):\(label)"
            if let t = target {
                let found = (try? cx.source.scripts.labelLookup(t).find(s.textValue(1))) ?? -1 >= 0
                add(scan, .label, k, s, key, found ? "found" : "missing", found)
            } else {
                add(scan, .label, k, s, key, "noscript", false)
            }
        }
    }

    private static func addLabel(_ scan: ScriptScan, _ k: Int, _ s: StatementView, _ label: String, _ found: Bool) {
        add(scan, .label, k, s, label, found ? "found" : "missing", found)
    }

    private static func add(_ scan: ScriptScan, _ kind: ReferenceKind, _ k: Int, _ s: StatementView, _ key: String, _ result: String, _ resolved: Bool, allowed: String? = nil) {
        let ref = CensusReference(kind: kind, script: k, offset: s.offset, command: s.name, key: key, result: result, resolved: resolved)
        scan.references.append(ref)
        if !resolved {
            let al = allowed ?? CensusAllowList.reason(ref)
            scan.findings.append(CensusFinding(check: kind.rawValue, detail: ref.line, allowedBecause: al))
        }
    }

    private static func seKey(_ name: String) -> String { name.uppercased() }

    private static func isNumber(_ value: String) -> Bool {
        let t = value.hasPrefix("-") ? String(value.dropFirst()) : value
        return !t.isEmpty && t.allSatisfy { $0.isNumber }
    }

    private static func textIds(_ references: [CensusReference]) -> [Int] {
        var ids = Set<Int>()
        for r in references where r.kind == .text {
            if let id = Int(r.key) {
                ids.insert(id)
            }
        }
        return ids.sorted()
    }

    private static func checkTargets(
        _ cx: Context, _ references: [CensusReference], _ options: CensusOptions,
        _ findings: inout [CensusFinding], _ checks: inout [CensusCheck]
    ) {
        let source = cx.source
        var imageFiles = 0
        var imageFails = 0
        var imageSeen = Set<ImageId>()

        for r in references where r.kind == .image {
            guard let res = try? cx.resolver.resolve(ByteSpan(Array(r.key.utf8))) else { continue }
            for id in [res.fileId, res.overlayId, res.reducedId].compactMap({ $0 }) {
                guard imageSeen.insert(id).inserted else { continue }
                imageFiles += 1
                do {
                    let image = try source.openImage(Int(id.archive.rawValue), id.index)
                    if image.header.tiles < 1 {
                        imageFails += 1
                        findings.append(CensusFinding(check: "image-file", detail: "\(id): no tiles", allowedBecause: nil))
                    }
                } catch {
                    imageFails += 1
                    findings.append(CensusFinding(check: "image-file", detail: "\(id): \(error)", allowedBecause: nil))
                }
            }
        }
        checks.append(CensusCheck(name: "picture files opened (header and tile table)", checked: imageFiles, failed: imageFails))

        // Check movies
        var movieFiles = 0
        var movieFails = 0
        let movieIds = Set(references.filter { $0.kind == .movie && $0.resolved }.compactMap { Int($0.key) }).sorted()
        for id in movieIds {
            for lang in 0..<4 {
                let index = MovieTable.remap(id, Language(rawValue: UInt8(lang)) ?? .ja)
                movieFiles += 1
                let path = source.movie(index)
                if (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value == 0 {
                    movieFails += 1
                    findings.append(CensusFinding(check: "movie-file", detail: "movie \(id): \(path) is empty", allowedBecause: nil))
                }
            }
        }
        checks.append(CensusCheck(name: "movie ids x 4 languages -> files", checked: movieFiles, failed: movieFails))

        // Check text
        let tIds = textIds(references)
        var textReads = 0
        var textFails = 0
        for lang in TextRules.selectableLanguages {
            for id in tIds {
                textReads += 1
                let span = source.textLine(lang, id)
                if span.isEmpty {
                    textFails += 1
                    findings.append(CensusFinding(check: "text-line", detail: "\(lang) line \(id) is empty", allowedBecause: nil))
                }
            }
        }
        checks.append(CensusCheck(name: "text lines x 4 languages read", checked: textReads, failed: textFails))
    }
}
