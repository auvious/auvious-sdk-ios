//
//  RTCModuleLoopbackTests.swift
//  AuviousSDK Tests
//
//  RTCModule against a FakeSFU in the same process: the conference signalling of a published
//  and a viewed stream, with real media over WebRTC, without a backend.
//

import XCTest
import WebRTC
@testable import AuviousSDK

final class RTCModuleLoopbackTests: XCTestCase {

    private var module: RTCModule!
    private var events: RecordingRTCDelegate!
    private var sfu: FakeSFU!

    override func setUp() {
        super.setUp()
        // Set by the login in the app; stopping the camera reports it.
        UserEndpointModule.sharedInstance.userEndpointId = "endpoint"
        module = RTCModule()
        module.initialisePeerConnectionFactory()
        module.factory.setOptions(FakeSFU.loopbackOnly)
        module.iceServers = []
        events = RecordingRTCDelegate()
        module.delegate = events
        sfu = FakeSFU()
    }

    override func tearDown() {
        // Callbacks still queued (late candidates) must not reach the next test's objects.
        module.delegate = nil
        events.onPublishOffer = nil
        events.onRemoteOffer = nil
        events.onPublishCandidates = nil
        events.onRemoteCandidates = nil
        events.onRemoteStream = nil
        sfu.onTrack = nil
        sfu.onConnectionState = nil
        module.removeAllStreams()
        module.emptyPeerConnections()
        sfu.close()
        module = nil
        events = nil
        sfu = nil
        super.tearDown()
    }

    /// Viewing a stream: the SDK's receive-only offer, answered with an audio and a video track in one
    /// stream, reaches the delegate as one stream holding both tracks, and its video plays.
    func testViewedStreamIsDeliveredOnceWithBothTracksAndPlays() {
        let delivered = expectation(description: "remote stream delivered")
        var deliveries: [RTCMediaStream] = []
        viewStream(sending: [sfu.makeAudioTrack(), sfu.makeVideoTrack()], streamIds: ["publisher-stream"]) { stream in
            deliveries.append(stream)
            delivered.fulfill()
        }
        wait(for: [delivered], timeout: 20)

        guard let stream = deliveries.first else { return }
        XCTAssertEqual(stream.audioTracks.count, 1)
        XCTAssertEqual(stream.videoTracks.count, 1)
        guard let video = stream.videoTracks.first else { return }
        let played = expectation(description: "10 frames rendered")
        let counter = FrameCounter(target: 10, reached: played)
        video.add(counter)
        wait(for: [played], timeout: 20)
        video.remove(counter)

        XCTAssertEqual(deliveries.count, 1, "the stream was delivered once per track")
        XCTAssertEqual(events.errors.count, 0, "\(events.errors)")
    }

    /// Tracks sent without a stream (msid "-") reach the delegate together, as one stream holding
    /// both, and its video plays.
    func testViewedTracksWithoutAStreamAreDeliveredTogether() {
        let delivered = expectation(description: "remote tracks delivered")
        var deliveries: [RTCMediaStream] = []
        viewStream(sending: [sfu.makeAudioTrack(), sfu.makeVideoTrack()], streamIds: []) { stream in
            deliveries.append(stream)
            if deliveries.count == 1 { delivered.fulfill() }
        }
        wait(for: [delivered], timeout: 20)

        guard let stream = deliveries.first else { return }
        XCTAssertEqual(stream.audioTracks.count, 1)
        XCTAssertEqual(stream.videoTracks.count, 1)
        guard let video = stream.videoTracks.first else { return }
        let played = expectation(description: "10 frames rendered")
        let counter = FrameCounter(target: 10, reached: played)
        video.add(counter)
        wait(for: [played], timeout: 20)
        video.remove(counter)

        XCTAssertEqual(deliveries.count, 1, "the tracks were delivered separately")
    }

    /// Publishing: the SDK's offer sends its tracks with addTrack (Unified Plan), audio before video,
    /// and the SFU receives both over a connected transport.
    func testPublishedStreamSendsAudioAndVideoTracks() {
        let received = expectation(description: "SFU received audio and video")
        received.expectedFulfillmentCount = 2
        let connected = expectation(description: "connected")
        var kinds: [String] = []
        var offer = ""
        var isConnected = false

        sfu.onTrack = { receiver in
            kinds.append(receiver.track?.kind ?? "none")
            received.fulfill()
        }
        sfu.onConnectionState = { state in
            if !isConnected && state == .connected {
                isConnected = true
                connected.fulfill()
            }
        }
        events.onPublishOffer = { [unowned self] streamId, sdp in
            offer = sdp
            self.sfu.answer(sdp, sending: [], streamIds: []) { answer, error in
                XCTAssertNil(error)
                if let answer = answer {
                    self.module.handleAnswerReceivedPublish(withRemoteSDP: answer, streamId: streamId)
                }
            }
        }
        events.onPublishCandidates = { [unowned self] candidates in self.sfu.addRemoteCandidates(candidates) }

        module.configurePublishStream(type: .micAndCam, streamId: "local-stream", endpointId: "endpoint", userId: "user")
        wait(for: [received, connected], timeout: 20)

        XCTAssertEqual(kinds.sorted(), ["audio", "video"])
        let audio = offer.range(of: "m=audio"), video = offer.range(of: "m=video")
        XCTAssertNotNil(audio)
        XCTAssertNotNil(video)
        if let audio = audio, let video = video {
            XCTAssertLessThan(audio.lowerBound, video.lowerBound, "audio m-line first, as with Plan B")
        }
        // Without a camera (simulator) the capturer fails to start; nothing else may fail.
        let unexpected = events.errors.filter { error in
            if case .startCaptureFailure = error { return false }
            return true
        }
        XCTAssertEqual(unexpected.count, 0, "\(unexpected)")
    }

    // MARK: -

    /// Views a remote stream of the SFU's `tracks` in `streamIds`, through RTCModule's conference signalling.
    private func viewStream(sending tracks: [RTCMediaStreamTrack], streamIds: [String],
                            onStream: @escaping (RTCMediaStream) -> Void) {
        events.onRemoteOffer = { [unowned self] streamId, sdp in
            self.sfu.answer(sdp, sending: tracks, streamIds: streamIds) { answer, error in
                XCTAssertNil(error)
                if let answer = answer {
                    self.module.handleAnswerReceivedRemote(withRemoteSDP: answer, streamId: streamId)
                }
            }
        }
        events.onRemoteCandidates = { [unowned self] candidates in self.sfu.addRemoteCandidates(candidates) }
        events.onRemoteStream = { stream, streamId, type in
            XCTAssertEqual(streamId, "remote-stream")
            XCTAssertEqual(type, .micAndCam)
            onStream(stream)
        }
        module.configureRemoteStream(type: .micAndCam, streamId: "remote-stream", endpointId: "remote-endpoint", userId: "remote-user")
    }
}
