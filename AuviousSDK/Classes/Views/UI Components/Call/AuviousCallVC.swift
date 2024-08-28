//
//  AuviousCallVC.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 19/07/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import UIKit
import os

public protocol AuviousSimpleCallDelegate: class {
    
    func onCallError(_ error: AuviousSDKGenericError)
    func onCallSuccess()
}

open class AuviousCallVC: UIViewController, AuviousSDKCallDelegate {
    
    //Outgoing call
    private var callId: String?
    
    //UI components
    private var localVideoView: StreamView!
    private var remoteVideoView: StreamView!
    private var hangupButton: UIButton!
    
    //UI configuration
    private var localVideoSizeRatio: CGFloat = 4.2
    private var localVideoBottomConstraint: CGFloat = 16
    private var localVideoRightConstraint: CGFloat = 16
    private var animationDuration = 1.5
    
    //Delegate
    private weak var delegate: AuviousSimpleCallDelegate?
    
    //Control flags
    private var performedInitialValidations: Bool = false
    private var callEstablished: Bool = false
    
    //Call properties
    private var username: String = ""
    private var password: String = ""
    private var target: String = ""
    private var baseEndpoint: String = ""
    private var mqttEndpoint: String = ""
    private var sipHeaders: [String : String]?
    private var configuredStreamType: StreamType = .unknown
    
    //Call timers
    private var waitForAnswerTimer: Timer?
    public var waitForAnswerDuration: TimeInterval = 10
    
    public init(username: String, password: String, target: String, baseEndpoint: String, mqttEndpoint: String, sipHeaders: [String : String]? = nil, delegate: AuviousSimpleCallDelegate, callMode: AuviousCallMode) {
        
        self.username = username
        self.password = password
        self.target = target
        self.baseEndpoint = baseEndpoint
        self.mqttEndpoint = mqttEndpoint
        self.delegate = delegate
        self.sipHeaders = sipHeaders
        
        switch callMode {
        case .audio:
            configuredStreamType = .mic
        case .video:
            configuredStreamType = .cam
        case .audioVideo:
            configuredStreamType = .micAndCam
        }
        
        // Create a Sentry client and start crash handler
//        do {
//            Client.shared = try Client(dsn: "https://74765e10688d4f828efd5bc5320c607c@sentry.auvious.com/9")
//            try Client.shared?.startCrashHandler()
//        } catch let error {
//            os_log("\(error)")
//        }
        
        super.init(nibName: nil, bundle: nil)
        
        os_log("UI Call component: initialised", log: Log.callUI, type: .debug)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("Not implemented")
    }
    
