import XCTest
import Metal
import TsukiCore
import TsukiEngine
@testable import TsukiRender

final class RenderTests: XCTestCase {
    func testStecTables() {
        let flags = [Int32](repeating: 0x100, count: StecTables.count)
        let wb = [Int32](repeating: 10, count: StecTables.count)
        let wr = [Int32](repeating: 20, count: StecTables.count)
        var luts = [UInt8](repeating: 0, count: StecTables.count * 3 * 256)
        luts[0] = 42

        let tables = StecTables(flags: flags, weightBlue: wb, weightRed: wr, luts: luts)
        XCTAssertEqual(tables.flags(1), 0x100)
        XCTAssertEqual(tables.weightBlue(1), 10)
        XCTAssertEqual(tables.weightRed(1), 20)
        XCTAssertEqual(tables.lut(1, 0)[0], 42)
    }

    func testStecKernelBrightnessAndContrast() {
        var bLut = [UInt8](repeating: 0, count: 256)
        StecKernel.brightnessLut(0, &bLut)
        XCTAssertEqual(bLut[0], 0)
        XCTAssertEqual(bLut[128], 128)
        XCTAssertEqual(bLut[255], 255)

        StecKernel.brightnessLut(10, &bLut)
        XCTAssertEqual(bLut[0], 10)
        XCTAssertEqual(bLut[250], 255)

        var cLut = [UInt8](repeating: 0, count: 256)
        StecKernel.contrastLut(0, &cLut)
        XCTAssertEqual(cLut[0], 0)
        XCTAssertEqual(cLut[128], 128)
        XCTAssertEqual(cLut[255], 255)
    }

    func testTileGrader() {
        XCTAssertFalse(TileGrader.isGraded(TextureRef.none))
        let plainPic = TextureRef.pictureTile(archive: 0, entry: 1, tile: 2, colourEffect: 0)
        XCTAssertFalse(TileGrader.isGraded(plainPic))
        let gradedPic = TextureRef.pictureTile(archive: 0, entry: 1, tile: 2, colourEffect: 5)
        XCTAssertTrue(TileGrader.isGraded(gradedPic))
    }

    func testDrawEffectDecode() {
        let e0 = DrawEffect.decode(0)
        XCTAssertEqual(e0.e, 0)
        XCTAssertEqual(e0.blendState, 1)

        let e52 = DrawEffect.decode(52)
        XCTAssertEqual(e52.e, 52)
        XCTAssertEqual(e52.blendState, 2)

        let e56 = DrawEffect.decode(56)
        XCTAssertEqual(e56.e, 56)
        XCTAssertEqual(e56.blendState, 11)
    }

    func testTransitionParams() {
        let tp = TransitionParams.forRule(0.5)
        XCTAssertLessThanOrEqual(tp.lo, tp.hi)
    }

    func testFadsNumbers() {
        XCTAssertEqual(Fads.crossfadeAlphaByte(0.0), 0)
        XCTAssertEqual(Fads.crossfadeAlphaByte(1.0), 255)
        XCTAssertEqual(Fads.crossfadeAlphaByte(0.5), 127)
    }

    func testStagingPool() {
        let pool = StagingPool(budgetBytes: 1024)
        let b1 = pool.rent(size: 256)
        XCTAssertEqual(b1.length, 256)
        XCTAssertEqual(pool.outstandingBytes, 256)
        pool.returnBuffer(b1)
        XCTAssertEqual(pool.outstandingBytes, 0)
    }

    func testRenderSmoke() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available")
        }
        let smoke = try RenderSmoke.render(device: device)
        XCTAssertEqual(smoke.mismatches, 0, "Smoke render should match expected target pixels")
        XCTAssertEqual(smoke.pixels.count, RenderSmoke.width * RenderSmoke.height * 4)
    }

    func testMetalCompositorClearAndRead() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available")
        }
        let compositor = try MetalCompositor(device: device, width: 64, height: 64)
        compositor.beginFrame()
        compositor.clear(target: 0, r: 255, g: 0, b: 0, a: 255)
        compositor.endFrame()

        let pixels = compositor.readTarget(0)
        XCTAssertEqual(pixels.count, 64 * 64 * 4)
        // Check top-left pixel is Red (255, 0, 0, 255)
        XCTAssertEqual(pixels[0], 255)
        XCTAssertEqual(pixels[1], 0)
        XCTAssertEqual(pixels[2], 0)
        XCTAssertEqual(pixels[3], 255)
    }

    func testTextureCacheLRU() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available")
        }
        let cache = TextureCache(device: device, capacityBytes: 1024, spareCapacityBytes: 2048)
        let key1 = TextureRef.pictureTile(archive: 0, entry: 0, tile: 1)
        let key2 = TextureRef.pictureTile(archive: 0, entry: 0, tile: 2)

        let pixels = [UInt8](repeating: 255, count: 16 * 16 * 4) // 1024 bytes
        _ = cache.upload(key: key1, width: 16, height: 16, rgba: pixels)
        let alloc2 = cache.upload(key: key2, width: 16, height: 16, rgba: pixels)
        XCTAssertTrue(alloc2, "First overflow allocates before trim moves evicted to spare")
        XCTAssertTrue(cache.contains(key2))
        XCTAssertFalse(cache.contains(key1), "key1 should be evicted by trim()")

        // Uploading third 1024-byte texture should recycle evicted key1 from spare
        let key3 = TextureRef.pictureTile(archive: 0, entry: 0, tile: 3)
        let alloc3 = cache.upload(key: key3, width: 16, height: 16, rgba: pixels)
        XCTAssertFalse(alloc3, "Should recycle evicted texture from spare pool")
        XCTAssertTrue(cache.contains(key3))
        XCTAssertFalse(cache.contains(key1))
    }

    func testDisplayListExecutor() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available")
        }
        let compositor = try MetalCompositor(device: device, width: 64, height: 64)
        let cache = TextureCache(device: device)
        let executor = DisplayListExecutor(compositor: compositor, textures: cache)

        let list = DisplayList()
        list.add(DrawCommand(
            kind: .clear,
            target: 0,
            v0: Vertex(x: 0, y: 0, u: 0, v: 0, rgba: 0xFF0000FF)
        ))
        list.seal()

        let stats = executor.execute(list)
        XCTAssertEqual(stats.commands, 1)
        let pixels = compositor.readTarget(0)
        XCTAssertEqual(pixels[0], 255) // R
        XCTAssertEqual(pixels[3], 255) // A
    }
}
