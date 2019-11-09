//
//  AuviousCallVC.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 19/07/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import UIKit

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
    
    //Call timers
    private var waitForAnswerTimer: Timer?
    public var waitForAnswerDuration: TimeInterval = 10
    
    public init(username: String, password: String, target: String, baseEndpoint: String, mqttEndpoint: String, sipHeaders: [String : String]? = nil, delegate: AuviousSimpleCallDelegate) {
        
        self.username = username
        self.password = password
        self.target = target
        self.baseEndpoint = baseEndpoint
        self.mqttEndpoint = mqttEndpoint
        self.delegate = delegate
        self.sipHeaders = sipHeaders
        
        // Create a Sentry client and start crash handler
//        do {
//            Client.shared = try Client(dsn: "https://74765e10688d4f828efd5bc5320c607c@sentry.auvious.com/9")
//            try Client.shared?.startCrashHandler()
//        } catch let error {
//            print("\(error)")
//        }
        
        super.init(nibName: nil, bundle: nil)
        
        log("UI Call component: initialised")
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
        log("UI Call component: viewDidLoad")
        
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
                log("UI Call component: viewDidAppear - no video permission, returning error")
                handleError(AuviousSDKError.videoPermissionIsDisabled)
                return
            }
            
            if !validateMicPermissions() {
                log("UI Call component: viewDidAppear - no audio permission, returning error")
                handleError(AuviousSDKError.audioPermissionIsDisabled)
                return
            }
            
            //Check credentials
            if username.isEmpty || password.isEmpty {
                log("UI Call component: viewDidAppear - username/password empty, returning error")
                handleError(AuviousSDKError.missingSDKCredentials)
                return
            }
            
            //Check call target
            if target.isEmpty {
                log("UI Call component: viewDidAppear - target is empty, returning error")
                handleError(AuviousSDKError.missingCallTarget)
                return
            }
            
            performedInitialValidations = true
        }
        
        if performedInitialValidations {
            AuviousCallSDK.sharedInstance.delegate = self
            AuviousCallSDK.sharedInstance.configure(username: username, password: password, organization: "", baseEndpoint: baseEndpoint, mqttEndpoint: mqttEndpoint)
            log("UI Call component: Configured CallSDK")
            
            //Get access to the local video stream immediately
            let localStream = AuviousCallSDK.sharedInstance.createLocalMediaStream(type: .micAndCam, streamId: "test")
            log("UI Call component: Created local media stream")
            
            AuviousCallSDK.sharedInstance.login(oAuth: true, onLoginSuccess: {(endpointId) in
                self.log("UI Call component: Login success")
                
                do {
                    self.callId = try AuviousCallSDK.sharedInstance.startCallFlow(target: self.target, sendMode: .micAndCam, localStream: localStream, sipHeaders: self.sipHeaders)
                    self.startWaitingAnswerTimer()
                    
                    self.log("UI Call component: Started call \(self.callId)")
                } catch let error {
                    self.log("UI Call component: startCallFlow error \(error.localizedDescription)")
                    self.handleError(error)
                }
                
            }, onLoginFailure: {(error) in
                self.log("UI Call component: Login error \(error.localizedDescription)")
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
        self.log("UI Call component: agentSwitchedCamera toFront \(toFront)")
        
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
    
    public func auviousSDK(didReceiveCallEvent event: CallEvent) {
        switch event.type! {
        case .callCreated:
            self.log("UI Call component: didReceiveCallEvent CallCreated - ignoring")
            break
        case .callRinging:
            self.log("UI Call component: didReceiveCallEvent CallRinging - ignoring")
            break
        case .callCancelled:
            self.log("UI Call component: didReceiveCallEvent CallCancelled - ignoring")
            break
        case .callRejected:
            self.log("UI Call component: didReceiveCallEvent CallRejected")
            handleCallRejected(event as! CallRejectedEvent)
        case .callAnswered:
            self.log("UI Call component: didReceiveCallEvent CallAnswered")
            callEstablished = true
        case .callEnded:
            self.log("UI Call component: didReceiveCallEvent CallEnded")
            handleCallEnded()
        default:
            self.log("UI Call component: didReceiveCallEvent Unknown - ignoring")
            break
        }
    }
    
    public func auviousSDK(didReceiveRemoteStream stream: RTCMediaStream, streamId: String, endpointId: String) {
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
            
            self.log("UI Call component: didReceiveRemoteStream")
        }
    }
    
    public func auviousSDK(didReceiveLocalVideoTrack localVideoTrack: RTCVideoTrack!) {
        self.localVideoView.transform = CGAffineTransform(scaleX: -1, y: 1)
        self.localVideoView.alpha = 1.0
        localVideoView.videoStreamAdded(localVideoTrack)
        
        self.log("UI Call component: didReceiveLocalStream")
    }
    
    //MARK: Actions
    
    //Hangs up or cancels a call
    @objc private func hangupButtonPressed() {
        self.log("UI Call component: hangup pressed")
        
        guard let callId = callId else {
            self.log("UI Call component: hangupButtonPressed, no call id found, ignoring")
            return
        }
        
        do {
            if callEstablished {
                self.log("UI Call component: hangupButtonPressed: call is established, hanging up")
                try AuviousCallSDK.sharedInstance.hangupCall(callId: callId)
            } else {
                self.log("UI Call component: hangupButtonPressed: call not established, cancelling call")
                try AuviousCallSDK.sharedInstance.cancelCall(callId: callId)
            }
            
            //Always end the call
            handleCallEnded()
            
        } catch let error {
            handleCallEnded()
            
            if callEstablished {
                self.log("UI Call component: hangupButtonPressed: error hanging up \(error.localizedDescription)")
            } else {
                self.log("UI Call component: hangupButtonPressed: error cancelling call \(error.localizedDescription)")
            }
        }
    }
    
    //MARK: Helpers
    private func log(_ msg: String){
        print(msg)
//        let event = Event(level: .debug)
//        event.message = msg
//        event.environment = baseEndpoint
//
//        let extra = ["platform": "ios", "callId" : callId]
//        event.extra = extra
//
//        Client.shared?.send(event: event)
        print("self.log(\(msg))")
    }
    
    private func handleError(_ error: Error) {
        let auviousError = error as! AuviousSDKError
        
        self.log("UI Call component: handleError \(error.localizedDescription)")
        
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
        self.log("UI Call component: handleCallEnded with success flag \(success)")
        if (callId != nil){
            callId = nil
            callEstablished = false
            remoteVideoView?.resetStreamView()
            localVideoView.resetStreamView()
            hangupButton.alpha = 0.0
            
            AuviousCallSDK.sharedInstance.rtcClient.removeAllStreams()
            try AuviousCallSDK.sharedInstance.logout(onSuccess: {
                self.log("UI Call component: logout.onSuccess()")
            }, onFailure: { (Error) in
                self.log("UI Call component: logout.onFailure() \(Error)")
            })
            
            UIView.animate(withDuration: 0.1, animations: {
                self.remoteVideoView?.alpha = 0.0
                self.localVideoView.alpha = 0.0
            }, completion: {finished in
                
                self.log("UI Call component: handleCallEnded call ended")
                if success {
                    self.log("UI Call component: handleCallEnded success, invoking onCallSuccess()")
                    self.delegate?.onCallSuccess()
                } else {
                    self.handleError(AuviousSDKError.callNotAnswered)
                }
            })
        }
    }
    
    private func handleCallRejected(_ event: CallRejectedEvent){
        self.log("UI Call component: handleCallRejected")
        
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
        self.log("UI Call component: stopped answer waiting timer")
        waitForAnswerTimer?.invalidate()
    }
    
    //Answer waiting timer tick
    @objc private func onWaitingAnswerTick(timer: Timer) {
        guard !callEstablished, let callId = callId else {
            self.log("UI Call component: onWaitingAnswerTick but callEstablished = \(callEstablished) - invalidating timer")
            stopWaitingAnswerTimer()
            return
        }
        
        self.log("UI Call components: onWaitingAnswerTick() - cancel outgoing call")
        do {
            try AuviousCallSDK.sharedInstance.cancelCall(callId: callId)
            handleCallEnded(success: false)
        } catch let error {
            self.log("UI Call component: onWaitingAnswerTick: error cancelling call \(error.localizedDescription)")
        }
    }
}
