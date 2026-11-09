//
//  AuviousConferenceSDK.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 14/05/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import Foundation
import UIKit
import CoreMedia
import SwiftyJSON
import Network
import os

/// Receives the co-browse specific signalling that does not go through `AuviousSDKConferenceDelegate`.
internal protocol CobrowseSignallingDelegate: AnyObject {

    /// A non-versioned user event (co-browse request/terminate, sketch, laser pointer)
    func cobrowseUserEventReceived(_ type: RtcUserEventType, json: JSON)

    /// A SKETCH / AR_POINTER / AR_POINTER_COLORS conference metadata change from another participant
    func cobrowseMetadataChanged(_ event: ConferenceMetadataUpdatedEvent)
}

/// Receives the AR pointer and sketch signalling of a regular call (camera and screen share annotations).
internal protocol AnnotationSignallingDelegate: AnyObject {

    /// A sketch or AR pointer user event
    func annotationUserEventReceived(_ type: RtcUserEventType, json: JSON)

    /// A SKETCH / AR_POINTER / AR_POINTER_COLORS conference metadata change from another participant
    func annotationMetadataChanged(_ event: ConferenceMetadataUpdatedEvent)
}

/// Another endpoint in the current conference, as far as AR pointer events need to know it
internal struct RemoteParticipant {
    let userId: String
    let endpointId: String

    /// stream id -> the publisher's correlation id
    var correlationIds: [String: String] = [:]
}

public final class AuviousConferenceSDK: MQTTConferenceDelegate, MQTTUserEventDelegate, RTCDelegate, UserEndpointDelegate {

    /// Singleton instance
    public static let sharedInstance = AuviousConferenceSDK()

    /// How this endpoint presents itself when joining a conference
    internal var joinProfile: JoinProfile = .stream

    /// Co-browse signalling sink, set while a co-browse session is active
    internal weak var cobrowseDelegate: CobrowseSignallingDelegate?

    /// AR pointer / sketch signalling sink of the call screen. Gets the annotation events alongside `cobrowseDelegate`;
    /// each sketch session filters by its own sketch and target, so double delivery is safe.
    internal weak var annotationDelegate: AnnotationSignallingDelegate?

    /// The other endpoints of the current conference, by endpoint id
    internal private(set) var remoteParticipants: [String: RemoteParticipant] = [:]

    /// When true, the co-browse session manages app lifecycle itself and the public pause/resume calls are ignored
    internal var isCobrowseActive: Bool = false

    /// Marks the published screen stream as an in-call co-browse (stream metadata "cobrowse"), so the agent shows it in the co-browse view
    internal var screenStreamIsCobrowse: Bool = false

    /// Per-frame hook for the screen share capture (co-browse masking). Returns the buffer to send, or nil to drop the frame.
    internal var screenFrameProcessor: ((CMSampleBuffer, CVPixelBuffer) -> CVPixelBuffer?)? {
        didSet {
            rtcClient?.screenFrameProcessor = screenFrameProcessor
        }
    }

    /// The username property, used for logging in
    internal var username: String?
    
    /// The password property, used for logging in
    internal var password: String?
    
    /// The participant name
    internal var participantName: String?
    
    /// The client id property, used for logging in
    internal var clientId: String?
    
    /// Map of parameters to be passed on login call
    internal var loginParams: [String: String]?
    
    /// UI Configuration
    internal var uiConfiguration: AuviousConferenceConfiguration = AuviousConferenceConfiguration()
    
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
    
    /// MQTT messages waiting to be processed: the ones after a conference version we have not received yet
    private var mqttMessages: [ConferenceEvent] = [ConferenceEvent]()

    /// List of MQTT messages cached for future processing
    private var mqttCachedMessages: [ConferenceEvent] = [ConferenceEvent]()

    /// How long to wait for a missing conference version before fetching the conference state
    private let missingMessageWaitTime: Double = 1.5

    /// Indicates whether processing of MQTT messages is taking place
    private var isProcessingMessages: Bool = false

    /// Fetches the conference state when a conference version is still missing after missingMessageWaitTime
    private var resyncWorkItem: DispatchWorkItem?

    /// Conference state fetches in a row that left messages still waiting
    private var resyncAttempts: Int = 0

    /// Conference state fetches in a row after which the waiting messages are dropped
    private let maxResyncAttempts: Int = 3

    /// The currently joined conference, if any
    private var currentConference: ConferenceSimpleView? {
        didSet {
            if currentConference != nil {
                lastConferenceJoined = currentConference?.id
            }
            //Messages waiting for another conference's versions would never be processed
            if currentConference?.id != oldValue?.id {
                mqttMessages.removeAll()
                cancelResync()
            }
            rebuildRemoteParticipants()
        }
    }
    
    /// The conference we were last known to have joined (used for automatic rejoining)
    private var lastConferenceJoined: String? {
        didSet {
            sdkLog("lastConferenceJoined set to %@", log: Log.conferenceSDK, type: .debug, String(describing: lastConferenceJoined))
        }
    }
    
    /// Our viewer id per stream Id
    private var viewerIdMap: [String: String] = [:]

    /// Rebuilds the connection of a call stream that lost it, e.g. after a network drop
    private lazy var streamRecovery = StreamRecoveryManager(
        recover: { [weak self] streamId, isLocal in self?.recoverStream(streamId, isLocal: isLocal) },
        stateChanged: { [weak self] endpointId, isLocal, state in
            self?.delegate?.auviousSDK(streamConnectionChanged: state, endpointId: endpointId, isLocal: isLocal)
        }
    )

    /// Tells MQTT and the stream recovery when the device has a network again
    private var pathMonitor: NWPathMonitor?

    /// Republished streams whose muted tracks must be marked muted again once the backend has them
    private var republishedStreamsToMute: Set<String> = []

    /// The conference is on hold, which disables our tracks without the user muting them
    private var isConferenceOnHold = false
    
    /// Reference to the background task used for gracefully stopping streams
    private var backgroundTask: UIBackgroundTaskIdentifier = UIBackgroundTaskIdentifier.invalid
    
    /// Internal flag for handling the iOS ReplayKit permission dialog app resume
    internal var sharingMyScreen: Bool = false

    /// Set to true while the ReplayKit permission dialog is being shown, cleared inside onApplicationResume.
    /// This prevents a conference rejoin when the app briefly backgrounds during the dialog,
    /// regardless of whether the completion handler fires before or after applicationDidBecomeActive.
    internal var isPendingScreenSharePermission: Bool = false

    /// Internal flag for handling the iOS Screenshot dialog app resume
    internal var wasBackgroundedDueToScreenshot: Bool = false

    /// Cancels the screenshot reset timer if the app actually backgrounds before it fires
    private var screenshotResetWorkItem: DispatchWorkItem?

    /// True when peer connections are kept alive in background with audio still running
    internal var isBackgroundAudioActive: Bool = false

    /// True when onApplicationPause() was called, so onApplicationResume() only runs after a real background transition
    private var didPauseForBackground: Bool = false

    /// True if the camera was active when the app went to background (background audio path only)
    private var cameraWasEnabledBeforeBackground: Bool = false

    /// GCD timer used for keep-alive while in background (RunLoop timers don't fire in background)
    private var backgroundKeepAliveTimer: DispatchSourceTimer?

    /// Whether the host app has declared the "audio" background mode in Info.plist
    private var hostAppSupportsBackgroundAudio: Bool {
        guard let modes = Bundle.main.infoDictionary?["UIBackgroundModes"] as? [String] else { return false }
        return modes.contains("audio")
    }

