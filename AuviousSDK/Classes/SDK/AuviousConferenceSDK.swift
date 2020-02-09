//
//  AuviousConferenceSDK.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 14/05/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import Foundation

public final class AuviousConferenceSDK: MQTTConferenceDelegate, RTCDelegate, UserEndpointDelegate {
    
    /// Singleton instance
    public static let sharedInstance = AuviousConferenceSDK()
    
    /// The username property, used for logging in
    internal var username: String?
    
    /// The password property, used for logging in
    internal var password: String?
    
    /// The organization property, used for logging in
    internal var organization: String?
    
    public var isLoggedIn: Bool {
        return AuthenticationModule.sharedInstance.isLoggedIn
    }
    
    public var userEndpointId: String? {
        return UserEndpointModule.sharedInstance.userEndpointId
    }

    /// ARTCClient handles all things streams related
    internal var rtcClient: RTCModule!
    
    /// The video resolution to be used when publishing
    public var publishVideoResolution: PublishVideoResolution = .min
    
    /// This delegate informs of all conference related stream state changes and errors
    public var delegate: AuviousSDKConferenceDelegate?
    
    /// List of MQTT messages
    private var mqttMessages: [ConferenceEvent] = [ConferenceEvent]()
    
    /// List of MQTT messages flagged for delayed processing
    private var mqttDelayedMessages: [ConferenceEvent] = [ConferenceEvent]()
    
    /// Configuration setting for the interval between the processing of delayed messages
    private let delayedMessageWaitTime: Double = 0.7
    
    /// Indicates whether processing of MQTT messages is taking place
    private var isProcessingMessages: Bool = false
    
    /// Number of times to try processing an MQTT message flagged for delayed processing
    private let maxDelayedProcessingAttempts: Int = 3
    
    /// The currently joined conference, if any
    private var currentConference: ConferenceSimpleView? {
        didSet {
            if currentConference != nil {
                lastConferenceJoined = currentConference?.id
            }
        }
    }
    
    /// The conference we were last known to have joined (used for automatic rejoining)
    private var lastConferenceJoined: String? {
        didSet {
            print("AuviousSDK lastConferenceJoined set to \(String(describing: lastConferenceJoined))")
        }
    }
    
    /// Our viewer id
    private var viewerId: String?
    
    /// Reference to the background task used for gracefully stopping streams
    private var backgroundTask: UIBackgroundTaskIdentifier = UIBackgroundTaskIdentifier.invalid
    
    //MARK: -
    //MARK: Pause/Resume handlers
    //MARK: -
    
    /// Background task completion handler, invalidates the background task.
    private func endBackgroundTask(){
        print("Background task ended.")
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
        
        //Pause the keepAlive timer
        UserEndpointModule.sharedInstance.keepAliveTimer?.invalidate()
        
        if let conf = currentConference {
            leaveConference(conferenceId: conf.id, onSuccess: {
                
                self.endBackgroundTask()
                
            }, onFailure: {(error) in
                self.endBackgroundTask()
            })
        } else {
            endBackgroundTask()
        }
    }
    
    /**
     Should be called when the application is foregrounded in order to automatically
     rejoin the conference and reconnect to remote streams.
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
                
                //Rejoin conference if needed
                if let rejoinId = self.lastConferenceJoined {
                    self.rejoinConference(conferenceId: rejoinId)
                }
                
            } else {
                self.delegate?.auviousSDK(onError: AuviousSDKError.connectionError)
            }
        }, onFailure: {(error) in
            
            UserEndpointModule.sharedInstance.createEndpoint(newEndpointId: UUID().uuidString, userId: userId, onSuccess: {(newEndpointId) in
                
                //Rejoin conference if needed
                if let rejoinId = self.lastConferenceJoined {
                    self.rejoinConference(conferenceId: rejoinId)
                }
                
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
    public func configure(username: String, password: String, organization: String) {
        self.username = username
        self.password = password
        self.organization = organization
    }
    
    //ARTC client
    private func initializeARTCClient(){
        rtcClient = RTCModule()
        
        rtcClient.iceServers = ServerConfiguration.iceServers
        
        rtcClient.publishVideoResolution = publishVideoResolution
        rtcClient.delegate = self
        rtcClient.initialisePeerConnectionFactory()
    }
    
    /**
     Rejoins the conference we had joined.
     
     - Parameter conferenceId: The conference id to rejoin
     */
    private func rejoinConference(conferenceId: String) {
        joinConference(conferenceId: conferenceId, onSuccess: {conference in
            
            if let conf = conference {
                self.delegate?.auviousSDK(didRejoinConference: conf)
            }
        }, onFailure: {(error) in
            print("Unable to rejoin conference \(conferenceId) - error \(error)")
        })
        
        lastConferenceJoined = nil
    }
    
