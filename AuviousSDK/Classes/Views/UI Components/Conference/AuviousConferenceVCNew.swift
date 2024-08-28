//
//  AuviousConferenceVCNew.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 24/9/20.
//

import UIKit
import os

public class AuviousConferenceVCNew: UIViewController, AuviousSDKConferenceDelegate {
    
    //UI components
    
    //Network indicator view
    private let networkIndicator = NetworkIndicatorView()
    private let networkIndicatorDetails = NetworkDetailsNotificationView(with: nil)
    private var hideNetworkDetailsBlock: DispatchWorkItem?
    private var lastKnownNetworkStatistics: NetworkStatistics? = nil
    
    //Container of all stream views
    private var streamContainerView: UIView!
    //Our local stream view
    private var localView: StreamView = StreamView()
    //List of all remote stream views, excluding the share screen
    private var remoteViews: [StreamView] = []
    //Share screen stream view
    private var shareScreenContainerView: StreamView?
    //Bottom button bar
    private var buttonContainerView: ConferenceButtonBar!
    
    //Overlay view for hold mode
    private var blurredOverlayView: ConferenceHoldView?
    
    //UI constraints
    private var existingConstraints: [NSLayoutConstraint] = []
    private let viewPadding: CGFloat = 10
    private let viewSize: CGFloat = 80
    private var networkIndicatorDetailsTop: NSLayoutConstraint!
    private let maximumRemoteStreamsRendered = 3
    
    //UI feedback
    private let selectionFeedbackGenerator = UIImpactFeedbackGenerator()
    
    //Service dispatch group for distinguishing remote streams
    private let serviceGroup = DispatchGroup()
    
    //Configuration
    private var videoViewBackgroundColor: UIColor = UIColor.gray
    
    //Conference properties
    private var username: String = ""
    private var password: String = ""
    private var conference: String = ""
    private var baseEndpoint: String = ""
    private var mqttEndpoint: String = ""
    private var clientId: String = ""
    private var params: [String: String] = [:]
    private var configuredStreamType: StreamType = .unknown
    
    //Control flags
    private var performedInitialValidations: Bool = false
    private var conferenceJoined: Bool = false
    private var shareScreenFullScreen: Bool = false
    private var initialStreamsConnected: Bool = false
    
    //Delegate
    private weak var delegate: AuviousSimpleConferenceDelegate?
    
    //Our local stream id
    private var localStreamId: String?
    private var localStreamType: StreamType?
    //The conference we're in
    private var currentConference: ConferenceSimpleView!
    //Current conference participants
    private var conferenceParticipants: Int = 0 {
        didSet {
            setScreenTitle()
        }
    }
    
    //Public constructor
    public init(clientId: String, params: [String: String], baseEndpoint: String, mqttEndpoint: String, delegate: AuviousSimpleConferenceDelegate,  callMode: AuviousCallMode) {
        self.params = params
        self.clientId = clientId
        self.baseEndpoint = baseEndpoint
        self.mqttEndpoint = mqttEndpoint
        self.delegate = delegate
        
        if let username = params["username"] {
            self.username = username
        }
        
        if let password = params["password"] {
            self.password = password
        }
        
        if let conference = params["conference"] {
            self.conference = conference
        }
        
        switch callMode {
        case .audio:
            configuredStreamType = .mic
        case .video:
            configuredStreamType = .cam
        case .audioVideo:
            configuredStreamType = .micAndCam
        }
        
        super.init(nibName: nil, bundle: Bundle(for: AuviousConferenceVC.self))
        
        os_log("UI Conference component: initialised", log: Log.conferenceUI, type: .debug)
    }
    
    //Public constructor
    public init(clientId: String, username: String, password: String, conference: String, baseEndpoint: String, mqttEndpoint: String, delegate: AuviousSimpleConferenceDelegate, callMode: AuviousCallMode) {
        self.clientId = clientId
        self.username = username
        self.password = password
        self.conference = conference
        self.baseEndpoint = baseEndpoint
        self.mqttEndpoint = mqttEndpoint
        self.delegate = delegate
        
        switch callMode {
        case .audio:
            configuredStreamType = .mic
        case .video:
            configuredStreamType = .cam
        case .audioVideo:
            configuredStreamType = .micAndCam
        }
        
        super.init(nibName: nil, bundle: Bundle(for: AuviousConferenceVC.self))
        
        os_log("UI Conference component: initialised", log: Log.conferenceUI, type: .debug)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: -
    // MARK: VC Lifecycle
    // MARK: -
        
    override open func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(self, selector: #selector(self.orientationChanged), name: UIApplication.didChangeStatusBarOrientationNotification, object: nil)
        
        view.backgroundColor = .black
        
        //Setup the container of all stream views
        streamContainerView = UIView(frame: .zero)
        streamContainerView.translatesAutoresizingMaskIntoConstraints = false
        streamContainerView.backgroundColor = .clear
        view.addSubview(streamContainerView)
        streamContainerView.topAnchor.constraint(equalTo: view.topAnchor, constant: 0).isActive = true
        streamContainerView.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 0).isActive = true
        streamContainerView.rightAnchor.constraint(equalTo: view.rightAnchor, constant: 0).isActive = true
        streamContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0).isActive = true
        
        //Network indicator
        view.addSubview(networkIndicator)
        networkIndicator.alpha = 0.7
        networkIndicator.topAnchor.constraint(equalTo: view.saferAreaLayoutGuide.topAnchor).isActive = true
        networkIndicator.leadingAnchor.constraint(equalTo: view.saferAreaLayoutGuide.leadingAnchor).isActive = true
        networkIndicator.widthAnchor.constraint(equalToConstant: 40).isActive = true
        networkIndicator.heightAnchor.constraint(equalToConstant: 50).isActive = true
        let tapRecogniser = UITapGestureRecognizer(target: self, action: #selector(self.networkIndicatorPressed))
        networkIndicator.addGestureRecognizer(tapRecogniser)
        
        //Network indicator details
        view.addSubview(networkIndicatorDetails)
        networkIndicatorDetails.layer.zPosition = 2100
        networkIndicatorDetails.alpha = 0
        networkIndicatorDetails.leadingAnchor.constraint(equalTo: view.saferAreaLayoutGuide.leadingAnchor, constant: 10).isActive = true
        networkIndicatorDetails.trailingAnchor.constraint(equalTo: view.saferAreaLayoutGuide.trailingAnchor, constant: -10).isActive = true
        networkIndicatorDetails.heightAnchor.constraint(equalToConstant: 60).isActive = true
        networkIndicatorDetailsTop = networkIndicatorDetails.topAnchor.constraint(equalTo: view.saferAreaLayoutGuide.topAnchor, constant: -100)
        networkIndicatorDetailsTop.isActive = true
        networkIndicatorDetails.closeButton.addTarget(self, action: #selector(self.hideNetworkDetailsPressed), for: .touchUpInside)
        view.bringSubviewToFront(networkIndicatorDetails)
        
        //Setup a cancellable piece of code to hide the network details
        hideNetworkDetailsBlock = DispatchWorkItem {
            self.hideNetworkDetails()
        }
        //Setup feedback
        selectionFeedbackGenerator.prepare()
        
        //Setup notifications
        AuviousNotification.shared.presenter = self
        
        //Create local stream view
        localView.translatesAutoresizingMaskIntoConstraints = false
        localView.frame = .zero
        localView.layer.zPosition = 100
        localView.layer.borderColor = UIColor.gray.cgColor
        localView.layer.borderWidth = 1.0 / UIScreen.main.scale
        
        streamContainerView.addSubview(localView)

        createButtonBar()
    }
     
    //Shows the toast notification view
    @objc private func showNetworkDetails() {
        networkIndicatorDetails.alpha = 1
        
        UIView.animate(withDuration: 0.2, animations: {
            self.networkIndicatorDetailsTop.constant = 10
            self.view.layoutIfNeeded()
        }, completion: { finished in
            if finished {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.hideNetworkDetails()
                }
            }
        })
    }
    