    private init() {
        AuviousDiagnostics.start()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenshotTaken),
            name: UIApplication.userDidTakeScreenshotNotification,
            object: nil
        )
    }

    /// Called when the user takes a screenshot. Sets the flag so that if the user taps
    /// the thumbnail and the app briefly backgrounds, we skip the conference rejoin.
    /// A fallback timer resets the flag after 15 seconds if the app never backgrounds.
    @objc private func handleScreenshotTaken() {
        wasBackgroundedDueToScreenshot = true
        sdkLog("Screenshot detected — suppressing next app resume rejoin", log: Log.conferenceSDK, type: .debug)

        screenshotResetWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.wasBackgroundedDueToScreenshot = false
            self?.screenshotResetWorkItem = nil
        }
        screenshotResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 7, execute: workItem)
    }

    //MARK: -
    //MARK: Pause/Resume handlers
    //MARK: -
    
    /// Background task completion handler, invalidates the background task.
    private func endBackgroundTask(){
        sdkLog("Background task ended", log: Log.conferenceSDK, type: .debug)
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = UIBackgroundTaskIdentifier.invalid
    }

    /// Starts a GCD-based keep-alive timer for use in background (RunLoop timers don't fire).
    private func startBackgroundKeepAliveTimer() {
        let interval = UserEndpointModule.sharedInstance.keepAliveSeconds - 5
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler {
            UserEndpointModule.sharedInstance.performKeepAlive()
        }
        timer.resume()
        backgroundKeepAliveTimer = timer
    }

    /// Cancels the GCD-based background keep-alive timer.
    private func stopBackgroundKeepAliveTimer() {
        backgroundKeepAliveTimer?.cancel()
        backgroundKeepAliveTimer = nil
    }
    
    /**
     Should be called when the application is backgrounded in order to gracefully
     disconnect from remote streams.
     */
    public func onApplicationPause(){
        //Co-browse sessions observe the app lifecycle themselves
        guard !isCobrowseActive else { return }
        
        didPauseForBackground = true

        // App is entering real background — cancel the screenshot fallback timer so it doesn't
        // reset wasBackgroundedDueToScreenshot while we are backgrounded. onApplicationResume()
        // will clear the flag once the user returns.
        screenshotResetWorkItem?.cancel()
        screenshotResetWorkItem = nil

        // Background audio path: keep peer connections alive, pause only video
        if uiConfiguration.backgroundAudioEnabled && hostAppSupportsBackgroundAudio && currentConference != nil {
            isBackgroundAudioActive = true
            cameraWasEnabledBeforeBackground = rtcClient?.localVideoTrack?.isEnabled == true
            rtcClient?.pauseVideoForBackground()

            if cameraWasEnabledBeforeBackground,
               let conference = currentConference,
               let endpointId = UserEndpointModule.sharedInstance.userEndpointId,
               let videoStreamId = rtcClient.peerConnections.first(where: { ($0.streamType == .cam || $0.streamType == .micAndCam) && $0.isLocal })?.streamId {
                let request = UpdateMetadataRequest(conferenceId: conference.id, streamId: videoStreamId, userEndpointId: endpointId, operation: .set, type: .video, value: "true")
                API2.sharedInstance.updateConferenceMetadata(request, onSuccess: { _ in }, onFailure: { _ in })
            }

            stopScreenShareForBackground()

            // Switch from RunLoop timer (won't fire in background) to GCD timer
            UserEndpointModule.sharedInstance.keepAliveTimer?.invalidate()
            startBackgroundKeepAliveTimer()

            backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
                // OS is about to kill us — fall back to full teardown
                self?.stopBackgroundKeepAliveTimer()
                self?.isBackgroundAudioActive = false
                if let conf = self?.currentConference {
                    self?.leaveConference(conferenceId: conf.id, onSuccess: {
                        self?.endBackgroundTask()
                    }, onFailure: { _ in
                        self?.endBackgroundTask()
                    })
                } else {
                    self?.endBackgroundTask()
                }
            }

            sdkLog("Background audio active — keeping peer connections alive", log: Log.conferenceSDK, type: .debug)
            return
        }

        if uiConfiguration.backgroundAudioEnabled && !hostAppSupportsBackgroundAudio {
            sdkLog("backgroundAudioEnabled is true but UIBackgroundModes 'audio' is missing from Info.plist — falling back to full teardown", log: Log.conferenceSDK, type: .error)
        }

        // Existing full teardown path
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }

        // A regular screen share ends with the call, before leaving. Left running, sharingMyScreen would
        // stay set and onApplicationResume() would skip the rejoin, leaving the call without media.
        // An in-call co-browse stops and resumes its own share (CobrowseSessionController).
        if !screenStreamIsCobrowse {
            stopScreenShareForBackground()
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
    
    /// Stops a regular screen share when the app leaves the foreground (switching to another app):
    /// in-app ReplayKit capture only records this app, so it can't continue in background.
    private func stopScreenShareForBackground() {
        guard sharingMyScreen, let rtcClient = rtcClient else { return }

        // Find the screen share stream before tearing it down
        let screenStreamId = rtcClient.peerConnections.first(where: { $0.streamType == .screen && $0.isLocal })?.streamId

        rtcClient.stopScreenSharing()
        sharingMyScreen = false

        if let streamId = screenStreamId,
           let conference = currentConference,
           let userId = AuthenticationModule.sharedInstance.loginResponse?.userId,
           let endpointId = UserEndpointModule.sharedInstance.userEndpointId {
            _ = rtcClient.removePublishStreams(streamId: streamId)
            let usRequest = UnpublishStreamRequest(
                conferenceId: conference.id,
                streamId: streamId,
                userEndpointId: endpointId,
                userId: userId
            )
            API2.sharedInstance.unpublishStream(usRequest, onSuccess: { _ in }, onFailure: { _ in })
        }

        //stopScreenSharing() already told the delegate (screenSharingStopped)
        sdkLog("Screen share stopped, the app left the foreground", log: Log.conferenceSDK, type: .debug)
    }

    /**
     Should be called when the application is foregrounded in order to automatically
     rejoin the conference and reconnect to remote streams.
     */
    public func onApplicationResume(){
        //Co-browse sessions observe the app lifecycle themselves
        guard !isCobrowseActive else { return }
        
        // Background audio path: connections are still alive, just resume video
        if isBackgroundAudioActive {
            sdkLog("Resuming from background audio — restoring video", log: Log.conferenceSDK, type: .debug)
            isBackgroundAudioActive = false
            didPauseForBackground = false
            stopBackgroundKeepAliveTimer()
            UserEndpointModule.sharedInstance.startKeepAliveTimer()
            rtcClient?.resumeVideoForForeground()

            if cameraWasEnabledBeforeBackground,
               let conference = currentConference,
               let endpointId = UserEndpointModule.sharedInstance.userEndpointId,
               let videoStreamId = rtcClient.peerConnections.first(where: { ($0.streamType == .cam || $0.streamType == .micAndCam) && $0.isLocal })?.streamId {
                let request = UpdateMetadataRequest(conferenceId: conference.id, streamId: videoStreamId, userEndpointId: endpointId, operation: .remove, type: .video, value: "false")
                API2.sharedInstance.updateConferenceMetadata(request, onSuccess: { _ in }, onFailure: { _ in })
            }
            cameraWasEnabledBeforeBackground = false

            endBackgroundTask()
            delegate?.auviousSDK(didResumeFromBackground: true)
            return
        }

        // Only rejoin if onApplicationPause() was actually called (real background transition).
        // Notification center / widgets center only trigger willResignActive → didBecomeActive,
        // which would otherwise cause a spurious rejoin and duplicate stream publishing.
        guard didPauseForBackground else {
            if isPendingScreenSharePermission {
                isPendingScreenSharePermission = false
            }
            // App became active without a real background transition (e.g. screenshot thumbnail
            // auto-dismissed, notification centre briefly shown). Clear the screenshot flag now
            // so it doesn't suppress a future real-background rejoin.
            if wasBackgroundedDueToScreenshot {
                wasBackgroundedDueToScreenshot = false
                screenshotResetWorkItem?.cancel()
                screenshotResetWorkItem = nil
            }
            return
            
        }
        didPauseForBackground = false

        //Ensure we have logged in, and have created an endpoint
        guard let loginResponse = AuthenticationModule.sharedInstance.loginResponse, let userId = loginResponse.userId else {
            return
        }

        guard let userEndpointId = UserEndpointModule.sharedInstance.userEndpointId else {
            return
        }

        //Ensure we are not resuming due to ReplayKit permission dialog closure
        guard !sharingMyScreen && !wasBackgroundedDueToScreenshot && !isPendingScreenSharePermission else {
            sdkLog("%@", log: Log.conferenceSDK, type: .debug, "onApplicationResume() called but we are sharing our screen / resuming from screenshot / pending screen share permission so no rejoin")
            wasBackgroundedDueToScreenshot = false
            screenshotResetWorkItem?.cancel()
            screenshotResetWorkItem = nil
            isPendingScreenSharePermission = false
            return
        }
        
        //Check if endpoint is alive
        UserEndpointModule.sharedInstance.keepAliveRequest = KeepAliveRequest(userEndpointId: userEndpointId, userId: userId)
        API2.sharedInstance.keepAlive(UserEndpointModule.sharedInstance.keepAliveRequest!, onSuccess: {(json) in
            if let _ = json {
                UserEndpointModule.sharedInstance.startKeepAliveTimer()
                MQTTModule2.sharedInstance.reconnect()
                
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
     Configures the Auvious SDK with the necessary UI settings.
     
     - Parameter config: The UI configuration
     */
    public func setUIConfiguration(config: AuviousConferenceConfiguration) {
        self.uiConfiguration = config
    }
    
    /**
     Configures the Auvious SDK with the necessary user and server settings.
     
     - Parameter username: The username
     - Parameter password: The password
     - Parameter clientId: The client id used for authentication
     */
    public func configure(params: [String: String], username: String, password: String, name: String?, clientId: String, baseEndpoint: String, mqttEndpoint: String) {
        self.loginParams = params
        self.username = username
        self.password = password
        self.clientId = clientId
        self.participantName = name
        
        ServerConfiguration.baseRTC = baseEndpoint
        ServerConfiguration.baseMeeting = baseEndpoint
        ServerConfiguration.mqttHost = mqttEndpoint
        ServerConfiguration.clientId = clientId
    }
    
    //ARTC client
    private func initializeARTCClient(){
        rtcClient = RTCModule()
        
        rtcClient.iceServers = ServerConfiguration.iceServers
        
        rtcClient.publishVideoResolution = publishVideoResolution
        rtcClient.screenFrameProcessor = screenFrameProcessor
        rtcClient.delegate = self
        rtcClient.initialisePeerConnectionFactory()

        MQTTModule2.sharedInstance.onReconnected = { [weak self] in
            DispatchQueue.main.async { self?.catchUpAfterReconnect() }
        }
        startNetworkMonitor()
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
            sdkLog("Unable to rejoin conference %@ - error %@", log: Log.conferenceSDK, type: .error, conferenceId, error.localizedDescription)
            // Notify the delegate so the UI can surface the error rather than leaving
            // the user with a frozen stream and no feedback.
            self.delegate?.auviousSDK(onError: AuviousSDKError.connectionError)
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
    
    public func startScreenSharingFlow() throws -> String? {
        guard let loginResponse = AuthenticationModule.sharedInstance.loginResponse, let userId = loginResponse.userId else {
            throw AuviousSDKError.notLoggedIn
        }
        
        guard let endpointId = UserEndpointModule.sharedInstance.userEndpointId else {
            throw AuviousSDKError.endpointNotCreated
        }
        
        let streamId = UUID().uuidString
        
        return streamId
    }
    
    /**
     Starts the publish stream flow for the specified type. Returns the stream id.
     Success/Failure handled with delegation using the AuviousSDKDelegate
     
     - Parameter type: The stream type you wish to publish (mic, cam, mic & cam etc.)
     - Returns: The id of the stream that you are about to publish
     - Throws: AuviousSDKError detailing the error
     */
    /// Requests screen share permission by starting ReplayKit capture.
    /// The completion is called on the ReplayKit callback thread with true if the user allowed, false if denied.
    /// On success, the pending capturer is reused when startPublishLocalStreamFlow(type: .screen) is called.
    public func requestScreenSharePermission(completion: @escaping (Bool) -> Void) {
        // Set flag before the dialog appears. It is cleared inside onApplicationResume,
        // so the guard there fires regardless of whether the ReplayKit completion
        // handler runs before or after applicationDidBecomeActive.
        isPendingScreenSharePermission = true
        rtcClient.startScreenCapture(completion: completion)
    }

    public func startPublishLocalStreamFlow(type: StreamType) throws -> String? {
        
        guard let loginResponse = AuthenticationModule.sharedInstance.loginResponse, let userId = loginResponse.userId else {
            throw AuviousSDKError.notLoggedIn
        }
        
        guard let endpointId = UserEndpointModule.sharedInstance.userEndpointId else {
            throw AuviousSDKError.endpointNotCreated
        }
        
        if type == .screen {
            guard currentConference != nil else {
                throw AuviousSDKError.notInConference
            }
            isPendingScreenSharePermission = false
            sharingMyScreen = true
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
        
        if streamType == .screen {
            sharingMyScreen = false
        }
        
        streamRecovery.forget(streamId)
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
        
        if streamType == .screen {
            rtcClient.stopScreenSharing()
        }
        
        let usRequest = UnpublishStreamRequest(conferenceId: conference.id, streamId: streamId, userEndpointId: endpointId, userId: userId)
        API2.sharedInstance.unpublishStream(usRequest, onSuccess: {(json) in
            
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
                        API2.sharedInstance.unpublishStream(usRequest, onSuccess: {(json) in
                            
                            if let _ = json {
                                //success
                            }
                            
                        }, onFailure: {(error) in
                            let streamId = String(describing: peerConnection.streamId)
                            sdkLog("unpublishAllLocalStreams() error for stream %@ - error %@", log: Log.conferenceSDK, type: .error, streamId, error.localizedDescription)
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
        
        streamRecovery.forget(streamId)
        self.delegate?.auviousSDK(didChangeState: .remoteStreamIsDisconnecting, streamId: streamId, streamType: streamType, endpointId:remoteEndpointId)
        
        let svsRequest = StopViewStreamRequest(conferenceId: conference.id, streamId: streamId, userEndpointId: remoteEndpointId, userId: remoteUserId, viewerId: endpointId)
        API2.sharedInstance.stopViewStream(svsRequest, onSuccess: {(response) in
            
            if let _ = response {
                self.delegate?.auviousSDK(didChangeState: .remoteStreamDisconnected, streamId: streamId, streamType: streamType, endpointId:remoteEndpointId)
            }
            
        }, onFailure: {(error) in
            //os_log("Call stop view stream ERROR: \(String(describing: error))")
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
                    
                    if let _ = UserEndpointModule.sharedInstance.userEndpointId, let conference = currentConference, let viewerId = self.viewerIdMap[peerConnection.streamId] {
                        let svsRequest = StopViewStreamRequest(conferenceId: conference.id, streamId: peerConnection.streamId, userEndpointId: peerConnection.endpointId, userId: peerConnection.userId, viewerId: viewerId)
                        API2.sharedInstance.stopViewStream(svsRequest, onSuccess: {(response) in
                            //success
                        }, onFailure: {(error) in
                            let streamId = String(describing: peerConnection.streamId)
                            sdkLog("stopAllRemoteStreams() error for stream %@ is %@", log: Log.conferenceSDK, type: .error, streamId, error.localizedDescription)
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
        API2.sharedInstance.createConference(request, onSuccess: {(json) in
            if let data = json {
                let conference = ConferenceSummary(fromJson: data)
                onSuccess(conference)
            }
        }, onFailure: {(error) in
            sdkLog("CreateConference failed: Error %@", log: Log.conferenceSDK, type: .error, error.localizedDescription)
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
        
        let request = JoinConferenceRequest(conferenceId: conferenceId, userEndpointId: endpointId, userId: userId, participantName: participantName)
        API2.sharedInstance.joinConference(request, onSuccess: {(json) in
            if json != nil {
                
                sdkLog("Joined conference %@", log: Log.conferenceSDK, type: .debug, conferenceId)
                //Retrieve and store the current conference state
                API2.sharedInstance.getConferenceSimpleView(conferenceId, onSuccess: {(json) in
                    if let data = json {
                        
                        self.isConferenceOnHold = false
                        self.currentConference = ConferenceSimpleView(fromJson: data)
                        sdkLog("Obtained simple view for conference %@", log: Log.conferenceSDK, type: .debug, conferenceId)
                        //Notify the user of successfully joining
                        onSuccess(self.currentConference)
                        
                        //Process any messages we might have received before joining was complete
                        if !self.mqttCachedMessages.isEmpty {
                            for m in self.mqttCachedMessages {
                                sdkLog("Processing cached MQTT msg", log: Log.conferenceSDK, type: .debug)
                                #warning("TODO: Extra val here")
                                self.delegateConferenceMessage(msg: m)
                            }

                            sdkLog("Finished processing of %d cached messages", log: Log.conferenceSDK, type: .debug, self.mqttCachedMessages.count)
                            self.mqttCachedMessages.removeAll()
                        }

                        //Notify if recording was already active when we joined
                        if self.currentConference?.isRecording == true {
                            self.delegate?.auviousSDK(recorderStateChanged: true)
                        }
                    }
                }, onFailure: {(error) in
                    onFailure(error)
                })
            }
        }, onFailure: {(error) in
            sdkLog("JoinConference failed: Error  %@", log: Log.conferenceSDK, type: .error, error.localizedDescription)
            onFailure(error)
        })
    }
    
    /**
     Leave the specified conference.
     
     - Parameter conferenceId: The id of the conference to leave
     - Parameter onSuccess: Called after successfully leaving the conference
     - Parameter onFailure: Called in case of failure with the designated Error
     */
    public func leaveConference(conferenceId: String, reason: String = "", onSuccess: @escaping ()->(), onFailure: @escaping (Error)->()) {
        guard let loginResponse = AuthenticationModule.sharedInstance.loginResponse, let userId = loginResponse.userId else {
            onFailure(AuviousSDKError.notLoggedIn)
            return
        }

        guard let endpointId = UserEndpointModule.sharedInstance.userEndpointId else {
            onFailure(AuviousSDKError.endpointNotCreated)
            return
        }

        guard self.currentConference != nil else {
            onFailure(AuviousSDKError.notInConference)
            return
        }

        // Clean up background audio state if active
        isBackgroundAudioActive = false
        if sharingMyScreen {
            rtcClient.stopScreenSharing()
        }
        sharingMyScreen = false
        stopBackgroundKeepAliveTimer()

        streamRecovery.clear()
        republishedStreamsToMute.removeAll()
        isConferenceOnHold = false

        //Step 1 - Close all streams
        removeAllStreams()

        //Step 2 - Unpublish all local streams (needs currentConference, must run before nil-ing it)
        unpublishAllLocalStreams()

        //Step 3 - Stop all remote streams (needs currentConference, must run before nil-ing it)
        stopAllRemoteStreams()

        //Step 4 - Empty peer connections
        emptyPeerConnections()

        // Nil currentConference synchronously before the HTTP call. The HTTP callback below
        // must not touch client state — a concurrent rejoin may already have set a new
        // currentConference for the same conferenceId, and overwriting it would cause the
        // UI's subsequent leave to fail with notInConference.
        self.currentConference = nil

        //Step 5 - Leave conference
        let lcRequest = LeaveConferenceRequest(conferenceId: conferenceId, reason: reason, userEndpointId: endpointId, userId: userId)
        API2.sharedInstance.leaveConference(lcRequest, onSuccess: {(json) in
            if let _ = json {
                onSuccess()
            }
        }, onFailure: {(error) in
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
        API2.sharedInstance.endConference(ecRequest, onSuccess: {(json) in
            
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
     
     - Parameter onLoginSuccess: Called after a successful login, returning your endpoint and conferenceId
     - Parameter onLoginFailure: Called in case of failure with the designated Error
     */
    public func login(onLoginSuccess: @escaping (String?, String?)->(), onLoginFailure: @escaping (Error)->()) {
        guard let username = self.username, let password = self.password, let _ = self.clientId else {
            onLoginFailure(AuviousSDKError.missingSDKCredentials)
            return
        }
        
        AuthenticationModule.sharedInstance.login(params: loginParams, username: username, password: password, onSuccess: { endpointId, conferenceId in
            
            if let endpoint = endpointId {
                //Server configuration has already been retrieved
                AuviousConferenceSDK.sharedInstance.initializeARTCClient()
                
                MQTTModule2.sharedInstance.configure(endpointId: endpoint)
                MQTTModule2.sharedInstance.conferenceDelegate = self
                MQTTModule2.sharedInstance.userEventDelegate = self
                MQTTModule2.sharedInstance.connect(onSubscription: {
                    onLoginSuccess(endpointId, conferenceId)
                    //We no longer want the closure to be called
                    MQTTModule2.sharedInstance.clearSubscriptionCallback()
                })
            }
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
            self.logoutRequest(onSuccess: {
                onSuccess()
            }, onFailure: {(error) in
                onFailure(error)
            })
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
            UserEndpointModule.sharedInstance.userEndpointId = nil
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
        API2.sharedInstance.stopTokenRefreshTimer()
        MQTTModule2.sharedInstance.disconnect()
        stopNetworkMonitor()
        self.currentConference = nil
    }
    
    //Helper for HOLD, MUTE/UNMUTE functionality
    internal func removeLocalVideoStream() {
        if let stream = self.rtcClient.localStream, let localVideo = self.rtcClient.localVideoTrack {
            stream.removeVideoTrack(localVideo)
            sdkLog("RTCClient removed local video track", log: Log.conferenceSDK, type: .debug)
        }
    }
    
    internal func removeLocalAudioStream() {
        if let stream = self.rtcClient.localStream, let localAudio = self.rtcClient.localAudioTrack {
            stream.removeAudioTrack(localAudio)
            sdkLog("RTCClient removed local audio track", log: Log.conferenceSDK, type: .debug)
        } 
    }
    
    internal func addLocalVideoStream() {
        if let stream = self.rtcClient.localStream, let localVideo = self.rtcClient.localVideoTrack {
            stream.addVideoTrack(localVideo)
            sdkLog("RTCClient added local video track", log: Log.conferenceSDK, type: .debug)
        }
    }
    
    internal func addLocalAudioStream() {
        if let stream = self.rtcClient.localStream, let localAudio = self.rtcClient.localAudioTrack {
            stream.addAudioTrack(localAudio)
            sdkLog("RTCClient added local audio track", log: Log.conferenceSDK, type: .debug)
        }
    }
    
    public func toggleLocalStream(conferenceId: String, streamId: String, operation: MetadataRequestOperation, type: MetadataRequestType, onSuccess: @escaping ()->(), onFailure: @escaping (Error)->()) {
        guard let endpointId = UserEndpointModule.sharedInstance.userEndpointId else {
            onFailure(AuviousSDKError.endpointNotCreated)
            return
        }
        
        //Mute/unmute local audio or video track
        let isEnabled = operation == .set ? false : true
        if type == .video {
            rtcClient.localVideoTrack?.isEnabled = isEnabled
        } else if type == .audio {
            rtcClient.localAudioTrack?.isEnabled = isEnabled
        }
        
        let request = UpdateMetadataRequest(conferenceId: conferenceId, streamId: streamId, userEndpointId: endpointId, operation: operation, type: type, value: isEnabled ? "false" : "true")
        
        //Call the api
        API2.sharedInstance.updateConferenceMetadata(request, onSuccess: {json in
            if let _ = json {
                sdkLog("toggleLocalStream() success API", log: Log.conferenceSDK, type: .debug)
                
                if operation == .set {
                    if type == .video {
                        self.removeLocalVideoStream()
                    } else if type == .audio {
                        self.removeLocalAudioStream()
                    }
                } else if operation == .remove {
                    if type == .video {
                        self.addLocalVideoStream()
                    } else if type == .audio {
                        self.addLocalAudioStream()
                    }
                }
                
                //All done
                onSuccess()
            }
        }, onFailure: {error in
            sdkLog("toggleLocalStream() error API: %@", log: Log.conferenceSDK, type: .error, error.localizedDescription)
            onFailure(error)
        })
    }
    
    //MARK: -
    //MARK: MQTT Client Delegate
    //MARK: -
    
    internal func userEventReceived(_ type: RtcUserEventType, json: JSON) {
        cobrowseDelegate?.cobrowseUserEventReceived(type, json: json)
        if type.isAnnotation {
            annotationDelegate?.annotationUserEventReceived(type, json: json)
        }
    }

    //MARK: Participants

    private func rebuildRemoteParticipants() {
        var participants: [String: RemoteParticipant] = [:]
        let me = UserEndpointModule.sharedInstance.userEndpointId
        for participant in currentConference?.participants ?? [] {
            guard let userId = participant.id else { continue }
            for endpoint in participant.endpoints ?? [] where endpoint.id != nil && endpoint.id != me {
                var remote = RemoteParticipant(userId: userId, endpointId: endpoint.id)
                for stream in endpoint.streams ?? [] {
                    remote.correlationIds[stream.id] = stream.correlationId ?? stream.id
                }
                participants[endpoint.id] = remote
            }
        }
        remoteParticipants = participants
    }

    private func updateRemoteParticipants(_ msg: ConferenceEvent) {
        guard let endpointId = msg.userEndpointId, let userId = msg.userId, let type = msg.type else { return }

        switch type {
        case .conferenceJoined:
            if remoteParticipants[endpointId] == nil {
                remoteParticipants[endpointId] = RemoteParticipant(userId: userId, endpointId: endpointId)
            }
        case .conferenceLeft:
            remoteParticipants[endpointId] = nil
        case .conferenceStreamPublished:
            let object = msg as! ConferenceStreamPublishedEvent
            var remote = remoteParticipants[endpointId] ?? RemoteParticipant(userId: userId, endpointId: endpointId)
            remote.correlationIds[object.streamId] = object.correlationId ?? object.streamId
            remoteParticipants[endpointId] = remote
        case .conferenceStreamUnpublished:
            let object = msg as! ConferenceStreamUnpublishedEvent
            remoteParticipants[endpointId]?.correlationIds[object.streamId] = nil
        default:
            break
        }
    }

    /// The correlation id of a remote stream, as the AR pointer and sketch events name it
    internal func correlationId(ofRemoteStream streamId: String) -> String? {
        return remoteParticipants.values.lazy.compactMap { $0.correlationIds[streamId] }.first
    }
    
    internal func conferenceMessageReceived(_ object: ConferenceEvent) {
        //Ensure we're in a conference
        guard let _ = currentConference else {
            mqttCachedMessages.append(object)
            
            sdkLog("WARNING: Caching conference msg received because we're not in a conference", log: Log.conferenceSDK, type: .debug)
            return
        }
        
        mqttMessages.append(object)
        if !isProcessingMessages {
            processMessages()
        } else {
            sdkLog("Queued conference msg, it is processed after the current one", log: Log.conferenceSDK, type: .debug)
        }
    }
    
    //MQTT message processor: applies the messages in conference version order. Messages after a version we
    //have not received wait for it; if it does not come, resyncConference() catches up from the conference state
    private func processMessages(){
        //Lock processing; messages received meanwhile are picked up by this loop
        isProcessingMessages = true
        defer { isProcessingMessages = false }

        while let conference = currentConference {
            //The conference has ended whatever came before; otherwise messages without a version, or the next one
            let nextIndex = mqttMessages.firstIndex(where: { $0.type == .conferenceEnded })
                ?? mqttMessages.firstIndex(where: { $0.conferenceVersion.map { $0 <= conference.version } ?? true })
            guard let index = nextIndex else {
                break
            }
            let msg = mqttMessages.remove(at: index)

            //Discard older messages
            if let eventConferenceVersion = msg.conferenceVersion, eventConferenceVersion < conference.version {
                let cVersion = String(describing: eventConferenceVersion)
                let ourVersion = String(describing: conference.version)
                sdkLog("Discarding message because its conference version %@ < our conference version %@", log: Log.conferenceSDK, type: .debug, cVersion, ourVersion)
                continue
            }

            //Only process messages coming from other users
            if let userEndpointId = UserEndpointModule.sharedInstance.userEndpointId, msg.userEndpointId != userEndpointId {
                delegateConferenceMessage(msg: msg)
            }

            //Increase conference version number
            if let eventConferenceVersion = msg.conferenceVersion, eventConferenceVersion == currentConference?.version {
                currentConference?.version += 1
                resyncAttempts = 0
                sdkLog("Local conference version incremented to %@", log: Log.conferenceSDK, type: .debug, String(describing: currentConference?.version))
            }
        }

        if mqttMessages.isEmpty {
            cancelResync()
        } else if resyncWorkItem == nil {
            sdkLog("Delaying %d conference msgs until conference version %@ arrives", log: Log.conferenceSDK, type: .debug, mqttMessages.count, String(describing: currentConference?.version))
            let workItem = DispatchWorkItem { [weak self] in
                self?.resyncWorkItem = nil
                self?.resyncConference()
            }
            resyncWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + missingMessageWaitTime, execute: workItem)
        }
    }

    private func cancelResync() {
        resyncWorkItem?.cancel()
        resyncWorkItem = nil
        resyncAttempts = 0
    }

    /// A conference version never arrived: fetches the conference state and delegates the messages we missed
    /// (participants who joined or left, streams published or unpublished), then the ones that were waiting
    private func resyncConference(force: Bool = false) {
        guard let conference = currentConference, force || !mqttMessages.isEmpty else {
            return
        }
        resyncAttempts += force ? 0 : 1
        guard resyncAttempts <= maxResyncAttempts else {
            sdkLog("Dropping %d conference msgs still waiting after %d conference state fetches", log: Log.conferenceSDK, type: .error, mqttMessages.count, maxResyncAttempts)
            mqttMessages.removeAll()
            resyncAttempts = 0
            return
        }

        sdkLog("Conference version %@ is missing, fetching the conference state", log: Log.conferenceSDK, type: .debug, String(describing: conference.version))
        API2.sharedInstance.getConferenceSimpleView(conference.id, onSuccess: {(json) in
            guard let data = json, let current = self.currentConference, current.id == conference.id else {
                return
            }
            let fresh = ConferenceSimpleView(fromJson: data)
            if fresh.version > current.version {
                let missed = self.missedMessages(until: fresh)
                sdkLog("Conference state is at version %@, delegating %d missed msgs", log: Log.conferenceSDK, type: .debug, String(describing: fresh.version), missed.count)
                self.currentConference = fresh
                missed.forEach { self.delegateConferenceMessage(msg: $0) }
            }
            //Processes the messages after the fetched version, or waits again
            self.processMessages()
        }, onFailure: {(error) in
            sdkLog("Unable to fetch the conference state - error %@", log: Log.conferenceSDK, type: .error, error.localizedDescription)
            //No such conference any more: we missed that it ended
            if case AuviousSDKError.httpError(let code) = error, code == 404,
               let current = self.currentConference, current.id == conference.id {
                self.mqttMessages.removeAll()
                self.delegateConferenceMessage(msg: ConferenceEndedEvent(fromJson: JSON(["type": ConferenceEventType.conferenceEnded.rawValue, "conferenceId": conference.id ?? ""])))
                return
            }
            self.processMessages()
        })
    }

    /// The participant and stream messages that take the remote participants we know of to the conference's.
    /// Must run before currentConference is set to the conference, which rebuilds remoteParticipants.
    private func missedMessages(until conference: ConferenceSimpleView) -> [ConferenceEvent] {
        let me = UserEndpointModule.sharedInstance.userEndpointId
        var endpoints: [String: (userId: String, endpoint: ParticipantEndpoint)] = [:]
        for participant in conference.participants ?? [] {
            guard let userId = participant.id else { continue }
            for endpoint in participant.endpoints ?? [] where endpoint.id != nil && endpoint.id != me {
                endpoints[endpoint.id] = (userId, endpoint)
            }
        }

        func message(_ type: ConferenceEventType, userId: String, endpointId: String, _ fields: [String: Any] = [:]) -> JSON {
            var json: [String: Any] = ["type": type.rawValue, "conferenceId": conference.id ?? "", "userId": userId, "userEndpointId": endpointId]
            json.merge(fields) { $1 }
            return JSON(json)
        }
        let subscribed = rtcClient?.peerConnections.filter { !$0.isLocal } ?? []

        //Gone first: the streams that were unpublished, then the participants who left
        var missed: [ConferenceEvent] = []
        for (endpointId, remote) in remoteParticipants {
            let streamIds = Set(endpoints[endpointId]?.endpoint.streams.compactMap { $0.id } ?? [])
            for streamId in remote.correlationIds.keys where !streamIds.contains(streamId) {
                guard let container = subscribed.first(where: { $0.streamId == streamId }), let type = container.streamType else { continue }
                missed.append(ConferenceStreamUnpublishedEvent(fromJson: message(.conferenceStreamUnpublished, userId: remote.userId, endpointId: endpointId, ["streamId": streamId, "streamType": type.rawValue])))
            }
            if endpoints[endpointId] == nil {
                missed.append(ConferenceLeftEvent(fromJson: message(.conferenceLeft, userId: remote.userId, endpointId: endpointId)))
            }
        }

        //Then the participants who joined, and the streams that were published
        for (endpointId, entry) in endpoints {
            let known = remoteParticipants[endpointId]
            if known == nil {
                let metadata: [String: Any] = ["roles": entry.endpoint.roles, "name": entry.endpoint.name ?? "", "type": entry.endpoint.endpointType ?? ""]
                missed.append(ConferenceJoinedEvent(fromJson: message(.conferenceJoined, userId: entry.userId, endpointId: endpointId, ["metadata": metadata])))
            }
            for stream in entry.endpoint.streams ?? [] where stream.id != nil && stream.type != nil {
                guard known?.correlationIds[stream.id] == nil, !subscribed.contains(where: { $0.streamId == stream.id }) else { continue }
                var metadata: [String: Any] = ["portraitMode": stream.portraitMode]
                if let correlationId = stream.correlationId {
                    metadata["correlationId"] = correlationId
                }
                missed.append(ConferenceStreamPublishedEvent(fromJson: message(.conferenceStreamPublished, userId: entry.userId, endpointId: endpointId, ["streamId": stream.id!, "streamType": stream.type.rawValue, "metadata": metadata])))
            }
        }
        return missed
    }

    //MQTT message delegation
    private func delegateConferenceMessage(msg: ConferenceEvent) {
        updateRemoteParticipants(msg)

        switch msg.type! {
        case .conferenceJoined, .conferenceLeft, .conferenceStreamPublished, .conferenceNetworkIndicatorEvent:
            delegate?.auviousSDK(didReceiveConferenceEvent: msg)
        case .conferenceEnded:
            streamRecovery.clear()
            isConferenceOnHold = false
            removeAllStreams()
            emptyPeerConnections()
            delegate?.auviousSDK(didReceiveConferenceEvent: msg)
        case .conferenceStreamUnpublished:
            let object = msg as! ConferenceStreamUnpublishedEvent
            streamRecovery.forget(object.streamId)
            if (rtcClient.removeRemoteStreams(streamId: object.streamId)){
                delegate?.auviousSDK(didReceiveConferenceEvent: msg)
            }
        case .conferenceMetadataUpdatedEvent:
            let object = msg as! ConferenceMetadataUpdatedEvent
            let isEnabled = object.operation == .set ? false : true
            
            //Co-browse annotations (sketch / laser pointer discovery)
            if object.isSketch || object.isArPointer || object.isArPointerColors {
                cobrowseDelegate?.cobrowseMetadataChanged(object)
                annotationDelegate?.annotationMetadataChanged(object)
                
            //Conference on hold
            } else if object.isHold {
                
                isConferenceOnHold = !isEnabled

                //Mute/unmute local audio and video
                rtcClient.localVideoTrack?.isEnabled = isEnabled
                rtcClient.localAudioTrack?.isEnabled = isEnabled
                //Never keep streaming the screen while on hold
                rtcClient.setScreenTrackEnabled(isEnabled)
                
                //Delegate back to client
                delegate?.auviousSDK(conferenceOnHold: !isEnabled)
            } else if object.isRecorder {
                // we get a SET with value = {on:true} when the recorder starts
                // we get a REMOVE when the recorder stops
                delegate?.auviousSDK(recorderStateChanged: object.operation == .set)
                
            } else if object.isMuteToggle {
                //Mute/unmute
                rtcClient.toggleRemoteStreams(object)
                
                var streamType: StreamType = .cam
                if object.streamType == MetadataRequestType.audio {
                    streamType = .mic
                }
                
                //Delegate back to client
                if isEnabled {
                    delegate?.auviousSDK(trackUnmuted: streamType, endpointId: object.userEndpointId)
                } else {
                    delegate?.auviousSDK(trackMuted: streamType, endpointId: object.userEndpointId)
                }
                
            }
        
        case .conferenceStreamMetadataUpdatedEvent:
            let object = msg as! ConferenceStreamMetadataUpdatedEvent
            delegate?.auviousSDK(agentPortraitMode: object.portraitMode, endpointId: object.userEndpointId)
            
        default:
            sdkLog("WARNING: Processing unknown message of type %@", log: Log.conferenceSDK, type: .debug, String(describing: msg.typeDescription))
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
    
    internal func rtcClient(didReceiveLocalStream stream: RTCMediaStream, streamId: String, type: StreamType) {
        delegate?.auviousSDK(didReceiveLocalStream: stream, streamId: streamId, type: type)
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
        
        let psRequest: PublishStreamRequest = PublishStreamRequest(conferenceId: conference.id, streamType: streamType, sdpOffer: sdpOffer, streamId: streamId, userEndpointId: endpointId, userId: userId, participantName: self.participantName)
        
        API2.sharedInstance.publishStream(psRequest, onSuccess:{(conferencePublishResult) in
            
            if let data = conferencePublishResult {
                let response = PublishStreamResponse(fromJson: data)
                
                self.rtcClient.handleAnswerReceivedPublish(withRemoteSDP: response.sdpAnswer, streamId: streamId)
                DispatchQueue.main.async { self.restoreMutedTracks(ofRepublishedStream: streamId) }
            }
            
        }, onFailure: {(error) in
            DispatchQueue.main.async {
                //A recovery attempt that failed is retried, not an error for the app
                if self.streamRecovery.isRecovering(streamId) {
                    self.streamRecovery.attemptFailed(streamId)
                    return
                }
                self.delegate?.auviousSDK(onError: AuviousSDKError.publishStreamFailure(fragment: .publishStreamRequest, output: error.localizedDescription))
            }
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
        
        let viewerId = UUID().uuidString
        self.viewerIdMap[streamId] = viewerId
        let vsRequest:ViewStreamRequest = ViewStreamRequest(conferenceId: conference.id, sdpOffer: sdpOffer, streamId: streamId, userEndpointId: remoteEndpointId, userId: remoteUserId, viewerId: viewerId)
        
        API2.sharedInstance.viewStream(vsRequest, onSuccess:{(conferenceViewResult) in
            
            if let data = conferenceViewResult {
                let response = ViewStreamResponse(fromJson: data)
                self.rtcClient.handleAnswerReceivedRemote(withRemoteSDP: response.sdpAnswer, streamId: streamId)
            }
            
        }, onFailure: {(error) in
            DispatchQueue.main.async {
                if self.streamRecovery.isRecovering(streamId) {
                    //No such stream any more: the remote side unpublished it while we were away
                    if case AuviousSDKError.httpError(let code) = error, code == 404 {
                        self.streamGone(streamId, conferenceId: conference.id)
                    } else {
                        self.streamRecovery.attemptFailed(streamId)
                    }
                    return
                }
                self.delegate?.auviousSDK(onError: AuviousSDKError.remoteStreamFailure(fragment: .remoteStreamRequest, output: error.localizedDescription))
            }
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
        var candidatesArray: [IceCandidate] = [IceCandidate]()
        for item in candidates {
            let obj = IceCandidate(candidate: item.sdp, sdpMLineIndex: item.sdpMLineIndex, sdpMid: item.sdpMid!)
            candidatesArray.append(obj)
        }
        
        let psicRequest = PublishStreamIceCandidatesRequest(conferenceId: conference.id, candidates: candidatesArray, streamId: streamId, userEndpointId: endpointId, userId: userId)
        API2.sharedInstance.addPublishStreamIceCandidates(psicRequest, onSuccess: {(json) in
            
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
        
        guard let viewerId = viewerIdMap[streamId] else {
            delegate?.auviousSDK(onError: AuviousSDKError.internalError)
            return
        }
        
        var candidatesArray:[IceCandidate] = [IceCandidate]()
        for item in candidates {
            let obj = IceCandidate(candidate: item.sdp, sdpMLineIndex: item.sdpMLineIndex, sdpMid: item.sdpMid!)
            candidatesArray.append(obj)
        }
        
        let vsicRequest = ViewStreamIceCandidatesRequest(conferenceId: conference.id, candidates: candidatesArray, streamId: streamId, userEndpointId: endpointId, userId: userId, viewerId: viewerId)
        API2.sharedInstance.addViewStreamIceCandidates(vsicRequest, onSuccess: {(json) in
            
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
    
    internal func rtcClient(recorderStateChanged toActive: Bool) {
        delegate?.auviousSDK(recorderStateChanged: toActive)
    }
    
    internal func rtcClient(didStopScreenSharing: Bool) {
        delegate?.auviousSDK(screenSharingStopped: true)
    }
    
    internal func rtcClient(didStartScreenSharing: Bool) {
        delegate?.auviousSDK(screenSharingStarted: true)
    }

    internal func rtcClient(didFailToStartScreenSharing: Bool) {
        sharingMyScreen = false
    }

    internal func rtcClient(iceConnectionChanged state: StreamIceState, streamId: String, isLocal: Bool, endpointId: String) {
        DispatchQueue.main.async {
            self.streamRecovery.iceStateChanged(streamId: streamId, isLocal: isLocal, endpointId: endpointId, state: state)
        }
    }

    /**
     Rebuilds the connection of a call stream that lost it: republishes our stream under a new stream ID over
     the capture that keeps running (so the other side sees a new stream and subscribes to it), or views a
     remote stream again. Returns the stream ID the new connection carries, nil if there is nothing to recover.
     */
    private func recoverStream(_ streamId: String, isLocal: Bool) -> String? {
        guard let conference = currentConference, let userId = currentUserId,
              let endpointId = UserEndpointModule.sharedInstance.userEndpointId else {
            return nil
        }
        guard let container = rtcClient.peerConnections.first(where: { $0.streamId == streamId && $0.isLocal == isLocal }),
              let streamType = container.streamType else {
            return nil
        }
        sdkLog("Recovering %{public}@ stream %{public}@ (%{public}@)", log: Log.conferenceSDK, type: .default,
               isLocal ? "published" : "subscribed", streamId, streamType.rawValue)

        if isLocal {
            //Tell the backend, which may still list the lost stream
            let request = UnpublishStreamRequest(conferenceId: conference.id, streamId: streamId, userEndpointId: endpointId, userId: userId)
            API2.sharedInstance.unpublishStream(request, onSuccess: { _ in }, onFailure: { error in
                sdkLog("Unpublishing the lost stream %{public}@ failed - error %{public}@", log: Log.conferenceSDK, type: .default, streamId, error.localizedDescription)
            })

            let newStreamId = UUID().uuidString
            guard rtcClient.republishLocalStream(replacing: streamId, with: newStreamId) else {
                return nil
            }
            //The new stream starts unmuted for viewers: mark what the user muted once it is published
            let videoMuted = rtcClient.localVideoTrack.map { !$0.isEnabled } ?? false
            let audioMuted = rtcClient.localAudioTrack.map { !$0.isEnabled } ?? false
            if !isConferenceOnHold && (videoMuted || audioMuted) {
                republishedStreamsToMute.insert(newStreamId)
            }
            delegate?.auviousSDK(didRepublishLocalStream: streamId, as: newStreamId)
            return newStreamId
        }

        guard let remoteEndpointId = container.endpointId, let remoteUserId = container.userId else {
            return nil
        }
        let request = StopViewStreamRequest(conferenceId: conference.id, streamId: streamId, userEndpointId: remoteEndpointId, userId: remoteUserId, viewerId: endpointId)
        API2.sharedInstance.stopViewStream(request, onSuccess: { _ in }, onFailure: { error in
            sdkLog("Stopping the lost view of %{public}@ failed - error %{public}@", log: Log.conferenceSDK, type: .default, streamId, error.localizedDescription)
        })
        _ = rtcClient.removeRemoteStreams(streamId: streamId)
        rtcClient.configureRemoteStream(type: streamType, streamId: streamId, endpointId: remoteEndpointId, userId: remoteUserId)
        return streamId
    }

    /// A remote stream we were recovering no longer exists: unpublishes it as the backend would have told us,
    /// so the app removes its view (the unpublished message, live or missed, finds no stream to remove after this)
    private func streamGone(_ streamId: String, conferenceId: String) {
        guard let container = rtcClient.peerConnections.first(where: { $0.streamId == streamId && !$0.isLocal }),
              let type = container.streamType, let endpointId = container.endpointId, let userId = container.userId else {
            streamRecovery.forget(streamId)
            _ = rtcClient.removeRemoteStreams(streamId: streamId)
            return
        }
        let json: [String: Any] = ["type": ConferenceEventType.conferenceStreamUnpublished.rawValue, "conferenceId": conferenceId,
                                   "userId": userId, "userEndpointId": endpointId, "streamId": streamId, "streamType": type.rawValue]
        delegateConferenceMessage(msg: ConferenceStreamUnpublishedEvent(fromJson: JSON(json)))
    }

    private func restoreMutedTracks(ofRepublishedStream streamId: String) {
        guard republishedStreamsToMute.remove(streamId) != nil, let conference = currentConference else { return }
        if rtcClient.localVideoTrack?.isEnabled == false {
            toggleLocalStream(conferenceId: conference.id, streamId: streamId, operation: .set, type: .video, onSuccess: {}, onFailure: { _ in })
        }
        if rtcClient.localAudioTrack?.isEnabled == false {
            toggleLocalStream(conferenceId: conference.id, streamId: streamId, operation: .set, type: .audio, onSuccess: {}, onFailure: { _ in })
        }
    }

    /// MQTT is back after a drop: catch up with the conference messages we missed meanwhile
    private func catchUpAfterReconnect() {
        guard currentConference != nil else { return }
        sdkLog("MQTT reconnected, fetching the conference state", log: Log.conferenceSDK, type: .default)
        resyncConference(force: true)
    }

    private func startNetworkMonitor() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let available = path.status == .satisfied
                self?.streamRecovery.setNetworkAvailable(available)
                if available {
                    MQTTModule2.sharedInstance.reconnect()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "AuviousSDK.network"))
        pathMonitor = monitor
    }

    /// Started again on the next login
    private func stopNetworkMonitor() {
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    internal func rtcClient(screenShareICEConnectionNeedsRestart streamId: String) {
        // Tear down the failed peer connection and unpublish, but keep the
        // screen capturer running so we can re-publish without asking for
        // ReplayKit permission again.
        _ = rtcClient.removePublishStreams(streamId: streamId)

        guard let loginResponse = AuthenticationModule.sharedInstance.loginResponse,
              let userId = loginResponse.userId,
              let endpointId = UserEndpointModule.sharedInstance.userEndpointId,
              let conference = currentConference else {
            // Cannot retry — fall through to permanent failure.
            rtcClient.stopScreenSharing()
            sharingMyScreen = false
            delegate?.auviousSDK(screenSharingStopped: true)
            return
        }

        let usRequest = UnpublishStreamRequest(
            conferenceId: conference.id,
            streamId: streamId,
            userEndpointId: endpointId,
            userId: userId
        )

        API2.sharedInstance.unpublishStream(usRequest, onSuccess: { [weak self] _ in
            self?.retryScreenSharePublish(endpointId: endpointId, userId: userId)
        }, onFailure: { [weak self] _ in
            // Unpublish failed, but still attempt the re-publish
            self?.retryScreenSharePublish(endpointId: endpointId, userId: userId)
        })
    }

    /// Re-publishes the screen share stream using the still-running ReplayKit capturer.
    private func retryScreenSharePublish(endpointId: String, userId: String) {
        // Move the running capturer to pending state so configurePublishStream reuses it
        // instead of creating a new one (which would trigger the permission dialog again).
        rtcClient.prepareScreenCaptureForRetry()

        let newStreamId = UUID().uuidString
        delegate?.auviousSDK(didChangeState: .localStreamIsConnecting, streamId: newStreamId, streamType: .screen, endpointId: endpointId)
        rtcClient.configurePublishStream(type: .screen, streamId: newStreamId, endpointId: endpointId, userId: userId)
    }

    internal func rtcClient(screenShareICEConnectionFailed streamId: String) {
        sharingMyScreen = false
        rtcClient.stopScreenSharing()
        _ = rtcClient.removePublishStreams(streamId: streamId)

        guard let loginResponse = AuthenticationModule.sharedInstance.loginResponse,
              let userId = loginResponse.userId,
              let endpointId = UserEndpointModule.sharedInstance.userEndpointId,
              let conference = currentConference else { return }

        let usRequest = UnpublishStreamRequest(
            conferenceId: conference.id,
            streamId: streamId,
            userEndpointId: endpointId,
            userId: userId
        )
        API2.sharedInstance.unpublishStream(usRequest, onSuccess: { [weak self] _ in
            self?.delegate?.auviousSDK(screenSharingStopped: true)
        }, onFailure: { [weak self] _ in
            self?.delegate?.auviousSDK(screenSharingStopped: true)
        })
    }
}

//MARK: -
//MARK: Co-browse helpers
//MARK: -

extension AuviousConferenceSDK {
    
    /// The logged in user id ('sub' claim)
    internal var currentUserId: String? {
        return AuthenticationModule.sharedInstance.loginResponse?.userId
    }
    
    /// The conference we are currently joined to
    internal var currentConferenceId: String? {
        return currentConference?.id
    }
    
    /// Raw conference metadata values (key -> value) as received when joining
    internal var joinedConferenceMetadata: [String: String] {
        return currentConference?.metadataValues ?? [:]
    }
    
    /// The id of our published screen stream, if any (changes after an ICE re-publish)
    internal var localScreenStreamId: String? {
        return rtcClient?.peerConnections.first(where: { $0.streamType == .screen && $0.isLocal })?.streamId
    }
    
    /// Stops the screen capture and unpublishes the screen stream, if any.
    internal func stopLocalScreenShare(completion: (() -> Void)? = nil) {
        guard rtcClient != nil else {
            completion?()
            return
        }
        
        let streamId = localScreenStreamId
        sharingMyScreen = false
        isPendingScreenSharePermission = false
        
        if rtcClient.isScreenCapturing {
            rtcClient.stopScreenSharing()
        }
        
        guard let screenStreamId = streamId,
              rtcClient.removePublishStreams(streamId: screenStreamId),
              let conference = currentConference,
              let userId = currentUserId,
              let endpointId = UserEndpointModule.sharedInstance.userEndpointId else {
            completion?()
            return
        }
        
        let request = UnpublishStreamRequest(conferenceId: conference.id, streamId: screenStreamId, userEndpointId: endpointId, userId: userId)
        API2.sharedInstance.unpublishStream(request, onSuccess: { _ in
            completion?()
        }, onFailure: { error in
            sdkLog("Co-browse unpublish screen failed %@", log: Log.conferenceSDK, type: .error, error.localizedDescription)
            completion?()
        })
    }
    
    /// Restores connectivity after the app returns to the foreground during a co-browse session.
    /// Re-registers the endpoint and rejoins the conference if the server dropped us while suspended.
    internal func restoreCobrowseConnection(onSuccess: @escaping () -> Void, onFailure: @escaping (Error) -> Void) {
        guard let userId = currentUserId, let endpointId = UserEndpointModule.sharedInstance.userEndpointId else {
            onFailure(AuviousSDKError.notLoggedIn)
            return
        }
        
        let conferenceId = currentConference?.id ?? lastConferenceJoined
        let request = KeepAliveRequest(userEndpointId: endpointId, userId: userId)
        UserEndpointModule.sharedInstance.keepAliveRequest = request
        
        API2.sharedInstance.keepAlive(request, validateStatus: true, onSuccess: { _ in
            UserEndpointModule.sharedInstance.startKeepAliveTimer()
            MQTTModule2.sharedInstance.reconnect()
            onSuccess()
        }, onFailure: { _ in
            sdkLog("Co-browse endpoint expired while in background, re-registering", log: Log.conferenceSDK, type: .debug)
            
            UserEndpointModule.sharedInstance.createEndpoint(newEndpointId: UUID().uuidString, userId: userId, onSuccess: { newEndpointId in
                MQTTModule2.sharedInstance.configure(endpointId: newEndpointId)
                MQTTModule2.sharedInstance.disconnectAndReconnect()
                
                guard let rejoinId = conferenceId else {
                    onFailure(AuviousSDKError.notInConference)
                    return
                }
                
                //Our previous membership is gone, rejoin as a fresh endpoint
                self.removeAllStreams()
                self.emptyPeerConnections()
                self.currentConference = nil
                self.joinConference(conferenceId: rejoinId, onSuccess: { _ in
                    onSuccess()
                }, onFailure: onFailure)
            }, onFailure: onFailure)
        })
    }
}
