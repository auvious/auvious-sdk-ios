//
//  RecordingRTCDelegate.swift
//  AuviousSDK Tests
//
//  RTCModule's delegate in place of AuviousConferenceSDK: hands the signalling to the test,
//  always on the main queue (RTCModule calls it from WebRTC's threads).
//

import Foundation
import WebRTC
@testable import AuviousSDK

final class RecordingRTCDelegate: RTCDelegate {

    var onPublishOffer: ((_ streamId: String, _ sdp: String) -> Void)?
    var onRemoteOffer: ((_ streamId: String, _ sdp: String) -> Void)?
    var onPublishCandidates: (([RTCIceCandidate]) -> Void)?
    var onRemoteCandidates: (([RTCIceCandidate]) -> Void)?
    var onRemoteStream: ((_ stream: RTCMediaStream, _ streamId: String, _ type: StreamType) -> Void)?

    private(set) var errors: [AuviousSDKError] = []

    private func main(_ block: @escaping () -> Void) {
        DispatchQueue.main.async(execute: block)
    }

    func rtcClient(publishStream streamId: String, streamType: StreamType, sdpOffer: String) {
        main { self.onPublishOffer?(streamId, sdpOffer) }
    }

    func rtcClient(remoteStream streamId: String, sdpOffer: String, remoteEndpointId: String, remoteUserId: String) {
        main { self.onRemoteOffer?(streamId, sdpOffer) }
    }

    func rtcClient(addPublishStreamIceCandidates candidates: [RTCIceCandidate], streamId: String, streamType: StreamType) {
        main { self.onPublishCandidates?(candidates) }
    }

    func rtcClient(addRemoteStreamIceCandidates candidates: [RTCIceCandidate], userId: String, endpointId: String, streamId: String, streamType: StreamType) {
        main { self.onRemoteCandidates?(candidates) }
    }

    func rtcClient(didReceiveRemoteStream stream: RTCMediaStream, streamId: String, endpointId: String, type: StreamType) {
        main { self.onRemoteStream?(stream, streamId, type) }
    }

    func rtcClient(onError error: AuviousSDKError) {
        main { self.errors.append(error) }
    }

    func rtcClient(didReceiveLocalVideoTrack localVideoTrack: RTCVideoTrack!) {}
    func rtcClient(didReceiveLocalStream stream: RTCMediaStream, streamId: String, type: StreamType) {}
    func rtcClient(didChangeState newState: StreamEventState, streamId: String, streamType: StreamType, endpointId: String) {}
    func rtcClient(didStopScreenSharing: Bool) {}
    func rtcClient(didStartScreenSharing: Bool) {}
}