    //MARK: -
    //MARK: UserEndpoint delegate
    //MARK: -
    
    func userEndpoint(onError error: AuviousSDKError) {
        delegate?.auviousSDK(onError: error)
    }
    
    //MARK: -
    //MARK: SDK Conference functions
    //MARK: -
    
    /**
     Starts the publish stream flow for the specified type. Returns the stream id.
     Success/Failure handled with delegation using the AuviousSDKDelegate
     
     - Parameter type: The stream type you wish to publish (mic, cam, mic & cam etc.)
     - Returns: The id of the stream that you are about to publish
     - Throws: AuviousSDKError detailing the error
     */
    public func startPublishLocalStreamFlow(type: StreamType) throws -> String? {
        
        guard let loginResponse = AuthenticationModule.sharedInstance.loginResponse, let userId = loginResponse.userId else {
            throw AuviousSDKError.notLoggedIn
        }
        
        guard let endpointId = UserEndpointModule.sharedInstance.userEndpointId else {
            throw AuviousSDKError.endpointNotCreated
        }
        
        let streamId = UUID().uuidString
        delegate?.auviousSDK(didChangeState: .localStreamIsConnecting, streamId: streamId, streamType: type, endpointId:endpointId)
        rtcClient.configurePublishStream(type: type, streamId: streamId, endpointId: endpointId, userId: userId)
        
        return streamId
    }
    
    /**
     Initiates the unpublishing of the given stream.
     
     - Parameter streamId: The id of the stream to unpublish
     - Parameter streamType: The type of the stream you are unpublishing
     - Throws: AuviousSDKError detailing the error
     */
    public func startUnpublishLocalStreamFlow(streamId: String, streamType: StreamType) throws {
        
        guard let loginResponse = AuthenticationModule.sharedInstance.loginResponse, let _ = loginResponse.userId else {
            throw AuviousSDKError.notLoggedIn
        }
        
        guard let userEndpointId = UserEndpointModule.sharedInstance.userEndpointId else {
            throw AuviousSDKError.endpointNotCreated
        }
        
        guard let _ = currentConference else {
            throw AuviousSDKError.notInConference
        }
        
        delegate?.auviousSDK(didChangeState: .localStreamIsDisconnecting, streamId: streamId, streamType: streamType, endpointId:userEndpointId)
        
        if rtcClient.removePublishStreams(streamId: streamId) {
            do {
                try unpublishLocalStream(streamId: streamId, streamType: streamType)
            } catch let error {
                throw error
            }
        }
    }
    
    /**
     HTTP request used to unpublish a stream.
     
     - Parameter streamId: The id of the stream to unpublish
     - Parameter streamType: The type of the stream to unpublish
     - Throws: AuviousSDKError detailing the error
     */
    private func unpublishLocalStream(streamId: String, streamType: StreamType) throws {
        
        guard let loginResponse = AuthenticationModule.sharedInstance.loginResponse, let userId = loginResponse.userId else {
            throw AuviousSDKError.notLoggedIn
        }
        
        guard let endpointId = UserEndpointModule.sharedInstance.userEndpointId else {
            throw AuviousSDKError.endpointNotCreated
        }
        
        guard let conference = currentConference else {
            throw AuviousSDKError.notInConference
        }
        
        let usRequest = UnpublishStreamRequest(conferenceId: conference.id, streamId: streamId, userEndpointId: endpointId, userId: userId)
        API.sharedInstance.unpublishStream(usRequest, onSuccess: {(json) in
            
            if let _ = json {
                self.delegate?.auviousSDK(didChangeState: .localStreamDisconnected, streamId: streamId, streamType: streamType, endpointId:endpointId)
            }
        }, onFailure: {(error) in
            self.delegate?.auviousSDK(onError: AuviousSDKError.publishStreamFailure(fragment: .unpublishStream, output: error.localizedDescription))
        })
    }
    
