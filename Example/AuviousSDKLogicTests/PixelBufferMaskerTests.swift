//
//  PixelBufferMaskerTests.swift
//  AuviousSDKLogicTests
//
//  Created by Auvious on 15/10/26.
//

import XCTest
import CoreMedia
import CoreVideo

final class PixelBufferMaskerTests: XCTestCase {

    //MARK: Mapping

    func testMapsUprightScreenPointsToPixels() {
        let rects = PixelBufferMasker.pixelRects(for: [CGRect(x: 20, y: 94, width: 350, height: 48)],
                                                 screenSize: CGSize(width: 390, height: 844),
                                                 bufferSize: CGSize(width: 1170, height: 2532),
                                                 orientation: nil)
        XCTAssertEqual(rects, [CGRect(x: 60, y: 282, width: 1050, height: 144)])
    }

    func testExpandsToEvenPixelsAndClampsToTheBuffer() {
        let rects = PixelBufferMasker.pixelRects(for: [CGRect(x: -10, y: 0.4, width: 30, height: 10)],
                                                 screenSize: CGSize(width: 100, height: 100),
                                                 bufferSize: CGSize(width: 100, height: 100),
                                                 orientation: .up)
        XCTAssertEqual(rects, [CGRect(x: 0, y: 0, width: 20, height: 12)])
    }

    func testMapsRotatedBuffers() {
        //Landscape screen delivered as a portrait buffer that must be rotated 90° clockwise
        let right = PixelBufferMasker.pixelRects(for: [CGRect(x: 0, y: 0, width: 100, height: 50)],
                                                 screenSize: CGSize(width: 844, height: 390),
                                                 bufferSize: CGSize(width: 1170, height: 2532),
                                                 orientation: .right)
        XCTAssertEqual(right, [CGRect(x: 0, y: 2232, width: 150, height: 300)])

        let left = PixelBufferMasker.pixelRects(for: [CGRect(x: 0, y: 0, width: 100, height: 50)],
                                                screenSize: CGSize(width: 844, height: 390),
                                                bufferSize: CGSize(width: 1170, height: 2532),
                                                orientation: .left)
        XCTAssertEqual(left, [CGRect(x: 1020, y: 0, width: 150, height: 300)])
    }

    func testRefusesAmbiguousRotation() {
        XCTAssertNil(PixelBufferMasker.pixelRects(for: [CGRect(x: 0, y: 0, width: 10, height: 10)],
                                                  screenSize: CGSize(width: 844, height: 390),
                                                  bufferSize: CGSize(width: 1170, height: 2532),
                                                  orientation: nil))
    }

    //MARK: Filling

    func testBlacksOutBiPlanarYUV() throws {
        let buffer = try makeBuffer(format: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, width: 16, height: 16)
        fillPlanes(buffer, luma: 200, chroma: 50)

        XCTAssertTrue(PixelBufferMasker.fill(buffer, rects: [CGRect(x: 4, y: 4, width: 8, height: 8)]))

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let luma = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)!.assumingMemoryBound(to: UInt8.self)
        let lumaRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let chroma = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)!.assumingMemoryBound(to: UInt8.self)
        let chromaRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)

        XCTAssertEqual(luma[5 * lumaRow + 5], 16, "Video range black")
        XCTAssertEqual(luma[11 * lumaRow + 11], 16)
        XCTAssertEqual(luma[3 * lumaRow + 3], 200, "Outside the rect is untouched")
        XCTAssertEqual(luma[12 * lumaRow + 12], 200)
        XCTAssertEqual(chroma[3 * chromaRow + 2 * 3], 128, "Neutral chroma inside")
        XCTAssertEqual(chroma[3 * chromaRow + 2 * 3 + 1], 128)
        XCTAssertEqual(chroma[0], 50, "Chroma outside is untouched")
    }

    func testBlacksOutBGRA() throws {
        let buffer = try makeBuffer(format: kCVPixelFormatType_32BGRA, width: 8, height: 8)
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer)!, 255, CVPixelBufferGetDataSize(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])

        XCTAssertTrue(PixelBufferMasker.fill(buffer, rects: [CGRect(x: 2, y: 2, width: 2, height: 2)]))

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let row = CVPixelBufferGetBytesPerRow(buffer)
        let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let inside = 2 * row + 2 * 4
        XCTAssertEqual([bytes[inside], bytes[inside + 1], bytes[inside + 2], bytes[inside + 3]], [0, 0, 0, 255])
        XCTAssertEqual(bytes[0], 255)
    }

    func testUnknownPixelFormatFailsClosed() throws {
        let buffer = try makeBuffer(format: kCVPixelFormatType_32ARGB, width: 8, height: 8)
        XCTAssertFalse(PixelBufferMasker.fill(buffer, rects: [CGRect(x: 0, y: 0, width: 2, height: 2)]))
    }

    //MARK: Frame decisions

    func testPassesFramesThroughWhenNothingIsMasked() throws {
        let buffer = try makeBuffer(format: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, width: 16, height: 16)
        let sample = try makeSample(buffer)
        XCTAssertTrue(PixelBufferMasker.process(sampleBuffer: sample, pixelBuffer: buffer, snapshot: .empty))
    }

    func testDropsFramesWhenTheSnapshotIsStale() throws {
        let buffer = try makeBuffer(format: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, width: 16, height: 16)
        let sample = try makeSample(buffer)
        let snapshot = MaskSnapshot(rects: [CGRect(x: 0, y: 0, width: 4, height: 4)], screenSize: CGSize(width: 16, height: 16), timestamp: 10)

        XCTAssertTrue(PixelBufferMasker.process(sampleBuffer: sample, pixelBuffer: buffer, snapshot: snapshot, now: 10.1))
        XCTAssertFalse(PixelBufferMasker.process(sampleBuffer: sample, pixelBuffer: buffer, snapshot: snapshot, now: 10.5))
    }

    //MARK: Helpers

    private func makeBuffer(format: OSType, width: Int, height: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, format, attributes, &buffer)
        guard status == kCVReturnSuccess, let result = buffer else {
            throw NSError(domain: "PixelBufferMaskerTests", code: Int(status))
        }
        return result
    }

    private func fillPlanes(_ buffer: CVPixelBuffer, luma: Int32, chroma: Int32) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        memset(CVPixelBufferGetBaseAddressOfPlane(buffer, 0)!, luma, CVPixelBufferGetBytesPerRowOfPlane(buffer, 0) * CVPixelBufferGetHeightOfPlane(buffer, 0))
        memset(CVPixelBufferGetBaseAddressOfPlane(buffer, 1)!, chroma, CVPixelBufferGetBytesPerRowOfPlane(buffer, 1) * CVPixelBufferGetHeightOfPlane(buffer, 1))
    }

    private func makeSample(_ buffer: CVPixelBuffer) throws -> CMSampleBuffer {
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &format)
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMTime(value: 1, timescale: 30), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescription: format!, sampleTiming: &timing, sampleBufferOut: &sample)
        guard let result = sample else {
            throw NSError(domain: "PixelBufferMaskerTests", code: -1)
        }
        return result
    }
}
