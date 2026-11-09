//
//  PixelBufferCopier.swift
//  AuviousSDK
//
//  Created by Auvious on 15/10/26.
//

import Foundation
import CoreVideo

/**
 Copies captured frames into buffers the SDK owns.

 ReplayKit recycles its capture buffers while WebRTC still encodes them asynchronously. Masking those
 buffers in place lets a newer, unmasked frame be written into a buffer before the encoder reads it,
 so masked frames are always copies.
 */
internal final class PixelBufferCopier {

    private struct PoolKey: Equatable {
        let width: Int
        let height: Int
        let format: OSType
    }

    private var pool: CVPixelBufferPool?
    private var poolKey: PoolKey?
    private let lock = NSLock()

    /// A copy of `source` in a pooled, IOSurface backed buffer, or nil when it can't be copied
    func copy(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }

        let key = PoolKey(width: CVPixelBufferGetWidth(source), height: CVPixelBufferGetHeight(source), format: CVPixelBufferGetPixelFormatType(source))
        if key != poolKey {
            pool = makePool(for: key)
            poolKey = pool == nil ? nil : key
        }

        guard let pool = pool else { return nil }

        var destination: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &destination) == kCVReturnSuccess, let copy = destination else {
            return nil
        }

        guard CVPixelBufferLockBaseAddress(source, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
        guard CVPixelBufferLockBaseAddress(copy, []) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(copy, []) }

        if CVPixelBufferIsPlanar(source) {
            let planes = CVPixelBufferGetPlaneCount(source)
            guard planes == CVPixelBufferGetPlaneCount(copy) else { return nil }
            for plane in 0..<planes {
                guard let from = CVPixelBufferGetBaseAddressOfPlane(source, plane),
                      let to = CVPixelBufferGetBaseAddressOfPlane(copy, plane) else { return nil }
                copyRows(from: from, fromRowBytes: CVPixelBufferGetBytesPerRowOfPlane(source, plane),
                         to: to, toRowBytes: CVPixelBufferGetBytesPerRowOfPlane(copy, plane),
                         rows: CVPixelBufferGetHeightOfPlane(source, plane))
            }
        } else {
            guard let from = CVPixelBufferGetBaseAddress(source), let to = CVPixelBufferGetBaseAddress(copy) else { return nil }
            copyRows(from: from, fromRowBytes: CVPixelBufferGetBytesPerRow(source),
                     to: to, toRowBytes: CVPixelBufferGetBytesPerRow(copy),
                     rows: CVPixelBufferGetHeight(source))
        }

        //Color space and transfer function travel as attachments
        CVBufferPropagateAttachments(source, copy)
        return copy
    }

    private func copyRows(from: UnsafeMutableRawPointer, fromRowBytes: Int, to: UnsafeMutableRawPointer, toRowBytes: Int, rows: Int) {
        if fromRowBytes == toRowBytes {
            memcpy(to, from, fromRowBytes * rows)
            return
        }
        let rowLength = min(fromRowBytes, toRowBytes)
        for row in 0..<rows {
            memcpy(to + row * toRowBytes, from + row * fromRowBytes, rowLength)
        }
    }

    private func makePool(for key: PoolKey) -> CVPixelBufferPool? {
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: key.format,
            kCVPixelBufferWidthKey as String: key.width,
            kCVPixelBufferHeightKey as String: key.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool)
        return pool
    }
}