    /**
     
     */
    public func unpublishAllLocalStreams() {
        
        if rtcClient != nil {
            for peerConnection in rtcClient.peerConnections {
                if peerConnection.isLocal == true {
                    if let conference = currentConference {
                        let usRequest = UnpublishStreamRequest(conferenceId: conference.id, streamId: peerConnection.streamId, userEndpointId: peerConnection.endpointId, userId: peerConnection.userId)
                        API.sharedInstance.unpublishStream(usRequest, onSuccess: {(json) in
                            
                            if let _ = json {
                                //success
                            }
                            
                        }, onFailure: {(error) in
                            print("unpublishAllLocalStreams() error for stream \(String(describing: peerConnection.streamId)) - error \(error)")
                        })
                    }
                }
            }
        }
    }
    
    /**
     Starts the async flow for stream viewing.
     
     - Parameter streamId: The stream id to view
     - Parameter endpointId: The endpoint id streaming the stream
     - Parameter streamType: The type of the stream (e.g. camera, microphone etc.)
     - Throws: AuviousSDKError detailing the error
     */
    public func startRemoteStreamFlow(streamId: String, endpointId: String, streamType: StreamType, remoteUserId: String) throws {
        
        guard let _ = AuthenticationModule.sharedInstance.loginResponse else {
            throw AuviousSDKError.notLoggedIn
        }
        
        delegate?.auviousSDK(didChangeState: .remoteStreamIsConnecting, streamId: streamId, streamType: streamType, endpointId:endpointId)
        
        //Create a new RTCPeerConnection and make view stream offer
        rtcClient.configureRemoteStream(type: streamType, streamId: streamId, endpointId: endpointId, userId: remoteUserId)
    }
    
    /**
     Stops stream viewing - this is triggered by the relevant remote message, i.e. when a remote stream
     is unpubilshed.
     
     - Parameter streamId:
     - Parameter remoteUserId:
     - Parameter remoteEndpointId:
     - Throws:
     */
    public func stopRemoteStream(streamId: String, remoteUserId: String, remoteEndpointId: String, streamType: StreamType) throws {
        
        guard let _ = AuthenticationModule.sharedInstance.loginResponse else {
            throw AuviousSDKError.notLoggedIn
        }
        
        guard let endpointId = UserEndpointModule.sharedInstance.userEndpointId else {
            throw AuviousSDKError.endpointNotCreated
        }
        
        guard let conference = currentConference else {
            throw AuviousSDKError.notInConference
        }
        
        self.delegate?.auviousSDK(didChangeState: .remoteStreamIsDisconnecting, streamId: streamId, streamType: streamType, endpointId:remoteEndpointId)
        
        let svsRequest = StopViewStreamRequest(conferenceId: conference.id, streamId: streamId, userEndpointId: remoteEndpointId, userId: remoteUserId, viewerId: endpointId)
        API.sharedInstance.stopViewStream(svsRequest, onSuccess: {(response) in
            
            if let _ = response {
                self.delegate?.auviousSDK(didChangeState: .remoteStreamDisconnected, streamId: streamId, streamType: streamType, endpointId:remoteEndpointId)
            }
            
        }, onFailure: {(error) in
            //print("Call stop view stream ERROR: \(String(describing: error))")
            // Getting 404 is valid, in the sense that the viewer is already gone
            switch error {
            case let AuviousSDKError.httpError(code) where code == 404:
                self.delegate?.auviousSDK(didChangeState: .remoteStreamDisconnected, streamId: streamId, streamType: streamType, endpointId:remoteEndpointId)
            default:
                self.delegate?.auviousSDK(onError: AuviousSDKError.remoteStreamFailure(fragment: .stopRemoteStreamRequest, output: error.localizedDescription))
                
            }
        })
    }
    
    /**
     
     */
    public func stopAllRemoteStreams() {
        
        if rtcClient != nil {
            for peerConnection in rtcClient.peerConnections {
                if peerConnection.isLocal == false {
                    if let endpointId = UserEndpointModule.sharedInstance.userEndpointId, let conference = currentConference {
                        let svsRequest = StopViewStreamRequest(conferenceId: conference.id, streamId: peerConnection.streamId, userEndpointId: peerConnection.endpointId, userId: peerConnection.userId, viewerId: endpointId)
                        API.sharedInstance.stopViewStream(svsRequest, onSuccess: {(response) in
                            //success
                        }, onFailure: {(error) in
                            print("stopAllRemoteStreams() error for stream \(String(describing: peerConnection.streamId))")
                        })
                    }
                }
            }
        }
    }
    
