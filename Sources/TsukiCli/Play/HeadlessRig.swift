import Foundation
import TsukiCore
import TsukiData
import TsukiEngine

public final class ScriptCache: FlowScripts {
    private let source: GameFolderSource
    private var images: [Int: ScriptImage] = [:]
    private var labelsMap: [Int: LabelTable] = [:]

    public init(_ source: GameFolderSource) {
        self.source = source
    }

    public func script(_ k: Int) -> ScriptImage {
        if let image = images[k] {
            return image
        }
        let image = source.script(k)
        images[k] = image
        return image
    }

    public func labels(_ k: Int) -> LabelTable {
        if let table = labelsMap[k] {
            return table
        }
        let table = (try? source.scripts.labelLookup(k)) ?? LabelTable(records: [])
        labelsMap[k] = table
        return table
    }
}

public final class HeadlessRig {
    public let source: GameFolderSource
    public let services: GameServices

    private init(source: GameFolderSource, services: GameServices) {
        self.source = source
        self.services = services
    }

    public static func open(_ folder: String) throws -> HeadlessRig {
        let source = try GameFolderSource.open(folder)
        let scriptCache = ScriptCache(source)
        let services = GameServices(data: source, scripts: scriptCache)
        services.seLookup = { name, flags in
            (try? source.soundEffectNames.lookup(name, flags: flags))?.index
        }
        return HeadlessRig(source: source, services: services)
    }

    public func dispose() {
        source.dispose()
    }
}
