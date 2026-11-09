//
//  PixelBufferCopierTests.swift
//  AuviousSDKLogicTests
//
//  Created by Auvious on 15/10/26.
//

import XCTest
import CoreVideo
import CoreMedia

final class PixelBufferCopierTests: XCTestCase {
    
    func testCopiesBothPlanesIntoANewBuffer() throws {
        var source: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary, &source)
        let original = try XCTUnwrap(source)
        
        CVPixelBufferLockBaseAddress(original, [])
        memset(CVPixelBufferGetBaseAddressOfPlane(original, 0)!, 200, CVPixelBufferGetBytesPerRowOfPlane(original, 0) * 16)
        memset(CVPixelBufferGetBaseAddressOfPlane(original, 1)!, 60, CVPixelBufferGetBytesPerRowOfPlane(original, 1) * 8)
        CVPixelBufferUnlockBaseAddress(original, [])
        
        let copy = try XCTUnwrap(PixelBufferCopier().copy(original))
        XCTAssertFalse(copy === original)
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(copy), kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        XCTAssertEqual(CVPixelBufferGetWidth(copy), 16)
        
        //Masking the copy leaves the capture buffer untouched
        XCTAssertTrue(PixelBufferMasker.fill(copy, rects: [CGRect(x: 0, y: 0, width: 16, height: 16)]))
        
        CVPixelBufferLockBaseAddress(original, .readOnly)
        CVPixelBufferLockBaseAddress(copy, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(original, .readOnly)
            CVPixelBufferUnlockBaseAddress(copy, .readOnly)
        }
        XCTAssertEqual(CVPixelBufferGetBaseAddressOfPlane(original, 0)!.load(as: UInt8.self), 200)
        XCTAssertEqual(CVPixelBufferGetBaseAddressOfPlane(original, 1)!.load(as: UInt8.self), 60)
        XCTAssertEqual(CVPixelBufferGetBaseAddressOfPlane(copy, 0)!.load(as: UInt8.self), 16)
        XCTAssertEqual(CVPixelBufferGetBaseAddressOfPlane(copy, 1)!.load(as: UInt8.self), 128)
    }
    
    func testDropsFramesWhenMaskingIsOff() throws {
        var source: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 8, 8, kCVPixelFormatType_32BGRA, nil, &source)
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: source!, formatDescriptionOut: &format)
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMTime(value: 1, timescale: 30), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: source!, formatDescription: format!, sampleTiming: &timing, sampleBufferOut: &sample)
        
        XCTAssertFalse(MaskRegistry.shared.isRunning)
        let output = PixelBufferMasker.maskedFrame(sampleBuffer: sample!, pixelBuffer: source!, registry: MaskRegistry.shared)
        XCTAssertNil(output)
    }
}