    /**
     Switches the device camera (rear & front).
     */
    public func switchCamera() {
        rtcClient.switchCamera()
    }
    
    /**
     Switches the audio routing (speaker, headphones)
     */
    public func changeAudioRoot(toSpeaker: Bool) -> Bool {
        return rtcClient.changeAudioRoot(toSpeaker: toSpeaker)
    }
    
    /**
     Creates a new conference.
     
     - Parameter id: Id of the conference (optional - will be auto generated if you don't specify it)
     - Parameter mode: Conference mode (camera, microphone etc.)
     - Parameter onSuccess: Called after a successful creation, returning a summary of the created conference
     - Parameter onFailure: Called in case of failure with the designated Error
     */
    public func createConference(id: String? = nil, mode: ConferenceMode, onSuccess: @escaping (ConferenceSummary?)->(), onFailure: @escaping (Error)->()) {
        guard let loginResponse = AuthenticationModule.sharedInstance.loginResponse, let userId = loginResponse.userId else {
            onFailure(AuviousSDKError.notLoggedIn)
            return
        }
        
        guard let endpointId = UserEndpointModule.sharedInstance.userEndpointId else {
            onFailure(AuviousSDKError.endpointNotCreated)
            return
        }
        
        var conferenceId = UUID().uuidString
        if let userDefinedId = id {
            conferenceId = userDefinedId
        }
        
        let request = CreateConferenceRequest(conferenceId: conferenceId, creatorId: userId, creatorEndpoint: endpointId, mode: mode)
        API.sharedInstance.createConference(request, onSuccess: {(json) in
            if let data = json {
                let conference = ConferenceSummary(fromJson: data)
                onSuccess(conference)
            }
        }, onFailure: {(error) in
            print("CreateConference failed: Error \(error)")
            onFailure(error)
        })
    }
    
    /**
     Joins the specified conference.
     
     - Parameter conferenceId: The id of the conference to join
     - Parameter onSuccess: Called after a successful creation, returning a summary of the joined conference
     - Parameter onFailure: Called in case of failure with the designated Error
     */
    public func joinConference(conferenceId: String, onSuccess: @escaping (ConferenceSimpleView?)->(), onFailure: @escaping (Error)->()) {
        guard let loginResponse = AuthenticationModule.sharedInstance.loginResponse, let userId = loginResponse.userId else {
            onFailure(AuviousSDKError.notLoggedIn)
            return
        }
        
        guard let endpointId = UserEndpointModule.sharedInstance.userEndpointId else {
            onFailure(AuviousSDKError.endpointNotCreated)
            return
        }
        
        let request = JoinConferenceRequest(conferenceId: conferenceId, userEndpointId: endpointId, userId: userId)
        API.sharedInstance.joinConference(request, onSuccess: {(json) in
            if json != nil {
                
                //Retrieve and store the current conference state
                API.sharedInstance.getConferenceSimpleView(conferenceId, onSuccess: {(json) in
                    if let data = json {
                        self.currentConference = ConferenceSimpleView(fromJson: data)
                        
                        //Notify the user of successfully joining
                        onSuccess(self.currentConference)
                    }
                }, onFailure: {(error) in
                    onFailure(error)
                })
            }
        }, onFailure: {(error) in
            print("JoinConference failed: Error \(error)")
            onFailure(error)
        })
    }
    
