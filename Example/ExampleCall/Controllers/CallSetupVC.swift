//
//  CallSetupVC.swift
//  ExampleCall
//
//  Created by Jace on 04/05/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import UIKit
import AuviousSDK
import BEMCheckBox
import AVFoundation
import OSLog

fileprivate enum CallButtonState {
    case invalid, readyToCall, calling
}

class CallSetupVC: UIViewController, UITextFieldDelegate, AuviousSDKCallDelegate {

    //UI components
    @IBOutlet weak var hangupButton: UIButton!
    @IBOutlet weak var callTextfield: UITextField!
    @IBOutlet weak var callButton: UIButton!
    @IBOutlet weak var ringingContainerView: UIView!
    @IBOutlet weak var localView: StreamView!
    @IBOutlet weak var acceptCallButton: UIButton!
    @IBOutlet weak var rejectCallButton: UIButton!
    @IBOutlet weak var outgoingCallContainer: UIView!
    @IBOutlet weak var callerSendVideoCheckbox: BEMCheckBox!
    @IBOutlet weak var callerSendAudioCheckbox: BEMCheckBox!
    @IBOutlet weak var calleeSendVideoCheckbox: BEMCheckBox!
    @IBOutlet weak var calleeSendAudioCheckbox: BEMCheckBox!
    @IBOutlet weak var remoteView: StreamView!
    
    //Incoming call
    private var callCreatedEvent: CallCreatedEvent?
    
    //Outgoing call
    private var callId: String?
    
    //Ringtones
    private var ringingTone: AVAudioPlayer?
    
