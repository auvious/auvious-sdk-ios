//
//  FakeSFU.swift
//  AuviousSDK Tests
//
//  The server side of a stream, in the test process: a peer connection of its own that answers
//  the SDK's offers, receiving what the SDK publishes or sending to a stream the SDK views.
//  Host candidates only, so nothing leaves the machine.
//

import Foundation
import CoreVideo
import QuartzCore
import WebRTC
import XCTest

final class FakeSFU: NSObject, RTCPeerConnectionDelegate {

    private static let factory: RTCPeerConnectionFactory = {
        let factory = RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(),
                                               decoderFactory: RTCDefaultVideoDecoderFactory())
        factory.setOptions(FakeSFU.loopbackOnly)
        return factory
    }()

    /// Candidates on 127.0.0.1/::1 only. The Mac's firewall (stealth mode) silently drops UDP to an
    /// unsigned app on the LAN address, and nothing should depend on the machine's network anyway.
    /// Set on RTCModule's factory as well, before it creates connections.
    static var loopbackOnly: RTCPeerConnectionFactoryOptions {
        let options = RTCPeerConnectionFactoryOptions()
        options.ignoreLoopbackNetworkAdapter = false
        options.ignoreWiFiNetworkAdapter = true
        options.ignoreEthernetNetworkAdapter = true
        options.ignoreCellularNetworkAdapter = true
        options.ignoreVPNNetworkAdapter = true
        return options
    }

    private(set) var connection: RTCPeerConnection!
    private var capturers: [SyntheticCapturer] = []
    private var onGatheringComplete: (() -> Void)?

    /// Called on the main queue for each track the SDK sends.
    var onTrack: ((RTCRtpReceiver) -> Void)?
    /// Called on the main queue on every connection (ICE + DTLS) state change.
    var onConnectionState: ((RTCPeerConnectionState) -> Void)?

    override init() {
        super.init()
        let configuration = RTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan
        configuration.continualGatheringPolicy = .gatherOnce
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        connection = FakeSFU.factory.peerConnection(with: configuration, constraints: constraints, delegate: self)
    }

    func makeAudioTrack() -> RTCAudioTrack {
        return FakeSFU.factory.audioTrack(withTrackId: "sfu-audio")
    }

    /// A video track fed by a synthetic camera (the simulator has none).
    func makeVideoTrack() -> RTCVideoTrack {
        let source = FakeSFU.factory.videoSource()
        let capturer = SyntheticCapturer(delegate: source)
        capturer.start()
        capturers.append(capturer)
        return FakeSFU.factory.videoTrack(with: source, trackId: "sfu-video")
    }

    /// Answers `offer`, sending `tracks` in the streams `streamIds`. The answer is passed on (main queue)
    /// once ICE gathering is complete, so it carries all of this side's candidates and none trickle back.
    func answer(_ offer: String, sending tracks: [RTCMediaStreamTrack], streamIds: [String],
                completion: @escaping (_ answer: String?, _ error: Error?) -> Void) {
        let done: (String?, Error?) -> Void = { answer, error in
            DispatchQueue.main.async { completion(answer, error) }
        }
        connection.setRemoteDescription(RTCSessionDescription(type: .offer, sdp: offer)) { [weak self] error in
            guard let self = self else { return }
            if let error = error { return done(nil, error) }
            for track in tracks where self.connection.add(track, streamIds: streamIds) == nil {
                return done(nil, NSError(domain: "FakeSFU", code: 1, userInfo: [NSLocalizedDescriptionKey: "add \(track.kind) track failed"]))
            }
            let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            self.connection.answer(for: constraints) { sdp, error in
                guard let sdp = sdp else { return done(nil, error) }
                DispatchQueue.main.async {
                    self.onGatheringComplete = { done(self.connection.localDescription?.sdp, nil) }
                    self.connection.setLocalDescription(sdp) { error in
                        if let error = error { done(nil, error) }
                    }
                }
            }
        }
    }

    /// The SDK's trickled candidates.
    func addRemoteCandidates(_ candidates: [RTCIceCandidate]) {
        for candidate in candidates {
            connection.add(candidate) { error in
                if let error = error { NSLog("FakeSFU: candidate rejected: %@", error.localizedDescription) }
            }
        }
    }

    func close() {
        // Holds this SFU until gathering completes, which a timed-out test may never see.
        onGatheringComplete = nil
        capturers.forEach { $0.stop() }
        connection.close()
    }

    // MARK: RTCPeerConnectionDelegate (called on WebRTC's signaling thread)

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        DispatchQueue.main.async { self.onTrack?(rtpReceiver) }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        DispatchQueue.main.async { self.onConnectionState?(newState) }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        guard newState == .complete else { return }
        DispatchQueue.main.async {
            let complete = self.onGatheringComplete
            self.onGatheringComplete = nil
            complete?()
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}

/// A camera that delivers a grey 320x240 frame at 15 fps.
final class SyntheticCapturer: RTCVideoCapturer {

    private let queue = DispatchQueue(label: "SyntheticCapturer")
    private var timer: DispatchSourceTimer?

    func start(width: Int = 320, height: Int = 240, fps: Double = 15) {
        var pixelBuffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, attributes, &pixelBuffer)
        guard let buffer = pixelBuffer else { return }
        CVPixelBufferLockBaseAddress(buffer, [])
        for plane in 0..<CVPixelBufferGetPlaneCount(buffer) {
            memset(CVPixelBufferGetBaseAddressOfPlane(buffer, plane), 128,
                   CVPixelBufferGetBytesPerRowOfPlane(buffer, plane) * CVPixelBufferGetHeightOfPlane(buffer, plane))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1.0 / fps)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            let frame = RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: buffer), rotation: ._0,
                                      timeStampNs: Int64(CACurrentMediaTime() * 1_000_000_000))
            self.delegate?.capturer(self, didCapture: frame)
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }
}

/// Counts the frames rendered from a track and fulfils `reached` at `target`.
final class FrameCounter: NSObject, RTCVideoRenderer {

    private let lock = NSLock()
    private var count = 0
    private let target: Int
    private let reached: XCTestExpectation

    init(target: Int, reached: XCTestExpectation) {
        self.target = target
        self.reached = reached
    }

    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: RTCVideoFrame?) {
        lock.lock()
        count += 1
        let hit = count == target
        lock.unlock()
        if hit { reached.fulfill() }
    }
}