    /**
     Leave the specified conference.
     
     - Parameter conferenceId: The id of the conference to leave
     - Parameter onSuccess: Called after successfully leaving the conference
     - Parameter onFailure: Called in case of failure with the designated Error
     */
    public func leaveConference(conferenceId: String, onSuccess: @escaping ()->(), onFailure: @escaping (Error)->()) {
        
        //Step 1 - Close all streams
        removeAllStreams()
        
        //Step 2 - Unpublish all local streams
        unpublishAllLocalStreams()
        
        //Step 3 - Stop all remote streams
        stopAllRemoteStreams()
        
        //Step 4 - Empty peer connections
        emptyPeerConnections()
        
        //Step 5 - Leave conference
        guard let loginResponse = AuthenticationModule.sharedInstance.loginResponse, let userId = loginResponse.userId else {
            onFailure(AuviousSDKError.notLoggedIn)
            return
        }
        
        guard let endpointId = UserEndpointModule.sharedInstance.userEndpointId else {
            onFailure(AuviousSDKError.endpointNotCreated)
            return
        }
        
        guard let _ = self.currentConference else {
            onFailure(AuviousSDKError.notInConference)
            return
        }
        
        let lcRequest = LeaveConferenceRequest(conferenceId: conferenceId, reason: "", userEndpointId: endpointId, userId: userId)
        API.sharedInstance.leaveConference(lcRequest, onSuccess: {(json) in
            
            if let _ = json {
                self.currentConference = nil
                onSuccess()
            }
            
        }, onFailure: {(error) in
            self.currentConference = nil
            onFailure(error)
        })
    }
    
    /**
     Ends the specified conference.
     
     - Parameter conferenceId: The id of the conference to end
     - Parameter onSuccess: Called after successfully ending the specified conference
     - Parameter onFailure: Called in case of failure with the designated Error
     */
    public func endConference(conferenceId: String, onSuccess: @escaping ()->(), onFailure: @escaping (Error)->()){
        
        //Step 1 - Close all streams
        removeAllStreams()
        
        //Step 2 - Unpublish all local streams
        unpublishAllLocalStreams()
        
        //Step 3 - Stop all remote streams
        stopAllRemoteStreams()
        
        //Step 4 - Empty peer connections
        emptyPeerConnections()
        
        //Step 5 - End conference
        guard let loginResponse = AuthenticationModule.sharedInstance.loginResponse, let userId = loginResponse.userId else {
            onFailure(AuviousSDKError.notLoggedIn)
            return
        }
        
        guard let endpointId = UserEndpointModule.sharedInstance.userEndpointId else {
            onFailure(AuviousSDKError.endpointNotCreated)
            return
        }
        
        guard let _ = currentConference else {
            onFailure(AuviousSDKError.notInConference)
            return
        }
        
        let ecRequest = EndConferenceRequest(conferenceId: conferenceId, reason: "", userEndpointId: endpointId, userId: userId)
        API.sharedInstance.endConference(ecRequest, onSuccess: {(json) in
            
            if let _ = json {
                self.currentConference = nil
                self.lastConferenceJoined = nil
                onSuccess()
            }
            
        }, onFailure: {(error) in
            self.currentConference = nil
            onFailure(error)
        })
    }
    
    private func removeAllStreams() {
        if rtcClient != nil {
            rtcClient.removeAllStreams()
        }
    }
    
    private func emptyPeerConnections() {
        if rtcClient != nil {
            rtcClient.emptyPeerConnections()
        }
    }
    
    /**
     Performs a login, using the configuration settings already provided.
     
     - Parameter onLoginSuccess: Called after a successful login, returning your endpoint
     - Parameter onLoginFailure: Called in case of failure with the designated Error
     */
    public func login(onLoginSuccess: @escaping (String?)->(), onLoginFailure: @escaping (Error)->()) {
        guard let username = self.username, let password = self.password, let organization = self.organization else {
            onLoginFailure(AuviousSDKError.missingSDKCredentials)
            return
        }
        
        AuthenticationModule.sharedInstance.login(username: username, password: password, organization: organization, onSuccess: {endpointId in
            
            if let endpoint = endpointId {
                //Server configuration has already been retrieved
                AuviousConferenceSDK.sharedInstance.initializeARTCClient()
                MQTTModule.sharedInstance.configure(endpointId: endpoint)
                MQTTModule.sharedInstance.conferenceDelegate = self
                MQTTModule.sharedInstance.connect()
            }
            
            onLoginSuccess(endpointId)
        }, onFailure: {error in
            onLoginFailure(error)
        })
    }
    
