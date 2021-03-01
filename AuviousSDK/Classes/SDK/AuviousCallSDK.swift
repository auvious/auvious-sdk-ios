//
//  AuviousCallSDK.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 14/05/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import Foundation
import CallKit
import os

public final class AuviousCallSDK: MQTTCallDelegate, RTCDelegate, UserEndpointDelegate, MQTTSnapshotDelegate {
    
    /// Singleton instance
    public static let sharedInstance = AuviousCallSDK()
    
    /// The username property, used for logging in
    internal var username: String?
    
    /// The password property, used for logging in
    internal var password: String?
    
    /// The organization property, used for logging in
    internal var organization: String?
    
    /// Determines whether the user is logged in
    public var isLoggedIn: Bool {
        return AuthenticationModule.sharedInstance.isLoggedIn
    }
    
    /// The user's endpoint
    public var userEndpointId: String? {
        return UserEndpointModule.sharedInstance.userEndpointId
    }
    
    /// The id of the current call, if any
    private var currentCallId: String?
    
    /// Optional SIP headers to be used
    private var sipHeaders: [String : String]?

    /// ARTCClient handles all things streams related
    internal var rtcClient: RTCModule!
    
    /// The video resolution to be used when publishing
    public var publishVideoResolution: PublishVideoResolution = .min
    
    /// This delegate informs of all call related stream state changes and errors
    public var delegate: AuviousSDKCallDelegate?
    
    /// Reference to the background task used for gracefully stopping streams
    private var backgroundTask: UIBackgroundTaskIdentifier = UIBackgroundTaskIdentifier.invalid
    
    internal var callObserver: CallObserver!
    
    //MARK: -
    //MARK: Pause/Resume handlers
    //MARK: -
    
    /// Background task completion handler, invalidates the background task.
    private func endBackgroundTask(){
        os_log("Background task ended", log: Log.callSDK, type: .debug)
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = UIBackgroundTaskIdentifier.invalid
    }
    
    /**
     Should be called when the application is backgrounded in order to gracefully
     disconnect from remote streams.
     */
    public func onApplicationPause(){
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
        
        guard let loginResponse = AuthenticationModule.sharedInstance.loginResponse, let userId = loginResponse.userId, let endpointId = UserEndpointModule.sharedInstance.userEndpointId else {
            os_log("onApplicationPause - not logged in, nothing to do", log: Log.callSDK, type: .debug)
            endBackgroundTask()
            return
        }
        
        //if in a call - hangup
        if let currentCall = currentCallId {
            os_log("onApplicationPause - already in a call, hanging up", log: Log.callSDK, type: .debug)
            do {
                try hangupCall(callId: currentCall)
                UserEndpointModule.sharedInstance.destroyEndpoint(endpointId: endpointId, userId: userId, onSuccess: {
                    MQTTModule.sharedInstance.disconnect()
                    self.endBackgroundTask()
                }, onFailure: {(error) in
                    MQTTModule.sharedInstance.disconnect()
                    self.endBackgroundTask()
                })
            } catch _ {
                os_log("onApplicationPause - error while trying to hangup current call", log: Log.callSDK, type: .debug)
                MQTTModule.sharedInstance.disconnect()
                self.endBackgroundTask()
            }
        } else {
            //rtc connection cleanup
            self.rtcClient.removeAllStreams()
            
            //endpoint unregister + endpoint stop timer + mqtt disconnect
            UserEndpointModule.sharedInstance.destroyEndpoint(endpointId: endpointId, userId: userId, onSuccess: {
                MQTTModule.sharedInstance.disconnect()
                self.endBackgroundTask()
            }, onFailure: {(error) in
                MQTTModule.sharedInstance.disconnect()
                self.endBackgroundTask()
            })
        }
    }
    
