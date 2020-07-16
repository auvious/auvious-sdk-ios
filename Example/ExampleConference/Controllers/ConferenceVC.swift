//
//  ConferenceVC.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 24/12/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import UIKit
import SVProgressHUD
import AuviousSDK

/*
 Collection view test cases covered:
 1) Incoming V stream added to list
 2) Incoming A stream added to list
 3) Incoming AV stream added to list
 4) Incoming V stream added to list. Then add an A stream and ensure CV cell reuse.
 5) Incoming A stream added to list. Then add a V stream and ensure CV cell reuse.
 6) Have an AV stream displayed. Then stop A and ensure V keeps playing.
 7) Have an AV stream displayed. Then stop V and ensure A keeps playing.
 8) Have an AV stream displayed. Remote user then leaves - ensure stream is removed from UI and state cleaned.
 9) Conference ends remotely. Inform UI, remove all streams & clean state.
 */

protocol ConferenceVCDelegate {
    func removeCreatedConferenceFromList(confId: String)
}

class ConferenceVC: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, AuviousSDKConferenceDelegate {
    @IBOutlet weak var shareMicBtn: StreamButton!
    @IBOutlet weak var shareCamBtn: StreamButton!
    @IBOutlet weak var shareVideoBtn: StreamButton!
    @IBOutlet weak var shareMicLb: UILabel!
    @IBOutlet weak var shareCamLb: UILabel!
    @IBOutlet weak var shareVideoLb: UILabel!
    
    @IBOutlet weak var endConfBtn: UIButton!
    @IBOutlet weak var leaveConfBtn: UIButton!
    @IBOutlet weak var switchCamBtn: UIButton!
    @IBOutlet weak var audioRootBtn: UIButton!
    
    @IBOutlet weak var upperButtonsView: UIView!
    @IBOutlet weak var footerButtonsView: UIView!
    @IBOutlet weak var upperButtonsViewYpos: NSLayoutConstraint!
    @IBOutlet weak var footerButtonsViewYpos: NSLayoutConstraint!
    
    @IBOutlet weak var localStreamView: StreamView!
    @IBOutlet weak var collectionView: UICollectionView!
    
    private var buttonsAreShown: Bool = false
    
    var delegate: ConferenceVCDelegate?
    
    //The conference we're in
    var currentConference:ConferenceSimpleView!
    var conferenceParticipants:Int = 0 {
        didSet {
            setScreenTitle()
        }
    }
    
    //Collection view data source
    var remoteParticipants:[ParticipantEndpoint] = [ParticipantEndpoint]()
    