    /**
     Logs the user out, stops all streams and cleans state.
     - Parameter onSuccess: Called after a successful logout.
     - Parameter onFailure: Called in case of failure with the designated Error
     */
    public func logout(onSuccess: @escaping ()->(), onFailure: @escaping (Error)->()) {
        
        guard let currentConference = currentConference else {
            
            //Step 1 - Close all streams
            removeAllStreams()
            
            //Step 2 - Unpublish all local streams
            unpublishAllLocalStreams()
            
            //Step 3 - Stop all remote streams
            stopAllRemoteStreams()
            
            //Step 4 - Empty peer connections
            emptyPeerConnections()
            
            //Step 5 - Logout
            logoutRequest(onSuccess: {
                onSuccess()
            }, onFailure: {(error) in
                onFailure(error)
            })
            return
        }
        
        leaveConference(conferenceId: currentConference.id, onSuccess: {
            self.logoutRequest(onSuccess: {
                onSuccess()
            }, onFailure: {(error) in
                onFailure(error)
            })
            
        }, onFailure: {(error) in
            onFailure(error)
        })
    }
    
    /**
     
     */
    private func logoutRequest(onSuccess: @escaping ()->(), onFailure: @escaping (Error)->()) {
        
        guard let loginResponse = AuthenticationModule.sharedInstance.loginResponse, let userId = loginResponse.userId else {
            onFailure(AuviousSDKError.notLoggedIn)
            return
        }
        
        guard let endpointId = UserEndpointModule.sharedInstance.userEndpointId else {
            onFailure(AuviousSDKError.endpointNotCreated)
            return
        }
        
        UserEndpointModule.sharedInstance.destroyEndpoint(endpointId: endpointId, userId: userId, onSuccess: {
            self.cleanState()
            onSuccess()
        }, onFailure: {(error) in
            //We still stop the timer and disconnect from mqtt, regardless of the http failure
            self.cleanState()
            onFailure(error)
        })
    }
    
    /// Cleanup state
    private func cleanState(){
        UserEndpointModule.sharedInstance.stopKeepAliveTimer()
        MQTTModule.sharedInstance.disconnect()
        self.currentConference = nil
    }
    
    //MARK: -
    //MARK: MQTT Client Delegate
    //MARK: -
    
    internal func conferenceMessageReceived(_ object: ConferenceEvent) {
        //Ensure we're in a conference
        guard let conference = currentConference else {
            return
        }
        
        //Discard older messages
        if object.conferenceVersion < conference.version {
            print("Discarding message because its conference version \(String(describing: object.conferenceVersion)) < our conference version \(String(describing: conference.version))")
            return
        }
        
        //Delay processing of messages with version > than we know
        if object.conferenceVersion > conference.version {
            print("Delaying message processing because its conference version \(String(describing: object.conferenceVersion)) > our conference version \(String(describing: conference.version))")
            mqttDelayedMessages.append(object)
            startDelayedMessageProcessorTimer(messageId: object.id)
            return
        }
        
        mqttMessages.append(object)
        if !isProcessingMessages {
            processMessages()
        }
    }
    
    //MQTT message processor
    private func processMessages(){
        guard !mqttMessages.isEmpty else {
            return
        }
        
        isProcessingMessages = true
        
        for (index,msg) in mqttMessages.enumerated() {
            
            //Only process messages coming from other users
            if let userEndpointId = UserEndpointModule.sharedInstance.userEndpointId, msg.userEndpointId != userEndpointId {
                
                delegateConferenceMessage(msg: msg)
                
                //Remove the message after successfull processing
                mqttMessages.remove(at: index)
            }
        }
        
        isProcessingMessages = false
    }
    
    //MQTT message delegation
    private func delegateConferenceMessage(msg: ConferenceEvent) {
        switch msg.type! {
        case .conferenceJoined, .conferenceLeft, .conferenceStreamPublished:
            delegate?.auviousSDK(didReceiveConferenceEvent: msg)
        case .conferenceEnded:
            removeAllStreams()
            emptyPeerConnections()
            delegate?.auviousSDK(didReceiveConferenceEvent: msg)
        case .conferenceStreamUnpublished:
            let object = msg as! ConferenceStreamUnpublishedEvent
            if (rtcClient.removeRemoteStreams(streamId: object.streamId)){
                delegate?.auviousSDK(didReceiveConferenceEvent: msg)
            }
        }
        
        //Increase conference version number
        currentConference?.version += 1
    }
    