    /**
     Should be called when the application is foregrounded in order to automatically
     relogin, create an endpoint and reconnect to mqtt.
     */
    public func onApplicationResume(){
        //Ensure we have logged in, and have created an endpoint
        guard let loginResponse = AuthenticationModule.sharedInstance.loginResponse, let userId = loginResponse.userId else {
            return
        }
        
        guard let userEndpointId = UserEndpointModule.sharedInstance.userEndpointId else {
            return
        }
        
        //Check if endpoint is alive
        UserEndpointModule.sharedInstance.keepAliveRequest = KeepAliveRequest(userEndpointId: userEndpointId, userId: userId)
        API.sharedInstance.keepAlive(UserEndpointModule.sharedInstance.keepAliveRequest!, onSuccess: {(json) in
            if let _ = json {
                UserEndpointModule.sharedInstance.startKeepAliveTimer()
                MQTTModule.sharedInstance.reconnect()
                os_log("onApplicationResume() - ready for call", log: Log.callSDK, type: .debug)
                
            } else {
                self.delegate?.auviousSDK(onError: AuviousSDKError.connectionError)
            }
        }, onFailure: {(error) in
            os_log("onApplicationResume() keep alive failed - creating new endpoint", log: Log.callSDK, type: .debug)
            UserEndpointModule.sharedInstance.createEndpoint(newEndpointId: UUID().uuidString, userId: userId, onSuccess: {(newEndpointId) in
                
                os_log("onApplicationResume() - created new endpoint %@", log: Log.callSDK, type: .debug, newEndpointId)
                MQTTModule.sharedInstance.configure(endpointId: newEndpointId)
                MQTTModule.sharedInstance.reconnect()
                
            }, onFailure: {(error) in
                self.delegate?.auviousSDK(onError: AuviousSDKError.connectionError)
            })
        })
    }
    
    /**
     Configures the Auvious SDK with the necessary user and server settings.
     
     - Parameter username: The username
     - Parameter password: The password
     - Parameter organization: The user's organization
     */
    public func configure(username: String, password: String, organization: String, baseEndpoint: String, mqttEndpoint: String) {
        self.username = username
        self.password = password
        self.organization = organization
        
        //Create an instance of the RTC module. This will be configured later on, once we obtain TURN/STUN endpoints
        rtcClient = RTCModule()
        rtcClient.delegate = self
        rtcClient.initialisePeerConnectionFactory()
        
        ServerConfiguration.baseRTC = baseEndpoint
        ServerConfiguration.baseMeeting = baseEndpoint
        ServerConfiguration.mqttHost = mqttEndpoint
        
        //Start the call observer
        callObserver = CallObserver()
        callObserver.start()
    }
    
    //RTC client
    private func initializeARTCClient(){
        if rtcClient == nil {
            rtcClient = RTCModule()
        }
        
        rtcClient.iceServers = ServerConfiguration.iceServers

        rtcClient.publishVideoResolution = publishVideoResolution
        rtcClient.delegate = self
        rtcClient.initialisePeerConnectionFactory()
    }
    
    /**
     Switches the device camera (rear & front).
     */
    public func switchCamera() {
        let _ = rtcClient.switchCamera()
    }
    
    /**
     Switches the audio routing (speaker, headphones)
     */
    public func changeAudioRoot(toSpeaker: Bool) -> Bool {
        return rtcClient.changeAudioRoot(toSpeaker: toSpeaker)
    }
    
