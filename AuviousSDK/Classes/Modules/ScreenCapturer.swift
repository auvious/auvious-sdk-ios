//
//  ScreenCapturer.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 21/10/25.
//

import WebRTC
import ReplayKit
import AVFoundation

protocol ScreenCapturerDelegate: class {
    func onScreenSharingStart()
    func onScreenSharingStop()
    func onScreenSharingFailed()
}

class ScreenCapturer: NSObject {
    private let videoSource: RTCVideoSource
    private let capturer: RTCVideoCapturer

    weak var delegate: ScreenCapturerDelegate?

    /// If set, called with true/false when the ReplayKit permission dialog resolves.
    /// When set, `onScreenSharingStart` is NOT called on success (deferred to the caller).
    var permissionCompletion: ((Bool) -> Void)?

    init(videoSource: RTCVideoSource) {
        self.videoSource = videoSource
        self.capturer = RTCVideoCapturer(delegate: videoSource) // <- create dummy capturer
        super.init()
    }

    func start() {
        let recorder = RPScreenRecorder.shared()
        recorder.isMicrophoneEnabled = false

        recorder.startCapture(handler: { [weak self] (sampleBuffer, sampleType, error) in
            guard let self = self else { return }
            guard error == nil else {
                print("❌ ReplayKit error: \(error!)")
                return
            }

            guard sampleType == .video,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
                  CMSampleBufferIsValid(sampleBuffer) else {
                return
            }

            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard CMTimeIsValid(pts) else { return }
            let timestampNs = CMTimeGetSeconds(pts) * Double(NSEC_PER_SEC)
            let rtcPixelBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
            let videoFrame = RTCVideoFrame(buffer: rtcPixelBuffer, rotation: ._0, timeStampNs: Int64(timestampNs))

            self.videoSource.capturer(self.capturer, didCapture: videoFrame) // ✅ Pass valid capturer
        }, completionHandler: { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                print("❌ Failed to start ReplayKit capture: \(error)")
                if let completion = self.permissionCompletion {
                    self.permissionCompletion = nil
                    completion(false)
                } else {
                    self.delegate?.onScreenSharingFailed()
                }
            } else {
                print("✅ ReplayKit screen capture started")
                if let completion = self.permissionCompletion {
                    self.permissionCompletion = nil
                    completion(true)
                } else {
                    self.delegate?.onScreenSharingStart()
                }
            }
        })
    }

    func stop() {
        RPScreenRecorder.shared().stopCapture { error in
            if let error = error {
                print("❌ Failed to stop screen capture: \(error)")
            } else {
                self.delegate?.onScreenSharingStop()
                print("🛑 Screen capture stopped")
            }
        }
    }
}
