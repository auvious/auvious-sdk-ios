//
//  MaskHistoryTests.swift
//  AuviousSDKLogicTests
//
//  Created by Auvious on 15/10/26.
//

import XCTest
import CoreMedia

final class MaskHistoryTests: XCTestCase {

    private let screen = CGSize(width: 390, height: 844)

    /// A field scrolling up 10pt every 1/60 s, starting at y = 500
    private func scrollingHistory(from start: CFTimeInterval, frames: Int) -> MaskHistory {
        var history = MaskHistory()
        for frame in 0..<frames {
            let y = 500 - CGFloat(frame) * 10
            history.append(MaskSnapshot(rects: [CGRect(x: 20, y: y, width: 350, height: 48)], screenSize: screen, timestamp: start + Double(frame) / 60))
        }
        return history
    }

    func testCoversEveryPositionAroundTheFrameTime() throws {
        let history = scrollingHistory(from: 10, frames: 60)

        //A frame stamped 0.5 s in, while the latest layout is already 0.48 s further
        let snapshot = try XCTUnwrap(history.snapshot(forFrameAt: 10.5))
        let ys = snapshot.rects.map { $0.minY }

        //Field position at 10.5 s is y = 500 - 30 * 10 = 200; positions up to lookBehind earlier must be masked too
        XCTAssertTrue(ys.contains(200))
        XCTAssertTrue(ys.contains(200 + CGFloat(Int(MaskHistory.lookBehind * 60)) * 10), "Layout up to lookBehind before the frame")
        XCTAssertFalse(ys.contains(500 - 59 * 10), "Not the latest layout, it is far ahead of this frame")
    }

    func testIncludesTheLayoutShownWhenTheWindowOpened() throws {
        var history = MaskHistory()
        //Layout changed once, long before the frame, and was then stable
        history.append(MaskSnapshot(rects: [CGRect(x: 0, y: 100, width: 10, height: 10)], screenSize: screen, timestamp: 1))

        let snapshot = try XCTUnwrap(history.snapshot(forFrameAt: 1.9))
        XCTAssertEqual(snapshot.rects, [CGRect(x: 0, y: 100, width: 10, height: 10)])
        XCTAssertEqual(snapshot.timestamp, 1, "Old, so the masker treats it as stale")
    }

    func testFramesOlderThanTheHistoryAreUnknown() {
        let history = scrollingHistory(from: 10, frames: 10)
        XCTAssertNil(history.snapshot(forFrameAt: 9))
        XCTAssertNil(MaskHistory().snapshot(forFrameAt: 10))
    }

    func testDropsSnapshotsPastRetention() {
        let history = scrollingHistory(from: 0, frames: 180)
        let oldest = history.snapshots.first?.timestamp ?? 0
        let newest = history.snapshots.last?.timestamp ?? 0
        XCTAssertLessThanOrEqual(newest - oldest, MaskHistory.retention + 0.0001)
    }

    func testScrollingFrameStaysMaskedEndToEnd() throws {
        //The masker places the union of positions, so the field's real position in the frame is always black
        let history = scrollingHistory(from: 10, frames: 60)
        let snapshot = try XCTUnwrap(history.snapshot(forFrameAt: 10.5))
        let rects = try XCTUnwrap(PixelBufferMasker.pixelRects(for: snapshot.rects, screenSize: screen, bufferSize: CGSize(width: 1170, height: 2532), orientation: nil))

        let fieldInFrame = CGRect(x: 60, y: 600, width: 1050, height: 144)
        XCTAssertTrue(rects.contains { $0.contains(fieldInFrame) })
    }

    func testFramesDuringAScreenTransitionAreDropped() throws {
        var history = MaskHistory()
        let field = [CGRect(x: 20, y: 300, width: 350, height: 48)]
        history.append(MaskSnapshot(rects: field, screenSize: screen, timestamp: 10))
        history.append(MaskSnapshot(rects: field, screenSize: screen, timestamp: 10.016, isUnsafe: true))
        //Snapshots keep coming every refresh once the transition settles
        for frame in 1...24 {
            history.append(MaskSnapshot(rects: field, screenSize: screen, timestamp: 10.016 + Double(frame) / 60))
        }

        let during = try XCTUnwrap(history.snapshot(forFrameAt: 10.02))
        XCTAssertTrue(during.isUnsafe)

        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, kCVPixelFormatType_32BGRA, nil, &buffer)
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer!, formatDescriptionOut: &format)
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMTime(seconds: 10.02, preferredTimescale: 1000), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer!, formatDescription: format!, sampleTiming: &timing, sampleBufferOut: &sample)
        XCTAssertFalse(PixelBufferMasker.process(sampleBuffer: sample!, pixelBuffer: buffer!, snapshot: during, now: 10.02))

        //Once the transition is over, frames are masked normally again
        let after = try XCTUnwrap(history.snapshot(forFrameAt: 10.4))
        XCTAssertFalse(after.isUnsafe)
    }

    func testFrameTimeFallsBackToNowForForeignClocks() throws {
        var format: CMVideoFormatDescription?
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 4, 4, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer!, formatDescriptionOut: &format)

        func sample(at seconds: Double) -> CMSampleBuffer {
            var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 1_000_000_000), decodeTimeStamp: .invalid)
            var buffer: CMSampleBuffer?
            CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer!, formatDescription: format!, sampleTiming: &timing, sampleBufferOut: &buffer)
            return buffer!
        }

        XCTAssertEqual(PixelBufferMasker.frameTime(of: sample(at: 99.95), now: 100), 99.95, accuracy: 0.0001)
        XCTAssertEqual(PixelBufferMasker.frameTime(of: sample(at: 3), now: 100), 100)
    }
}