    open override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        get {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            return UIInterfaceOrientationMask.portrait
        }
    }
    
    open override var shouldAutorotate: Bool {
        get {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            return false
        }
    }

    open override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        get {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            return UIInterfaceOrientation.portrait
        }
    }
    
    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    }
    
    override open func viewDidLoad() {
        super.viewDidLoad()
        os_log("UI Call component: viewDidLoad", log: Log.callUI, type: .debug)
        
        view.backgroundColor = .black
        
        //setup video views
        localVideoView = StreamView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: view.bounds.height))
        localVideoView.alpha = 0.0
        localVideoView.clipsToBounds = true
        localVideoView.layer.cornerRadius = 10
        view.addSubview(localVideoView)
        
        remoteVideoView = StreamView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: view.bounds.height))
        remoteVideoView.alpha = 0.0
        remoteVideoView.clipsToBounds = true
        remoteVideoView.layer.cornerRadius = 10
        view.addSubview(remoteVideoView)
        
        //setup ui
        hangupButton = UIButton(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        let podBundle = Bundle(for: AuviousCallVC.self)
        let resourceBundleURL = podBundle.url(forResource: "AuviousSDK", withExtension: "bundle")
        let resourceBundle = Bundle(url: resourceBundleURL!)
        let image = UIImage(named: "phone", in: resourceBundle, compatibleWith: nil)

        hangupButton.setImage(image, for: UIControl.State())
        hangupButton.imageEdgeInsets = UIEdgeInsets(top: 10,left: 10,bottom: 10,right: 10)
        hangupButton.backgroundColor = .red
        hangupButton.isUserInteractionEnabled = true
        hangupButton.addTarget(self, action: #selector(self.hangupButtonPressed), for: .touchUpInside)
        hangupButton.center = CGPoint(x: view.center.x, y: view.bounds.height - 60)
        hangupButton.clipsToBounds = true
        hangupButton.layer.cornerRadius = 30
        hangupButton.layer.zPosition = 1000
        view.addSubview(hangupButton)
    }
    
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if !performedInitialValidations {
            //Check for permissions
            if !validateVideoPermissions() {
                os_log("No video permission, returning error", log: Log.callUI, type: .debug)
                handleError(AuviousSDKError.videoPermissionIsDisabled)
                return
            }
            
            if !validateMicPermissions() {
                os_log("No audio permission, returning error", log: Log.callUI, type: .debug)
                handleError(AuviousSDKError.audioPermissionIsDisabled)
                return
            }
            
            //Check credentials
            if username.isEmpty || password.isEmpty {
                os_log("username/password empty, returning error", log: Log.callUI, type: .debug)
                handleError(AuviousSDKError.missingSDKCredentials)
                return
            }
            
            //Check call target
            if target.isEmpty {
                os_log("target is empty, returning error", log: Log.callUI, type: .debug)
                handleError(AuviousSDKError.missingCallTarget)
                return
            }
            
            performedInitialValidations = true
        }
        
        if performedInitialValidations {
            AuviousCallSDK.sharedInstance.delegate = self
            AuviousCallSDK.sharedInstance.configure(username: username, password: password, organization: "", baseEndpoint: baseEndpoint, mqttEndpoint: mqttEndpoint)
            os_log("Configured CallSDK", log: Log.callUI, type: .debug)
            
            //Get access to the local video stream immediately
            let localStream = AuviousCallSDK.sharedInstance.createLocalMediaStream(type: configuredStreamType, streamId: "test")
            os_log("Created local media stream", log: Log.callUI, type: .debug)
            
            AuviousCallSDK.sharedInstance.login(oAuth: true, onLoginSuccess: {(endpointId) in
                os_log("Login success", log: Log.callUI, type: .debug)
                
                do {
                    self.callId = try AuviousCallSDK.sharedInstance.startCallFlow(target: self.target, sendMode: self.configuredStreamType, localStream: localStream, sipHeaders: self.sipHeaders)
                    self.startWaitingAnswerTimer()
                    
                    os_log("Started call %@", log: Log.callUI, type: .debug, String(describing: self.callId))
                } catch let error {
                    os_log("startCallFlow error %@", log: Log.callUI, type: .error, error.localizedDescription)
                    self.handleError(error)
                }
                
            }, onLoginFailure: {(error) in
                os_log("Login error %@", log: Log.callUI, type: .error, error.localizedDescription)
                self.handleError(error)
            })
        }
    }
    
    //MARK: Validations
    
    //Check for video permissions
    func validateVideoPermissions() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }
    
    //Check for audio persmissions
    func validateMicPermissions() -> Bool {
        return AVAudioSession.sharedInstance().recordPermission == .granted
    }
    
    //MARK: AuviousSDKCallDelegate
    
    public func auviousSDK(didReceiveScreenshot image: UIImage) {
        
    }
    
    public func auviousSDK(agentSwitchedCamera toFront: Bool) {
        os_log("agentSwitchedCamera toFront %@", log: Log.callUI, type: .debug, toFront)
        
        //UIView.animate(withDuration: 0.3, animations: {
            
            let ratio = self.localVideoSizeRatio
            if toFront {
                UIView.animate(withDuration: animationDuration, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.8, options: .curveEaseInOut, animations: {
                    self.localVideoView.bounds.size = CGSize(width: self.view.bounds.width / 3, height: self.view.bounds.height / 3)
                    self.localVideoView.layoutIfNeeded()
                    
                    self.localVideoView.layer.zPosition = 30
                    self.remoteVideoView.layer.zPosition = 20
                    self.localVideoView.transform = CGAffineTransform(scaleX: -1, y: 1)
                    
                    UIView.animate(withDuration: self.animationDuration, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.8, options: .curveEaseInOut, animations: {
                        self.remoteVideoView.frame = CGRect(x: 0, y: 0, width: self.view.bounds.width, height: self.view.bounds.height)
                        self.remoteVideoView.layoutIfNeeded()
                        
                        self.localVideoView.frame = CGRect(x: self.view.bounds.width - (self.view.bounds.width / ratio) - self.localVideoRightConstraint, y: self.view.bounds.height - (self.view.bounds.height / ratio) - self.localVideoBottomConstraint, width: self.view.bounds.width / ratio, height: self.view.bounds.height / ratio)
                        self.localVideoView.layoutIfNeeded()
                    }, completion: { finished in
                        self.localVideoView.layer.zPosition = 30
                        self.remoteVideoView.layer.zPosition = 20
                        
                        
                        self.view.bringSubviewToFront(self.localVideoView)
                        self.view.bringSubviewToFront(self.hangupButton)
                    })
                    
                }, completion: { finished in
                })
                
            } else {
                UIView.animate(withDuration: animationDuration, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.8, options: .curveEaseInOut, animations: {
                    self.remoteVideoView.bounds.size = CGSize(width: self.view.bounds.width / 3, height: self.view.bounds.height / 3)
                    self.remoteVideoView.layoutIfNeeded()
                    
                    self.remoteVideoView.layer.zPosition = 30
                    self.localVideoView.layer.zPosition = 20
                    self.localVideoView.transform = CGAffineTransform(scaleX: 1, y: 1)
                    
                    UIView.animate(withDuration: self.animationDuration, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.8, options: .curveEaseInOut, animations: {
                        self.localVideoView.frame = CGRect(x: 0, y: 0, width: self.view.bounds.width, height: self.view.bounds.height)
                        self.localVideoView.layoutIfNeeded()
                        
                        self.remoteVideoView.frame = CGRect(x: self.view.bounds.width - (self.view.bounds.width / ratio) - self.localVideoRightConstraint, y: self.view.bounds.height - (self.view.bounds.height / ratio) - self.localVideoBottomConstraint, width: self.view.bounds.width / ratio, height: self.view.bounds.height / ratio)
                        self.remoteVideoView.layoutIfNeeded()
                    }, completion: { finished in
                        self.remoteVideoView.layer.zPosition = 30
                        self.localVideoView.layer.zPosition = 20
                        
                        self.view.bringSubviewToFront(self.remoteVideoView)
                        self.view.bringSubviewToFront(self.hangupButton)
                    })
                    
                }, completion: { finished in
                })
            }
    }
    
    public func auviousSDK(didChangeState newState: StreamEventState, callId: String, streamType: StreamType) {
        
    }
    
    public func auviousSDK(didReceiveLocalStream stream: RTCMediaStream, streamId: String, type: StreamType) {
        
    }
    
    public func auviousSDK(didReceiveCallEvent event: CallEvent) {
        switch event.type! {
        case .callCreated:
            os_log("didReceiveCallEvent CallCreated - ignoring", log: Log.callUI, type: .debug)
            break
        case .callRinging:
            os_log("didReceiveCallEvent CallRinging - ignoring", log: Log.callUI, type: .debug)
            break
        case .callCancelled:
            os_log("didReceiveCallEvent CallCancelled - ignoring", log: Log.callUI, type: .debug)
            break
        case .callRejected:
            os_log("didReceiveCallEvent CallRejected", log: Log.callUI, type: .debug)
            handleCallRejected(event as! CallRejectedEvent)
        case .callAnswered:
            os_log("didReceiveCallEvent CallAnswered", log: Log.callUI, type: .debug)
            callEstablished = true
        case .callEnded:
            os_log("didReceiveCallEvent CallEnded", log: Log.callUI, type: .debug)
            handleCallEnded()
        default:
            os_log("didReceiveCallEvent Unknown - ignoring", log: Log.callUI, type: .debug)
            break
        }
    }
    
    public func auviousSDK(didReceiveRemoteStream stream: RTCMediaStream, streamId: String, endpointId: String, type: StreamType) {
        DispatchQueue.main.async {
            
            self.view.bringSubviewToFront(self.localVideoView)
            UIView.animate(withDuration: self.animationDuration, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.8, options: .curveEaseInOut, animations: {
            
                self.hangupButton.alpha = 1.0
                
                let ratio:CGFloat = self.localVideoSizeRatio
                self.localVideoView.frame = CGRect(x: self.view.bounds.width - (self.view.bounds.width / ratio) - self.localVideoRightConstraint, y: self.view.bounds.height - (self.view.bounds.height / ratio) - self.localVideoBottomConstraint, width: self.view.bounds.width / ratio, height: self.view.bounds.height / ratio)
                self.localVideoView.layoutIfNeeded()
                
            }, completion: { finished in
            })
            
            self.remoteVideoView.alpha = 1.0
            
            //Add the video stream to our cell
            if stream.videoTracks.count > 0 {
                let remoteVideoTrack: RTCVideoTrack = stream.videoTracks.first!
                
                if stream.audioTracks.count > 0 {
                    self.remoteVideoView.avStreamAdded(remoteVideoTrack)
                } else {
                    self.remoteVideoView.videoStreamAdded(remoteVideoTrack)
                }
                
            } else if stream.audioTracks.count > 0 {
                self.remoteVideoView.audioStreamAdded()
            }
            
            os_log("didReceiveRemoteStream", log: Log.callUI, type: .debug)
        }
    }
    
    public func auviousSDK(didReceiveLocalVideoTrack localVideoTrack: RTCVideoTrack!) {
        self.localVideoView.transform = CGAffineTransform(scaleX: -1, y: 1)
        self.localVideoView.alpha = 1.0
        localVideoView.videoStreamAdded(localVideoTrack)
        
        os_log("didReceiveLocalStream", log: Log.callUI, type: .debug)
    }
    
    //MARK: Actions
    
    //Hangs up or cancels a call
    @objc private func hangupButtonPressed() {
        os_log("hangup pressed", log: Log.callUI, type: .debug)
        
        guard let callId = callId else {
            os_log("hangupButtonPressed, no call id found, ignoring", log: Log.callUI, type: .debug)
            return
        }
        
        do {
            if callEstablished {
                os_log("hangupButtonPressed: call is established, hanging up", log: Log.callUI, type: .debug)
                try AuviousCallSDK.sharedInstance.hangupCall(callId: callId)
            } else {
                os_log("hangupButtonPressed: call not established, cancelling call", log: Log.callUI, type: .debug)
                try AuviousCallSDK.sharedInstance.cancelCall(callId: callId)
            }
            
            //Always end the call
            handleCallEnded()
            
        } catch let error {
            handleCallEnded()
            
            if callEstablished {
                os_log("hangupButtonPressed: error hanging up %@", log: Log.callUI, type: .error, error.localizedDescription)
            } else {
                os_log("hangupButtonPressed: error cancelling call %@", log: Log.callUI, type: .error, error.localizedDescription)
            }
        }
    }
    
    //MARK: Helpers
    private func handleError(_ error: Error) {
        let auviousError = error as! AuviousSDKError
        
        os_log("handleError %@", log: Log.callUI, type: .error, error.localizedDescription)
        
        switch auviousError {
        case .videoPermissionIsDisabled:
            delegate?.onCallError(.PERMISSION_REQUIRED) // .videoPermissionIsDisabled
        case .audioPermissionIsDisabled:
            delegate?.onCallError(.PERMISSION_REQUIRED) // .audioPermissionIsDisabled
        case .missingSDKCredentials:
            delegate?.onCallError(.AUTHENTICATION_FAILURE) // .missingSDKCredentials
        case .missingCallTarget:
            delegate?.onCallError(.AUTHENTICATION_FAILURE) // .missingCallTarget
        case .noInternetConnection:
            delegate?.onCallError(.NETWORK_ERROR) // .noInternetConnection
        case .callNotAnswered:
            delegate?.onCallError(.CALL_REJECTED) // .callNotAnswered
        default:
            delegate?.onCallError(.UNKNOWN_FAILURE) // .callError
        }
    }
    
    private func handleCallEnded(_ event: CallEndedEvent? = nil, success: Bool = true) {
        os_log("handleCallEnded with success flag %@", log: Log.callUI, type: .debug, success)
        if (callId != nil){
            callId = nil
            callEstablished = false
            remoteVideoView?.resetStreamView()
            localVideoView.resetStreamView()
            hangupButton.alpha = 0.0
            
            AuviousCallSDK.sharedInstance.rtcClient.removeAllStreams()
            AuviousCallSDK.sharedInstance.logout(onSuccess: {
                os_log("logout.onSuccess()", log: Log.callUI, type: .debug)
            }, onFailure: { (Error) in
                os_log("logout.onFailure() %@", log: Log.callUI, type: .error, Error.localizedDescription)
            })
            
            UIView.animate(withDuration: 0.1, animations: {
                self.remoteVideoView?.alpha = 0.0
                self.localVideoView.alpha = 0.0
            }, completion: {finished in
                
                os_log("handleCallEnded call ended", log: Log.callUI, type: .debug)
                if success {
                    os_log("handleCallEnded success, invoking onCallSuccess()", log: Log.callUI, type: .debug)
                    self.delegate?.onCallSuccess()
                } else {
                    self.handleError(AuviousSDKError.callNotAnswered)
                }
            })
        }
    }
    
    private func handleCallRejected(_ event: CallRejectedEvent){
        os_log("handleCallRejected", log: Log.callUI, type: .debug)
        
        callEstablished = false
        remoteVideoView?.resetStreamView()
        localVideoView.resetStreamView()
        
        UIView.animate(withDuration: 0.1, animations: {
            self.remoteVideoView?.alpha = 0.0
            self.localVideoView.alpha = 0.0
        }, completion: {finished in
            self.handleError(AuviousSDKError.callNotAnswered)
        })
    }
    
    //Starts the timer waiting for call answer
    private func startWaitingAnswerTimer() {
        waitForAnswerTimer = Timer(timeInterval: waitForAnswerDuration, target: self, selector: #selector(onWaitingAnswerTick), userInfo: nil, repeats: false)
        RunLoop.current.add(waitForAnswerTimer!, forMode: .common)
    }
    
    //Stops the keep alive timer
    private func stopWaitingAnswerTimer() {
        os_log("stopped answer waiting timer", log: Log.callUI, type: .debug)
        waitForAnswerTimer?.invalidate()
    }
    
    //Answer waiting timer tick
    @objc private func onWaitingAnswerTick(timer: Timer) {
        guard !callEstablished, let callId = callId else {
            os_log("onWaitingAnswerTick but callEstablished = %@ - invalidating timer", log: Log.callUI, type: .debug, callEstablished)
            stopWaitingAnswerTimer()
            return
        }
        
        os_log("onWaitingAnswerTick() - cancel outgoing call", log: Log.callUI, type: .debug)
        do {
            try AuviousCallSDK.sharedInstance.cancelCall(callId: callId)
            handleCallEnded(success: false)
        } catch let error {
            os_log("onWaitingAnswerTick: error cancelling call %@", log: Log.callUI, type: .error, error.localizedDescription)
        }
    }
}