    /**
     Performs a login, using the configuration settings already provided.
     
     - Parameter oAuth: Determines the type of authentication to be used internally
     - Parameter onLoginSuccess: Called after a successful login, returning your endpoint
     - Parameter onLoginFailure: Called in case of failure with the designated Error
     */
    public func login(oAuth: Bool, onLoginSuccess: @escaping (String?)->(), onLoginFailure: @escaping (Error)->()) {
        guard let username = self.username, let password = self.password, let _ = self.organization else {
            onLoginFailure(AuviousSDKError.missingSDKCredentials)
            return
        }
        
        AuthenticationModule.sharedInstance.login(params: [:], username: username, password: password, onSuccess: {endpointId, conferenceId in
            
            if let endpoint = endpointId {
                //Server configuration has already been retrieved
                AuviousCallSDK.sharedInstance.initializeARTCClient()
                
                MQTTModule.sharedInstance.configure(endpointId: endpoint)
                MQTTModule.sharedInstance.callDelegate = self
                MQTTModule.sharedInstance.snapshotDelegate = self
                MQTTModule.sharedInstance.connect(onSubscription: {
                    onLoginSuccess(endpointId)
                    //We no longer want the closure to be called
                    MQTTModule.sharedInstance.clearSubscriptionCallback()
                })
            }
            
        }, onFailure: {error in
            onLoginFailure(error)
        })
    }
    
    public func logout(onSuccess: @escaping ()->(), onFailure: @escaping (Error)->()) {

        guard let loginResponse = AuthenticationModule.sharedInstance.loginResponse, let userId = loginResponse.userId else {
            onFailure(AuviousSDKError.notLoggedIn)
            return
        }
        
        guard let endpointId = UserEndpointModule.sharedInstance.userEndpointId else {
            onFailure(AuviousSDKError.endpointNotCreated)
            return
        }
        
        AuthenticationModule.sharedInstance.isLoggedIn = false
        
        //if in a call - hangup
        if let currentCall = currentCallId {
            do {
                try hangupCall(callId: currentCall)
                UserEndpointModule.sharedInstance.destroyEndpoint(endpointId: endpointId, userId: userId, onSuccess: {
                    MQTTModule.sharedInstance.disconnect()
                    onSuccess()
                }, onFailure: {(error) in
                    MQTTModule.sharedInstance.disconnect()
                    onFailure(error)
                })
            } catch let error {
                onFailure(error)
            }
        } else {
            //rtc connection cleanup
            self.rtcClient.removeAllStreams()
            
            //endpoint unregister + endpoint stop timer + mqtt disconnect
            UserEndpointModule.sharedInstance.destroyEndpoint(endpointId: endpointId, userId: userId, onSuccess: {
                MQTTModule.sharedInstance.disconnect()
                onSuccess()
            }, onFailure: {(error) in
                MQTTModule.sharedInstance.disconnect()
                onFailure(error)
            })
        }
    }
    
    //MARK: -
    //MARK: UserEndpoint delegate
    //MARK: -
    
    func userEndpoint(onError error: AuviousSDKError) {
        delegate?.auviousSDK(onError: error)
    }
    
    //MARK: -
    //MARK: SDK Call functions
    //MARK: -
    
    //Exposed for the needs of AuviousCallVC
    public func createLocalMediaStream(type: StreamType, streamId: String) -> RTCMediaStream {
        let stream = rtcClient.createLocalMediaStream(type: type, streamId: streamId)
        return stream
    }
    
    /**
     Starts an outgoing call, using the provided settings.
     
     - Parameter target: The user id to call
     - Parameter sendMode: The type of our local stream (i.e. mic, cam etc.)
     - Parameter localStream: The local stream to use. In case we've already created it, for UI purposes
     - Parameter sipHeaders: Optional SIP headers to be used for this call
     */
    public func startCallFlow(target: String, sendMode: StreamType, localStream: RTCMediaStream? = nil, sipHeaders: [String : String]? = nil) throws -> String? {
        
        guard let loginResponse = AuthenticationModule.sharedInstance.loginResponse, let userId = loginResponse.userId else {
            throw AuviousSDKError.notLoggedIn
        }
        
        guard let endpointId = UserEndpointModule.sharedInstance.userEndpointId else {
            throw AuviousSDKError.endpointNotCreated
        }
        
        //Keep a copy of the SIP headers for the call
        AuviousCallSDK.sharedInstance.sipHeaders = sipHeaders
        
        let callId = UUID().uuidString
        currentCallId = callId
        
        delegate?.auviousSDK(didChangeState: .localStreamIsConnecting, callId: callId, streamType: sendMode)
        rtcClient.configureCallStream(type: sendMode, streamId: callId, endpointId: endpointId, userId: userId, target: target)
        
        return callId
    }
    
