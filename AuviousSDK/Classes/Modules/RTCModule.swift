//
//  ARTCClient.swift
//  AuviousSDK_Foundation
//
//  Created by Macis on 03/12/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import Foundation
import AVFoundation
import os
import Sentry

//Return type for camera commands: success, and the error otherwise
internal typealias CameraResponse = (Bool, String)

internal protocol RTCDelegate {
    
    //required for client
    func rtcClient(didReceiveLocalVideoTrack localVideoTrack: RTCVideoTrack!)
    func rtcClient(didReceiveRemoteStream stream: RTCMediaStream, streamId: String, endpointId: String, type: StreamType)
    func rtcClient(didReceiveLocalStream stream: RTCMediaStream, streamId: String, type: StreamType)
    func rtcClient(onError error: AuviousSDKError)
    func rtcClient(didChangeState newState: StreamEventState, streamId: String, streamType: StreamType, endpointId: String)
    func rtcClient(recorderStateChanged toActive: Bool)
    func rtcClient(didStopScreenSharing: Bool)
    func rtcClient(didStartScreenSharing: Bool)
    func rtcClient(didFailToStartScreenSharing: Bool)
    func rtcClient(screenShareICEConnectionFailed streamId: String)
    func rtcClient(screenShareICEConnectionNeedsRestart streamId: String)
    //ICE state of a call stream's connection (all but our shared screen, which recovers itself)
    func rtcClient(iceConnectionChanged state: StreamIceState, streamId: String, isLocal: Bool, endpointId: String)
    
    //rest call + rtclient invocation
    func rtcClient(publishStream streamId: String, streamType: StreamType, sdpOffer: String)
    func rtcClient(remoteStream streamId: String, sdpOffer: String, remoteEndpointId: String, remoteUserId: String)
    
    //rest call + client delegation
    func rtcClient(addPublishStreamIceCandidates candidates: [RTCIceCandidate], streamId: String, streamType: StreamType)
    func rtcClient(addRemoteStreamIceCandidates candidates: [RTCIceCandidate], userId: String, endpointId: String, streamId: String, streamType: StreamType)
}

internal final class RTCMyVideoEncoderFactory: NSObject, RTCVideoEncoderFactory {
    func supportedCodecs() -> [RTCVideoCodecInfo] {
        var codecs: [RTCVideoCodecInfo] = []
        let codecName = kRTCVideoCodecH264Name
        
        let constrainedBaselineParams = [
            "profile-level-id": kRTCLevel31ConstrainedBaseline,
            "level-asymmetry-allowed": "1",
            "packetization-mode": "1"
            ] as [String : String]
        let constrainedBaselineInfo = RTCVideoCodecInfo(name: codecName, parameters: constrainedBaselineParams)
        codecs.append(constrainedBaselineInfo)
        
        return codecs
    }
    
    func createEncoder(_ info: RTCVideoCodecInfo) -> RTCVideoEncoder? {
        return RTCVideoEncoderH264(codecInfo: info)
    }
}

internal final class RTCMyVP8VideoEncoderFactory: NSObject, RTCVideoEncoderFactory {
    func supportedCodecs() -> [RTCVideoCodecInfo] {
        var codecs: [RTCVideoCodecInfo] = []
        let codecName = kRTCVp8CodecName
        
        let vp8CodecInfo = RTCVideoCodecInfo(name: codecName)
        codecs.append(vp8CodecInfo)
        
        return codecs
    }
    
    func createEncoder(_ info: RTCVideoCodecInfo) -> RTCVideoEncoder? {
        if (info.name == kRTCVideoCodecVp8Name) {
            return RTCVideoEncoderVP8.vp8Encoder()
        }
        
        return nil
    }
}

//Adding this to make the methods optional (a simple @obj optional func won't work in this case)
internal extension RTCDelegate {
    func rtcClient(publishStream streamId: String, streamType: StreamType, sdpOffer: String) {}
    func rtcClient(didReceiveLocalStream stream: RTCMediaStream, streamId: String, type: StreamType) {}
    func rtcClient(didReceiveRemoteStream stream: RTCMediaStream, streamId: String, endpointId: String, type: StreamType) {}
    func rtcClient(remoteStream streamId: String, sdpOffer: String, remoteEndpointId: String, remoteUserId: String) {}
    func rtcClient(addPublishStreamIceCandidates candidates: [RTCIceCandidate], streamId: String, streamType: StreamType) {}
    func rtcClient(addRemoteStreamIceCandidates candidates: [RTCIceCandidate], userId: String, endpointId: String, streamId: String, streamType: StreamType) {}
    func rtcClient(recorderStateChanged toActive: Bool){}
    func rtcClient(didFailToStartScreenSharing: Bool){}
    func rtcClient(screenShareICEConnectionFailed streamId: String) {}
    func rtcClient(screenShareICEConnectionNeedsRestart streamId: String) {}
    func rtcClient(iceConnectionChanged state: StreamIceState, streamId: String, isLocal: Bool, endpointId: String) {}
}

internal final class RTCModule: NSObject, RTCPeerConnectionDelegate, RTCVideoCapturerDelegate {
    
    //List of connections used. Changed on main, but WebRTC's callbacks read it on its signaling thread,
    //so every access goes through the lock (a read during a change of the array can crash)
    internal var peerConnections: [RTCPeerConnectionContainer] {
        get {
            peerConnectionsLock.lock()
            defer { peerConnectionsLock.unlock() }
            return lockedPeerConnections
        }
        set {
            peerConnectionsLock.lock()
            defer { peerConnectionsLock.unlock() }
            lockedPeerConnections = newValue
        }
    }
    private var lockedPeerConnections: [RTCPeerConnectionContainer] = []
    private let peerConnectionsLock = NSLock()
    