    //Hides the toast notification view
    @objc private func hideNetworkDetails() {
        UIView.animate(withDuration: 0.2, animations: {
            self.networkIndicatorDetailsTop.constant = -100
            self.view.layoutIfNeeded()
        }, completion: { finished in
            self.networkIndicatorDetails.updateUI(with: self.lastKnownNetworkStatistics)
        })
    }
    
    //Updates the toast notification view with latest network data and displays the view
    @objc private func networkIndicatorPressed() {
        networkIndicatorDetails.updateUI(with: lastKnownNetworkStatistics)
        showNetworkDetails()
    }
    
    //Cancels the scheduled dismissal of the toast view and hides it
    @objc private func hideNetworkDetailsPressed() {
        self.hideNetworkDetailsBlock?.cancel()
        hideNetworkDetails()
    }
    
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if !performedInitialValidations {
            //Check for permissions
            if !validateVideoPermissions() {
                os_log("No video permission, returning error", log: Log.conferenceUI, type: .debug)
                handleError(AuviousSDKError.videoPermissionIsDisabled)
                return
            }
            
            if !validateMicPermissions() {
                os_log("No audio permission, returning error", log: Log.conferenceUI, type: .debug)
                handleError(AuviousSDKError.audioPermissionIsDisabled)
                return
            }
            
            //Check credentials
            if username.isEmpty || password.isEmpty || clientId.isEmpty {
                os_log("Username/password/clientId empty, returning error", log: Log.conferenceUI, type: .debug)
                handleError(AuviousSDKError.missingSDKCredentials)
                return
            }
            
            //Check call target
//            if conference.isEmpty {
//                os_log("Conference is empty, returning error", log: Log.conferenceUI, type: .debug)
//                handleError(AuviousSDKError.missingCallTarget)
//                return
//            }
            
            performedInitialValidations = true
        }
            