    //invokes the ringing rest call
    private func invokeRinging(callId: String, fromEndpointId: String, fromUserId: String) throws {
        guard let loginResponse = AuthenticationModule.sharedInstance.loginResponse, let userId = loginResponse.userId else {
            throw AuviousSDKError.notLoggedIn
        }
        
        guard let userEndpointId = UserEndpointModule.sharedInstance.userEndpointId else {
            throw AuviousSDKError.endpointNotCreated
        }
        
        let object = CallRingingRequest(callId: callId, userEndpointId: userEndpointId, userId: userId)
        API.sharedInstance.callRinging(object, onSuccess: { (json) in
            
            if let _ = json {
                //success
            }
            
        }, onFailure: {(error) in
            self.delegate?.auviousSDK(onError: .callError)
        })
    }
    
    public func acceptCall(callEvent: CallCreatedEvent, sendMode: StreamType, receiveMode: StreamType) throws {
        guard let loginResponse = AuthenticationModule.sharedInstance.loginResponse, let userId = loginResponse.userId else {
            throw AuviousSDKError.notLoggedIn
        }
        
        guard let userEndpointId = UserEndpointModule.sharedInstance.userEndpointId else {
            throw AuviousSDKError.endpointNotCreated
        }
        
        let outboundStreamId = UUID().uuidString
        rtcClient.configureRemoteCallStream(event: callEvent, userEndpointId: userEndpointId, userId: userId, streamId: outboundStreamId, remoteStreamType: receiveMode, outgoingStreamType: sendMode)
    }
    
    public func rejectCall(callEvent: CallCreatedEvent, reason: String) throws {
        guard let loginResponse = AuthenticationModule.sharedInstance.loginResponse, let userId = loginResponse.userId else {
            throw AuviousSDKError.notLoggedIn
        }
        
        guard let userEndpointId = UserEndpointModule.sharedInstance.userEndpointId else {
            throw AuviousSDKError.endpointNotCreated
        }
        
        let request = CallRejectRequest(callId: callEvent.callId, reason: reason, userEndpointId: userEndpointId, userId: userId)
        API.sharedInstance.rejectCall(request, onSuccess: {(json) in
            
            if let _ = json {
                //success
            }
            
        }, onFailure: {(error) in
            self.delegate?.auviousSDK(onError: .callError)
        })
    }
    
    public func cancelCall(callId: String) throws {
        guard let loginResponse = AuthenticationModule.sharedInstance.loginResponse, let userId = loginResponse.userId else {
            throw AuviousSDKError.notLoggedIn
        }
        
        guard let userEndpointId = UserEndpointModule.sharedInstance.userEndpointId else {
            throw AuviousSDKError.endpointNotCreated
        }
        
        let request = CallCancelRequest(callId: callId, userEndpointId: userEndpointId, userId: userId)
        API.sharedInstance.callCancel(request, onSuccess: {(json) in
            
            if let _ = json {
                self.rtcClient.handleTerminatedCall(callId)
            }
            
        }, onFailure: {(error) in
            self.delegate?.auviousSDK(onError: .callError)
        })
    }
    
    public func hangupCall(callId: String) throws {
        guard let loginResponse = AuthenticationModule.sharedInstance.loginResponse, let userId = loginResponse.userId else {
            throw AuviousSDKError.notLoggedIn
        }
        
        guard let userEndpointId = UserEndpointModule.sharedInstance.userEndpointId else {
            throw AuviousSDKError.endpointNotCreated
        }
        
        let request = CallHangupRequest(callId: callId, reason: "No reason", userEndpointId: userEndpointId, userId: userId)
        API.sharedInstance.callHangup(request, onSuccess: {(json) in
            
            //Close all connections
            if let _ = json {
                self.rtcClient.removeAllStreams()
            }
            
        }, onFailure: {(error) in
            self.rtcClient.removeAllStreams()
            self.delegate?.auviousSDK(onError: .callError)
        })
    }
    
