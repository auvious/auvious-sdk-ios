//
//  PixelBufferMasker.swift
//  AuviousSDK
//
//  Created by Auvious on 15/10/26.
//

import Foundation
import CoreMedia
import CoreVideo
import ImageIO
import QuartzCore
import ReplayKit

/**
 Blacks out masked regions directly in the ReplayKit pixel buffers before they reach WebRTC.

 Fails closed: when regions exist but can't be placed reliably (stale snapshot, unknown pixel format,
 ambiguous orientation, buffer not writable) the frame is dropped instead of being sent unmasked.
 */
internal enum PixelBufferMasker {

    /// Snapshots older than this are not trusted
    static let maxSnapshotAge: CFTimeInterval = 0.25

    /// The frame's presentation time on the `CACurrentMediaTime()` clock.
    /// ReplayKit stamps frames with host time; anything implausible falls back to now.
    static func frameTime(of sampleBuffer: CMSampleBuffer, now: CFTimeInterval = CACurrentMediaTime()) -> CFTimeInterval {
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard pts.isValid else { return now }
        let seconds = CMTimeGetSeconds(pts)
        return abs(seconds - now) < 1 ? seconds : now
    }

    /// Frame copies handed to WebRTC (ReplayKit's own buffers are recycled while the encoder still reads them)
    static let copier = PixelBufferCopier()

    /**
     Frame processor for `ScreenCapturer`: returns the frame to send, or nil to drop it.

     While masking runs, the frame is copied into an SDK-owned buffer and the copy is masked with the
     layout around the frame's capture time. ReplayKit's buffer is never modified.
     */
    static func maskedFrame(sampleBuffer: CMSampleBuffer, pixelBuffer: CVPixelBuffer, registry: MaskRegistry) -> CVPixelBuffer? {
        guard registry.isRunning else {
            return pixelBuffer
        }

        let time = frameTime(of: sampleBuffer)
        #if DEBUG
        latencyMeter.record(sampleBuffer: sampleBuffer)
        #endif

        //Nothing recorded for that moment: we can't tell what the frame shows
        guard let snapshot = registry.snapshot(forFrameAt: time), let copy = copier.copy(pixelBuffer) else {
            return nil
        }

        //Stale when the layout hasn't been read for a while around this frame (e.g. main thread stalled)
        return process(sampleBuffer: sampleBuffer, pixelBuffer: copy, snapshot: snapshot, now: time) ? copy : nil
    }

