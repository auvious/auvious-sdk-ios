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

//Return type for camera commands such as FlashOn, FlashOff, CameraSwitch etc.
internal typealias CameraResponse = (Bool, String)

internal protocol RTCDelegate {
    
    //required for client
    func rtcClient(didReceiveLocalVideoTrack localVideoTrack: RTCVideoTrack!)
    func rtcClient(didReceiveRemoteStream stream: RTCMediaStream, streamId: String, endpointId: String, type: StreamType)
    func rtcClient(didReceiveLocalStream stream: RTCMediaStream, streamId: String, type: StreamType)
    func rtcClient(onError error: AuviousSDKError)
    func rtcClient(didChangeState newState: StreamEventState, streamId: String, streamType: StreamType, endpointId: String)
    func rtcClient(agentSwitchedCamera toFront: Bool)
    
    //rest call
    func rtcClient(call streamId: String, sdpOffer: String, target: String)
    
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
    func rtcClient(call streamId: String, sdpOffer: String, target: String) {}
    func rtcClient(publishStream streamId: String, streamType: StreamType, sdpOffer: String) {}
    func rtcClient(didReceiveLocalStream stream: RTCMediaStream, streamId: String, type: StreamType) {}
    func rtcClient(didReceiveRemoteStream stream: RTCMediaStream, streamId: String, endpointId: String, type: StreamType) {}
    func rtcClient(remoteStream streamId: String, sdpOffer: String, remoteEndpointId: String, remoteUserId: String) {}
    func rtcClient(addPublishStreamIceCandidates candidates: [RTCIceCandidate], streamId: String, streamType: StreamType) {}
    func rtcClient(addRemoteStreamIceCandidates candidates: [RTCIceCandidate], userId: String, endpointId: String, streamId: String, streamType: StreamType) {}
}

internal final class RTCModule: NSObject, RTCPeerConnectionDelegate, RTCVideoCapturerDelegate {
    
    //List of connections used
    internal var peerConnections: [RTCPeerConnectionContainer] = [RTCPeerConnectionContainer]()
    
    //Connection factory
    private var factory: RTCPeerConnectionFactory!
    