    //MARK: Snapshots
    
    internal func respondToCameraRequest(request: SnapshotCameraRequestedEvent, result: CameraResponse) throws {
        guard let loginResponse = AuthenticationModule.sharedInstance.loginResponse, let userId = loginResponse.userId else {
            throw AuviousSDKError.notLoggedIn
        }
        
        guard let userEndpointId = UserEndpointModule.sharedInstance.userEndpointId else {
            throw AuviousSDKError.endpointNotCreated
        }
        
        let object = SnapshotCameraRQRPRequest(info: result.1, snapshotCameraRequestId: request.snapshotCameraRequestId, succeeded: result.0, userEndpointId: userEndpointId, userId: userId)
        API.sharedInstance.cameraRequestRespond(object, onSuccess: {json in
            
            if let _ = json {
                //success
            }
            
        }, onFailure: {error in
            self.delegate?.auviousSDK(onError: .internalError)
        })
    }
    
    internal func uploadSnapshot(request: SnapshotRequestedEvent, snapshot: UIImage) throws {
        guard let loginResponse = AuthenticationModule.sharedInstance.loginResponse, let userId = loginResponse.userId else {
            throw AuviousSDKError.notLoggedIn
        }
        
        guard let userEndpointId = UserEndpointModule.sharedInstance.userEndpointId else {
            throw AuviousSDKError.endpointNotCreated
        }
        
        let upload = SnapshotUploadRequest(snapshot: snapshot, id: request.snapshotId, suffix: "jpeg", type: request.snapshotType, userEndpointId:  userEndpointId, userId: userId)
        API.sharedInstance.uploadSnapshot(upload, onSuccess: {
            //success
        }, onFailure: {error in
            //error
        })
    }
    
    //MARK: MQTTSnapshotDelegate
    
    func snapshotMessageReceived(_ object: SnapshotEvent) {
        switch object.type! {
        case .snapshotAcquiredEvent:
            os_log("snapshotAcquiredEvent msg received", log: Log.callSDK, type: .debug)
        case .snapshotApprovedEvent:
            os_log("snapshotApprovedEvent msg received", log: Log.callSDK, type: .debug)
        case .snapshotCameraRequestedEvent:
            os_log("snapshotCameraRequestedEvent msg received", log: Log.callSDK, type: .debug)
            
            let obj = object as! SnapshotCameraRequestedEvent
            switch obj.cameraRequestType! {
            case .cameraSwitch:
                let cameraResponse = rtcClient.switchCamera(fromRemoteAgent: true)
                do {
                    try respondToCameraRequest(request: obj, result: cameraResponse)
                } catch {}
                
            case .flashOff:
                let cameraResponse = rtcClient.toggleFlash(on: false)
                do {
                    try respondToCameraRequest(request: obj, result: cameraResponse)
                } catch {}
                
            case .flashOn:
                let cameraResponse = rtcClient.toggleFlash(on: true)
                do {
                    try respondToCameraRequest(request: obj, result: cameraResponse)
                } catch {}
            }
            
        case .snapshotCameraRequestProcessedEvent:
            os_log("snapshotCameraRequestProcessedEvent msg received", log: Log.callSDK, type: .debug)
        case .snapshotRequestedEvent:
            let obj = object as! SnapshotRequestedEvent
            let image = rtcClient.getSnapshot()
            if let img = image {
                delegate?.auviousSDK(didReceiveScreenshot: img)
                
                do {
                    try uploadSnapshot(request: obj, snapshot: img)
                } catch {}
                
            }
        }
    }
    