    /// Frame processor for `ScreenCapturer`. Returns false to drop the frame.
    static func process(sampleBuffer: CMSampleBuffer, pixelBuffer: CVPixelBuffer, snapshot: MaskSnapshot, now: CFTimeInterval = CACurrentMediaTime()) -> Bool {
        //Masked content is moving in a screen transition: hold the last frame instead
        guard !snapshot.isUnsafe else {
            return false
        }

        guard !snapshot.rects.isEmpty else {
            return true
        }

        guard now - snapshot.timestamp <= maxSnapshotAge else {
            return false
        }

        guard let rects = pixelRects(for: snapshot.rects,
                                     screenSize: snapshot.screenSize,
                                     bufferSize: CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer)),
                                     orientation: sampleOrientation(sampleBuffer)) else {
            return false
        }

        return fill(pixelBuffer, rects: rects)
    }

    /// The rotation ReplayKit attached to the sample, if any
    static func sampleOrientation(_ sampleBuffer: CMSampleBuffer) -> CGImagePropertyOrientation? {
        guard let value = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber else {
            return nil
        }
        return CGImagePropertyOrientation(rawValue: value.uint32Value)
    }

    /**
     Maps screen point rects to integral buffer pixel rects.

     `orientation` describes how the buffer must be rotated to appear upright (EXIF semantics), e.g. `.right`
     means buffer row 0 is the screen's right edge and buffer column 0 is the screen's top edge.
     Returns nil when the mapping is ambiguous.
     */
    static func pixelRects(for rects: [CGRect], screenSize: CGSize, bufferSize: CGSize, orientation: CGImagePropertyOrientation?) -> [CGRect]? {
        guard screenSize.width > 0, screenSize.height > 0, bufferSize.width > 0, bufferSize.height > 0 else {
            return nil
        }

        let screenIsLandscape = screenSize.width > screenSize.height
        let bufferIsLandscape = bufferSize.width > bufferSize.height

        var effectiveOrientation = orientation ?? .up
        if screenIsLandscape != bufferIsLandscape && (effectiveOrientation == .up || effectiveOrientation == .down) {
            //Rotated buffer without rotation info: we can't tell which way, drop the frame
            return nil
        }
        if orientation == nil {
            effectiveOrientation = .up
        }

        let isRotated: Bool
        switch effectiveOrientation {
        case .up, .down:
            isRotated = false
        case .left, .right:
            isRotated = true
        default:
            //Mirrored orientations are not produced by screen capture
            return nil
        }

        //Size of the upright image, in buffer pixels
        let displayWidth = isRotated ? bufferSize.height : bufferSize.width
        let displayHeight = isRotated ? bufferSize.width : bufferSize.height
        let sx = displayWidth / screenSize.width
        let sy = displayHeight / screenSize.height
        let bufferBounds = CGRect(origin: .zero, size: bufferSize)

        var result: [CGRect] = []
        for rect in rects {
            let d = CGRect(x: rect.minX * sx, y: rect.minY * sy, width: rect.width * sx, height: rect.height * sy)

            let mapped: CGRect
            switch effectiveOrientation {
            case .down:
                mapped = CGRect(x: displayWidth - d.maxX, y: displayHeight - d.maxY, width: d.width, height: d.height)
            case .right:
                mapped = CGRect(x: d.minY, y: displayWidth - d.maxX, width: d.height, height: d.width)
            case .left:
                mapped = CGRect(x: displayHeight - d.maxY, y: d.minX, width: d.height, height: d.width)
            default:
                mapped = d
            }

            //Expand outwards to whole, even pixels (chroma is subsampled 2x2)
            let minX = floor(mapped.minX / 2) * 2
            let minY = floor(mapped.minY / 2) * 2
            let maxX = ceil(mapped.maxX / 2) * 2
            let maxY = ceil(mapped.maxY / 2) * 2
            let clamped = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).intersection(bufferBounds)
            if !clamped.isNull && !clamped.isEmpty {
                result.append(clamped)
            }
        }
        return result
    }

    /// Writes black into the given pixel rects. Returns false when the buffer can't be written.
    static func fill(_ pixelBuffer: CVPixelBuffer, rects: [CGRect]) -> Bool {
        guard !rects.isEmpty else { return true }

        guard CVPixelBufferLockBaseAddress(pixelBuffer, []) == kCVReturnSuccess else {
            return false
        }
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        }

        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        switch format {
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            guard CVPixelBufferGetPlaneCount(pixelBuffer) >= 2,
                  let luma = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
                  let chroma = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else {
                return false
            }

            let black: Int32 = format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ? 16 : 0
            let lumaRowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let lumaWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
            let lumaHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
            let chromaRowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
            let chromaHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
            let chromaWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)

            for rect in rects {
                let x0 = max(0, Int(rect.minX)), x1 = min(lumaWidth, Int(rect.maxX))
                let y0 = max(0, Int(rect.minY)), y1 = min(lumaHeight, Int(rect.maxY))
                guard x1 > x0, y1 > y0 else { continue }

                for y in y0..<y1 {
                    memset(luma + y * lumaRowBytes + x0, black, x1 - x0)
                }

                //Interleaved CbCr at half resolution: neutral chroma (128, 128)
                let cx0 = x0 / 2, cx1 = min(chromaWidth, (x1 + 1) / 2)
                let cy0 = y0 / 2, cy1 = min(chromaHeight, (y1 + 1) / 2)
                guard cx1 > cx0, cy1 > cy0 else { continue }
                for y in cy0..<cy1 {
                    memset(chroma + y * chromaRowBytes + cx0 * 2, 128, (cx1 - cx0) * 2)
                }
            }
            return true

        case kCVPixelFormatType_32BGRA:
            guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
                return false
            }
            let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)

            //B, G, R, A = 0, 0, 0, 255 in memory
            let opaqueBlack = UInt32(0xFF00_0000)
            for rect in rects {
                let x0 = max(0, Int(rect.minX)), x1 = min(width, Int(rect.maxX))
                let y0 = max(0, Int(rect.minY)), y1 = min(height, Int(rect.maxY))
                guard x1 > x0, y1 > y0 else { continue }

                for y in y0..<y1 {
                    let row = (base + y * rowBytes + x0 * 4).assumingMemoryBound(to: UInt32.self)
                    row.initialize(repeating: opaqueBlack, count: x1 - x0)
                }
            }
            return true

        default:
            return false
        }
    }
}

#if DEBUG
extension PixelBufferMasker {
    
    /// Debug builds log how late ReplayKit frames arrive compared to their timestamp, to tune `MaskHistory`
    static let latencyMeter = CaptureLatencyMeter()
}

/// Prints the delay between a frame's presentation timestamp and its delivery, every 2 seconds
internal final class CaptureLatencyMeter {
    
    private let lock = NSLock()
    private var samples: [CFTimeInterval] = []
    private var foreignClockFrames = 0
    private var windowStart: CFTimeInterval = 0
    
    func record(sampleBuffer: CMSampleBuffer, now: CFTimeInterval = CACurrentMediaTime()) {
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard pts.isValid else { return }
        let delay = now - CMTimeGetSeconds(pts)
        
        lock.lock()
        defer { lock.unlock() }
        
        if abs(delay) < 1 {
            samples.append(delay)
        } else {
            foreignClockFrames += 1
        }
        
        if windowStart == 0 {
            windowStart = now
        }
        guard now - windowStart >= 2 else { return }
        
        let sorted = samples.sorted()
        if let max = sorted.last {
            let average = sorted.reduce(0, +) / Double(sorted.count)
            let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
            print(String(format: "[Auvious masking] frame delay over %d frames: avg %.1f ms, p95 %.1f ms, max %.1f ms (window %.0f ms back / %.0f ms ahead)",
                         sorted.count, average * 1000, p95 * 1000, max * 1000, MaskHistory.lookBehind * 1000, MaskHistory.lookAhead * 1000))
        }
        if foreignClockFrames > 0 {
            print("[Auvious masking] \(foreignClockFrames) frames had timestamps on another clock; they were matched to the current time")
        }
        samples.removeAll(keepingCapacity: true)
        foreignClockFrames = 0
        windowStart = now
    }
}
#endif
