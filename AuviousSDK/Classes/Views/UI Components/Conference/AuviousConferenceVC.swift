//
//  AuviousConferenceVC.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 23/6/20.
//

import UIKit
import os

//Interface for communicating back to the host app
public protocol AuviousSimpleConferenceDelegate: class {
    
    func onConferenceError(_ error: AuviousSDKGenericError)
    func onConferenceSuccess()
}

public class AuviousConferenceVC: UIViewController, AuviousSDKConferenceDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    //UI properties
    @IBOutlet weak var localStreamView: StreamView!
    @IBOutlet weak var collectionView: UICollectionView!
    let collectionViewLayout: UICollectionViewFlowLayout = UICollectionViewFlowLayout()
    
    //Conference properties
    private var clientId: String = ""
    private var username: String = ""
    private var password: String = ""
    private var conference: String = ""
    private var baseEndpoint: String = ""
    private var mqttEndpoint: String = ""

    //Control flags
    private var performedInitialValidations: Bool = false
    private var conferenceJoined: Bool = false
    
    //Delegate
    private weak var delegate: AuviousSimpleConferenceDelegate?
    
    //The conference we're in
    var currentConference: ConferenceSimpleView!
    //Current conference participants
    var conferenceParticipants: Int = 0 {
        didSet {
            setScreenTitle()
        }
    }
    
    //Collection view data source
    var remoteParticipants: [ParticipantEndpoint] = [ParticipantEndpoint]()
    
    //Public constructor
    public init(clientId: String, username: String, password: String, conference: String, baseEndpoint: String, mqttEndpoint: String, delegate: AuviousSimpleConferenceDelegate, callMode: AuviousCallMode) {
        self.clientId = clientId
        self.username = username
        self.password = password
        self.conference = conference
        self.baseEndpoint = baseEndpoint
        self.mqttEndpoint = mqttEndpoint
        self.delegate = delegate
        
        super.init(nibName: nil, bundle: Bundle(for: AuviousConferenceVC.self))
        
        os_log("UI Conference component: initialised")
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override open func viewDidLoad() {
        super.viewDidLoad()

        setupUI()
    }
    
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if !performedInitialValidations {
            //Check for permissions
            if !validateVideoPermissions() {
                os_log("UI Conference component: viewDidAppear - no video permission, returning error")
                handleError(AuviousSDKError.videoPermissionIsDisabled)
                return
            }
            
            if !validateMicPermissions() {
                os_log("UI Conference component: viewDidAppear - no audio permission, returning error")
                handleError(AuviousSDKError.audioPermissionIsDisabled)
                return
            }
            
            //Check credentials
            if username.isEmpty || password.isEmpty {
                os_log("UI Conference component: viewDidAppear - username/password empty, returning error")
                handleError(AuviousSDKError.missingSDKCredentials)
                return
            }
            
            //Check call target
            if conference.isEmpty {
                os_log("UI Conference component: viewDidAppear - conference is empty, returning error")
                handleError(AuviousSDKError.missingCallTarget)
                return
            }
            
            performedInitialValidations = true
        }
        
        if performedInitialValidations && !conferenceJoined {
            AuviousConferenceSDK.sharedInstance.delegate = self
            AuviousConferenceSDK.sharedInstance.configure(params: [:], username: username, password: password, clientId: clientId, baseEndpoint: baseEndpoint, mqttEndpoint: mqttEndpoint)
            os_log("UI Conference component: Configured ConferenceSDK")
//
//            //Get access to the local video stream immediately
//            let localStream = AuviousCallSDK.sharedInstance.createLocalMediaStream(type: .micAndCam, streamId: "test")
//            log("UI Call component: Created local media stream")
//
            
            AuviousConferenceSDK.sharedInstance.login(onLoginSuccess: {(userId, conferenceId) in
                os_log("UI Conference component: Login success")
                
                self.conference = conferenceId!
                AuviousConferenceSDK.sharedInstance.joinConference(conferenceId: self.conference, onSuccess: {(joinedConference) in
                    
                    if let jConference = joinedConference {
                        //os_log("Joined conference with id \(String(describing: jConference.id))")
                        self.currentConference = jConference
                        self.conferenceJoined = true
                        
                        //Start connecting to any existing streams in our conference
                        self.handleExistingConferenceStreams()
                        self.startLocalStream()
                    } else {
                        os_log("WARNING: Unable to join conference")
                    }
                }, onFailure: {(error) in
                    self.handleError(error)
                })
                
            }, onLoginFailure: {(error) in
                self.handleError(error)
            })
        }
    }

    //MARK: UI
    
    internal func setupUI() {
        setupCollectionView()
    }
    
    internal func setupCollectionView() {
        //Collection view layout
        collectionViewLayout.sectionInset = UIEdgeInsets.init(top: 0, left: 0, bottom: 0, right: 0)
        collectionViewLayout.minimumInteritemSpacing = 0.0
        collectionViewLayout.minimumLineSpacing = 0.0
        
        //Collection view
        collectionView.collectionViewLayout = collectionViewLayout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isScrollEnabled = false
        collectionView.register(UINib(nibName: String(describing: ConferenceCell.self), bundle: Bundle(for: ConferenceCell.self)), forCellWithReuseIdentifier: ConferenceCell.identifier)
        
    }
    
    //MARK: AuviousSDKConferenceDelegate
    
    public func auviousSDK(conferenceOnHold flag: Bool) {
        
    }
    
    public func auviousSDK(didReceiveLocalStream stream: RTCMediaStream, streamId: String, type: StreamType) {
    
    }
    
    public func auviousSDK(didReceiveConferenceEvent event: ConferenceEvent) {
        if event is ConferenceJoinedEvent {
            conferenceParticipants += 1
        }
        else if event is ConferenceLeftEvent {
            conferenceParticipants -= 1
        }
        else if event is ConferenceEndedEvent {
            handleConferenceEndedEvent()
        }
        else if event is ConferenceStreamPublishedEvent {
            let object = event as! ConferenceStreamPublishedEvent
            do {
                try AuviousConferenceSDK.sharedInstance.startRemoteStreamFlow(streamId: object.streamId, endpointId: object.userEndpointId, streamType: object.streamType, remoteUserId: object.userId)
            } catch let error {
                //os_log("Error \(error) - \(error.localizedDescription)")
                handleError(error)
            }
        }
        else if event is ConferenceStreamUnpublishedEvent {
            let object = event as! ConferenceStreamUnpublishedEvent
            
            do {
                try AuviousConferenceSDK.sharedInstance.stopRemoteStream(streamId: object.streamId, remoteUserId: object.userId, remoteEndpointId: object.userEndpointId, streamType: object.streamType)
            } catch let error {
                //os_log("Error \(error) - \(error.localizedDescription)")
                handleError(error)
            }
        }
    }
    
    public func auviousSDK(didReceiveRemoteStream stream: RTCMediaStream, streamId: String, endpointId: String, type: StreamType) {
        DispatchQueue.main.async {
            if let indexPath = self.getIndexPathForStream(stream: stream, streamId: streamId, endpointId: endpointId),
                let cell = self.collectionView.cellForItem(at: indexPath) as? ConferenceCell {
                
                //Add the video stream to our cell
                if stream.videoTracks.count > 0 {
                    let remoteVideoTrack: RTCVideoTrack = stream.videoTracks.first!
                    
                    if stream.audioTracks.count > 0 {
                        cell.streamView.avStreamAdded(remoteVideoTrack)
                    } else {
                        cell.streamView.videoStreamAdded(remoteVideoTrack)
                    }
                    
                } else if stream.audioTracks.count > 0 {
                    cell.streamView.audioStreamAdded()
                }
            }
        }
    }
    
    public func auviousSDK(didRejoinConference conference: ConferenceSimpleView) {
        //Clear the streams from the UI
        remoteParticipants.removeAll()
        collectionView.reloadData()
        
        currentConference = conference
        conferenceParticipants = currentConference.participants.count
        
        //Reconnect to conference streams
        handleExistingConferenceStreams()
    }
    
    public func auviousSDK(didChangeState newState: StreamEventState, streamId: String, streamType: StreamType, endpointId: String) {
        switch newState {
        case .localStreamIsConnecting:
            os_log("Local Stream Is Connecting")
        case .localStreamConnected:
            os_log("Local Stream Connected")
            didPublishStream(streamId: streamId, streamType: streamType)
        case .remoteStreamIsConnecting:
            os_log("Remote Stream Is Connecting")
        case .remoteStreamConnected:
            os_log("Remote Stream Connected")
        case .localStreamIsDisconnecting:
            os_log("Local Stream Is Disonnecting")
        case .localStreamDisconnected:
            os_log("Local Stream Disconnected")
            didUnpublishStream(streamId: streamId, streamType: streamType)
        case .remoteStreamIsDisconnecting:
            os_log("Remote Stream Is Disonnecting")
        case .remoteStreamDisconnected:
            os_log("Remote Stream Disconnected")
            handleStreamDisconnection(streamId: streamId, streamType:streamType, endpointId: endpointId)
        case .localCaptureStarted:
            os_log("Local Capture Started")
        case .localCaptureStoped:
            os_log("Local Capture Stoped")
        }
    }
    
    public func auviousSDK(didReceiveLocalVideoTrack localVideoTrack: RTCVideoTrack!) {
        localStreamView.videoStreamAdded(localVideoTrack)
    }
    
    public func auviousSDK(trackMuted type: StreamType, endpointId: String) {
        
    }
    
    public func auviousSDK(trackUnmuted type: StreamType, endpointId: String) {
        
    }
    
    //MARK: Collection view
    
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ConferenceCell.identifier, for: indexPath) as! ConferenceCell
        cell.contentView.backgroundColor = UIColor.random
        
        cell.streamView.videoView.setSize(CGSize(width: cell.contentView.bounds.width, height: cell.contentView.bounds.height))
        
        return cell
    }
    
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return remoteParticipants.count
    }
    
    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
    
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        
        if remoteParticipants.count < 4 {
            return CGSize(width: self.collectionView.bounds.width, height: self.collectionView.bounds.height / (CGFloat(remoteParticipants.count)))
        } else if remoteParticipants.count == 4 {
            return CGSize(width: self.collectionView.bounds.width / 2, height: self.collectionView.bounds.height / 2)
        } else if remoteParticipants.count < 7 {
            return CGSize(width: self.collectionView.bounds.width / 2, height: self.collectionView.bounds.height / 3)
        } else if remoteParticipants.count < 10 {
            return CGSize(width: self.collectionView.bounds.width / 3, height: self.collectionView.bounds.height / 3)
        } else if remoteParticipants.count < 17 {
            return CGSize(width: self.collectionView.bounds.width / 4, height: self.collectionView.bounds.height / 4)
        }
        
        return CGSize(width: self.collectionView.bounds.width / 5, height: self.collectionView.bounds.height / 5)
    }
    
    //Animates the layout/cell change cause by stream addition/removal
    private func animateCollectionViewCellChange(){
        collectionView.collectionViewLayout.invalidateLayout()
        
        UIView.animate(
            withDuration: 0.4,
            delay: 0.0,
            usingSpringWithDamping: 1.0,
            initialSpringVelocity: 0.0,
            options: UIView.AnimationOptions(),
            animations: {
                self.collectionView.layoutIfNeeded()
        },
            completion: { finished in
                self.collectionView.reloadSections(IndexSet(integer: 0))
        }
        )
    }
    
    //MARK: Helpers
    
    //tmp until we have the UI with buttons etc
    private func startLocalStream() {
        do {
            let _ = try AuviousConferenceSDK.sharedInstance.startPublishLocalStreamFlow(type: .micAndCam)
        } catch let error {
            //os_log("Error \(error) - \(error.localizedDescription)")
            handleError(error)
        }
    }
    
    private func handleConferenceEndedEvent(){
        delegate?.onConferenceSuccess()
    }
    
    //Initialises the RTC view stream flow for existing conference streams
    private func handleExistingConferenceStreams(){
        if !currentConference.participants.isEmpty {
            for user in currentConference.participants {
                for endpointStream in user.endpoints {
                    for stream in endpointStream.streams {
                        do {
                            try AuviousConferenceSDK.sharedInstance.startRemoteStreamFlow(streamId: stream.id, endpointId: endpointStream.id, streamType: stream.type, remoteUserId: user.id)
                        } catch let error {
                            //os_log("Error \(error) - \(error.localizedDescription)")
                            handleError(error)
                        }
                    }
                }
            }
        }
    }
    
    func didPublishStream(streamId: String, streamType: StreamType) {
        
        //Update UI accordingly
//        if streamType == .cam {
//            shareCamBtn.isUserInteractionEnabled = true
//            shareCamBtn.isSelected = true
//            switchCamBtn.isEnabled = true
//        } else if streamType == .mic {
//            shareMicBtn.isUserInteractionEnabled = true
//            shareMicBtn.isSelected = true
//            switchCamBtn.isEnabled = false
//
//            localStreamView.audioStreamAdded()
//        } else if streamType == .micAndCam {
//            shareVideoBtn.isUserInteractionEnabled = true
//            shareVideoBtn.isSelected = true
//            switchCamBtn.isEnabled = true
//        }
//
//        animateLabelsAndButtons(streamType: streamType, stateOn: true)
    }
    
    func didUnpublishStream(streamId: String, streamType: StreamType) {
        
        //Update UI accordingly
//        if streamType == .cam {
//            shareCamBtn.isUserInteractionEnabled = true
//            shareCamBtn.isSelected = false
//            switchCamBtn.isEnabled = false
//
//            localStreamView.videoStreamRemoved()
//        } else if streamType == .mic {
//            shareMicBtn.isUserInteractionEnabled = true
//            shareMicBtn.isSelected = false
//
//            localStreamView.audioStreamRemoved()
//        } else if streamType == .micAndCam {
//            shareVideoBtn.isUserInteractionEnabled = true
//            shareVideoBtn.isSelected = false
//            switchCamBtn.isEnabled = false
//
//            localStreamView.avStreamRemoved()
//        }
//
//        animateLabelsAndButtons(streamType: streamType, stateOn: false)
    }
    
    //Triggers cell refresh/removal according to the remote participant's stream state
    private func handleStreamDisconnection(streamId: String, streamType: StreamType, endpointId:String){
        var remoteParticipantIndex:Int?
        for (index,item) in remoteParticipants.enumerated() {
            if item.id == endpointId {
                remoteParticipantIndex = index
                break
            }
        }
        
        if let index = remoteParticipantIndex {
            let participant = remoteParticipants[index]
            let indexPath = IndexPath(row: index, section: 0)
            
            //We only had 1 stream from this participant, therefore we should remove the cell from the collection view
            if participant.streams.count == 1 {
                remoteParticipants.remove(at: index)
                
                if let cell = self.collectionView.cellForItem(at: indexPath) as? ConferenceCell {
                    if streamType == .mic {
                        cell.streamView.audioStreamRemoved()
                    } else if streamType == .cam {
                        cell.streamView.videoStreamRemoved()
                    } else if streamType == .micAndCam {
                        cell.streamView.avStreamRemoved()
                    }
                }
                
                collectionView.deleteItems(at: [indexPath])
                
            } else if participant.streams.count > 1 {
                
                if let cell = self.collectionView.cellForItem(at: indexPath) as? ConferenceCell {
                    
                    //Remove the video if needed
                    if streamType == .cam {
                        cell.streamView.videoStreamRemoved()
                    } else if streamType == .mic {
                        cell.streamView.audioStreamRemoved()
                    } else if streamType == .micAndCam {
                        cell.streamView.avStreamRemoved()
                    }
                }
            }
        }
    }
    
    //Returns the collection view index path of the cell that will handle this stream
    private func getIndexPathForStream(stream: RTCMediaStream, streamId: String, endpointId: String) -> IndexPath? {
        var streamType: StreamType!
        if stream.audioTracks.count > 0 && stream.videoTracks.count > 0 {
            streamType = StreamType.micAndCam
        } else if stream.audioTracks.count == 0 && stream.videoTracks.count > 0 {
            streamType = StreamType.cam
        } else if stream.audioTracks.count > 0 && stream.videoTracks.count == 0 {
            streamType = StreamType.mic
        }
        
        var remoteParticipantIndex:Int?
        for (index,item) in remoteParticipants.enumerated() {
            if item.id == endpointId {
                remoteParticipantIndex = index
                break
            }
        }
        
        //Collection view cell is already created
        if let index = remoteParticipantIndex {
            
            //Add new stream to this user's endpoint
            let participantEndpoint = remoteParticipants[index]
            let participantStream = ParticipantEndpointStream(id: streamId, type: streamType)
            participantEndpoint.streams.append(participantStream)
            
            let indexPath = IndexPath(row: index, section: 0)
            return indexPath
        } else {
            
            //Create a new remote participant with the incoming stream
            let participantEndpoint = ParticipantEndpoint(endpointId: endpointId)
            let participantStream = ParticipantEndpointStream(id: streamId, type: streamType)
            participantEndpoint.streams.append(participantStream)
            self.remoteParticipants.append(participantEndpoint)
            
            let indexPath = IndexPath(row: remoteParticipants.count - 1, section: 0)
            self.collectionView.insertItems(at: [indexPath])
            
            return indexPath
        }
    }
    
    //Sets the screen title, according to the number of conference participants
    private func setScreenTitle() {
        let membersString = conferenceParticipants == 1 ? "member" : "members"
        var screenTitle = currentConference.id + " ("
        screenTitle += String(conferenceParticipants) + " "
        screenTitle += membersString + ")"
        title =  screenTitle
    }
    
    //Check for video permissions
    func validateVideoPermissions() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }
    
    //Check for audio persmissions
    func validateMicPermissions() -> Bool {
        return AVAudioSession.sharedInstance().recordPermission == .granted
    }
    
    private func handleError(_ error: Error) {
        let auviousError = error as! AuviousSDKError
        
        //os_log("UI Conference component: handleError \(error.localizedDescription)")
        
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
}

extension UIColor {
    static var random: UIColor {
        return UIColor(red: .random(in: 0...1),
                       green: .random(in: 0...1),
                       blue: .random(in: 0...1),
                       alpha: 1.0)
    }
}