    //MARK: MQTTCallDelegate
    
    internal func callMessageReceived(_ object: CallEvent) {
        
        switch object.type! {
        case .callRinging:
            delegate?.auviousSDK(didReceiveCallEvent: object)
        case .callCancelled:
            currentCallId = nil
            sipHeaders = nil
            delegate?.auviousSDK(didReceiveCallEvent: object)
        case .callAnswered:
            //Setup streams and inform client
            currentCallId = object.callId
            rtcClient.handleCallAnsweredEvent(object as! CallAnsweredEvent, userEndpointId: UserEndpointModule.sharedInstance.userEndpointId!, userId: AuthenticationModule.sharedInstance.loginResponse!.userId)
            delegate?.auviousSDK(didReceiveCallEvent: object)
        case .callCreated:
            delegate?.auviousSDK(didReceiveCallEvent: object)
            let msg = object as! CallCreatedEvent
            
            do {
                try invokeRinging(callId: msg.callId, fromEndpointId: msg.userEndpointId, fromUserId: msg.userId)
            } catch _ {
                
            }
        case .callRejected:
            //Clean state and inform the client
            currentCallId = nil
            sipHeaders = nil
            rtcClient.handleCallRejectedEvent(object as! CallRejectedEvent)
            delegate?.auviousSDK(didReceiveCallEvent: object)
        case .callEnded:
            currentCallId = nil
            sipHeaders = nil
            rtcClient.handleCallEndedEvent(object as! CallEndedEvent)
            delegate?.auviousSDK(didReceiveCallEvent: object)
        case .callIceCandidatesFound:
            rtcClient.addCallIceCandidates(event: object as! IceCandidatesFoundEvent)
        }
    
    }
    
    //MARK: -
    //MARK: ARTCClientDelegate
    //MARK: -
    
    internal func rtcClient(didReceiveLocalVideoTrack localVideoTrack: RTCVideoTrack!) {
        delegate?.auviousSDK(didReceiveLocalVideoTrack: localVideoTrack)
    }
    
    internal func rtcClient(didReceiveRemoteStream stream: RTCMediaStream, streamId: String, endpointId: String, type: StreamType) {
        delegate?.auviousSDK(didReceiveRemoteStream: stream, streamId: streamId, endpointId: endpointId, type: type)
    }
    
    //Make a call
    internal func rtcClient(call streamId: String, sdpOffer: String, target: String) {
        
        guard let loginResponse = AuthenticationModule.sharedInstance.loginResponse, let userId = loginResponse.userId else {
            delegate?.auviousSDK(onError: AuviousSDKError.notLoggedIn)
            return
        }
        
        guard let endpointId = UserEndpointModule.sharedInstance.userEndpointId else {
            delegate?.auviousSDK(onError: AuviousSDKError.endpointNotCreated)
            return
        }
        
        let callRequest = CallRequest(callId: streamId, sdpOffer: sdpOffer, target: target, userEndpointId: endpointId, userId: userId, sipHeaders: AuviousCallSDK.sharedInstance.sipHeaders)
        API.sharedInstance.call(callRequest, onSuccess: { (json) in
            
            if let _ = json {
                //success
            }
            
        }, onFailure: {(error) in
            os_log("call error %@", log: Log.callSDK, type: .error, error.localizedDescription)
            self.delegate?.auviousSDK(onError: .callError)
        })
        
    }
    
    internal func rtcClient(onError error: AuviousSDKError) {
        delegate?.auviousSDK(onError: error)
    }
    
    internal func rtcClient(didChangeState newState: StreamEventState, streamId: String, streamType: StreamType, endpointId:String) {
        delegate?.auviousSDK(didChangeState: newState, callId: streamId, streamType: streamType)
    }
    
    internal func rtcClient(agentSwitchedCamera toFront: Bool) {
        delegate?.auviousSDK(agentSwitchedCamera: toFront)
    }
}