    //State
    fileprivate var callButtonState: CallButtonState = .invalid {
        didSet {
            handleCallButtonState()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Call setup"
        
        hangupButton.clipsToBounds = true
        hangupButton.layer.cornerRadius = 25
        hangupButton.alpha = 0.0
        hangupButton.layer.zPosition = 210
        
        callTextfield.delegate = self
        callTextfield.addTarget(self, action: #selector(textFieldDidChange(_:)), for: .editingChanged)
        
        let logoutButton = UIBarButtonItem(title: "Logout", style: .done, target: self, action: #selector(self.logoutPressed))
        logoutButton.tintColor = .gray
        self.navigationItem.leftBarButtonItem = logoutButton
        
        setupRingingAlert()
        
        callButton.layer.cornerRadius = 5.0
        acceptCallButton.layer.cornerRadius = 5.0
        rejectCallButton.layer.cornerRadius = 5.0
        
        remoteView.alpha = 0.0
        localView.alpha = 0.0
        localView.layer.zPosition = 200
        
        AuviousCallSDK.sharedInstance.delegate = self
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if !AuviousCallSDK.sharedInstance.isLoggedIn {
            let vc = LoginVC()
            let nc = UINavigationController(rootViewController: vc)
            self.navigationController?.present(nc, animated: true, completion: nil)
        }
    }
    
    //MARK: Textfield delegate
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        
        if textField == callTextfield {
            textField.resignFirstResponder()
        }
        return true
    }
    
    @objc func textFieldDidChange(_ textField: UITextField) {
        if let text = textField.text, text.count > 0 {
            callButtonState = .readyToCall
        } else {
            callButtonState = .invalid
        }
    }
    
    //MARK: UI
    
    fileprivate func handleCallButtonState() {
        switch callButtonState {
        case .invalid:
            callButton.backgroundColor = UIColor(red: 0.882, green: 0.882, blue: 0.882, alpha: 1.00)
            callButton.setTitleColor(UIColor(red: 0.259, green: 0.259, blue: 0.259, alpha: 1.00), for: [])
        case .readyToCall:
            callButton.backgroundColor = callerSendVideoCheckbox.onCheckColor
            callButton.setTitleColor(.white, for: [])
            callButton.setTitle("Call", for: [])
        case .calling:
            callButton.backgroundColor = .red
            callButton.setTitle("Cancel call", for: [])
        }
    }
    
    func setupRingingAlert(){
        hideRingingAlert()
        
        ringingContainerView.clipsToBounds = true
        ringingContainerView.layer.cornerRadius = 10
    }
    
    func showRingingAlert(){
        UIView.animate(withDuration: 0.1, animations: {
            self.outgoingCallContainer.alpha = 0.0
        }, completion: {finished in
            
        })
        
        callTextfield.resignFirstResponder()
        ringingContainerView.alpha = 1.0
    }
    
    func hideRingingAlert(){
        UIView.animate(withDuration: 0.1, animations: {
            self.outgoingCallContainer.alpha = 1.0
        }, completion: {finished in
            
        })
        
        ringingContainerView.alpha = 0.0
    }
    
    func hideLocalView(){
        localView.resetStreamView()
        
        UIView.animate(withDuration: 0.2, animations: {
            self.localView.alpha = 0.0
        }, completion: {finished in
            
        })
    }
    
    func hideRemoteView(){
        remoteView?.resetStreamView()
        hangupButton.alpha = 0.0
        
        UIView.animate(withDuration: 0.2, animations: {
            self.remoteView?.alpha = 0.0
        }, completion: {finished in
            
        })
    }
    
    private func playRingingTone(isRemote: Bool){
        let file = isRemote ? "remote_ringing.mp3" : "ringing.mp3"
        
        let path = Bundle.main.path(forResource: file, ofType: nil)!
        let url = URL(fileURLWithPath: path)
        
        do {
            ringingTone = try AVAudioPlayer(contentsOf: url)
            ringingTone?.play()
        } catch {
            
        }
    }
    
    //MARK: Actions
    
    @IBAction func hangupButtonPressed(_ sender: Any) {
        if let callId = callId {
            do {
                try AuviousCallSDK.sharedInstance.hangupCall(callId: callId)
                
                if let text = self.callTextfield.text, text.count > 0 {
                    self.callButtonState = .readyToCall
                } else {
                    self.callButtonState = .invalid
                }
                
            } catch let error {
                self.showAlert(title: "Error", msg: error.localizedDescription)
            }
        }
    }
    
    //Logout
    @objc func logoutPressed() {
        AuviousCallSDK.sharedInstance.logout(onSuccess: {
            
            if !AuviousCallSDK.sharedInstance.isLoggedIn {
                let vc = LoginVC()
                let nc = UINavigationController(rootViewController: vc)
                self.navigationController?.present(nc, animated: true, completion: nil)
            }
            
        }, onFailure: {(error) in
            self.showAlert(title: "Error", msg: error.localizedDescription)
        })
    }
    
    //Place/cancel a call
    @IBAction func callButtonPressed(_ sender: Any) {
        guard let target = callTextfield.text, target.count > 0 else {
            showAlert(title: "Error", msg: "Please enter a user to call.")
            return
        }
        
        callTextfield.resignFirstResponder()
        
        do {
            if callButtonState == .readyToCall {
                //Determine what to send
                let sendMode = configureOutgoingStream(sendVideo: callerSendVideoCheckbox.on, sendAudio: callerSendAudioCheckbox.on)
                
                let sipHeaders: [String: String] = [
                    "X-Genesys-Video_MSISDN": "6971234567",
                    "X-Genesys-Video_EMAIL": "test@test.gr",
                    "X-Genesys-Video_APPSESSIONID": "something-unique",
                    "X-Genesys-Video_TOPIC": "OnBoarding"
                ]
                
                os_log("Starting call with type %@", log: Log.callApp, type: .error, sendMode.rawValue)

                self.callId = try AuviousCallSDK.sharedInstance.startCallFlow(target: target, sendMode: sendMode, sipHeaders: sipHeaders)
                callButtonState = .calling
            } else if callButtonState == .calling {
                if let callId = callId {
                    try AuviousCallSDK.sharedInstance.cancelCall(callId: callId)
                    callButtonState = .readyToCall
                    self.ringingTone?.stop()
                }
            }
        } catch let error {
            os_log("callButton error %@", log: Log.callApp, type: .error, error.localizedDescription)
        }
    }
    
    //Accept a call
    @IBAction func acceptCallPressed(_ sender: Any) {
        guard let callCreatedEvent = callCreatedEvent else {
            return
        }
        
        self.callId = callCreatedEvent.callId
        
        do {
            let sendMode = configureOutgoingStream(sendVideo: calleeSendVideoCheckbox.on, sendAudio: calleeSendAudioCheckbox.on)
            try AuviousCallSDK.sharedInstance.acceptCall(callEvent: callCreatedEvent, sendMode: sendMode, receiveMode: .micAndCam)
            hideRingingAlert()
            
        } catch let error {
            os_log("error in acceptCallPressed %@", log: Log.callApp, type: .error, error.localizedDescription)
        }
        
    }
    
    //Reject a call
    @IBAction func rejectCallPressed(_ sender: Any) {
        guard let callCreatedEvent = callCreatedEvent else {
            return
        }
        
        do {
            try AuviousCallSDK.sharedInstance.rejectCall(callEvent: callCreatedEvent, reason: "Busy")
            hideRingingAlert()
            
        } catch let error {
            os_log("error in rejectCallPressed %@", log: Log.callApp, type: .error, error.localizedDescription)
        }
    }
    
    @objc func image(_ image: UIImage, didFinishSavingWithError error: NSError?, contextInfo: UnsafeRawPointer) {
        if let error = error {
            // we got back an error!
//            let ac = UIAlertController(title: "Save error", message: error.localizedDescription, preferredStyle: .alert)
//            ac.addAction(UIAlertAction(title: "OK", style: .default))
//            present(ac, animated: true)
        } else {
//            let ac = UIAlertController(title: "Saved!", message: "Your image has been saved to your photos.", preferredStyle: .alert)
//            ac.addAction(UIAlertAction(title: "OK", style: .default))
//            present(ac, animated: true)
        }
    }
    
    //MARK: Helpers
    
    private func configureOutgoingStream(sendVideo: Bool, sendAudio: Bool) -> AuviousSDK.StreamType {
        var sendMode: StreamType = .micAndCam
        if !sendVideo && !sendAudio {
            sendMode = .unknown
        } else if sendAudio && !sendVideo {
            sendMode = .mic
        } else if !sendAudio && sendVideo {
            sendMode = .cam
        }
        
        return sendMode
    }
    
    private func handleCallCancelled() {
        ringingTone?.stop()
        hideRingingAlert()
        showAlert(title: "Message", msg: "Remote user cancelled the call.")
    }
    
    private func handleCallRejected(_ event: CallRejectedEvent){
        ringingTone?.stop()
        hideRemoteView()
        
        var title = "Message"
        //call rejected by remote party
        if let myEndpoint = AuviousCallSDK.sharedInstance.userEndpointId, myEndpoint != event.userEndpointId {
            title = "Call rejected"
            showAlert(title: title, msg: event.reason)
        }
        
        callButtonState = .readyToCall
    }
    
    private func handleCallEnded(_ event: CallEndedEvent) {
        remoteView?.resetStreamView()
        hangupButton.alpha = 0.0
        
        UIView.animate(withDuration: 0.1, animations: {
            self.remoteView?.alpha = 0.0
        }, completion: {finished in
            
            if let myEndpoint = AuviousCallSDK.sharedInstance.userEndpointId, myEndpoint != event.userEndpointId {
                self.showAlert(title: "Call ended", msg: "Remote user hang up")
                self.callButtonState = .readyToCall
            }
        })
    }
    
    //MARK: AuviousSDK call delegate
    
    func auviousSDK(didReceiveCallEvent event: CallEvent) {
        
        switch event.type! {
        case .callCreated:
            self.callCreatedEvent = event as? CallCreatedEvent
            playRingingTone(isRemote: false)
            showRingingAlert()
        case .callRinging:
            playRingingTone(isRemote: true)
        case .callCancelled:
            handleCallCancelled()
        case .callRejected:
            handleCallRejected(event as! CallRejectedEvent)
        case .callAnswered:
            ringingTone?.stop()
        case .callEnded:
            handleCallEnded(event as! CallEndedEvent)
        default:
            break
            
        }
    }
    
    func auviousSDK(didReceiveScreenshot image: UIImage) {
        DispatchQueue.main.async {
            UIImageWriteToSavedPhotosAlbum(image, self, #selector(self.image(_:didFinishSavingWithError:contextInfo:)), nil)
        }
    }
    
    func auviousSDK(didChangeState newState: StreamEventState, callId: String, streamType: StreamType) {
        switch newState {
        case .localCaptureStoped:
            hideLocalView()
        default:
            break
        }
    }
    
    func auviousSDK(didReceiveLocalVideoTrack localVideoTrack: RTCVideoTrack!) {
        localView.videoStreamAdded(localVideoTrack)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.localView.alpha = 1.0
        }
    }
        
    func auviousSDK(didReceiveRemoteStream stream: RTCMediaStream, streamId: String, endpointId: String, type: AuviousSDK.StreamType) {
        DispatchQueue.main.async {
            
            if let remoteView = self.remoteView {
                remoteView.alpha = 1.0
                self.hangupButton.alpha = 1.0
                
                //Add the video stream to our cell
                if stream.videoTracks.count > 0 {
                    let remoteVideoTrack: RTCVideoTrack = stream.videoTracks.first!
                    
                    if stream.audioTracks.count > 0 {
                        remoteView.avStreamAdded(remoteVideoTrack)
                        
                        //Switch audio routing to speaker
                        #warning("UNCOMMENT BEFORE SENDING VERSION")
                        //let result = AuviousCallSDK.sharedInstance.changeAudioRoot(toSpeaker: true)
                        
                    } else {
                        remoteView.videoStreamAdded(remoteVideoTrack)
                    }
                    
                } else if stream.audioTracks.count > 0 {
                    remoteView.audioStreamAdded()
                    
                    //Switch audio routing to speaker
                    #warning("UNCOMMENT BEFORE SENDING VERSION")
                    //let result = AuviousCallSDK.sharedInstance.changeAudioRoot(toSpeaker: true)
                }
            }
        }
    }
    
    func auviousSDK(agentSwitchedCamera toFront: Bool) {}
}
