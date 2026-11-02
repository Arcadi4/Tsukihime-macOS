import Foundation
import TsukiCore
@testable import TsukiPlatform
import XCTest

final class PlatformTests: XCTestCase {
    // MARK: - FixedStepClock Tests

    func testGridIsDriftFreeOverTenMinutes() {
        let freq: Int64 = 10_000_000
        let start: Int64 = 123_456_789
        let clock = FixedStepClock(frequency: freq, startTimestamp: start)
        var frames: Int64 = 0

        for n in 0...36_000 {
            let due = start + (Int64(n) * freq / 60)
            var tick = LogicTick(frame: 0, nominalTimestamp: 0)

            XCTAssertFalse(clock.tryNextTick(now: due - 1, tick: &tick))
            XCTAssertTrue(clock.tryNextTick(now: due, tick: &tick))
            XCTAssertEqual(Int64(n), tick.frame)
            XCTAssertEqual(due, tick.nominalTimestamp)
            frames += 1
        }

        XCTAssertEqual(36_001, frames)
        XCTAssertEqual(start + (600 * freq), start + clock.stepsToUnits(36_000))
        XCTAssertEqual(0, clock.skippedSteps)
    }

    func testStepReadsNominalTime() {
        let freq: Int64 = 10_000_000
        let start: Int64 = 123_456_789
        let clock = FixedStepClock(frequency: freq, startTimestamp: start)
        var tick = LogicTick(frame: 0, nominalTimestamp: 0)

        XCTAssertTrue(clock.tryNextTick(now: start, tick: &tick))
        let due = start + clock.stepsToUnits(1)
        let late = due + 70_000

        XCTAssertTrue(clock.tryNextTick(now: late, tick: &tick))
        XCTAssertEqual(1, tick.frame)
        XCTAssertEqual(due, tick.nominalTimestamp)
        XCTAssertFalse(clock.tryNextTick(now: late, tick: &tick))
        XCTAssertEqual(start + clock.stepsToUnits(2), clock.nextDueTimestamp)
    }

    // MARK: - WindowFit Tests

    func testWindowFitPresets() {
        XCTAssertTrue(WindowFit.presets.count >= 4)
        XCTAssertEqual(1600, WindowFit.defaultWidth)
        XCTAssertEqual(900, WindowFit.defaultHeight)

        let fits = WindowFit.fits(width: 1280, height: 720, workWidth: 1920, workHeight: 1080)
        XCTAssertTrue(fits)

        let clamped = WindowFit.clamp(width: 2560, height: 1440, workWidth: 1920, workHeight: 1080)
        XCTAssertLessThanOrEqual(clamped.width, WindowFit.maxWidth(workWidth: 1920))
        XCTAssertLessThanOrEqual(clamped.height, WindowFit.maxHeight(workHeight: 1080))
    }

    // MARK: - Viewport Tests

    func testViewportLetterboxing() {
        let vp = Viewport.fit(windowWidth: 1920, windowHeight: 1080)
        XCTAssertEqual(0, vp.x)
        XCTAssertEqual(0, vp.y)
        XCTAssertEqual(1920, vp.width)
        XCTAssertEqual(1080, vp.height)

        let (inside, px, py) = vp.toPointer(x: 960, y: 540)
        XCTAssertTrue(inside)
        XCTAssertEqual(320, px)
        XCTAssertEqual(224, py)
    }

    // MARK: - InputMapper Tests

    func testInputMapperBasic() {
        let mapper = InputMapper()
        let keys = KeySet.of(.enter, .space)
        let pad = PadSnapshot()
        let pointer = PointerSample(x: 100, y: 100, inside: true, held: [], wheel: 0)

        let frame = mapper.map(frame: 0, keys: keys, pad: pad, pointer: pointer)
        XCTAssertTrue(frame.held.contains(.decide))
        XCTAssertTrue(frame.pressed.contains(.decide))

        let nextFrame = mapper.map(frame: 1, keys: keys, pad: pad, pointer: pointer)
        XCTAssertTrue(nextFrame.held.contains(.decide))
        XCTAssertFalse(nextFrame.pressed.contains(.decide))
    }

    // MARK: - AudioOutput Pull Mode Tests

    func testAudioOutputPullMode() {
        final class Counter: @unchecked Sendable {
            var count = 0
        }
        let counter = Counter()
        let output = AudioOutput.createPullOnly { buffer in
            for i in 0..<buffer.count {
                buffer[i] = Float(i) * 0.001
            }
            counter.count += buffer.count / AudioOutput.channels
        }

        var sampleData = [Float](repeating: 0, count: 512 * AudioOutput.channels)
        sampleData.withUnsafeMutableBufferPointer { buf in
            let got = output.pull(buf)
            XCTAssertEqual(512, got)
        }

        XCTAssertEqual(512, counter.count)
        XCTAssertEqual(512, output.framesRendered)
    }
}