        if performedInitialValidations && !conferenceJoined {
            AuviousConferenceSDK.sharedInstance.delegate = self
            AuviousConferenceSDK.sharedInstance.configure(params: params, username: username, password: password, clientId: clientId, baseEndpoint: baseEndpoint, mqttEndpoint: mqttEndpoint)
            os_log("Configured ConferenceSDK", log: Log.conferenceUI, type: .debug)
//
//            //Get access to the local video stream immediately
//            let localStream = AuviousCallSDK.sharedInstance.createLocalMediaStream(type: .micAndCam, streamId: "test")
//            log("UI Call component: Created local media stream")
//
            
            AuviousConferenceSDK.sharedInstance.login(onLoginSuccess: {(userId, conferenceId) in
                os_log("Login success", log: Log.conferenceUI, type: .debug)
                
                if let conference = conferenceId {
                    self.conference = conference
                }
                
                AuviousConferenceSDK.sharedInstance.joinConference(conferenceId: self.conference, onSuccess: {(joinedConference) in
                    
                    if let jConference = joinedConference {
                        os_log("Joined conference with id %@", log: Log.conferenceUI, type: .debug, String(describing: jConference.id))
                        self.currentConference = jConference
                        self.conferenceJoined = true
                        
                        //Start connecting to any existing streams in our conference
                        self.handleExistingConferenceStreams()
                        self.startLocalStream()
                        
                        //Joined conference is on hold
                        if self.currentConference.onHold {
                            self.auviousSDK(conferenceOnHold: true)
                        }
                    } else {
                        os_log("Unable to join conference", log: Log.conferenceUI, type: .error)
                    }
                }, onFailure: {(error) in
                    self.handleError(error)
                })
                
            }, onLoginFailure: {(error) in
                self.handleError(error)
            })
        }
    }
    
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        AuviousConferenceSDK.sharedInstance.logout(onSuccess: {
        }, onFailure: {error in
        })
    }
    
    //When orientation changes we simply reevaluate our UI constraints
    @objc func orientationChanged(notification: NSNotification) {
        createConstraints()
    }
    
    // MARK: -
    // MARK: Helpers
    // MARK: -
    
    private func startLocalStream() {
        do {
            localStreamId = try AuviousConferenceSDK.sharedInstance.startPublishLocalStreamFlow(type: configuredStreamType)
        } catch let error {
            os_log("startPublishLocalStreamFlow error %@", log: Log.conferenceUI, type: .error, error.localizedDescription)
            handleError(error)
        }
    }
    
    //Initialises the RTC view stream flow for existing conference streams
    private func handleExistingConferenceStreams(){
        //Reset our flag, and start connecting to remote participants
        initialStreamsConnected = false
        var serviceGroupEntries = 0
        
        if !currentConference.participants.isEmpty {
            for user in currentConference.participants {
                for endpointStream in user.endpoints {
                    for stream in endpointStream.streams {
                        do {
                            if !initialStreamsConnected {
                                serviceGroup.enter()
                                serviceGroupEntries += 1
                            }
                            try AuviousConferenceSDK.sharedInstance.startRemoteStreamFlow(streamId: stream.id, endpointId: endpointStream.id, streamType: stream.type, remoteUserId: user.id)
                        } catch let error {
                            os_log("startRemoteStreamFlow error %@", log: Log.conferenceUI, type: .error, error.localizedDescription)
                            
                            if !initialStreamsConnected {
                                serviceGroup.leave()
                            }
                            
                            handleError(error)
                        }
                    }
                }
            }
            
            //Sanity check
            if serviceGroupEntries == 0 {
                initialStreamsConnected = true
            }
            
        } else {
            initialStreamsConnected = true
        }
    }
    
    //Check for video permissions
    func validateVideoPermissions() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }
    
    //Check for audio persmissions
    func validateMicPermissions() -> Bool {
        return AVAudioSession.sharedInstance().recordPermission == .granted
    }
    
    //Sets the screen title, according to the number of conference participants
    private func setScreenTitle() {
        let membersString = conferenceParticipants == 1 ? "member" : "members"
        var screenTitle = currentConference.id + " ("
        screenTitle += String(conferenceParticipants) + " "
        screenTitle += membersString + ")"
        title =  screenTitle
    }
    
    private func handleError(_ error: Error) {
        let auviousError = error as! AuviousSDKError
        os_log("Handle error %@", log: Log.conferenceUI, type: .error, error.localizedDescription)
        
        switch auviousError {
        case .videoPermissionIsDisabled:
            delegate?.onConferenceError(.PERMISSION_REQUIRED) // .videoPermissionIsDisabled
        case .audioPermissionIsDisabled:
            delegate?.onConferenceError(.PERMISSION_REQUIRED) // .audioPermissionIsDisabled
        case .missingSDKCredentials:
            delegate?.onConferenceError(.AUTHENTICATION_FAILURE) // .missingSDKCredentials
        case .missingCallTarget:
            delegate?.onConferenceError(.CONFERENCE_MISSING) // .missingCallTarget
        case .noInternetConnection:
            delegate?.onConferenceError(.NETWORK_ERROR) // .noInternetConnection
        case .callNotAnswered:
            delegate?.onConferenceError(.CALL_REJECTED) // .callNotAnswered
        default:
            delegate?.onConferenceError(.UNKNOWN_FAILURE) // .callError
        }
    }
    
    private func handleConferenceEndedEvent(){
        delegate?.onConferenceSuccess()
    }
    
    //Triggers stream view refresh/removal according to the remote participant's stream state
    private func handleStreamDisconnection(streamId: String, streamType: StreamType, endpointId: String) {
        if streamType == .screen {
            shareScreenContainerView?.videoStreamRemoved()
            shareScreenContainerView?.removeFromSuperview()
            shareScreenContainerView = nil
            
            //Refresh UI
            createConstraints()
        } else {
            var remoteParticipantIndex: Int?
            for (index, item) in remoteViews.enumerated() {
                if item.participantEndpoint?.id == endpointId {
                    remoteParticipantIndex = index
                    break
                }
            }

            if let index = remoteParticipantIndex {
                let participant = remoteViews[index].participantEndpoint
                
                //We only had 1 stream from this participant, therefore we should remove the cell from the collection view
                if participant?.streams.count == 1 {
                    let remoteView = remoteViews.remove(at: index)

                    if index < maximumRemoteStreamsRendered {
                        if streamType == .mic {
                            remoteView.audioStreamRemoved()
                        } else if streamType == .cam {
                            remoteView.videoStreamRemoved()
                        } else if streamType == .micAndCam {
                            remoteView.avStreamRemoved()
                        }
                    }
                        
                    remoteView.removeFromSuperview()
                    
                    //Refresh UI
                    createConstraints()

                } else if (participant?.streams!.count)! > 1 {

                    let remoteView = remoteViews[index]
                    //Remove the video if needed
                    if streamType == .cam {
                        remoteView.videoStreamRemoved()
                    } else if streamType == .mic {
                        remoteView.audioStreamRemoved()
                    } else if streamType == .micAndCam {
                        remoteView.avStreamRemoved()
                    }
                }
            }
        }
    }
    
    //Returns the collection view index path of the cell that will handle this stream
    private func getIndexPathForStream(stream: RTCMediaStream, streamId: String, endpointId: String) -> Int {
        var streamType: StreamType!
        if stream.audioTracks.count > 0 && stream.videoTracks.count > 0 {
            streamType = StreamType.micAndCam
        } else if stream.audioTracks.count == 0 && stream.videoTracks.count > 0 {
            streamType = StreamType.cam
        } else if stream.audioTracks.count > 0 && stream.videoTracks.count == 0 {
            streamType = StreamType.mic
        }
        
        var remoteParticipantIndex: Int?
        for (index, item) in remoteViews.enumerated() {
            if item.participantEndpoint?.id == endpointId {
                remoteParticipantIndex = index
                break
            }
        }
        
        //Stream view is already created
        if let index = remoteParticipantIndex {
            
            //Add new stream to this user's endpoint
            let participantEndpoint = remoteViews[index].participantEndpoint
            let participantStream = ParticipantEndpointStream(id: streamId, type: streamType)
            participantEndpoint?.streams.append(participantStream)
            
            return index
        } else {
            
            //Create a new remote participant with the incoming stream
            let participantEndpoint = ParticipantEndpoint(endpointId: endpointId)
            let participantStream = ParticipantEndpointStream(id: streamId, type: streamType)
            participantEndpoint.streams.append(participantStream)
            
            //Create a view for this remote stream
            let remoteView = StreamView(frame: .zero)
            remoteView.translatesAutoresizingMaskIntoConstraints = false
            remoteView.participantEndpoint = participantEndpoint
            remoteView.backgroundColor = videoViewBackgroundColor
            self.remoteViews.append(remoteView)
            streamContainerView.addSubview(remoteView)
            view.bringSubviewToFront(buttonContainerView)
            
            //If we can't show remote video due to UI limits, notify the user
            if initialStreamsConnected && remoteViews.count > maximumRemoteStreamsRendered {
                self.networkIndicatorDetails.titleLabel.text = "A new participant has joined"
                self.networkIndicatorDetails.subtitleLabel.text = "Due to current limitations, you can only listen"
                self.showNetworkDetails()
            }
            
            return self.remoteViews.count - 1
        }
    }
    
    // MARK: -
    // MARK: AuviousSDKConferenceDelegate
    // MARK: -
    
    public func auviousSDK(conferenceOnHold flag: Bool) {
        let effectDuration: Double = 0.2
        
        if flag {
            
            if let screenshot = streamContainerView.screenshot().grayscaled {
                
                blurredOverlayView = ConferenceHoldView(frame: .zero)
                blurredOverlayView!.image = screenshot
                view.addSubview(blurredOverlayView!)
                
                blurredOverlayView?.topAnchor.constraint(equalTo: view.topAnchor, constant: 0).isActive = true
                blurredOverlayView?.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0).isActive = true
                blurredOverlayView?.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 0).isActive = true
                blurredOverlayView?.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 0).isActive = true
                
                UIView.animate(withDuration: effectDuration, animations: {
                    self.blurredOverlayView?.blurView.alpha = 0.9
                }, completion: { _ in
                    self.buttonContainerView.conferenceOnHold(true)
                    AuviousConferenceSDK.sharedInstance.removeLocalAudioStream()
                    AuviousConferenceSDK.sharedInstance.removeLocalVideoStream()
                })
            }
        } else {
            if let blurredOverlayView = blurredOverlayView {
                UIView.animate(withDuration: effectDuration, animations: {
                    blurredOverlayView.alpha = 0
                }, completion: { _ in
                    self.buttonContainerView.conferenceOnHold(false)
                    
                    AuviousConferenceSDK.sharedInstance.addLocalAudioStream()
                    AuviousConferenceSDK.sharedInstance.addLocalVideoStream()
                    
                    blurredOverlayView.removeFromSuperview()
                    self.blurredOverlayView = nil
                })
            }
        }
    }

    public func auviousSDK(didReceiveConferenceEvent event: ConferenceEvent) {
        if event is ConferenceJoinedEvent {
            conferenceParticipants += 1
        } else if event is ConferenceLeftEvent {
            conferenceParticipants -= 1
        } else if event is ConferenceEndedEvent {
            handleConferenceEndedEvent()
        } else if event is ConferenceNetworkIndicatorEvent {
            let endpoint = AuviousConferenceSDK.sharedInstance.userEndpointId
            let object = event as! ConferenceNetworkIndicatorEvent
            networkIndicator.updateUI(with: object, participantId: endpoint)
            
            if let endpoint = endpoint {
                self.lastKnownNetworkStatistics = object.data[endpoint]
            }
        } else if event is ConferenceStreamPublishedEvent {
            let object = event as! ConferenceStreamPublishedEvent
            do {
                os_log("Starting remote stream flow for type %@", log: Log.conferenceUI, type: .debug, object.streamType.rawValue)
                try AuviousConferenceSDK.sharedInstance.startRemoteStreamFlow(streamId: object.streamId, endpointId: object.userEndpointId, streamType: object.streamType, remoteUserId: object.userId)
            } catch let error {
                os_log("startRemoteStreamFlow error %@", log: Log.conferenceUI, type: .error, error.localizedDescription)
                handleError(error)
            }
        } else if event is ConferenceStreamUnpublishedEvent {
            let object = event as! ConferenceStreamUnpublishedEvent
            
            do {
                try AuviousConferenceSDK.sharedInstance.stopRemoteStream(streamId: object.streamId, remoteUserId: object.userId, remoteEndpointId: object.userEndpointId, streamType: object.streamType)
            } catch let error {
                os_log("stopRemoteStream error %@", log: Log.conferenceUI, type: .error, error.localizedDescription)
                handleError(error)
            }
        }
    }
    
    public func auviousSDK(didReceiveRemoteStream stream: RTCMediaStream, streamId: String, endpointId: String, type: StreamType) {
        DispatchQueue.main.async {
            if type == .screen {
                self.shareScreenContainerView = StreamView(frame: .zero)
                self.shareScreenContainerView!.translatesAutoresizingMaskIntoConstraints = false
                self.shareScreenContainerView!.setZoomable(true)
                
                let tap = UITapGestureRecognizer(target: self, action: #selector(self.shareScreenDoubleTapped))
                tap.numberOfTapsRequired = 2
                self.shareScreenContainerView?.addGestureRecognizer(tap)
                
                //Create a new remote participant with the incoming stream
                let participantEndpoint = ParticipantEndpoint(endpointId: endpointId)
                let participantStream = ParticipantEndpointStream(id: streamId, type: type)
                participantEndpoint.streams.append(participantStream)
                
                self.shareScreenContainerView!.participantEndpoint = participantEndpoint
                self.shareScreenContainerView!.backgroundColor = self.videoViewBackgroundColor
                
                //Add the video stream to our cell
                if stream.videoTracks.count > 0 {
                    let remoteVideoTrack: RTCVideoTrack = stream.videoTracks.first!
                    self.shareScreenContainerView!.videoStreamAdded(remoteVideoTrack, isScreen: true)
                }
                
                self.streamContainerView.addSubview(self.shareScreenContainerView!)
                
            } else {
                let remoteViewIndex = self.getIndexPathForStream(stream: stream, streamId: streamId, endpointId: endpointId)
                let remoteView = self.remoteViews[remoteViewIndex]
                
                //Add the video stream to our cell
                if stream.videoTracks.count > 0 {
                    let remoteVideoTrack: RTCVideoTrack = stream.videoTracks.first!

                    if stream.audioTracks.count > 0 {
                        remoteView.avStreamAdded(remoteVideoTrack)
                    } else {
                        remoteView.videoStreamAdded(remoteVideoTrack)
                    }
                    
                    //Handle muted video tracks
                    if self.currentConference.mutedVideoTracks.contains(streamId) {
                        remoteView.videoStreamRemoved()
                    }
                    //Hande muted audio tracks
                    if self.currentConference.mutedAudioTracks.contains(streamId) {
                        remoteView.audioStreamRemoved()
                    }
                    
                    os_log("Remote stream added", log: Log.conferenceUI, type: .debug)
                
                } else if stream.audioTracks.count > 0 {
                    remoteView.audioStreamAdded()
                    
                    //Handle muted audio tracks
                    if self.currentConference.mutedAudioTracks.contains(streamId) {
                        remoteView.audioStreamRemoved()
                    }
                }
            }
            
            //Keep track of this stream addition
            if !self.initialStreamsConnected {
                self.serviceGroup.leave()
            }
            
            // Proceed when all API requests are finished
            self.serviceGroup.notify(queue: DispatchQueue.main) {
                if !self.initialStreamsConnected {
                    self.initialStreamsConnected = true
                    
                    if self.remoteViews.count > self.maximumRemoteStreamsRendered {
                        let title = "Limited visibility"
                        let subtitle = "You can only see \(self.maximumRemoteStreamsRendered)/\(self.remoteViews.count) participants"
                        self.networkIndicatorDetails.titleLabel.text = title
                        self.networkIndicatorDetails.subtitleLabel.text = subtitle
                        self.showNetworkDetails()
                    }
                }
            }
            
            //Refresh UI
            self.createConstraints()
        }
    }
    
    public func auviousSDK(didRejoinConference conference: ConferenceSimpleView) {
        //Clear the streams from the UI
        _ = remoteViews.map{ $0.removeFromSuperview() }
        remoteViews.removeAll()
        
        currentConference = conference
        conferenceParticipants = currentConference.participants.count
        
        //Reconnect to conference streams
        handleExistingConferenceStreams()
        startLocalStream()
    }
    
    public func auviousSDK(didChangeState newState: StreamEventState, streamId: String, streamType: StreamType, endpointId: String) {
        switch newState {
        case .localStreamIsConnecting:
            os_log("Local Stream Is Connecting", log: Log.conferenceUI, type: .debug)
        case .localStreamConnected:
            os_log("Local Stream Connected", log: Log.conferenceUI, type: .debug)
        case .remoteStreamIsConnecting:
            os_log("Remote Stream Is Connecting", log: Log.conferenceUI, type: .debug)
        case .remoteStreamConnected:
            os_log("Remote Stream Connected", log: Log.conferenceUI, type: .debug)
        case .localStreamIsDisconnecting:
            os_log("Local Stream Is Disonnecting", log: Log.conferenceUI, type: .debug)
        case .localStreamDisconnected:
            os_log("Local Stream Disconnected", log: Log.conferenceUI, type: .debug)
        case .remoteStreamIsDisconnecting:
            os_log("Remote Stream Is Disonnecting", log: Log.conferenceUI, type: .debug)
        case .remoteStreamDisconnected:
            os_log("Remote Stream Disconnected", log: Log.conferenceUI, type: .debug)
            handleStreamDisconnection(streamId: streamId, streamType:streamType, endpointId: endpointId)
        case .localCaptureStarted:
            os_log("Local Capture Started", log: Log.conferenceUI, type: .debug)
        case .localCaptureStoped:
            os_log("Local Capture Stoped", log: Log.conferenceUI, type: .debug)
        }
    }
    
    //Local stream received (streamAdded)
    public func auviousSDK(didReceiveLocalVideoTrack localVideoTrack: RTCVideoTrack!) {
        localView.avStreamAdded(localVideoTrack)
        createConstraints()
        
        // sync local view with call type
        switch (configuredStreamType){
            case .cam:
                localView.audioStreamRemoved();
                break;
            case .mic:
                localView.videoStreamRemoved();
                break;
            default:
                // no changes
            break;
        }
    }
    
    public func auviousSDK(didReceiveLocalStream stream: RTCMediaStream, streamId: String, type: StreamType) {
       localStreamType = type
        if  type == .mic {
            localView.audioStreamAdded()
        }
    }
    
    public func auviousSDK(trackMuted type: StreamType, endpointId: String) {
        var remoteParticipantIndex: Int?
        for (index, item) in remoteViews.enumerated() {
            if item.participantEndpoint?.id == endpointId {
                remoteParticipantIndex = index
                break
            }
        }
        
        if let index = remoteParticipantIndex {
            if type == .mic {
                remoteViews[index].audioStreamRemoved()
            } else if type == .cam {
                remoteViews[index].videoStreamRemoved()
            }
        }
    }
    
    public func auviousSDK(trackUnmuted type: StreamType, endpointId: String) {
        var remoteParticipantIndex: Int?
        for (index, item) in remoteViews.enumerated() {
            if item.participantEndpoint?.id == endpointId {
                remoteParticipantIndex = index
                break
            }
        }
        
        if let index = remoteParticipantIndex {
            if type == .mic {
                remoteViews[index].audioStreamAdded()
            } else if type == .cam {
                remoteViews[index].videoStreamAdded()
            }
        }
    }
    
    // MARK: -
    // MARK: UI
    // MARK: -
    
    //Creates the button bar
    private func createButtonBar() {
        //Button container
        buttonContainerView = ConferenceButtonBar(frame: .zero)
        buttonContainerView.delegate = self
        view.addSubview(buttonContainerView)
        
        buttonContainerView.leadingAnchor.constraint(equalTo: view.saferAreaLayoutGuide.leadingAnchor, constant: 0).isActive = true
        buttonContainerView.trailingAnchor.constraint(equalTo: view.saferAreaLayoutGuide.trailingAnchor, constant: 0).isActive = true
        buttonContainerView.bottomAnchor.constraint(equalTo: view.saferAreaLayoutGuide.bottomAnchor, constant: 0).isActive = true
        buttonContainerView.heightAnchor.constraint(equalToConstant: 60).isActive = true
        
        switch (configuredStreamType){
            case .cam:
                buttonContainerView.micButton.type = .micDisabled
                break;
            case .mic:
                buttonContainerView.cameraButton.type = .camDisabled
                buttonContainerView.cameraSwitchButton.type = .camSwitchDisabled
                break;
            default:
                // no changes
            break;
        }
    }
    
    @objc func shareScreenDoubleTapped() {
        self.shareScreenFullScreen = !shareScreenFullScreen
        createConstraints()
    }
    
    private func createConstraints() {
        var constraints: [NSLayoutConstraint] = []
        let safeArea = streamContainerView.saferAreaLayoutGuide
        let isLandscape = UIApplication.shared.statusBarOrientation.isLandscape
        var safeLeadingConstraint = view.leadingAnchor
        
        //For landscape left we use the safe area leading constraint - otherwise superview
        if UIDevice.current.orientation == UIDeviceOrientation.landscapeLeft {
            safeLeadingConstraint = safeArea.leadingAnchor
        } else if UIDevice.current.orientation == UIDeviceOrientation.landscapeRight {
            safeLeadingConstraint = view.leadingAnchor
        }
        
        //Full screen screen sharing
        if let shareScreenContainer = shareScreenContainerView, shareScreenFullScreen {
            os_log("Screen share full screen mode", log: Log.conferenceUI, type: .info)
            
            if remoteViews.count == 0 {
                constraints.append(localView.centerXAnchor.constraint(equalTo: buttonContainerView.buttonStackView.centerXAnchor, constant: 0))
                constraints.append(localView.widthAnchor.constraint(equalTo: buttonContainerView.buttonStackView.widthAnchor, multiplier: 0.5))
                constraints.append(localView.heightAnchor.constraint(equalTo: localView.widthAnchor, constant: 0))
                constraints.append(localView.topAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: 150))
                
                //share screen
                constraints.append(shareScreenContainer.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 0))
                constraints.append(shareScreenContainer.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: 0))
                constraints.append(shareScreenContainer.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 0))
                constraints.append(shareScreenContainer.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: 0))
            } else if remoteViews.count == 1 {
                let view1 = remoteViews[0]
                constraints.append(view1.leadingAnchor.constraint(equalTo: buttonContainerView.buttonStackView.leadingAnchor, constant: 0))
                constraints.append(view1.widthAnchor.constraint(equalTo: view1.heightAnchor, multiplier: 1))
                constraints.append(view1.topAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: 150))
                
                constraints.append(localView.trailingAnchor.constraint(equalTo: buttonContainerView.buttonStackView.trailingAnchor, constant: 0))
                constraints.append(localView.widthAnchor.constraint(equalTo: localView.heightAnchor, multiplier: 1))
                constraints.append(localView.topAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: 150))
                
                //relationship
                constraints.append(view1.widthAnchor.constraint(equalTo: localView.widthAnchor, constant: 0))
                constraints.append(view1.trailingAnchor.constraint(equalTo: localView.leadingAnchor, constant: -viewPadding))
                
                //share screen
                constraints.append(shareScreenContainer.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 0))
                constraints.append(shareScreenContainer.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: 0))
                constraints.append(shareScreenContainer.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 0))
                constraints.append(shareScreenContainer.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: 0))
            } else if remoteViews.count == 2 {
                let view1 = remoteViews[0]
                let view2 = remoteViews[1]
                
                constraints.append(view2.centerXAnchor.constraint(equalTo: buttonContainerView.buttonStackView.centerXAnchor))
                constraints.append(view2.topAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: 150))
                constraints.append(view2.heightAnchor.constraint(equalToConstant: viewSize))
                constraints.append(view2.widthAnchor.constraint(equalTo: view2.heightAnchor, multiplier: 1))
                
                constraints.append(view1.trailingAnchor.constraint(equalTo: view2.leadingAnchor, constant: -viewPadding))
                constraints.append(view1.widthAnchor.constraint(equalTo: view2.widthAnchor, constant: 0))
                constraints.append(view1.heightAnchor.constraint(equalTo: view2.heightAnchor, constant: 0))
                constraints.append(view1.topAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: 150))
                
                constraints.append(localView.leadingAnchor.constraint(equalTo: view2.trailingAnchor, constant: viewPadding))
                constraints.append(localView.widthAnchor.constraint(equalTo: view2.widthAnchor, constant: 0))
                constraints.append(localView.heightAnchor.constraint(equalTo: view2.heightAnchor, constant: 0))
                constraints.append(localView.topAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: 150))
                
                //relationship
                constraints.append(view2.widthAnchor.constraint(equalTo: view1.widthAnchor, constant: 0))
                constraints.append(view2.widthAnchor.constraint(equalTo: localView.widthAnchor, constant: 0))
                
                //share screen
                constraints.append(shareScreenContainer.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 0))
                constraints.append(shareScreenContainer.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: 0))
                constraints.append(shareScreenContainer.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 0))
                constraints.append(shareScreenContainer.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: 0))
            } else if remoteViews.count >= maximumRemoteStreamsRendered {
                let view1 = remoteViews[0]
                let view2 = remoteViews[1]
                let view3 = remoteViews[2]
                
                constraints.append(view1.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: viewPadding))
                constraints.append(view1.trailingAnchor.constraint(equalTo: view2.leadingAnchor, constant: -viewPadding))
                constraints.append(view1.topAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: 150))
                constraints.append(view1.heightAnchor.constraint(equalToConstant: viewSize))
                
                constraints.append(view2.leadingAnchor.constraint(equalTo: view1.trailingAnchor, constant: viewPadding))
                constraints.append(view2.trailingAnchor.constraint(equalTo: view3.leadingAnchor, constant: -viewPadding))
                constraints.append(view2.topAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: 150))
                constraints.append(view2.heightAnchor.constraint(equalTo: view1.heightAnchor, constant: 0))
                
                constraints.append(view3.leadingAnchor.constraint(equalTo: view2.trailingAnchor, constant: viewPadding))
                constraints.append(view3.trailingAnchor.constraint(equalTo: localView.leadingAnchor, constant: -viewPadding))
                constraints.append(view3.topAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: 150))
                constraints.append(view3.heightAnchor.constraint(equalTo: view1.heightAnchor, constant: 0))
                
                constraints.append(localView.leadingAnchor.constraint(equalTo: view3.trailingAnchor, constant: viewPadding))
                constraints.append(localView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -viewPadding))
                constraints.append(localView.topAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: 150))
                constraints.append(localView.heightAnchor.constraint(equalTo: view1.heightAnchor, constant: 0))
                
                //relationship
                constraints.append(view1.widthAnchor.constraint(equalTo: view2.widthAnchor, constant: 0))
                constraints.append(view2.widthAnchor.constraint(equalTo: view3.widthAnchor, constant: 0))
                constraints.append(view3.widthAnchor.constraint(equalTo: localView.widthAnchor, constant: 0))
                
                //share screen
                constraints.append(shareScreenContainer.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 0))
                constraints.append(shareScreenContainer.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: 0))
                constraints.append(shareScreenContainer.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 0))
                constraints.append(shareScreenContainer.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: 0))
                //constraints.append(localView.topAnchor.constraint(equalTo: shareScreenContainer.bottomAnchor, constant: 15))
            }
        } else {
        
            //Local view, no screen sharing
            if shareScreenContainerView == nil && remoteViews.count < maximumRemoteStreamsRendered {
                
                //Solo, no screen sharing
                if remoteViews.count == 0 {
                    constraints.append(localView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: 0))
                    constraints.append(localView.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 0))
                    constraints.append(localView.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: 0))
                    constraints.append(localView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 0))
                } else {
                
                    if !isLandscape {
                        constraints.append(localView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -20))
                        constraints.append(localView.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 10))
                        constraints.append(localView.widthAnchor.constraint(equalToConstant: 75))
                        constraints.append(localView.heightAnchor.constraint(equalTo: localView.widthAnchor, multiplier: 16/9))
                    } else {
                        constraints.append(localView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -20))
                        constraints.append(localView.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 10))
                        constraints.append(localView.widthAnchor.constraint(equalToConstant: 132))
                        constraints.append(localView.heightAnchor.constraint(equalTo: localView.widthAnchor, multiplier: 9/16))
                    }
                }
            }
            if remoteViews.count == 0 {
                //0 Remote WITH Share screen
                if let shareScreenContainer = shareScreenContainerView {
                    if !isLandscape {
                        constraints.append(localView.centerXAnchor.constraint(equalTo: buttonContainerView.buttonStackView.centerXAnchor, constant: 0))
                        constraints.append(localView.widthAnchor.constraint(equalTo: buttonContainerView.buttonStackView.widthAnchor, multiplier: 0.5))
                        constraints.append(localView.heightAnchor.constraint(equalTo: localView.widthAnchor, constant: 0))
                        constraints.append(localView.bottomAnchor.constraint(equalTo: buttonContainerView.topAnchor, constant: -15))
                        constraints.append(localView.topAnchor.constraint(equalTo: shareScreenContainer.bottomAnchor, constant: 15))
                        
                        //share screen
                        constraints.append(shareScreenContainer.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 0))
                        constraints.append(shareScreenContainer.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: 0))
                        constraints.append(shareScreenContainer.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 0))
                    } else {
                        constraints.append(localView.leadingAnchor.constraint(equalTo: safeLeadingConstraint, constant: viewPadding))
                        constraints.append(localView.trailingAnchor.constraint(equalTo: shareScreenContainer.leadingAnchor, constant: -viewPadding))
                        constraints.append(localView.centerYAnchor.constraint(equalTo: shareScreenContainer.centerYAnchor, constant: 0))
                        constraints.append(localView.widthAnchor.constraint(equalTo: buttonContainerView.buttonStackView.widthAnchor, multiplier: 0.5))
                        constraints.append(localView.heightAnchor.constraint(equalTo: localView.widthAnchor, constant: 0))

                        //share screen
                        constraints.append(shareScreenContainer.leadingAnchor.constraint(equalTo: localView.trailingAnchor, constant: viewPadding))
                        constraints.append(shareScreenContainer.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: 0))
                        constraints.append(shareScreenContainer.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 0))
                        constraints.append(shareScreenContainer.bottomAnchor.constraint(equalTo: buttonContainerView.topAnchor, constant: 0))
                    }
                }
                
            } else if remoteViews.count == 1 {
                let view1 = remoteViews[0]
                
                //1 Remote WITH Share screen
                if let shareScreenContainer = shareScreenContainerView {
                    if !isLandscape {
                        constraints.append(view1.leadingAnchor.constraint(equalTo: buttonContainerView.buttonStackView.leadingAnchor, constant: 0))
                        constraints.append(view1.widthAnchor.constraint(equalTo: view1.heightAnchor, multiplier: 1))
                        constraints.append(view1.bottomAnchor.constraint(equalTo: buttonContainerView.topAnchor, constant: -15))
                        
                        constraints.append(localView.trailingAnchor.constraint(equalTo: buttonContainerView.buttonStackView.trailingAnchor, constant: 0))
                        constraints.append(localView.widthAnchor.constraint(equalTo: localView.heightAnchor, multiplier: 1))
                        constraints.append(localView.bottomAnchor.constraint(equalTo: buttonContainerView.topAnchor, constant: -15))
                        constraints.append(localView.topAnchor.constraint(equalTo: shareScreenContainer.bottomAnchor, constant: 15))
                        
                        //relationship
                        constraints.append(view1.widthAnchor.constraint(equalTo: localView.widthAnchor, constant: 0))
                        constraints.append(view1.trailingAnchor.constraint(equalTo: localView.leadingAnchor, constant: -viewPadding))
                        
                        //share screen
                        constraints.append(shareScreenContainer.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 0))
                        constraints.append(shareScreenContainer.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: 0))
                        constraints.append(shareScreenContainer.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 0))
                    } else {
                        constraints.append(view1.leadingAnchor.constraint(equalTo: safeLeadingConstraint, constant: viewPadding))
                        constraints.append(view1.trailingAnchor.constraint(equalTo: shareScreenContainer.leadingAnchor, constant: -viewPadding))
                        constraints.append(view1.widthAnchor.constraint(equalToConstant: viewSize))
                        constraints.append(view1.centerYAnchor.constraint(equalTo: shareScreenContainer.centerYAnchor, constant: -(viewSize / 2) - viewPadding))
                        constraints.append(view1.heightAnchor.constraint(equalTo: view1.widthAnchor, multiplier: 1))
                        
                        constraints.append(localView.leadingAnchor.constraint(equalTo: safeLeadingConstraint, constant: viewPadding))
                        constraints.append(localView.trailingAnchor.constraint(equalTo: shareScreenContainer.leadingAnchor, constant: -viewPadding))
                        constraints.append(localView.centerYAnchor.constraint(equalTo: shareScreenContainer.centerYAnchor, constant: viewSize / 2))
                        
                        //relationship
                        constraints.append(view1.widthAnchor.constraint(equalTo: localView.widthAnchor, constant: 0))
                        constraints.append(view1.heightAnchor.constraint(equalTo: localView.heightAnchor, constant: 0))
                        
                        //share screen
                        constraints.append(shareScreenContainer.leadingAnchor.constraint(equalTo: view1.trailingAnchor, constant: viewPadding))
                        constraints.append(shareScreenContainer.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: 0))
                        constraints.append(shareScreenContainer.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 0))
                        constraints.append(shareScreenContainer.bottomAnchor.constraint(equalTo: buttonContainerView.topAnchor, constant: 0))
                    }
                    
                } else { //1 Remote WITHOUT Share screen
                
                    if !isLandscape {
                        constraints.append(view1.centerXAnchor.constraint(equalTo: view.centerXAnchor))
                        constraints.append(view1.centerYAnchor.constraint(equalTo: view.centerYAnchor))
                        constraints.append(view1.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 0))
                        constraints.append(view1.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: 0))
                        constraints.append(view1.heightAnchor.constraint(equalToConstant: 200))
                    } else {
                        constraints.append(view1.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 0))
                        constraints.append(view1.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: 0))
                        constraints.append(view1.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 0))
                        constraints.append(view1.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: 0))
                    }
                }
            } else if remoteViews.count == 2 {
                let view1 = remoteViews[0]
                let view2 = remoteViews[1]
                
                //2 Remote WITH share screen
                if let shareScreenContainer = shareScreenContainerView {
                    if !isLandscape {
                        
                        constraints.append(view2.centerXAnchor.constraint(equalTo: buttonContainerView.buttonStackView.centerXAnchor))
                        constraints.append(view2.bottomAnchor.constraint(equalTo: buttonContainerView.topAnchor, constant: -15))
                        constraints.append(view2.heightAnchor.constraint(equalToConstant: viewSize))
                        constraints.append(view2.widthAnchor.constraint(equalTo: view2.heightAnchor, multiplier: 1))
                        
                        constraints.append(view1.trailingAnchor.constraint(equalTo: view2.leadingAnchor, constant: -viewPadding))
                        constraints.append(view1.widthAnchor.constraint(equalTo: view2.widthAnchor, constant: 0))
                        constraints.append(view1.heightAnchor.constraint(equalTo: view2.heightAnchor, constant: 0))
                        constraints.append(view1.bottomAnchor.constraint(equalTo: buttonContainerView.topAnchor, constant: -15))
                        
                        constraints.append(localView.leadingAnchor.constraint(equalTo: view2.trailingAnchor, constant: viewPadding))
                        constraints.append(localView.widthAnchor.constraint(equalTo: view2.widthAnchor, constant: 0))
                        constraints.append(localView.heightAnchor.constraint(equalTo: view2.heightAnchor, constant: 0))
                        constraints.append(localView.bottomAnchor.constraint(equalTo: buttonContainerView.topAnchor, constant: -15))
                        constraints.append(localView.topAnchor.constraint(equalTo: shareScreenContainer.bottomAnchor, constant: 15))
                        
                        //relationship
                        constraints.append(view2.widthAnchor.constraint(equalTo: view1.widthAnchor, constant: 0))
                        constraints.append(view2.widthAnchor.constraint(equalTo: localView.widthAnchor, constant: 0))
                        
                        //share screen
                        constraints.append(shareScreenContainer.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 0))
                        constraints.append(shareScreenContainer.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: 0))
                        constraints.append(shareScreenContainer.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 0))
                    } else {
                        constraints.append(view1.leadingAnchor.constraint(equalTo: safeLeadingConstraint, constant: viewPadding))
                        constraints.append(view1.trailingAnchor.constraint(equalTo: shareScreenContainer.leadingAnchor, constant: -viewPadding))
                        constraints.append(view1.widthAnchor.constraint(equalToConstant: viewSize))
                        constraints.append(view1.bottomAnchor.constraint(equalTo: view2.topAnchor, constant: -viewPadding))
                        constraints.append(view1.heightAnchor.constraint(equalTo: shareScreenContainer.heightAnchor, multiplier: 0.25))
                        
                        constraints.append(view2.leadingAnchor.constraint(equalTo: safeLeadingConstraint, constant: viewPadding))
                        constraints.append(view2.trailingAnchor.constraint(equalTo: shareScreenContainer.leadingAnchor, constant: -viewPadding))
                        constraints.append(view2.widthAnchor.constraint(equalToConstant: viewSize))
                        constraints.append(view2.centerYAnchor.constraint(equalTo: shareScreenContainer.centerYAnchor, constant: 0))
                        constraints.append(view2.heightAnchor.constraint(equalTo: shareScreenContainer.heightAnchor, multiplier: 0.25))
                        
                        constraints.append(localView.leadingAnchor.constraint(equalTo: safeLeadingConstraint, constant: viewPadding))
                        constraints.append(localView.trailingAnchor.constraint(equalTo: shareScreenContainer.leadingAnchor, constant: -viewPadding))
                        constraints.append(localView.topAnchor.constraint(equalTo: view2.bottomAnchor, constant: viewPadding))
                        
                        //relationship
                        constraints.append(view1.widthAnchor.constraint(equalTo: localView.widthAnchor, constant: 0))
                        constraints.append(view1.heightAnchor.constraint(equalTo: localView.heightAnchor, constant: 0))
                        
                        //share screen
                        constraints.append(shareScreenContainer.leadingAnchor.constraint(equalTo: view1.trailingAnchor, constant: viewPadding))
                        constraints.append(shareScreenContainer.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: 0))
                        constraints.append(shareScreenContainer.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 0))
                        constraints.append(shareScreenContainer.bottomAnchor.constraint(equalTo: buttonContainerView.topAnchor, constant: 0))
                    }
                } else {
                
                    if !isLandscape {
                        constraints.append(view1.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 0))
                        constraints.append(view1.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: 0))
                        constraints.append(view1.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 0))
                        
                        constraints.append(view2.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 0))
                        constraints.append(view2.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: 0))
                        constraints.append(view2.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: 0))
                        
                        constraints.append(view1.bottomAnchor.constraint(equalTo: view2.topAnchor, constant: -viewPadding))
                        constraints.append(view1.heightAnchor.constraint(equalTo: view2.heightAnchor, constant: 0))
                    } else {
                        constraints.append(view1.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 0))
                        constraints.append(view1.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 0))
                        constraints.append(view1.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: 0))
                        
                        constraints.append(view2.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 0))
                        constraints.append(view2.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: 0))
                        constraints.append(view2.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: 0))
                        
                        constraints.append(view1.widthAnchor.constraint(equalTo: view2.widthAnchor, constant: 0))
                        constraints.append(view1.trailingAnchor.constraint(equalTo: view2.leadingAnchor, constant: -viewPadding))
                    }
                }

            } else if remoteViews.count >= maximumRemoteStreamsRendered {
                let view1 = remoteViews[0]
                let view2 = remoteViews[1]
                let view3 = remoteViews[2]
                
                //3 Remote WITH share screen
                if let shareScreenContainer = shareScreenContainerView {
                    if !isLandscape {
                        constraints.append(view1.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: viewPadding))
                        constraints.append(view1.trailingAnchor.constraint(equalTo: view2.leadingAnchor, constant: -viewPadding))
                        constraints.append(view1.bottomAnchor.constraint(equalTo: buttonContainerView.topAnchor, constant: -15))
                        constraints.append(view1.heightAnchor.constraint(equalToConstant: viewSize))
                        
                        constraints.append(view2.leadingAnchor.constraint(equalTo: view1.trailingAnchor, constant: viewPadding))
                        constraints.append(view2.trailingAnchor.constraint(equalTo: view3.leadingAnchor, constant: -viewPadding))
                        constraints.append(view2.bottomAnchor.constraint(equalTo: buttonContainerView.topAnchor, constant: -15))
                        constraints.append(view2.heightAnchor.constraint(equalTo: view1.heightAnchor, constant: 0))
                        
                        constraints.append(view3.leadingAnchor.constraint(equalTo: view2.trailingAnchor, constant: viewPadding))
                        constraints.append(view3.trailingAnchor.constraint(equalTo: localView.leadingAnchor, constant: -viewPadding))
                        constraints.append(view3.bottomAnchor.constraint(equalTo: buttonContainerView.topAnchor, constant: -15))
                        constraints.append(view3.heightAnchor.constraint(equalTo: view1.heightAnchor, constant: 0))
                        
                        constraints.append(localView.leadingAnchor.constraint(equalTo: view3.trailingAnchor, constant: viewPadding))
                        constraints.append(localView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -viewPadding))
                        constraints.append(localView.bottomAnchor.constraint(equalTo: buttonContainerView.topAnchor, constant: -15))
                        constraints.append(localView.heightAnchor.constraint(equalTo: view1.heightAnchor, constant: 0))
                        
                        //relationship
                        constraints.append(view1.widthAnchor.constraint(equalTo: view2.widthAnchor, constant: 0))
                        constraints.append(view2.widthAnchor.constraint(equalTo: view3.widthAnchor, constant: 0))
                        constraints.append(view3.widthAnchor.constraint(equalTo: localView.widthAnchor, constant: 0))
                        
                        //share screen
                        constraints.append(shareScreenContainer.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 0))
                        constraints.append(shareScreenContainer.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: 0))
                        constraints.append(shareScreenContainer.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 0))
                        constraints.append(localView.topAnchor.constraint(equalTo: shareScreenContainer.bottomAnchor, constant: 15))
                    } else {
                        constraints.append(view1.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: viewPadding))
                        constraints.append(view1.leadingAnchor.constraint(equalTo: safeLeadingConstraint, constant: viewPadding))
                        constraints.append(view1.trailingAnchor.constraint(equalTo: shareScreenContainer.leadingAnchor, constant: -viewPadding))
                        constraints.append(view1.widthAnchor.constraint(equalToConstant: viewSize))
                        constraints.append(view1.bottomAnchor.constraint(equalTo: view2.topAnchor, constant: -viewPadding))
                        constraints.append(view1.heightAnchor.constraint(equalTo: shareScreenContainer.heightAnchor, multiplier: 0.25))
                        
                        constraints.append(view2.leadingAnchor.constraint(equalTo: safeLeadingConstraint, constant: viewPadding))
                        constraints.append(view2.trailingAnchor.constraint(equalTo: shareScreenContainer.leadingAnchor, constant: -viewPadding))
                        constraints.append(view2.widthAnchor.constraint(equalToConstant: viewSize))
                        constraints.append(view2.bottomAnchor.constraint(equalTo: view3.topAnchor, constant: -viewPadding))
                        constraints.append(view2.heightAnchor.constraint(equalTo: shareScreenContainer.heightAnchor, multiplier: 0.25))
                        
                        constraints.append(view3.leadingAnchor.constraint(equalTo: safeLeadingConstraint, constant: viewPadding))
                        constraints.append(view3.trailingAnchor.constraint(equalTo: shareScreenContainer.leadingAnchor, constant: -viewPadding))
                        constraints.append(view3.widthAnchor.constraint(equalToConstant: viewSize))
                        constraints.append(view3.bottomAnchor.constraint(equalTo: localView.topAnchor, constant: -viewPadding))
                        constraints.append(view3.heightAnchor.constraint(equalTo: shareScreenContainer.heightAnchor, multiplier: 0.25))
                        
                        constraints.append(localView.leadingAnchor.constraint(equalTo: safeLeadingConstraint, constant: viewPadding))
                        constraints.append(localView.trailingAnchor.constraint(equalTo: shareScreenContainer.leadingAnchor, constant: -viewPadding))
                        constraints.append(localView.topAnchor.constraint(equalTo: view3.bottomAnchor, constant: viewPadding))
                        
                        //relationship
                        constraints.append(view1.widthAnchor.constraint(equalTo: localView.widthAnchor, constant: 0))
                        constraints.append(view1.heightAnchor.constraint(equalTo: localView.heightAnchor, constant: 0))
                        
                        //share screen
                        constraints.append(shareScreenContainer.leadingAnchor.constraint(equalTo: view1.trailingAnchor, constant: viewPadding))
                        constraints.append(shareScreenContainer.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: 0))
                        constraints.append(shareScreenContainer.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 0))
                        constraints.append(shareScreenContainer.bottomAnchor.constraint(equalTo: buttonContainerView.topAnchor, constant: 0))
                    }
                } else {
                
                    //Same for landscape & portrait
                    constraints.append(view1.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 0))
                    constraints.append(view1.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 0))
                    
                    constraints.append(view2.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: 0))
                    constraints.append(view2.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 0))
                    
                    constraints.append(view3.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 0))
                    constraints.append(view3.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: 0))
                    
                    constraints.append(localView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: 0))
                    constraints.append(localView.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: 0))
                    
                    //relationship
                    constraints.append(view1.trailingAnchor.constraint(equalTo: view2.leadingAnchor, constant: -viewPadding))
                    constraints.append(view3.trailingAnchor.constraint(equalTo: localView.leadingAnchor, constant: -viewPadding))
                    constraints.append(view1.bottomAnchor.constraint(equalTo: view3.topAnchor, constant: -viewPadding))
                    constraints.append(view2.bottomAnchor.constraint(equalTo: localView.topAnchor, constant: -viewPadding))
                 
                    constraints.append(view1.widthAnchor.constraint(equalTo: view2.widthAnchor, constant: 0))
                    constraints.append(view3.widthAnchor.constraint(equalTo: localView.widthAnchor, constant: 0))
                    constraints.append(view1.heightAnchor.constraint(equalTo: view2.heightAnchor, constant: 0))
                    constraints.append(view3.heightAnchor.constraint(equalTo: localView.heightAnchor, constant: 0))
                    constraints.append(view1.heightAnchor.constraint(equalTo: view3.heightAnchor, constant: 0))
                    constraints.append(view2.heightAnchor.constraint(equalTo: localView.heightAnchor, constant: 0))
                }
            } else {
                //nothing to do here
            }
        }
        
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 9, options: .curveEaseInOut, animations: {
            //Clear existing constraints
            if !self.existingConstraints.isEmpty {
                NSLayoutConstraint.deactivate(self.existingConstraints)
            }
            
            NSLayoutConstraint.activate(constraints)
            self.existingConstraints = constraints
            
            self.view.layoutIfNeeded()
        })
    }
}