    //Default connection constraint, used when instatiating a connection
    private let defaultConnectionConstraint = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: ["DtlsSrtpKeyAgreement": "true"])
    
    private var capturer: RTCCameraVideoCapturer!
    private var localVideoSource: RTCVideoSource?
    
    private var usingFrontCamera: Bool = true
    private var switchCamStreamId: String = ""
    private var switchCameStreamType: StreamType! = .unknown
    
    var iceServers: [RTCIceServer] = []

    var publishVideoResolution: PublishVideoResolution = .min
    
    var delegate: RTCDelegate?
    
    private var outgoingCallStreamType: StreamType?
    
    //Latest local captured frame
    private var lastLocalFrame: RTCVideoFrame?
    private var capturingScreenshot: Bool = false
    
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
    
    //Configures a stream for publishing in a call (create call)
    internal func configureCallStream(type: StreamType, streamId: String, endpointId: String, userId: String, target: String, localStream: RTCMediaStream? = nil) {
        
        self.outgoingCallStreamType = type
        
        //Create a new RTCPeerConnection
        initialisePeerConnection(streamId: streamId, endpointId: endpointId, userId: userId, type: type, isLocal: true, callId: streamId)
        
        //Add the stream obtained, or use the provided one
        if let stream = localStream {
            
            guard let peerConnection = getConnectionForStream(streamId: streamId) else {
                delegate?.rtcClient(onError: AuviousSDKError.missingPeerConnection(streamId: streamId))
                return
            }
            
            peerConnection.add(stream)
        } else {
            if type == .cam || type == .mic || type == .micAndCam {
                addStream(type: type, streamId: streamId)
            }
        }
        
        makeOfferCallStream(type:type, streamId: streamId, target: target)
    }
    
    //Configures an outgoing stream for a call (answer call)
    internal func configureRemoteCallStream(event: CallCreatedEvent, userEndpointId: String, userId: String, streamId: String, remoteStreamType: StreamType, outgoingStreamType: StreamType) {
        let callId = event.callId!
        let endpointId = event.userEndpointId!
        let userId = event.userId!
        let sdpOffer = event.sdpOffer!
        
        //Create a new RTCPeerConnection
        initialisePeerConnection(streamId: callId, endpointId: endpointId, userId: userId, type: remoteStreamType, isLocal: true, callId: callId)
        
        //if we are sending audio and/or video create a stream for it
        if outgoingStreamType == .cam || outgoingStreamType == .mic || outgoingStreamType == .micAndCam {
            self.outgoingCallStreamType = outgoingStreamType
            addStream(type: outgoingStreamType, streamId: callId)
        }
        
        //Get back our connection
        let results = peerConnections.filter{$0.callId == callId}
        guard let object = results.first else {
            delegate?.rtcClient(onError: AuviousSDKError.missingPeerConnection( streamId: streamId))
            return
        }
        
        let offer = RTCSessionDescription(type: .offer, sdp: sdpOffer)
        object.connection.setRemoteDescription(offer, completionHandler: {(error) in
            if error == nil {
                
                object.connection.answer(for: self.createConstraintForConference(type: remoteStreamType), completionHandler: {(sessionDescription, error) in
                    
                    if error == nil {
                        object.connection.setLocalDescription(sessionDescription!, completionHandler: {(error) in
                            
                            if error == nil {
                                self.invokeAnswer(callId: callId, sdpAnswer: sessionDescription!.sdp, userEndpointId: userEndpointId, userId: userId, container: object)
                                
                            } else {
                                os_log("ARTCClient set local description ERROR %@", log: Log.rtc, type: .error, error!.localizedDescription)
                            }
                        })
                    } else {
                        os_log("ARTCClient sdp answer creation FAILURE - error %@", log: Log.rtc, type: .error, error!.localizedDescription)
                    }
                })
                
            } else {
                os_log("ARTCClient remote description FAILED for call answer. Error is %@", log: Log.rtc, type: .error, error!.localizedDescription)
            }
        })
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
    internal func initialisePeerConnection(streamId: String, endpointId: String, userId: String, type: StreamType, isLocal: Bool, callId: String? = nil) {
        let configuration = RTCConfiguration()
        configuration.iceServers = iceServers
        
        let connection = factory.peerConnection(with: configuration, constraints: self.defaultConnectionConstraint, delegate: self)
        let connectionContainer = RTCPeerConnectionContainer(conn: connection, streamId: streamId, endpointId: endpointId, userId: userId, type: type, isLocal: isLocal)
        
        if let callId = callId {
            connectionContainer.callId = callId
        }
        
        peerConnections.append(connectionContainer)
        os_log("Created connection for stream type", log: Log.rtc, type: .debug, type.rawValue)
    }
    
    //Returns the connection created for the given stream id, if any
    private func getConnectionForStream(streamId: String) -> RTCPeerConnection? {
        let results = peerConnections.filter{$0.streamId == streamId}
        guard let object = results.first else {
            delegate?.rtcClient(onError: AuviousSDKError.missingPeerConnection( streamId: streamId))
            return nil
        }
        
        return object.connection
    }
    
    private func addStream(type: StreamType, streamId: String) {
        guard let peerConnection = getConnectionForStream(streamId: streamId) else {
            delegate?.rtcClient(onError: AuviousSDKError.missingPeerConnection(streamId: streamId))
            return
        }
        
        let localStream = createLocalMediaStream(type: type, streamId: streamId)
        peerConnection.add(localStream)
    }
    
    internal func createLocalMediaStream(type: StreamType, streamId: String) -> RTCMediaStream {
        os_log("createLocalMediaStream() for type %@ and stream %@", log: Log.rtc, type: .debug, type.rawValue, streamId)
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
                os_log("local video track added", log: Log.rtc, type: .debug)
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
    
    private func makeOfferCallStream(type: StreamType, streamId: String, target: String) {
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
                self?.handleSdpGeneratedPublishCall(sdpDescription: sdp, streamType:type, streamId: streamId, target: target)
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
    
    private func createConstraintForCall(type: StreamType) -> RTCMediaConstraints {
        return RTCMediaConstraints(mandatoryConstraints: ["OfferToReceiveAudio" : "true", "OfferToReceiveVideo": "true"], optionalConstraints: nil)
    }
    
    internal func makeOfferRemoteStream(type: StreamType, streamId: String) {
        guard let peerConnection = getConnectionForStream(streamId: streamId) else {
            delegate?.rtcClient(onError: AuviousSDKError.missingPeerConnection(streamId: streamId))
            return
        }
        
        let constraint = createConstraintForConference(type: type)
        peerConnection.offer(for: constraint, completionHandler: { [weak self]  (sdp, error) in
            guard let _ = self else {
                return
            }
            if let error = error {
                self!.delegate?.rtcClient(onError: AuviousSDKError.remoteStreamFailure(fragment: .makeOfferRemoteStream, output: error.localizedDescription))
            }
            else {
                self?.handleSdpGeneratedRemote(sdpDescription: sdp, streamId: streamId)
            }
        })
    }
    
    private func handleSdpGeneratedPublishCall(sdpDescription: RTCSessionDescription?, streamType: StreamType, streamId: String, target: String) {
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
                //Use rest call
                self?.invokeCall(sdpDescription: sdpDescription!, streamId: streamId, target: target)
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
    
    private func invokeAnswer(callId: String, sdpAnswer: String, userEndpointId: String, userId: String, container: RTCPeerConnectionContainer) {
        let object = CallAnswerRequest(callId: callId, sdpAnswer: sdpAnswer, userEndpointId: userEndpointId, userId: userId)
        API.sharedInstance.answerCall(object, onSuccess: {(json) in
            
            if let _ = json {
                
                if !container.iceCandidates.isEmpty {
                    
                    var candidatesArray:[IceCandidate] = [IceCandidate]()
                    for item in container.iceCandidates {
                        let obj = IceCandidate(candidate: item.sdp, sdpMLineIndex: item.sdpMLineIndex, sdpMid: item.sdpMid!)
                        candidatesArray.append(obj)
                    }
                    
                    let iceCandidatesRequest = CallIceCandidatesRequest(callId: callId, candidates: candidatesArray, userEndpointId: userEndpointId, userId: userId)
                    API.sharedInstance.addCallIceCandidates(iceCandidatesRequest, onSuccess: {(json) in
                        
                        if let _ = json {
                            //success
                        }
                        
                    }, onFailure: {(error) in
                        os_log("addCallIceCandidates request error %@", log: Log.rtc, type: .error, error.localizedDescription)
                    })
                }
            }
        }, onFailure: {(error) in
            os_log("answer call error %@", log: Log.rtc, type: .error, error.localizedDescription)
        })
        
    }
    
    internal func handleTerminatedCall(_ callId: String) {
        let containerList = peerConnections.filter{$0.callId == callId}
        guard containerList.first != nil else {
            os_log("error no connection for call id %@", log: Log.rtc, type: .error, callId)
            delegate?.rtcClient(onError: AuviousSDKError.missingPeerConnection(streamId: callId))
            return
        }
        
        if let outgoingStream = outgoingCallStreamType {
            stopCapture(type: outgoingStream, streamId: callId)
            removeAllStreams()
        }
    }
    
    internal func handleCallRejectedEvent(_ event: CallRejectedEvent) {
        let containerList = peerConnections.filter{$0.callId == event.callId!}
        guard containerList.first != nil else {
            os_log("error no connection for call id %@", log: Log.rtc, type: .error, event.callId!)
            delegate?.rtcClient(onError: AuviousSDKError.missingPeerConnection(streamId: event.callId))
            return
        }
        
        if let outgoingStream = outgoingCallStreamType {
            stopCapture(type: outgoingStream, streamId: event.callId)
            removeAllStreams()
        }
    }
    
    internal func handleCallEndedEvent(_ event: CallEndedEvent){
        let containerList = peerConnections.filter{$0.callId == event.callId!}
        guard containerList.first != nil else {
            os_log("error no connection for call id %@", log: Log.rtc, type: .error, event.callId!)
            delegate?.rtcClient(onError: AuviousSDKError.missingPeerConnection(streamId: event.callId))
            return
        }
        
        if let outgoingStream = outgoingCallStreamType {
            stopCapture(type: outgoingStream, streamId: event.callId)
            removeAllStreams()
        }
    }
    
    internal func handleCallAnsweredEvent(_ event: CallAnsweredEvent, userEndpointId: String, userId: String) {
        let containerList = peerConnections.filter{$0.callId == event.callId!}
        guard containerList.first != nil else {
            os_log("error no connection for call id %@", log: Log.rtc, type: .error, event.callId!)
            delegate?.rtcClient(onError: AuviousSDKError.missingPeerConnection(streamId: event.callId))
            return
        }
        
        event.sdpAnswer = event.sdpAnswer.replacingOccurrences(of: "h264", with: "H264")
        event.sdpAnswer = event.sdpAnswer.replacingOccurrences(of: "vp8", with: "VP8")
        
        let sessionDescription = RTCSessionDescription.init(type: .answer, sdp: event.sdpAnswer)
        containerList.first?.connection.setRemoteDescription(sessionDescription, completionHandler: {(error) in
            
            if error != nil {
                //error
            } else {
                
                //invoke rest call
                var candidatesArray:[IceCandidate] = [IceCandidate]()
                if let container = containerList.first {
                    for item in container.iceCandidates {
                        let obj = IceCandidate(candidate: item.sdp, sdpMLineIndex: item.sdpMLineIndex, sdpMid: item.sdpMid!)
                        candidatesArray.append(obj)
                    }
                    
                    let iceCandidatesRequest = CallIceCandidatesRequest(callId: event.callId, candidates: candidatesArray, userEndpointId: userEndpointId, userId: userId)
                    API.sharedInstance.addCallIceCandidates(iceCandidatesRequest, onSuccess: {(json) in
                        
                        if let _ = json {
                            //success
                        }
                        
                    }, onFailure: {(error) in
                        os_log("addCallIceCandidates request error %@", log: Log.rtc, type: .error, error.localizedDescription)
                    })
                }
            }
        })
    }
    
    internal func addCallIceCandidates(event: IceCandidatesFoundEvent) {
        let containerList = peerConnections.filter{$0.callId == event.callId!}
        guard containerList.first != nil else {
            os_log("error no connection for call id %@", log: Log.rtc, type: .error, event.callId!)
            delegate?.rtcClient(onError: AuviousSDKError.missingPeerConnection(streamId: event.callId))
            return
        }
        
        for candidate in event.iceCandidates {
            let c = RTCIceCandidate(sdp: candidate.candidate, sdpMLineIndex: candidate.sdpMLineIndex, sdpMid: candidate.sdpMid)
            containerList.first?.connection.add(c)
        }
    }
    
    private func invokeCall(sdpDescription: RTCSessionDescription, streamId: String, target: String) {
        delegate?.rtcClient(call: streamId, sdpOffer: sdpDescription.sdp, target: target)
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
        
        if isPublish {
            delegate?.rtcClient(addPublishStreamIceCandidates: container.iceCandidates, streamId:streamId, streamType: container.streamType)
        }
        else{
            delegate?.rtcClient(addRemoteStreamIceCandidates: container.iceCandidates, userId:container.userId, endpointId:container.endpointId, streamId:streamId, streamType: container.streamType)
        }
    }
    
    //------------------------------------------
    internal func removePublishStreams(streamId: String) -> Bool{
        
        var objects = peerConnections.filter {$0.streamId == streamId}
        for (index, obj) in objects.enumerated() {
            if(obj.streamId == streamId){
                let peerConnection = obj.connection
                
                if(obj.streamType == .cam || obj.streamType == .micAndCam){
                    stopCapture(type: obj.streamType, streamId: obj.streamId)
                }
                
                peerConnection?.close()
                objects.remove(at: index)
                
                return true
            }
        }
        return false
    }
    
    internal func removeRemoteStreams(streamId: String) -> Bool{
        
        var objects = peerConnections.filter {$0.streamId == streamId}
        for (index, obj) in objects.enumerated() {
            if(obj.streamId == streamId){
                let peerConnection = obj.connection
                peerConnection?.close()
                objects.remove(at: index)
                
                return true
            }
        }
        return false
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
                        let _ = streamConnection.connection.localStreams.map {$0.audioTracks.map {$0.isEnabled = false} }
                    } else if event.streamType == MetadataRequestType.video {
                        //Mute video
                        let _ = streamConnection.connection.localStreams.map {$0.videoTracks.map {$0.isEnabled = false} }
                    }
                } else {
                    if event.streamType == MetadataRequestType.audio {
                        //Unmute audio
                        let _ = streamConnection.connection.localStreams.map {$0.audioTracks.map {$0.isEnabled = true} }
                    } else if event.streamType == MetadataRequestType.video {
                        //Unmute video
                        let _ = streamConnection.connection.localStreams.map {$0.videoTracks.map {$0.isEnabled = true} }
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
                os_log("headphone plugged in", log: Log.rtc, type: .debug)
            } else {
                os_log("headphone pulled out", log: Log.rtc, type: .debug)
                changeAudioRoot(toSpeaker: true)
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
                os_log("Headphones/Bluetooth device just connected", log: Log.rtc, type: .debug)
                break
            }
        case .oldDeviceUnavailable:
            if let previousRoute =
                userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription {
                for output in previousRoute.outputs where output.portType == AVAudioSession.Port.headphones || output.portType == AVAudioSession.Port.bluetoothHFP || output.portType == AVAudioSession.Port.bluetoothA2DP || output.portType == AVAudioSession.Port.bluetoothLE {
                    os_log("Headphones/Bluetooth device just removed, switching to speaker", log: Log.rtc, type: .debug)
                    changeAudioRoot(toSpeaker: true)
                    break
                }
            }
        default: ()
        }
    }
    
    // MARK: RTCPeerConnectionDelegate
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        
        var targetContainer: RTCPeerConnectionContainer!
        for item in peerConnections {
            if item.connection == peerConnection {
                targetContainer = item
                break
            }
        }
        
        checkCurrentAudioRoute()
        
        delegate?.rtcClient(didReceiveRemoteStream: stream, streamId: targetContainer.streamId, endpointId: targetContainer.endpointId, type: targetContainer.streamType)
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
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
//        os_log("RTCPeerConnectionDelegate - ARTCClient - Channel did open", log: Log.rtc, type: .debug)
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
        //os_log("RTCPeerConnectionDelegate - ARTCClient - Connection state changed: %@", log: Log.rtc, type: .debug, newState.rawValue)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        //os_log("RTCPeerConnectionDelegate - ARTCClient - Candidate was removed", log: Log.rtc, type: .debug)
    }
    
    // MARK: Camera controls
    internal func toggleFlash(on: Bool) -> CameraResponse {
        let position = self.usingFrontCamera ? AVCaptureDevice.Position.front : AVCaptureDevice.Position.back
        guard let device = self.findDeviceForPosition(position: position) else {
            return CameraResponse(false, "Unable to access camera")
        }
        
        guard device.hasTorch && device.isTorchAvailable else {
            os_log("no torch available", log: Log.rtc, type: .debug)
            return CameraResponse(false, "No torch available")
        }
        
        do {
            try device.lockForConfiguration()
            
            if on {
                os_log("Torch set to on", log: Log.rtc, type: .debug)
                device.torchMode = .on
            } else {
                os_log("Torch set to off", log: Log.rtc, type: .debug)
                device.torchMode = .off
            }
            
            device.unlockForConfiguration()
        } catch {
            return CameraResponse(false, "Unable to access torch")
        }
        
        return CameraResponse(true, "")
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
            if !capturingScreenshot {
                self.lastLocalFrame = frame
            }
            
            local.capturer(capturer, didCapture: frame)
        }
    }

    private func stopCapture(type: StreamType, streamId: String) {
        if capturer != nil {
            capturer.stopCapture()
            
            delegate?.rtcClient(didChangeState: .localCaptureStoped, streamId: streamId, streamType: type, endpointId: UserEndpointModule.sharedInstance.userEndpointId!)
            capturer = nil
        } else {
            os_log("ARTCClient error stopping local capture", log: Log.rtc, type: .error)
        }
    }
    
    @discardableResult
    internal func switchCamera(fromRemoteAgent: Bool = false) -> CameraResponse {
        //#warning("Feature Idea: Change mic direction when user is switching camera (https://www.twilio.com/docs/video/ios-v2-configuring-audio-video-inputs-and-outputs)")
        self.usingFrontCamera = !self.usingFrontCamera
        
        if self.usingFrontCamera {
            publishVideoResolution = .min
        } else {
            publishVideoResolution = .max
        }
        
        //Inform the client about a successful camera switch, if triggered by a remote agent
        let response = self.startCapture(type: switchCameStreamType, streamId: switchCamStreamId)
        if fromRemoteAgent && response.0 == true {
            delegate?.rtcClient(agentSwitchedCamera: self.usingFrontCamera)
        }
        
        return response
    }
    
    internal func getSnapshot() -> UIImage? {
        if let frame = lastLocalFrame {
            capturingScreenshot = true
            
            let buffer = frame.buffer as! RTCCVPixelBuffer
            let pixBuffer = buffer.pixelBuffer
            let ciImage = CIImage(cvImageBuffer: pixBuffer)
            
            let context = CIContext(options:nil)
            let cgImage = context.createCGImage(ciImage, from: ciImage.extent)
            
            if let cgi = cgImage {
                let imageRaw = UIImage(cgImage: cgi)
                let image = imageRaw.fixedOrientation().imageRotatedByDegrees(degrees: 90.0)
                
                capturingScreenshot = false
                return image
            } else {
                capturingScreenshot = false
                return nil
            }
            
        } else {
            os_log("getSnapshot() error", log: Log.rtc, type: .error)
            capturingScreenshot = false
            return nil
        }
    }
    
    @discardableResult
    internal func changeAudioRoot(toSpeaker: Bool) -> Bool {
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