    //Schedules the delayed message processor timer
    private func startDelayedMessageProcessorTimer(messageId: String) {
        let delayedMessageProcessorTimer = Timer(timeInterval: delayedMessageWaitTime, target: self, selector: #selector(onDelayedMessageTick), userInfo: ["messageId" : messageId], repeats: true)
        RunLoop.current.add(delayedMessageProcessorTimer, forMode: .common)
    }
    
    //Delayed message processor timer tick
    @objc private func onDelayedMessageTick(timer: Timer) {
        //Ensure we're in a conference
        guard let conference = currentConference else {
            timer.invalidate()
            return
        }
        
        //No timer context? Disregard timer and message
        guard let context = timer.userInfo as? [String: String] else {
            timer.invalidate()
            return
        }
        
        //Invalid timer context? Disregard timer and message
        let messageId = context["user", default: ""]
        if messageId.isEmpty {
            timer.invalidate()
            return
        } else {
            
            let filteredMessage = mqttDelayedMessages.filter {$0.id == messageId}.first
            if let message = filteredMessage {
                message.processedTimes += 1
                
                //Attempt to process
                if message.processedTimes <= maxDelayedProcessingAttempts && message.conferenceVersion == conference.version {
                    //all good, safe to process now
                    delegateConferenceMessage(msg: message)
                    //and remove from list
                    mqttDelayedMessages.removeAll()
                    return
                } else {
                    //Tried to process delayed message enough times but we still have a version mismatch - disregard timer and message and throw error
                    mqttDelayedMessages.removeAll()
                    timer.invalidate()
                    delegate?.auviousSDK(onError: AuviousSDKError.internalError)
                    return
                }
            }
        }
    }
    
    //MARK: -
    //MARK: ARTCClientDelegate
    //MARK: -
    
    internal func rtcClient(didReceiveLocalVideoTrack localVideoTrack: RTCVideoTrack!) {
        delegate?.auviousSDK(didReceiveLocalVideoTrack: localVideoTrack)
    }
    
    internal func rtcClient(didReceiveRemoteStream stream: RTCMediaStream, streamId: String, endpointId: String) {
        delegate?.auviousSDK(didReceiveRemoteStream: stream, streamId: streamId, endpointId: endpointId)
    }
    
    //Publish a stream
    internal func rtcClient(publishStream streamId: String, streamType: StreamType, sdpOffer: String) {
        
        guard let loginResponse = AuthenticationModule.sharedInstance.loginResponse, let userId = loginResponse.userId else {
            delegate?.auviousSDK(onError: AuviousSDKError.notLoggedIn)
            return
        }
        
        guard let endpointId = UserEndpointModule.sharedInstance.userEndpointId else {
            delegate?.auviousSDK(onError: AuviousSDKError.endpointNotCreated)
            return
        }
        
        guard let conference = self.currentConference else {
            delegate?.auviousSDK(onError: AuviousSDKError.notInConference)
            return
        }
        
        let psRequest:PublishStreamRequest = PublishStreamRequest(conferenceId: conference.id, streamType: streamType, sdpOffer: sdpOffer, streamId: streamId, userEndpointId: endpointId, userId: userId)
        
        API.sharedInstance.publishStream(psRequest, onSuccess:{(conferencePublishResult) in
            
            if let data = conferencePublishResult {
                let response = PublishStreamResponse(fromJson: data)
                
                self.rtcClient.handleAnswerReceivedPublish(withRemoteSDP: response.sdpAnswer, streamId: streamId)
            }
            
        }, onFailure: {(error) in
            self.delegate?.auviousSDK(onError: AuviousSDKError.publishStreamFailure(fragment: .publishStreamRequest, output: error.localizedDescription))
        })
    }
    
    internal func rtcClient(remoteStream streamId: String, sdpOffer: String, remoteEndpointId: String, remoteUserId: String) {
        
        guard let _ = AuthenticationModule.sharedInstance.loginResponse else {
            delegate?.auviousSDK(onError: AuviousSDKError.notLoggedIn)
            return
        }
        
        guard let conference = currentConference else {
            delegate?.auviousSDK(onError: AuviousSDKError.notInConference)
            return
        }
        
        let vsRequest:ViewStreamRequest = ViewStreamRequest(conferenceId: conference.id, sdpOffer: sdpOffer, streamId: streamId, userEndpointId: remoteEndpointId, userId: remoteUserId, viewerId: UUID().uuidString)
        
        API.sharedInstance.viewStream(vsRequest, onSuccess:{(conferenceViewResult) in
            
            if let data = conferenceViewResult {
                let response = ViewStreamResponse(fromJson: data)
                self.viewerId = response.viewerId
                self.rtcClient.handleAnswerReceivedRemote(withRemoteSDP: response.sdpAnswer, streamId: streamId)
            }
            
        }, onFailure: {(error) in
            self.delegate?.auviousSDK(onError: AuviousSDKError.remoteStreamFailure(fragment: .remoteStreamRequest, output: error.localizedDescription))
        })
    }
    
    //Add ice candidates for stream publishing
    internal func rtcClient(addPublishStreamIceCandidates candidates: [RTCIceCandidate], streamId:String, streamType:StreamType) {
        
        guard let loginResponse = AuthenticationModule.sharedInstance.loginResponse, let userId = loginResponse.userId else {
            delegate?.auviousSDK(onError: AuviousSDKError.notLoggedIn)
            return
        }
        
        guard let endpointId = UserEndpointModule.sharedInstance.userEndpointId else {
            delegate?.auviousSDK(onError: AuviousSDKError.endpointNotCreated)
            return
        }
        
        guard let conference = currentConference else {
            delegate?.auviousSDK(onError: AuviousSDKError.notInConference)
            return
        }
        
        #warning("TODO: Create a function for this")
        var candidatesArray:[IceCandidate] = [IceCandidate]()
        for item in candidates {
            let obj = IceCandidate(candidate: item.sdp, sdpMLineIndex: item.sdpMLineIndex, sdpMid: item.sdpMid!)
            candidatesArray.append(obj)
        }
        
        let psicRequest = PublishStreamIceCandidatesRequest(conferenceId: conference.id, candidates: candidatesArray, streamId: streamId, userEndpointId: endpointId, userId: userId)
        API.sharedInstance.addPublishStreamIceCandidates(psicRequest, onSuccess: {(json) in
            
            self.delegate?.auviousSDK(didChangeState: .localStreamConnected, streamId: streamId, streamType: streamType, endpointId:endpointId)
            
        }, onFailure: {(error) in
            self.delegate?.auviousSDK(onError: AuviousSDKError.publishStreamFailure(fragment: .publishStreamIceCandidatesRequest, output: error.localizedDescription))
        })
    }
    
    //Add ice candidates for stream view
    internal func rtcClient(addRemoteStreamIceCandidates candidates: [RTCIceCandidate], userId: String, endpointId: String, streamId: String, streamType: StreamType) {
        
        guard let conference = currentConference else {
            delegate?.auviousSDK(onError: AuviousSDKError.notInConference)
            return
        }
        
        var candidatesArray:[IceCandidate] = [IceCandidate]()
        for item in candidates {
            let obj = IceCandidate(candidate: item.sdp, sdpMLineIndex: item.sdpMLineIndex, sdpMid: item.sdpMid!)
            candidatesArray.append(obj)
        }
        
        let vsicRequest = ViewStreamIceCandidatesRequest(conferenceId: conference.id, candidates: candidatesArray, streamId: streamId, userEndpointId: endpointId, userId: userId, viewerId: self.viewerId!)
        API.sharedInstance.addViewStreamIceCandidates(vsicRequest, onSuccess: {(json) in
            
            self.delegate?.auviousSDK(didChangeState: .remoteStreamConnected, streamId: streamId, streamType: streamType, endpointId:endpointId)
            
        }, onFailure: {(error) in
            self.delegate?.auviousSDK(onError: AuviousSDKError.remoteStreamFailure(fragment: .remoteStreamIceCandidatesRequest, output: error.localizedDescription))
        })
    }
    
    internal func rtcClient(onError error: AuviousSDKError) {
        delegate?.auviousSDK(onError: error)
    }
    
    internal func rtcClient(didChangeState newState: StreamEventState, streamId: String, streamType: StreamType, endpointId:String) {
        delegate?.auviousSDK(didChangeState: newState, streamId: streamId, streamType: streamType, endpointId: endpointId)
    }
    
    //Not needed for conferences
    func rtcClient(agentSwitchedCamera toFront: Bool) {}
}