    //Connection factory (readable by the tests, to keep their connections on loopback)
    private(set) var factory: RTCPeerConnectionFactory!
    
    //Default connection constraint, used when instatiating a connection
    private let defaultConnectionConstraint = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: ["DtlsSrtpKeyAgreement": "true"])
    
    //Screen capturing
    private var screenCapturer: ScreenCapturer!
    private var localScreenVideoSource: RTCVideoSource?
    private var localScreenVideoTrack: RTCVideoTrack?
    private var localScreenStream: RTCMediaStream?

    // Pending capturer created during the permission phase (reused in createScreenSharingStream)
    private var pendingScreenVideoSource: RTCVideoSource?
    private var pendingScreenCapturer: ScreenCapturer?

    /// Per-frame hook applied to every screen capturer (e.g. co-browse masking)
    internal var screenFrameProcessor: ((CMSampleBuffer, CVPixelBuffer) -> CVPixelBuffer?)? {
        didSet {
            screenCapturer?.frameProcessor = screenFrameProcessor
            pendingScreenCapturer?.frameProcessor = screenFrameProcessor
        }
    }
    
    private var capturer: RTCCameraVideoCapturer!
    private var localVideoSource: RTCVideoSource?
    
    private var usingFrontCamera: Bool = true
    private var switchCamStreamId: String = ""
    private var switchCameStreamType: StreamType! = .unknown
    
    var iceServers: [RTCIceServer] = []

    var publishVideoResolution: PublishVideoResolution = .min
    
    var delegate: RTCDelegate?
    
    /// Stores the last speaker preference set via changeAudioRoot().
    /// Used by checkCurrentAudioRoute() so it doesn't override the user's choice.
    private var audioPrefersSpeaker: Bool = true
    
    //Local tracks (for muting/unmuting)
    internal var localVideoTrack: RTCVideoTrack?
    internal var localAudioTrack: RTCAudioTrack?
    internal var localStream: RTCMediaStream?
    
    internal override init(){
        super.init()
        
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(handleRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    //Initialises the connection factory
    internal func initialisePeerConnectionFactory() {
        //let encoderFactory = RTCMyVideoEncoderFactory.init()
        let encoderFactory = RTCMyVP8VideoEncoderFactory.init()
        let decoderFactory = RTCDefaultVideoDecoderFactory.init()
        
        factory = RTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)
        
        iceServers = ServerConfiguration.iceServers
    }
    
    //Configures a stream for publishing in a conference
    internal func configurePublishStream(type: StreamType, streamId: String, endpointId: String, userId: String) {
        
        //Create a new RTCPeerConnection
        initialisePeerConnection(streamId: streamId, endpointId: endpointId, userId: userId, type: type, isLocal: true)
        
        //Add the stream obtained
        addStream(type: type, streamId: streamId)
        makeOfferPublishStream(type:type, streamId: streamId)
    }
    
    //Configures a remote stream for viewing in a conference
    internal func configureRemoteStream(type: StreamType, streamId: String, endpointId: String, userId: String) {
        
        //Create a new RTCPeerConnection
        initialisePeerConnection(streamId: streamId, endpointId: endpointId, userId: userId, type: type, isLocal: false)
        makeOfferRemoteStream(type: type, streamId: streamId)
    }
    
    //Creates a new peer connection for the specified stream and endpoint IDs
    internal func initialisePeerConnection(streamId: String, endpointId: String, userId: String, type: StreamType, isLocal: Bool) {
        let configuration = RTCConfiguration()
        configuration.iceServers = iceServers
        configuration.continualGatheringPolicy = .gatherContinually
        //Keep the sockets per connection down: audio and video share one transport, and no host TCP candidates
        //(TURN over TCP/TLS still works). WebRTC's network thread stops once a socket's descriptor passes 1024,
        //which with one connection per stream froze calls of 5 participants.
        configuration.bundlePolicy = .maxBundle
        configuration.tcpCandidatePolicy = .disabled

        // nil if WebRTC rejects the configuration; callers then report missingPeerConnection
        guard let connection = factory.peerConnection(with: configuration, constraints: self.defaultConnectionConstraint, delegate: self) else {
            sdkLog("Could not create a connection for stream type %@", log: Log.rtc, type: .error, type.rawValue)
            return
        }
        let connectionContainer = RTCPeerConnectionContainer(conn: connection, streamId: streamId, endpointId: endpointId, userId: userId, type: type, isLocal: isLocal)
        
        peerConnections.append(connectionContainer)
        sdkLog("Created connection for stream type %@", log: Log.rtc, type: .debug, type.rawValue)
    }
    
    //Returns the connection created for the given stream id, if any (callers report a missing one)
    private func getConnectionForStream(streamId: String) -> RTCPeerConnection? {
        return peerConnections.first { $0.streamId == streamId }?.connection
    }
    
    private func addStream(type: StreamType, streamId: String) {
        guard let peerConnection = getConnectionForStream(streamId: streamId) else {
            delegate?.rtcClient(onError: AuviousSDKError.missingPeerConnection(streamId: streamId))
            return
        }
        
        if type == .screen {
            let screenStream = createScreenSharingStream(streamId: streamId)
            addTracks(of: screenStream, to: peerConnection)
        } else {
            let localStream = createLocalMediaStream(type: type, streamId: streamId)
            addTracks(of: localStream, to: peerConnection)
        }
    }

    //Unified Plan: a stream is sent as its tracks (addStream crashes), audio first like Plan B's SDP
    private func addTracks(of stream: RTCMediaStream, to peerConnection: RTCPeerConnection) {
        let tracks: [RTCMediaStreamTrack] = stream.audioTracks + stream.videoTracks
        for track in tracks where peerConnection.add(track, streamIds: [stream.streamId]) == nil {
            // The offer still goes out with the other tracks; the app learns this one isn't sent.
            sdkLog("Could not add %@ track to stream %@", log: Log.rtc, type: .error, track.kind, stream.streamId)
            delegate?.rtcClient(onError: AuviousSDKError.internalError)
        }
    }

    //The local tracks of a connection, of the given kind ("audio" or "video")
    private func sentTracks(_ connection: RTCPeerConnection, kind: String) -> [RTCMediaStreamTrack] {
        return connection.senders.compactMap { $0.track }.filter { $0.kind == kind }
    }
    
    /// Returns the device's native screen pixel dimensions (always portrait-ordered).
    /// Used to size the screen-share output to match the actual screen aspect ratio.
    private func nativeScreenSize() -> (width: Int32, height: Int32) {
        let bounds = UIScreen.main.nativeBounds
        return (Int32(bounds.width), Int32(bounds.height))
    }

    /// Starts ReplayKit capture to trigger the permission dialog.
    /// The capturer is stored as pending and reused in createScreenSharingStream.
    internal func startScreenCapture(completion: @escaping (Bool) -> Void) {
        let crumb = Breadcrumb(level: .info, category: "screen_share")
        crumb.message = "startScreenCapture called"
        AuviousDiagnostics.addBreadcrumb(crumb)

        pendingScreenVideoSource = factory.videoSource()
        let pendingDims = nativeScreenSize()
        pendingScreenVideoSource?.adaptOutputFormat(toWidth: pendingDims.width, height: pendingDims.height, fps: 15)
        let capturer = ScreenCapturer(videoSource: pendingScreenVideoSource!)
        capturer.delegate = self
        capturer.frameProcessor = screenFrameProcessor
        pendingScreenCapturer = capturer
        capturer.permissionCompletion = { [weak self] granted in
            guard let self = self else { return }
            if !granted {
                self.pendingScreenCapturer = nil
                self.pendingScreenVideoSource = nil
            }
            completion(granted)
        }
        capturer.start()
    }

    internal func createScreenSharingStream(streamId: String) -> RTCMediaStream {
        sdkLog("createLocalMediaStream() for type screen and stream %@", log: Log.rtc, type: .debug, streamId)
        localScreenStream = factory.mediaStream(withStreamId: streamId)

        if let pending = pendingScreenCapturer, let pendingSource = pendingScreenVideoSource {
            // Reuse the capturer that was already started during the permission phase
            screenCapturer = pending
            localScreenVideoSource = pendingSource
            pendingScreenCapturer = nil
            pendingScreenVideoSource = nil

            let crumb = Breadcrumb(level: .info, category: "screen_share")
            crumb.message = "Screen stream created (reusing pending capturer)"
            crumb.data = ["streamId": streamId]
            AuviousDiagnostics.addBreadcrumb(crumb)

            // Capture is already running; notify delegate directly
            delegate?.rtcClient(didStartScreenSharing: true)
        } else {
            localScreenVideoSource = factory.videoSource()
            let freshDims = nativeScreenSize()
            localScreenVideoSource?.adaptOutputFormat(toWidth: freshDims.width, height: freshDims.height, fps: 15)
            screenCapturer = ScreenCapturer(videoSource: localScreenVideoSource!)
            screenCapturer.delegate = self
            screenCapturer.frameProcessor = screenFrameProcessor

            let crumb = Breadcrumb(level: .warning, category: "screen_share")
            crumb.message = "Screen stream created (no pending capturer — starting fresh)"
            crumb.data = ["streamId": streamId]
            AuviousDiagnostics.addBreadcrumb(crumb)

            screenCapturer.start()
        }

        localScreenVideoTrack = factory.videoTrack(with: localScreenVideoSource!, trackId: "screenVideo")
        localScreenVideoTrack!.isEnabled = true
        localScreenStream!.addVideoTrack(localScreenVideoTrack!)

        return localScreenStream!
    }
    
    /// Moves the running screen capturer back to pending state so it can be
    /// reused by a subsequent `configurePublishStream(.screen, ...)` call
    /// without requesting ReplayKit permission again.
    internal func prepareScreenCaptureForRetry() {
        pendingScreenCapturer = screenCapturer
        pendingScreenVideoSource = localScreenVideoSource
        screenCapturer = nil
        localScreenVideoSource = nil
        localScreenVideoTrack = nil
        localScreenStream = nil
    }

    /// True while a ReplayKit capture is running or pending publication
    internal var isScreenCapturing: Bool {
        return screenCapturer != nil || pendingScreenCapturer != nil
    }

    /// Pauses/resumes the outgoing screen track without tearing down the capture (e.g. while on hold).
    internal func setScreenTrackEnabled(_ enabled: Bool) {
        localScreenVideoTrack?.isEnabled = enabled
    }

    internal func stopScreenSharing() {
        sdkLog("stopScreenSharing() for type screen and stream %@", log: Log.rtc, type: .debug, localScreenStream ?? "nil")
        let crumb = Breadcrumb(level: .info, category: "screen_share")
        crumb.message = "stopScreenSharing called"
        crumb.data = ["streamId": localScreenStream?.streamId ?? "nil"]
        AuviousDiagnostics.addBreadcrumb(crumb)
        delegate?.rtcClient(didStopScreenSharing: true)

        screenCapturer?.stop()
        screenCapturer = nil
        localScreenVideoTrack = nil
        localScreenVideoSource = nil
        localScreenStream = nil

        pendingScreenCapturer?.stop()
        pendingScreenCapturer = nil
        pendingScreenVideoSource = nil
    }
    
    internal func createLocalMediaStream(type: StreamType, streamId: String) -> RTCMediaStream {
        sdkLog("createLocalMediaStream() for type %@ and stream %@", log: Log.rtc, type: .debug, type.rawValue, streamId)
        localStream = factory.mediaStream(withStreamId: streamId)
        
        if AVCaptureDevice.authorizationStatus(for: AVMediaType.video) != .denied ||
            AVCaptureDevice.authorizationStatus(for: AVMediaType.video) != .restricted {
            
            if type != .mic {
                
                localVideoSource = factory.videoSource()
                capturer = RTCCameraVideoCapturer(delegate: localVideoSource!)
                capturer.delegate = self
                startCapture(type: type, streamId: streamId)
                
                localVideoTrack = factory.videoTrack(with: localVideoSource!, trackId: "ARDAMSv0")
                localVideoTrack!.isEnabled = true
                localStream!.addVideoTrack(localVideoTrack!)
                sdkLog("local video track added", log: Log.rtc, type: .debug)
            }
        }
        else {
            delegate?.rtcClient(onError: AuviousSDKError.videoPermissionIsDisabled)
        }
        
        if AVCaptureDevice.authorizationStatus(for: AVMediaType.audio) != .denied ||
            AVCaptureDevice.authorizationStatus(for: AVMediaType.audio) != .restricted {
            if type != .cam {
                localAudioTrack = factory.audioTrack(withTrackId: "ARDAMSa0")
                localStream!.addAudioTrack(localAudioTrack!)
            }
        }
        else {
            delegate?.rtcClient(onError: AuviousSDKError.audioPermissionIsDisabled)
        }
        
        
        if let localVideoTrack = localStream!.videoTracks.first {
            delegate?.rtcClient(didReceiveLocalVideoTrack: localVideoTrack)
        }
        
        if let localStream = localStream {
            delegate?.rtcClient(didReceiveLocalStream: localStream, streamId: localStream.streamId, type: type)
        }
        return localStream!
    }
    
    private func makeOfferPublishStream(type: StreamType, streamId: String) {
        guard let peerConnection = getConnectionForStream(streamId: streamId) else {
            delegate?.rtcClient(onError: AuviousSDKError.missingPeerConnection(streamId: streamId))
            return
        }
        
        let constraint = createConstraintForConference(type: type)
        peerConnection.offer(for: constraint, completionHandler: { [weak self]  (sdp, error) in

            if let error = error {
                self?.delegate?.rtcClient(onError: AuviousSDKError.publishStreamFailure(fragment: .makeOfferPublishStream, output: error.localizedDescription))
            }
            else {
                self?.handleSdpGeneratedPublish(sdpDescription: sdp, streamType:type, streamId: streamId)
            }
        })
    }
    
    //Creates the RTC media constraint for the specified conference type
    private func createConstraintForConference(type: StreamType) -> RTCMediaConstraints {
        switch type {
        case .mic:
            return RTCMediaConstraints(mandatoryConstraints: ["OfferToReceiveAudio" : "true", "OfferToReceiveVideo": "false"], optionalConstraints: nil)
        case .cam, .screen:
            return RTCMediaConstraints(mandatoryConstraints: ["OfferToReceiveAudio" : "false", "OfferToReceiveVideo": "true"], optionalConstraints: nil)
        default:
            return RTCMediaConstraints(mandatoryConstraints: ["OfferToReceiveAudio" : "true", "OfferToReceiveVideo": "true"], optionalConstraints: nil)
        }
    }
    
    internal func makeOfferRemoteStream(type: StreamType, streamId: String) {
        guard let peerConnection = getConnectionForStream(streamId: streamId) else {
            delegate?.rtcClient(onError: AuviousSDKError.missingPeerConnection(streamId: streamId))
            return
        }
        
        let constraint = createConstraintForConference(type: type)
        peerConnection.offer(for: constraint, completionHandler: { [weak self]  (sdp, error) in
            guard let self = self else {
                return
            }
            if let error = error {
                self.delegate?.rtcClient(onError: AuviousSDKError.remoteStreamFailure(fragment: .makeOfferRemoteStream, output: error.localizedDescription))
            }
            else {
                self.handleSdpGeneratedRemote(sdpDescription: sdp, streamId: streamId)
            }
        })
    }
    
    private func handleSdpGeneratedPublish(sdpDescription: RTCSessionDescription?, streamType: StreamType, streamId: String) {
        guard let peerConnection = getConnectionForStream(streamId: streamId)  else {
            delegate?.rtcClient(onError: AuviousSDKError.missingPeerConnection(streamId: streamId))
            return
        }
        
        //Call RTCPeerConnection.setLocalDescription(sdpOffer)
        peerConnection.setLocalDescription(sdpDescription!, completionHandler: {[weak self] (error) in
            
            if let error = error {
                self?.delegate?.rtcClient(onError: AuviousSDKError.publishStreamFailure(fragment: .localDescriptionPublishStream, output: error.localizedDescription))
            }
            else {
                //Use Conferences/publishStream
                self?.invokePublishStream(sdpDescription: sdpDescription!, streamType:streamType, streamId: streamId)
            }
        })
    }
    
    private func handleSdpGeneratedRemote(sdpDescription: RTCSessionDescription?, streamId: String) {
        let containerList = peerConnections.filter{$0.streamId == streamId}
        guard let container = containerList.first else {
            delegate?.rtcClient(onError: AuviousSDKError.missingPeerConnection(streamId: streamId))
            return
        }
        
        //Call RTCPeerConnection.setLocalDescription(sdpOffer)
        container.connection.setLocalDescription(sdpDescription!, completionHandler: {[weak self] (error) in
            if let error = error {
                self?.delegate?.rtcClient(onError: AuviousSDKError.remoteStreamFailure(fragment: .localDescriptionRemoteStream, output: error.localizedDescription))
            }
            else {
                //Use Conferences/publishStream
                self?.invokeViewRemoteStream(sdpDescription: sdpDescription!, streamId: streamId, remoteEndpointId: container.endpointId, remoteUserId: container.userId)
            }
        })
    }
    
    private func invokePublishStream(sdpDescription: RTCSessionDescription, streamType: StreamType, streamId: String){
        delegate?.rtcClient(publishStream: streamId, streamType: streamType, sdpOffer: sdpDescription.sdp)
    }
    
    private func invokeViewRemoteStream(sdpDescription: RTCSessionDescription, streamId: String, remoteEndpointId: String, remoteUserId: String){
        delegate?.rtcClient(remoteStream: streamId, sdpOffer: sdpDescription.sdp, remoteEndpointId:remoteEndpointId, remoteUserId:remoteUserId)
    }
    
    internal func handleAnswerReceivedPublish(withRemoteSDP remoteSdp: String?, streamId: String) {
        guard let peerConnection = getConnectionForStream(streamId: streamId) else {
            delegate?.rtcClient(onError: AuviousSDKError.missingPeerConnection(streamId: streamId))
            return
        }
        
        // Add remote description
        let sessionDescription: RTCSessionDescription = RTCSessionDescription.init(type: .answer, sdp: remoteSdp!)
        
        peerConnection.setRemoteDescription(sessionDescription, completionHandler: { [weak self] (error) in
            if let error = error {
                self?.delegate?.rtcClient(onError: AuviousSDKError.publishStreamFailure(fragment: .remoteDescriptionPublishStream, output: error.localizedDescription))
            }
            else {
                self?.handleRemoteDescriptionSet(isPublish: true, streamId: streamId)
            }
        })
    }
    
    internal func handleAnswerReceivedRemote(withRemoteSDP remoteSdp: String?, streamId: String) {
        guard let peerConnection = getConnectionForStream(streamId: streamId) else {
            delegate?.rtcClient(onError: AuviousSDKError.missingPeerConnection(streamId: streamId))
            return
        }
        
        // Add remote description
        let sessionDescription: RTCSessionDescription = RTCSessionDescription.init(type: .answer, sdp: remoteSdp!)
        
        peerConnection.setRemoteDescription(sessionDescription, completionHandler: { [weak self] (error) in
            if let error = error {
                self?.delegate?.rtcClient(onError: AuviousSDKError.remoteStreamFailure(fragment: .remoteDescriptionRemoteStream, output: error.localizedDescription))
            }
            else {
                self?.handleRemoteDescriptionSet(isPublish: false, streamId: streamId)
            }
        })
    }
    
    private func handleRemoteDescriptionSet(isPublish: Bool, streamId: String) {
        let containerList = peerConnections.filter{$0.streamId == streamId}
        guard let container = containerList.first else {
            delegate?.rtcClient(onError: AuviousSDKError.missingPeerConnection(streamId: streamId))
            return
        }

        container.remoteDescriptionSet = true

        // Flush any candidates that were gathered before the remote description was set.
        // Further candidates will be trickled from peerConnection(_:didGenerate:).
        sendUnsentCandidates(for: container)
    }

    /// Sends any ICE candidates that have not yet been delivered to the server.
    private func sendUnsentCandidates(for container: RTCPeerConnectionContainer) {
        guard container.candidatesSentCount < container.iceCandidates.count else { return }
        let unsent = Array(container.iceCandidates[container.candidatesSentCount...])
        container.candidatesSentCount = container.iceCandidates.count

        if container.isLocal {
            delegate?.rtcClient(addPublishStreamIceCandidates: unsent, streamId: container.streamId, streamType: container.streamType)
        } else {
            delegate?.rtcClient(addRemoteStreamIceCandidates: unsent, userId: container.userId, endpointId: container.endpointId, streamId: container.streamId, streamType: container.streamType)
        }
    }
    
    //------------------------------------------
    internal func removePublishStreams(streamId: String) -> Bool{
        guard let obj = peerConnections.first(where: { $0.streamId == streamId }) else {
            return false
        }
        if obj.streamType == .cam || obj.streamType == .micAndCam {
            stopCapture(type: obj.streamType, streamId: obj.streamId)
        }
        obj.connection?.close()
        peerConnections.removeAll { $0.streamId == streamId }
        return true
    }

    /**
     Publishes our camera or microphone stream again over a new connection, under a new stream ID, after its
     connection was lost. The capture and tracks keep running, so the local preview doesn't change.
     Returns false when there is no such stream.
     */
    internal func republishLocalStream(replacing oldStreamId: String, with newStreamId: String) -> Bool {
        guard let old = peerConnections.first(where: { $0.streamId == oldStreamId && $0.isLocal }),
              let type = old.streamType, let endpointId = old.endpointId, let userId = old.userId else {
            return false
        }
        let tracks = sentTracks(old.connection, kind: "audio") + sentTracks(old.connection, kind: "video")
        old.connection?.close()
        peerConnections.removeAll { $0.streamId == oldStreamId }

        initialisePeerConnection(streamId: newStreamId, endpointId: endpointId, userId: userId, type: type, isLocal: true)
        guard let connection = getConnectionForStream(streamId: newStreamId) else {
            delegate?.rtcClient(onError: AuviousSDKError.missingPeerConnection(streamId: newStreamId))
            return false
        }
        for track in tracks where connection.add(track, streamIds: [newStreamId]) == nil {
            sdkLog("Could not add %@ track to republished stream %@", log: Log.rtc, type: .error, track.kind, newStreamId)
        }
        if switchCamStreamId == oldStreamId {
            switchCamStreamId = newStreamId
        }
        makeOfferPublishStream(type: type, streamId: newStreamId)
        return true
    }

    internal func removeRemoteStreams(streamId: String) -> Bool{
        guard let obj = peerConnections.first(where: { $0.streamId == streamId }) else {
            return false
        }
        obj.connection?.close()
        peerConnections.removeAll { $0.streamId == streamId }
        return true
    }
    
    internal func removeAllStreams() {
        
        for obj in peerConnections {
            
            if(obj.isLocal == true){
                if(obj.streamType == .cam || obj.streamType == .micAndCam){
                    stopCapture(type: obj.streamType, streamId: obj.streamId)
                }
            }
            
            if let peerConnection = obj.connection {
                peerConnection.close()
            }
        }
    }
    
    internal func emptyPeerConnections() {
        peerConnections.removeAll()

        // Clear stale local media references so the next createLocalMediaStream()
        // starts completely fresh and doesn't interfere with old (dead) objects.
        // capturer is already nilled by stopCapture() inside removeAllStreams().
        localVideoTrack = nil
        localVideoSource = nil
        localAudioTrack = nil
        localStream = nil
    }
    
    // MARK: -
    // MARK: Track muting
    // MARK: -
    
    internal func toggleRemoteStreams(_ event: ConferenceMetadataUpdatedEvent) {
        if !event.isHold {
            //Remote stream to process
            if let remoteStreamId = event.streamId, let streamConnection = peerConnections.filter({$0.streamId == remoteStreamId}).first {
                if event.operation == MetadataRequestOperation.set {
                    if event.streamType == MetadataRequestType.audio {
                        //Mute audio
                        sentTracks(streamConnection.connection, kind: "audio").forEach { $0.isEnabled = false }
                    } else if event.streamType == MetadataRequestType.video {
                        //Mute video
                        sentTracks(streamConnection.connection, kind: "video").forEach { $0.isEnabled = false }
                    }
                } else {
                    if event.streamType == MetadataRequestType.audio {
                        //Unmute audio
                        sentTracks(streamConnection.connection, kind: "audio").forEach { $0.isEnabled = true }
                    } else if event.streamType == MetadataRequestType.video {
                        //Unmute video
                        sentTracks(streamConnection.connection, kind: "video").forEach { $0.isEnabled = true }
                    }
                }
            }
        }
    }
    
    // MARK: -
    // MARK: Audio routing
    // MARK: -
    
    private func checkCurrentAudioRoute() {
        let currentRoute = AVAudioSession.sharedInstance().currentRoute
        for description in currentRoute.outputs {
            
            if description.portType == AVAudioSession.Port.headphones || description.portType == AVAudioSession.Port.bluetoothHFP {
                sdkLog("headphone plugged in", log: Log.rtc, type: .debug)
            } else {
                sdkLog("headphone pulled out, flag:%{public}@", log: Log.rtc, type: .debug, String(audioPrefersSpeaker))
                changeAudioRoot(toSpeaker: audioPrefersSpeaker)
            }
        }
    }

    @objc func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
            let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue:reasonValue) else {
                return
        }
        
        switch reason {
        case .newDeviceAvailable:
            let session = AVAudioSession.sharedInstance()
            for output in session.currentRoute.outputs where output.portType == AVAudioSession.Port.headphones || output.portType == AVAudioSession.Port.bluetoothHFP || output.portType == AVAudioSession.Port.bluetoothA2DP || output.portType == AVAudioSession.Port.bluetoothLE {
                sdkLog("Headphones/Bluetooth device just connected", log: Log.rtc, type: .debug)
                break
            }
        case .oldDeviceUnavailable:
            if let previousRoute =
                userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription {
                for output in previousRoute.outputs where output.portType == AVAudioSession.Port.headphones || output.portType == AVAudioSession.Port.bluetoothHFP || output.portType == AVAudioSession.Port.bluetoothA2DP || output.portType == AVAudioSession.Port.bluetoothLE {
                    sdkLog("Headphones/Bluetooth device just removed, switching to speaker", log: Log.rtc, type: .debug)
                    changeAudioRoot(toSpeaker: true)
                    break
                }
            }
        default: ()
        }
    }
    
    // MARK: RTCPeerConnectionDelegate
    //Plan B's remote stream callback: M155 still fires it, but streams are delivered from
    //didAdd rtpReceiver, the Unified Plan callback, so this one must not deliver them again
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
    }

    //Unified Plan: one callback per remote track, fired once the whole remote description is
    //applied, so its streams already hold all their tracks. Each stream is delivered once.
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {

        //The connection may have been removed (call ended) before this callback ran
        guard let targetContainer = peerConnections.first(where: { $0.connection == peerConnection }) else {
            sdkLog("Remote track for a removed connection", log: Log.rtc, type: .debug)
            return
        }

        var streams = mediaStreams
        if streams.isEmpty {
            //No stream signalled for the track (msid "-"): one stream of all the connection's
            //received tracks, which all exist by now, delivered on the first of their callbacks.
            //Only negotiated ones: a transceiver the answer rejected has a track that never plays.
            //An offer we answer (incoming call) has no negotiated direction yet: there the
            //transceiver's own, receiving for every m-line of the offer (also one the caller
            //offers without sending, a track that never plays; the answer can't tell that apart).
            let stream = factory.mediaStream(withStreamId: targetContainer.streamId)
            let receiving = peerConnection.transceivers.filter { transceiver in
                var direction = RTCRtpTransceiverDirection.inactive
                if !transceiver.currentDirection(&direction) {
                    direction = transceiver.direction
                }
                return !transceiver.isStopped && (direction == .recvOnly || direction == .sendRecv)
            }
            for track in receiving.compactMap({ $0.receiver.track }) {
                if let audio = track as? RTCAudioTrack {
                    stream.addAudioTrack(audio)
                } else if let video = track as? RTCVideoTrack {
                    stream.addVideoTrack(video)
                }
            }
            streams = [stream]
        }

        for stream in streams where targetContainer.deliveredRemoteStreamIds.insert(stream.streamId).inserted {
            checkCurrentAudioRoute()
            delegate?.rtcClient(didReceiveRemoteStream: stream, streamId: targetContainer.streamId, endpointId: targetContainer.endpointId, type: targetContainer.streamType)
        }
    }
    
    //Setup an IceCandidate listener to gather candidates
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {

        //Find the appropriate connection
        var targetContainer: RTCPeerConnectionContainer?
        for item in peerConnections {
            if item.connection == peerConnection {
                targetContainer = item
                break
            }
        }

        //And set the ICE candidates
        if let container = targetContainer {
            if !container.iceCandidates.contains(candidate){
                container.iceCandidates.append(candidate)
            }

            // Trickle ICE: if remote description is already set, send new candidates immediately
            if container.remoteDescriptionSet {
                sendUnsentCandidates(for: container)
            }
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
//        sdkLog("RTCPeerConnectionDelegate - ARTCClient - Channel did open", log: Log.rtc, type: .debug)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        //os_log("RTCPeerConnectionDelegate - ARTCClient - Gathering new State: %@", log: Log.rtc, type: .debug, newState.rawValue)
    }
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        //os_log("RTCPeerConnectionDelegate - ARTCClient - Peer connection should negotiate", log: Log.rtc, type: .debug)
    }
    
    func peerConnection(onRenegotiationNeeded peerConnection: RTCPeerConnection!) {
        //os_log("RTCPeerConnectionDelegate - ARTCClient - WARNING: Renegotiation needed but unimplemented", log: Log.rtc, type: .debug)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        //os_log("RTCPeerConnectionDelegate - ARTCClient - Stream was removed", log: Log.rtc, type: .debug)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        //os_log("RTCPeerConnectionDelegate - ARTCClient - stateChanged: %@", log: Log.rtc, type: .debug, stateChanged.rawValue)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        //A connection we already dropped or replaced is no longer in the list
        guard let container = peerConnections.first(where: { $0.connection == peerConnection }) else { return }

        if !(container.streamType == .screen && container.isLocal), let streamId = container.streamId, let endpointId = container.endpointId {
            let state: StreamIceState
            switch newState {
            case .connected, .completed: state = .connected
            case .disconnected: state = .disconnected
            case .failed: state = .failed
            default: state = .other
            }
            sdkLog("ICE %{public}@ for %{public}@ stream %{public}@", log: Log.rtc, type: .default,
                   String(describing: state), container.isLocal ? "published" : "subscribed", streamId)
            delegate?.rtcClient(iceConnectionChanged: state, streamId: streamId, isLocal: container.isLocal, endpointId: endpointId)
        }

        guard container.streamType == .screen else { return }
        let stateName: String
        switch newState {
        case .new:          stateName = "new"
        case .checking:     stateName = "checking"
        case .connected:    stateName = "connected"
        case .completed:    stateName = "completed"
        case .failed:       stateName = "failed"
        case .disconnected: stateName = "disconnected"
        case .closed:       stateName = "closed"
        default:            stateName = "unknown(\(newState.rawValue))"
        }
        let crumb = Breadcrumb(level: newState == .failed ? .error : .info, category: "screen_share")
        crumb.message = "ICE connection state changed"
        crumb.data = ["state": stateName, "streamId": container.streamId ?? "unknown", "isLocal": container.isLocal, "restartAttempted": container.iceRestartAttempted]
        AuviousDiagnostics.addBreadcrumb(crumb)

        if newState == .failed, container.isLocal, let streamId = container.streamId {
            if !container.iceRestartAttempted {
                container.iceRestartAttempted = true

                let restartCrumb = Breadcrumb(level: .warning, category: "screen_share")
                restartCrumb.message = "Attempting ICE restart for screen share"
                restartCrumb.data = ["streamId": streamId]
                AuviousDiagnostics.addBreadcrumb(restartCrumb)

                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.rtcClient(screenShareICEConnectionNeedsRestart: streamId)
                }
            } else {
                let event = Event(level: .error)
                event.message = SentryMessage(formatted: "Screen share ICE connection failed after restart")
                event.extra = ["streamId": streamId, "isLocal": container.isLocal]
                AuviousDiagnostics.capture(event: event)

                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.rtcClient(screenShareICEConnectionFailed: streamId)
                }
            }
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        //os_log("RTCPeerConnectionDelegate - ARTCClient - Candidate was removed", log: Log.rtc, type: .debug)
    }
    
    // MARK: Capturer
    @discardableResult
    private func startCapture(type: StreamType, streamId: String) -> CameraResponse {
        let position = self.usingFrontCamera ? AVCaptureDevice.Position.front : AVCaptureDevice.Position.back
        
        guard let device = self.findDeviceForPosition(position: position) else {
            delegate?.rtcClient(onError: AuviousSDKError.startCaptureFailure)
            return CameraResponse(false, "Unable to access camera")
        }
        
        let format = self.selectFormatForDevice(device: device)
        let fps = self.selectFpsForFormat(format: format)
        
        capturer.startCapture(with: device, format: format, fps: fps)
        
        switchCamStreamId = streamId
        switchCameStreamType = type
//        delegate?.rtcClient(didChangeState: .localCaptureStarted, streamId: streamId, streamType: type, endpointId: UserEndpointModule.sharedInstance.userEndpointId!)
        
        return CameraResponse(true, "")
    }
    
    private func findDeviceForPosition(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let captureDevices = RTCCameraVideoCapturer.captureDevices()
        for device in captureDevices {
            if device.position == position {
                return device
            }
        }
        return captureDevices.first
    }
    
    private func selectFormatForDevice(device: AVCaptureDevice) -> AVCaptureDevice.Format {
        let supportedFormats = RTCCameraVideoCapturer.supportedFormats(for: device)
        
        let targetWidth = Int(publishVideoResolution.rawValue.components(separatedBy: "x").first!)!
        let targetHeight = Int(publishVideoResolution.rawValue.components(separatedBy: "x").last!)!
        
        var selectedFormat: AVCaptureDevice.Format? = nil
        var currentDiff = INT_MAX
        
        for format in supportedFormats {
            let dimension: CMVideoDimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let diff = abs(targetWidth - Int(dimension.width)) + abs(targetHeight - Int(dimension.height));
            if diff < currentDiff {
                selectedFormat = format
                currentDiff = Int32(diff)
            }
        }
        return selectedFormat!
    }
    
    private func selectFpsForFormat(format: AVCaptureDevice.Format) -> Int {
        var maxFramerate: Float64 = 0
        
        for fpsRange in format.videoSupportedFrameRateRanges {
            maxFramerate = fmax(maxFramerate, fpsRange.maxFrameRate)
        }
        
        return Int(maxFramerate)
    }
    
    func capturer(_ capturer: RTCVideoCapturer, didCapture frame: RTCVideoFrame) {
        //os_log("Frame captured %@ x %@ pixels", log: Log.rtc, type: .debug, String(frame.width), String(frame.height))
        
        if let local = localVideoSource {
            local.capturer(capturer, didCapture: frame)
        }
    }

    private func stopCapture(type: StreamType, streamId: String) {
        if capturer != nil {
            capturer.stopCapture()
            
            delegate?.rtcClient(didChangeState: .localCaptureStoped, streamId: streamId, streamType: type, endpointId: UserEndpointModule.sharedInstance.userEndpointId!)
            capturer = nil
        } else {
            sdkLog("ARTCClient error stopping local capture", log: Log.rtc, type: .error)
        }
    }
    
    // MARK: - Background audio support

    /// Pauses video capture and disables remote video tracks while keeping audio and peer connections alive.
    internal func pauseVideoForBackground() {
        // Pause local video capture (keep capturer reference alive for resume)
        localVideoTrack?.isEnabled = false
        if capturer != nil {
            capturer.stopCapture()
        }

        // Disable remote video tracks to prevent GPU work in background
        for container in peerConnections where !container.isLocal {
            for receiver in container.connection.receivers {
                if receiver.track?.kind == "video" {
                    receiver.track?.isEnabled = false
                }
            }
        }

        // Ensure audio session stays active
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// Resumes video capture and re-enables remote video tracks after returning from background.
    internal func resumeVideoForForeground() {
        // Re-enable local video track and restart capture
        localVideoTrack?.isEnabled = true
        if capturer != nil {
            let position = usingFrontCamera ? AVCaptureDevice.Position.front : AVCaptureDevice.Position.back
            if let device = findDeviceForPosition(position: position) {
                let format = selectFormatForDevice(device: device)
                let fps = selectFpsForFormat(format: format)
                capturer.startCapture(with: device, format: format, fps: fps)
            }
        }

        // Re-enable remote video tracks
        for container in peerConnections where !container.isLocal {
            for receiver in container.connection.receivers {
                if receiver.track?.kind == "video" {
                    receiver.track?.isEnabled = true
                }
            }
        }
    }

    @discardableResult
    internal func switchCamera() -> CameraResponse {
        //#warning("Feature Idea: Change mic direction when user is switching camera (https://www.twilio.com/docs/video/ios-v2-configuring-audio-video-inputs-and-outputs)")
        self.usingFrontCamera = !self.usingFrontCamera
        
        if self.usingFrontCamera {
            publishVideoResolution = .min
        } else {
            publishVideoResolution = .max
        }
        
        return self.startCapture(type: switchCameStreamType, streamId: switchCamStreamId)
    }
    
    @discardableResult
    internal func changeAudioRoot(toSpeaker: Bool) -> Bool {
        audioPrefersSpeaker = toSpeaker
        //#warning("Feature Idea: Change audio session type for better audio quality (https://www.twilio.com/docs/video/ios-v2-configuring-audio-video-inputs-and-outputs)")
        if toSpeaker {
            do {
                try AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
                return true
            }
            catch {
                return false
            }
        }
        else{
            do {
                try AVAudioSession.sharedInstance().overrideOutputAudioPort(.none)
                return true
            }
            catch{
                return false
            }
        }
    }
}

extension RTCModule: ScreenCapturerDelegate {
    func onScreenSharingStart() {
        delegate?.rtcClient(didStartScreenSharing: true)
    }

    func onScreenSharingStop() {

    }

    func onScreenSharingFailed() {
        delegate?.rtcClient(didFailToStartScreenSharing: true)
    }
}
