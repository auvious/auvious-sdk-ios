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
}

class ScreenCapturer: NSObject {
    private let videoSource: RTCVideoSource
    private let capturer: RTCVideoCapturer
    
    weak var delegate: ScreenCapturerDelegate?
    
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

            let timestampNs = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * Double(NSEC_PER_SEC)
            let rtcPixelBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
            let videoFrame = RTCVideoFrame(buffer: rtcPixelBuffer, rotation: ._0, timeStampNs: Int64(timestampNs))
            
            self.videoSource.capturer(self.capturer, didCapture: videoFrame) // ✅ Pass valid capturer
        }, completionHandler: { error in
            if let error = error {
                print("❌ Failed to start ReplayKit capture: \(error)")
            } else {
                self.delegate?.onScreenSharingStart()
                print("✅ ReplayKit screen capture started")
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
