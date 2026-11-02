import Foundation
import Metal
import TsukiCore
import TsukiEngine

/// Counters of a `TextureCache`.
public struct TextureCacheStats: Equatable, Sendable {
    public var resident: Int
    public var residentBytes: Int64
    public var allocations: Int64
    public var recycles: Int64
    public var evictions: Int64
    public var spareBytes: Int64

    public init(
        resident: Int = 0,
        residentBytes: Int64 = 0,
        allocations: Int64 = 0,
        recycles: Int64 = 0,
        evictions: Int64 = 0,
        spareBytes: Int64 = 0
    ) {
        self.resident = resident
        self.residentBytes = residentBytes
        self.allocations = allocations
        self.recycles = recycles
        self.evictions = evictions
        self.spareBytes = spareBytes
    }
}

extension TextureRef: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(a)
        hasher.combine(b)
        hasher.combine(c)
        hasher.combine(d)
    }
}

/// LRU texture cache mapping `TextureRef` to `MTLTexture`.
public final class TextureCache: ITextureSource, @unchecked Sendable {
    private final class Node {
        let key: TextureRef
        let texture: MTLTexture
        let width: Int
        let height: Int
        let bytes: Int64
        var prev: Node?
        var next: Node?

        init(key: TextureRef, texture: MTLTexture, width: Int, height: Int, bytes: Int64) {
            self.key = key
            self.texture = texture
            self.width = width
            self.height = height
            self.bytes = bytes
        }
    }

    private struct Dimensions: Hashable {
        let width: Int
        let height: Int
    }

    public let device: MTLDevice
    public let capacityBytes: Int64
    public let spareCapacityBytes: Int64

    public var grader: TileGrader?

    private var map: [TextureRef: Node] = [:]
    private var head: Node? // Most recently used
    private var tail: Node? // Least recently used

    private var spare: [Dimensions: [MTLTexture]] = [:]
    private var transitions: [TextureRef: TransitionParams] = [:]

    public private(set) var residentBytes: Int64 = 0
    private var spareBytes: Int64 = 0
    private var allocations: Int64 = 0
    private var recycles: Int64 = 0
    private var evictions: Int64 = 0

    public init(device: MTLDevice, capacityBytes: Int64 = 3 << 30, spareCapacityBytes: Int64 = 256 << 20) {
        self.device = device
        self.capacityBytes = capacityBytes
        self.spareCapacityBytes = spareCapacityBytes
    }

    public var count: Int {
        map.count
    }

    public var stats: TextureCacheStats {
        TextureCacheStats(
            resident: map.count,
            residentBytes: residentBytes,
            allocations: allocations,
            recycles: recycles,
            evictions: evictions,
            spareBytes: spareBytes
        )
    }

    public func contains(_ key: TextureRef) -> Bool {
        map[key] != nil
    }

    /// Marks `key` as used now (moves it to the front of LRU order).
    public func touch(_ key: TextureRef) -> Bool {
        guard let node = map[key] else {
            return false
        }
        moveToHead(node)
        return true
    }

    public func tryGetTexture(_ key: TextureRef) -> (texture: MTLTexture, transition: TransitionParams?)? {
        let tp = transitions[key]
        guard let node = map[key] else {
            return nil
        }
        moveToHead(node)
        return (texture: node.texture, transition: tp)
    }

    public func setTransitionParams(key: TextureRef, value: TransitionParams?) {
        if let v = value {
            transitions[key] = v
        } else {
            transitions.removeValue(forKey: key)
        }
    }

    /// Uploads RGBA8 pixels into a texture for `key`.
    @discardableResult
    public func upload(key: TextureRef, width: Int, height: Int, rgba: [UInt8], pregraded: Bool = false) -> Bool {
        rgba.withUnsafeBytes { ptr in
            upload(key: key, width: width, height: height, rgba: ptr, pregraded: pregraded)
        }
    }

    /// Uploads RGBA8 pixels from buffer pointer.
    @discardableResult
    public func upload(key: TextureRef, width: Int, height: Int, rgba: UnsafeRawBufferPointer, pregraded: Bool = false) -> Bool {
        precondition(width >= 1 && height >= 1)
        let bytes = Int64(width * height * 4)
        precondition(Int64(rgba.count) >= bytes)

        var gradedBytes: [UInt8]?
        let sourcePtr = rgba.baseAddress!

        if !pregraded, let g = grader, TileGrader.isGraded(key) {
            var buf = [UInt8](repeating: 0, count: Int(bytes))
            buf.withUnsafeMutableBytes { dst in
                dst.copyMemory(from: UnsafeRawBufferPointer(start: sourcePtr, count: Int(bytes)))
            }
            g.apply(key, &buf)
            gradedBytes = buf
        }

        if let gb = gradedBytes {
            return gb.withUnsafeBytes { ptr in
                uploadPixels(key: key, width: width, height: height, bytes: bytes, rawPointer: ptr.baseAddress!)
            }
        } else {
            return uploadPixels(key: key, width: width, height: height, bytes: bytes, rawPointer: sourcePtr)
        }
    }