// MARK: -
// MARK: ConferenceButtonBarDelegate
// MARK: -
extension AuviousConferenceVCNew: ConferenceButtonBarDelegate {
    @objc internal func hangupButtonPressed(_ sender: Any) {
        selectionFeedbackGenerator.impactOccurred()
        
        AuviousConferenceSDK.sharedInstance.leaveConference(conferenceId: currentConference.id, onSuccess: {
            os_log("Left conference", log: Log.conferenceUI, type: .debug)
            self.delegate?.onConferenceSuccess()

        }, onFailure: {(error) in
            self.handleError(error)
        })
    }
    
    @objc internal func camSwitchButtonPressed(_ sender: Any) {
        selectionFeedbackGenerator.impactOccurred()
        AuviousConferenceSDK.sharedInstance.switchCamera()
    }
    
    @objc internal func cameraButtonPressed(_ sender: Any) {
        guard let localStreamId = localStreamId else {
            return
        }
        
        selectionFeedbackGenerator.impactOccurred()
        
        let button = sender as! ConferenceButton
        
        // open camera
        if button.type == .camDisabled {
            button.type = .camEnabled
            localView.videoStreamAdded()
            // re-enable switch cam
            buttonContainerView.cameraSwitchButton.type = .camSwitch
            
            if localStreamType == .mic {
                // mic is open, we need to unpublish the stream and publish a micAndCam
                // todo: we should replace 'all local streams' if we want to support screen share
                AuviousConferenceSDK.sharedInstance.unpublishAllLocalStreams()
                configuredStreamType = .micAndCam
                startLocalStream()
                
            } else {
                AuviousConferenceSDK.sharedInstance.toggleLocalStream(conferenceId: currentConference.id, streamId: localStreamId, operation: .remove, type: .video, onSuccess: {
                    
                    AuviousNotification.shared.show(.cameraOn)
                    
                }, onFailure: { error in
                })
            }
            
        } else {
            // close camera
            button.type = .camDisabled
            localView.videoStreamRemoved()
            buttonContainerView.cameraSwitchButton.type = .camSwitchDisabled
            
            AuviousConferenceSDK.sharedInstance.toggleLocalStream(conferenceId: currentConference.id, streamId: localStreamId, operation: .set, type: .video, onSuccess: {
                AuviousNotification.shared.show(.cameraOff)
            }, onFailure: { error in
            })
        }
    }
    
