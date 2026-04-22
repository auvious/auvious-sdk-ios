//
//  ScreenCapturer.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 21/10/25.
//

import WebRTC
import ReplayKit
import AVFoundation
import Sentry

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

        let crumb = Breadcrumb(level: .info, category: "screen_share")
        crumb.message = "ReplayKit startCapture called"
        crumb.data = ["isAvailable": RPScreenRecorder.shared().isAvailable]
        SentrySDK.addBreadcrumb(crumb)

        var firstFrameReceived = false

        recorder.startCapture(handler: { [weak self] (sampleBuffer, sampleType, error) in
            guard let self = self else { return }
            if let error = error {
                print("❌ ReplayKit error: \(error)")
                SentrySDK.capture(error: error)
                return
            }

            guard sampleType == .video,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
                  CMSampleBufferIsValid(sampleBuffer) else {
                return
            }

            if !firstFrameReceived {
                firstFrameReceived = true
                let width = CVPixelBufferGetWidth(pixelBuffer)
                let height = CVPixelBufferGetHeight(pixelBuffer)
                let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
                let frameCrumb = Breadcrumb(level: .info, category: "screen_share")
                frameCrumb.message = "First screen frame received"
                frameCrumb.data = [
                    "width": width,
                    "height": height,
                    "pixelFormat": String(format: "0x%08X", pixelFormat)
                ]
                SentrySDK.addBreadcrumb(frameCrumb)
            }

            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard pts.isValid else { return }
            let timestampNs = CMTimeGetSeconds(pts) * Double(NSEC_PER_SEC)
            let rtcPixelBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
            let videoFrame = RTCVideoFrame(buffer: rtcPixelBuffer, rotation: ._0, timeStampNs: Int64(timestampNs))

            self.videoSource.capturer(self.capturer, didCapture: videoFrame) // ✅ Pass valid capturer
        }, completionHandler: { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                print("❌ Failed to start ReplayKit capture: \(error)")
                let failCrumb = Breadcrumb(level: .error, category: "screen_share")
                failCrumb.message = "ReplayKit startCapture failed"
                failCrumb.data = ["error": error.localizedDescription]
                SentrySDK.addBreadcrumb(failCrumb)
                SentrySDK.capture(error: error)
                if let completion = self.permissionCompletion {
                    self.permissionCompletion = nil
                    completion(false)
                } else {
                    self.delegate?.onScreenSharingFailed()
                }
            } else {
                print("✅ ReplayKit screen capture started")
                let successCrumb = Breadcrumb(level: .info, category: "screen_share")
                successCrumb.message = "ReplayKit startCapture succeeded"
                SentrySDK.addBreadcrumb(successCrumb)
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
        let crumb = Breadcrumb(level: .info, category: "screen_share")
        crumb.message = "ReplayKit stopCapture called"
        SentrySDK.addBreadcrumb(crumb)

        RPScreenRecorder.shared().stopCapture { error in
            if let error = error {
                print("❌ Failed to stop screen capture: \(error)")
                let failCrumb = Breadcrumb(level: .warning, category: "screen_share")
                failCrumb.message = "ReplayKit stopCapture failed"
                failCrumb.data = ["error": error.localizedDescription]
                SentrySDK.addBreadcrumb(failCrumb)
            } else {
                self.delegate?.onScreenSharingStop()
                print("🛑 Screen capture stopped")
                let stopCrumb = Breadcrumb(level: .info, category: "screen_share")
                stopCrumb.message = "ReplayKit stopCapture succeeded"
                SentrySDK.addBreadcrumb(stopCrumb)
            }
        }
    }
}