    init(conference:ConferenceSimpleView){
        super.init(nibName: nil, bundle: nil)
        self.currentConference = conference
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        AuviousConferenceSDK.sharedInstance.publishVideoResolution = .min
        AuviousConferenceSDK.sharedInstance.delegate = self
        
        conferenceParticipants = currentConference.participants.count
        
        //Collection view layout
        let collectionViewLayout: UICollectionViewFlowLayout = UICollectionViewFlowLayout()
        collectionViewLayout.sectionInset = UIEdgeInsets.init(top: 0, left: 0, bottom: 0, right: 0)
        collectionViewLayout.minimumInteritemSpacing = 0.0
        collectionViewLayout.minimumLineSpacing = 0.0
        //Collection view
        collectionView.collectionViewLayout = collectionViewLayout
        collectionView.register(UINib(nibName: String(describing: ConferenceCell.self), bundle: nil), forCellWithReuseIdentifier: ConferenceCell.identifier)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isScrollEnabled = false
        
        //Start connecting to any existing streams in our conference
        handleExistingConferenceStreams()
        
        //Configure buttons
        shareMicBtn.btnConfType = .mic
        shareCamBtn.btnConfType = .cam
        shareVideoBtn.btnConfType = .micAndCam
        
        shareMicLb.text = "Share Mic"
        shareCamLb.text = "Share Cam"
        shareVideoLb.text = "Share Video"
        
        switchCamBtn.isEnabled = false
        
        footerButtonsViewYpos.constant = footerButtonsView.frame.height
        upperButtonsViewYpos.constant = -upperButtonsView.frame.height
        showButtons()
        
        self.navigationItem.setHidesBackButton(true, animated: false)
        
        let tapGesture: UITapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(ConferenceVC.showButtons))
        self.view.addGestureRecognizer(tapGesture)
    }
    
    @objc func showButtons(){
        if buttonsAreShown {
            buttonsAreShown = false
            footerButtonsViewYpos.constant = footerButtonsView.frame.height
            upperButtonsViewYpos.constant = -upperButtonsView.frame.height
            UIView.animate(withDuration: 0.3) {
                self.view.layoutIfNeeded()
            }
        }
        else {
            buttonsAreShown = true
            footerButtonsViewYpos.constant = 0
            upperButtonsViewYpos.constant = 0
            UIView.animate(withDuration: 0.3) {
                self.view.layoutIfNeeded()
            }
        }
    }
    
    //MARK: Helpers
    
    //Initialises the RTC view stream flow for existing conference streams
    private func handleExistingConferenceStreams(){
        if !currentConference.participants.isEmpty {
            for user in currentConference.participants {
                for endpointStream in user.endpoints {
                    for stream in endpointStream.streams {
                        do {
                            try AuviousConferenceSDK.sharedInstance.startRemoteStreamFlow(streamId: stream.id, endpointId: endpointStream.id, streamType: stream.type, remoteUserId: user.id)
                        } catch let error {
                            print("Error \(error) - \(error.localizedDescription)")
                            showAlert(title: "Error", msg: error.localizedDescription)
                        }
                    }
                }
            }
        }
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
        var streamType:StreamType!
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
    
    private func handleConferenceEndedEvent(){
        self.showAlert(title: "Warning", msg: "Conference has ended.", onSuccess: {
            self.navigationController?.popViewController(animated: true)
        })
    }
    
    func handleShareBtnState(sender: StreamButton){
        if !sender.isSelected {
            do {
                let streamId = try AuviousConferenceSDK.sharedInstance.startPublishLocalStreamFlow(type: sender.btnConfType)
                sender.streamId = streamId
                sender.isUserInteractionEnabled = false
            } catch let error {
                print("Error \(error) - \(error.localizedDescription)")
                showAlert(title: "Error", msg: error.localizedDescription)
            }
        }
        else {
            do {
                try AuviousConferenceSDK.sharedInstance.startUnpublishLocalStreamFlow(streamId: sender.streamId, streamType: sender.btnConfType)
                sender.isUserInteractionEnabled = false
            } catch let error {
                print("Error \(error) - \(error.localizedDescription)")
                showAlert(title: "Error", msg: error.localizedDescription)
            }
        }
    }
    
    func didPublishStream(streamId: String, streamType: StreamType) {
        
        //Update UI accordingly
        if streamType == .cam {
            shareCamBtn.isUserInteractionEnabled = true
            shareCamBtn.isSelected = true
            switchCamBtn.isEnabled = true
        } else if streamType == .mic {
            shareMicBtn.isUserInteractionEnabled = true
            shareMicBtn.isSelected = true
            switchCamBtn.isEnabled = false
            
            localStreamView.audioStreamAdded()
        } else if streamType == .micAndCam {
            shareVideoBtn.isUserInteractionEnabled = true
            shareVideoBtn.isSelected = true
            switchCamBtn.isEnabled = true
        }
        
        animateLabelsAndButtons(streamType: streamType, stateOn: true)
    }
    
    func didUnpublishStream(streamId: String, streamType: StreamType) {
        
        //Update UI accordingly
        if streamType == .cam {
            shareCamBtn.isUserInteractionEnabled = true
            shareCamBtn.isSelected = false
            switchCamBtn.isEnabled = false
            
            localStreamView.videoStreamRemoved()
        } else if streamType == .mic {
            shareMicBtn.isUserInteractionEnabled = true
            shareMicBtn.isSelected = false
            
            localStreamView.audioStreamRemoved()
        } else if streamType == .micAndCam {
            shareVideoBtn.isUserInteractionEnabled = true
            shareVideoBtn.isSelected = false
            switchCamBtn.isEnabled = false
            
            localStreamView.avStreamRemoved()
        }
        
        animateLabelsAndButtons(streamType: streamType, stateOn: false)
    }
    
    func animateLabelsAndButtons(streamType: StreamType, stateOn: Bool){
        
        var sender: StreamButton!
        var imageName: String = ""
        
        var label: UILabel!
        var labelText: String = ""
        
        if streamType == .cam {
            sender = shareCamBtn
            label = shareCamLb
            if stateOn {
                imageName = "cam_icon_act"
                labelText = "Stop Cam"
            }
            else{
                imageName = "cam_icon"
                labelText = "Share Cam"
            }
        } else if streamType == .mic {
            sender = shareMicBtn
            label = shareMicLb
            if stateOn {
                imageName = "mic_icon_act"
                labelText = "Stop Mic"
            }
            else{
                imageName = "mic_icon"
                labelText = "Share Mic"
            }
        } else if streamType == .micAndCam {
            sender = shareVideoBtn
            label = shareVideoLb
            if stateOn {
                imageName = "video_icon_act"
                labelText = "Stop Video"
            }
            else{
                imageName = "video_icon"
                labelText = "Share Video"
            }
        }
        
        UIView.transition(with: sender, duration: 0.5, options: .transitionCrossDissolve, animations: {
            //sender.setImage(UIImage(named: imageName), for: .normal)
            //sender.setImage(UIImage(named: imageName), for: .selected)
            label.text = labelText
        }, completion: nil)
    }
    
    //MARK: Actions
    @IBAction func shareMicButtonPressed(_ sender: Any) {
        guard let _ = AuviousConferenceSDK.sharedInstance.userEndpointId else {
            self.showAlert(title: "Error", msg: "Invalid state - User endpoint not created")
            return
        }
        
        if(shareVideoBtn.isSelected == false){
            handleShareBtnState(sender: sender as! StreamButton)
        }
    }
    
    @IBAction func shareCamButtonPressed(_ sender: Any) {
        guard let _ = AuviousConferenceSDK.sharedInstance.userEndpointId else {
            self.showAlert(title: "Error", msg: "Invalid state - User endpoint not created")
            return
        }
        
        if(shareVideoBtn.isSelected == false){
            handleShareBtnState(sender: sender as! StreamButton)
        }
    }
    
    @IBAction func shareVideoButtonPressed(_ sender: Any) {
        guard let _ = AuviousConferenceSDK.sharedInstance.userEndpointId else {
            self.showAlert(title: "Error", msg: "Invalid state - User endpoint not created")
            return
        }
        
        if (shareCamBtn.isSelected == false && shareMicBtn.isSelected == false){
            handleShareBtnState(sender: sender as! StreamButton)
        }
    }
    
    @IBAction func endButtonPressed(_ sender: Any) {
        SVProgressHUD.show(withStatus: NSLocalizedString("Please wait...", comment: "General"))
        
        AuviousConferenceSDK.sharedInstance.endConference(conferenceId: currentConference.id, onSuccess: {
            SVProgressHUD.dismiss()
            self.delegate?.removeCreatedConferenceFromList(confId: self.currentConference.id)
            print("Ended conference")
            self.navigationController?.popViewController(animated: true)

        }, onFailure: {(error) in
            SVProgressHUD.dismiss()
            self.showAlert(title: "Error", msg: error.localizedDescription)
        })
    }
    
    @IBAction func leaveButtonPressed(_ sender: Any) {
        SVProgressHUD.show(withStatus: NSLocalizedString("Please wait...", comment: "General"))
        
        AuviousConferenceSDK.sharedInstance.leaveConference(conferenceId: currentConference.id, onSuccess: {
            SVProgressHUD.dismiss()

            print("Left conference")
            self.navigationController?.popViewController(animated: true)

        }, onFailure: {(error) in
            SVProgressHUD.dismiss()
            self.showAlert(title: "Error", msg: error.localizedDescription)
        })
    }
    
    @IBAction func switchCam(_ sender: Any) {
        AuviousConferenceSDK.sharedInstance.switchCamera()
    }
    
    @IBAction func changeAudioRoot(_ sender: Any) {
        
        if audioRootBtn.isSelected == false{
            audioRootBtn.isSelected = true
            if AuviousConferenceSDK.sharedInstance.changeAudioRoot(toSpeaker: audioRootBtn.isSelected) {
                
                UIView.transition(with: audioRootBtn, duration: 0.5, options: .transitionCrossDissolve, animations: {
                    self.audioRootBtn.setImage(UIImage(named: "speaker_icon_act"), for: .normal)
                    self.audioRootBtn.setImage(UIImage(named: "speaker_icon_act"), for: .selected)
                }, completion: nil)
            }
            else{
                audioRootBtn.isSelected = false
            }
        }
        else{
            audioRootBtn.isSelected = false
            if AuviousConferenceSDK.sharedInstance.changeAudioRoot(toSpeaker: audioRootBtn.isSelected) {
                
                UIView.transition(with: audioRootBtn, duration: 0.5, options: .transitionCrossDissolve, animations: {
                    self.audioRootBtn.setImage(UIImage(named: "speaker_icon"), for: .normal)
                    self.audioRootBtn.setImage(UIImage(named: "speaker_icon"), for: .selected)
                }, completion: nil)
            }
            else{
                audioRootBtn.isSelected = true
            }
        }
    }

    //MARK: Collection view
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ConferenceCell.identifier, for: indexPath) as! ConferenceCell
        cell.contentView.backgroundColor = UIColor.random
        
        cell.streamView.videoView.setSize(CGSize(width: cell.contentView.bounds.width, height: cell.contentView.bounds.height))
        
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return remoteParticipants.count
    }
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
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
    
    //MARK: AuviousSDKDelegate
    func auviousSDK(didReceiveConferenceEvent event: ConferenceEvent) {
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
                print("Error \(error) - \(error.localizedDescription)")
                showAlert(title: "Error", msg: error.localizedDescription)
            }
        }
        else if event is ConferenceStreamUnpublishedEvent {
            let object = event as! ConferenceStreamUnpublishedEvent
            
            do {
                try AuviousConferenceSDK.sharedInstance.stopRemoteStream(streamId: object.streamId, remoteUserId: object.userId, remoteEndpointId: object.userEndpointId, streamType: object.streamType)
            } catch let error {
                print("Error \(error) - \(error.localizedDescription)")
                showAlert(title: "Error", msg: error.localizedDescription)
            }
        }
    }
    
    func auviousSDK(didRejoinConference conference:ConferenceSimpleView) {
        //Clear the streams from the UI
        remoteParticipants.removeAll()
        collectionView.reloadData()
        
        currentConference = conference
        conferenceParticipants = currentConference.participants.count
        
        //Reconnect to conference streams
        handleExistingConferenceStreams()
    }
    
    func auviousSDK(didReceiveLocalVideoTrack localVideoTrack: RTCVideoTrack!) {
        localStreamView.videoStreamAdded(localVideoTrack)
    }
    
    func auviousSDK(didReceiveRemoteStream stream: RTCMediaStream, streamId: String, endpointId: String) {
        
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
    
    func auviousSDK(didChangeState newState: StreamEventState, streamId: String, streamType: StreamType, endpointId:String) {
        switch newState {
            case .localStreamIsConnecting:
            print("Local Stream Is Connecting")
        case .localStreamConnected:
            print("Local Stream Connected")
            didPublishStream(streamId: streamId, streamType: streamType)
        case .remoteStreamIsConnecting:
            print("Remote Stream Is Connecting")
        case .remoteStreamConnected:
            print("Remote Stream Connected")
        case .localStreamIsDisconnecting:
            print("Local Stream Is Disonnecting")
        case .localStreamDisconnected:
            print("Local Stream Disconnected")
            didUnpublishStream(streamId: streamId, streamType: streamType)
        case .remoteStreamIsDisconnecting:
            print("Remote Stream Is Disonnecting")
        case .remoteStreamDisconnected:
            print("Remote Stream Disconnected")
            handleStreamDisconnection(streamId: streamId, streamType:streamType, endpointId: endpointId)
        case .localCaptureStarted:
            print("Local Capture Started")
        case .localCaptureStoped:
            print("Local Capture Stoped")
        }
    }
    
    func auviousSDK(onError error: AuviousSDKError) {
        switch error {
        case .noInternetConnection:
            print("\(error.localizedDescription)")
        case .httpError(let code):
            print("Http error code \(code)")
        case .connectionError:
            print("\(error.localizedDescription)")
        case .missingSDKCredentials:
            print("\(error.localizedDescription)")
        case .notLoggedIn:
            print("\(error.localizedDescription)")
        case .endpointNotCreated:
            print("\(error.localizedDescription)")
        case .notInConference:
            print("\(error.localizedDescription)")
        case .missingPeerConnection(let streamId):
            print("\(error.localizedDescription) - \(streamId)")
        case .videoPermissionIsDisabled:
            print("\(error.localizedDescription)")
        case .audioPermissionIsDisabled:
            print("\(error.localizedDescription)")
        case .startCaptureFailure:
            print("\(error.localizedDescription)")
        case .publishStreamFailure(let fragment, let output):
            switch fragment {
            case .makeOfferPublishStream,
                 .localDescriptionPublishStream,
                 .remoteDescriptionPublishStream,
                 .unpublishStream,
                 .publishStreamRequest,
                 .publishStreamIceCandidatesRequest:
                print("\(output)")
            }
            self.showAlert(title: "Error", msg: output)
            return
        case .remoteStreamFailure(let fragment, let output):
            switch fragment {
            case .makeOfferRemoteStream,
                 .localDescriptionRemoteStream,
                 .remoteDescriptionRemoteStream,
                 .remoteStreamIceCandidatesRequest,
                 .remoteStreamRequest,
                 .stopRemoteStreamRequest:
                print("\(output)")
            }
            self.showAlert(title: "Error", msg: output)
            return
        case .unauthorizedRequest:
            print("\(error.localizedDescription)")
        case .internalError:
            print("\(error.localizedDescription)")
        default:
            print("\(error.localizedDescription)")
        }
        self.showAlert(title: "Error", msg: error.localizedDescription)
    }
}