    @objc internal func micButtonPressed(_ sender: Any) {
        guard let localStreamId = localStreamId else {
            return
        }
        
        selectionFeedbackGenerator.impactOccurred()
        
        let button = sender as! ConferenceButton
        
        // open microphone
        if button.type == .micDisabled {
            button.type = .micEnabled
            localView.audioStreamAdded()
            
            if localStreamType == .cam {
                // cam is open, we need to unpublish and publish a micAndCam stream
                AuviousConferenceSDK.sharedInstance.unpublishAllLocalStreams()
                configuredStreamType = .micAndCam
                startLocalStream()
                
            } else {
                AuviousConferenceSDK.sharedInstance.toggleLocalStream(conferenceId: currentConference.id, streamId: localStreamId, operation: .remove, type: .audio, onSuccess: {
                    AuviousNotification.shared.show(.microphoneOn)
                    
                }, onFailure: { error in
                })
            }
            
        } else {
            // close microphone
            button.type = .micDisabled
            localView.audioStreamRemoved()
            
            AuviousConferenceSDK.sharedInstance.toggleLocalStream(conferenceId: currentConference.id, streamId: localStreamId, operation: .set, type: .audio, onSuccess: {
                AuviousNotification.shared.show(.microphoneOff)
                
            }, onFailure: { error in
            })
        }
    }
}