    private func uploadPixels(key: TextureRef, width: Int, height: Int, bytes: Int64, rawPointer: UnsafeRawPointer) -> Bool {
        _ = remove(key)
        let dim = Dimensions(width: width, height: height)
        let allocated: Bool
        let tex: MTLTexture

        if var list = spare[dim], !list.isEmpty {
            tex = list.removeLast()
            spare[dim] = list
            spareBytes -= bytes
            tex.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: rawPointer,
                bytesPerRow: width * 4
            )
            recycles += 1
            allocated = false
        } else {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            desc.usage = [.shaderRead]
            desc.storageMode = .shared
            tex = device.makeTexture(descriptor: desc)!
            tex.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: rawPointer,
                bytesPerRow: width * 4
            )
            allocations += 1
            allocated = true
        }

        let node = Node(key: key, texture: tex, width: width, height: height, bytes: bytes)
        map[key] = node
        addToHead(node)
        residentBytes += bytes
        trim()
        return allocated
    }

    /// Pre-creates up to `maxCount` spare textures of `width` x `height`.
    public func prewarm(width: Int, height: Int, maxCount: Int) -> Int {
        let bytes = Int64(width * height * 4)
        var made = 0
        let dim = Dimensions(width: width, height: height)

        let zeros = [UInt8](repeating: 0, count: Int(bytes))
        while made < maxCount && spareBytes + bytes <= spareCapacityBytes {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            desc.usage = [.shaderRead]
            desc.storageMode = .shared
            guard let tex = device.makeTexture(descriptor: desc) else {
                break
            }
            zeros.withUnsafeBytes { ptr in
                tex.replace(
                    region: MTLRegionMake2D(0, 0, width, height),
                    mipmapLevel: 0,
                    withBytes: ptr.baseAddress!,
                    bytesPerRow: width * 4
                )
            }

            var list = spare[dim] ?? []
            list.append(tex)
            spare[dim] = list
            spareBytes += bytes
            allocations += 1
            made += 1
        }
        return made
    }

    /// Evicts `key` from the cache.
    @discardableResult
    public func remove(_ key: TextureRef) -> Bool {
        guard let node = map.removeValue(forKey: key) else {
            return false
        }
        removeNode(node)
        residentBytes -= node.bytes
        retire(node)
        return true
    }

    /// Reads back a resident texture as RGBA8 bytes.
    public func readBack(_ key: TextureRef) -> [UInt8]? {
        guard let node = map[key] else {
            return nil
        }
        var buf = [UInt8](repeating: 0, count: Int(node.bytes))
        buf.withUnsafeMutableBytes { ptr in
            node.texture.getBytes(
                ptr.baseAddress!,
                bytesPerRow: node.width * 4,
                from: MTLRegionMake2D(0, 0, node.width, node.height),
                mipmapLevel: 0
            )
        }
        return buf
    }

    public func clear() {
        map.removeAll()
        head = nil
        tail = nil
        spare.removeAll()
        transitions.removeAll()
        residentBytes = 0
        spareBytes = 0
    }

    private func trim() {
        while residentBytes > capacityBytes, let last = tail, map.count > 1 {
            removeNode(last)
            map.removeValue(forKey: last.key)
            residentBytes -= last.bytes
            evictions += 1
            retire(last)
        }
    }

    private func retire(_ node: Node) {
        if spareBytes + node.bytes > spareCapacityBytes {
            return
        }
        let dim = Dimensions(width: node.width, height: node.height)
        var list = spare[dim] ?? []
        list.append(node.texture)
        spare[dim] = list
        spareBytes += node.bytes
    }

    private func addToHead(_ node: Node) {
        node.next = head
        node.prev = nil
        if let h = head {
            h.prev = node
        }
        head = node
        if tail == nil {
            tail = node
        }
    }

    private func removeNode(_ node: Node) {
        if let prev = node.prev {
            prev.next = node.next
        } else {
            head = node.next
        }
        if let next = node.next {
            next.prev = node.prev
        } else {
            tail = node.prev
        }
        node.prev = nil
        node.next = nil
    }

    private func moveToHead(_ node: Node) {
        if head === node {
            return
        }
        removeNode(node)
        addToHead(node)
    }
}
