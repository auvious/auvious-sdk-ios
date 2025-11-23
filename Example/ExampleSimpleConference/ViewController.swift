//
//  ViewController.swift
//  ExampleSimpleConference
//
//  Created by Jason Kritikos on 19/6/20.
//  Copyright © 2020 Auvious. All rights reserved.
//

import UIKit
import AuviousSDK

class ViewController: UIViewController, AuviousSimpleConferenceDelegate {

    //UI components
    @IBOutlet weak var usernameTextfield: UITextField!
    @IBOutlet weak var passwordTextfield: UITextField!
    @IBOutlet weak var conferenceTextfield: UITextField!
    @IBOutlet weak var participantTextfield: UITextField!
    @IBOutlet weak var createConferenceSwitch: UISwitch!
    @IBOutlet weak var conferenceLabel: UILabel!
    @IBOutlet weak var callButton: UIButton!
    @IBOutlet weak var callMode: UISegmentedControl!
    @IBOutlet weak var cameraSwitch: UISwitch!
    @IBOutlet weak var speakerEnabledSwitch: UISwitch!
    @IBOutlet weak var micSwitch: UISwitch!
    @IBOutlet weak var speakerSwitch: UISwitch!
    @IBOutlet weak var pipSwitch: UISwitch!
    @IBOutlet weak var screenSharingSwitch: UISwitch!
    
    //Gradient
    private var gradientLayer = CAGradientLayer()
    
    var vc: AuviousConferenceVCNew!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        usernameTextfield.attributedPlaceholder = NSAttributedString(string: "Username", attributes: [NSAttributedString.Key.foregroundColor: UIColor.white.withAlphaComponent(0.7)])
        passwordTextfield.attributedPlaceholder = NSAttributedString(string: "Password", attributes: [NSAttributedString.Key.foregroundColor: UIColor.white.withAlphaComponent(0.7)])
        conferenceTextfield.attributedPlaceholder = NSAttributedString(string: "Conference to create/join", attributes: [NSAttributedString.Key.foregroundColor: UIColor.white.withAlphaComponent(0.7)])
        participantTextfield.attributedPlaceholder = NSAttributedString(string: "Participant name (optional)", attributes: [NSAttributedString.Key.foregroundColor: UIColor.white.withAlphaComponent(0.7)])
        
        usernameTextfield.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        passwordTextfield.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        conferenceTextfield.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        participantTextfield.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        
        usernameTextfield.textColor = .white
        passwordTextfield.textColor = .white
        conferenceTextfield.textColor = .white
        participantTextfield.textColor = .white
    
        // hard code values for faster debugging
        usernameTextfield.text = "goy-ckq"//"fav-xva"
        passwordTextfield.text = "b"
        conferenceTextfield.text = "-"
        
        gradientLayer.colors = [UIColor(red: 0/255, green: 31/255, blue: 122/255, alpha: 1).cgColor, UIColor(red: 51/255, green: 102/255, blue: 255/255, alpha: 1).cgColor]
        gradientLayer.setAngle(150)
//        view.layer.insertSublayer(gradientLayer, at: 0)
        
        checkPermissions()
        callButton.layer.cornerRadius = 5.0
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
//        gradientLayer.frame = view.bounds
    }
    
    //MARK: Actions
    
    @IBAction func switchToggled(_ sender: Any) {
        conferenceLabel.text = createConferenceSwitch.isOn ? "Create conference" : "Join conference"
    }
    
    @IBAction func callButtonPressed(_ sender: Any) {
        if validateForm() {
            let username = usernameTextfield.text!
            let password = passwordTextfield.text!
            let conferenceName = ""//conferenceTextfield.text!.trimmingCharacters(in: .whitespacesAndNewlines)
            let participantName = participantTextfield.text
            
            //TEST-RTC
//            let clientId: String = "auvious"
//            let baseEndpoint: String = "https://test-rtc.auvious.video/"
//            let mqttEndpoint: String = "wss://events.test-rtc.auvious.video/ws"
//            let params: [String: String] = ["username" : username, "password" : password, "grant_type" : "password", "conference" : conferenceName]
//
            //GENESYS DEV (customer)
            let clientId: String = "customer" //dev.auvious.video/t/vyn-kym <-----
            let baseEndpoint: String = "https://dev.auvious.video/"
//            let mqttEndpoint: String = "wss://dev.auvious.video/ws"
            let mqttEndpoint: String = "dev.auvious.video"
            let params: [String: String] = ["username" : username, "password" : password, "grant_type" : "password"]

            //GENESYS DEV (test-agent)
//            let clientId: String = "test-agent"
//            let baseEndpoint: String = "https://genesys.dev.auvious.com/"
//            let mqttEndpoint: String = "wss://events.genesys.dev.auvious.com/ws"
//            let params: [String: String] = ["username" : username, "password" : password, "grant_type" : "password"]
            
            //GENESYS STAGING (customer)
//            let clientId: String = "customer"
//            let baseEndpoint: String = "https://genesys.stg.auvious.com/"
//            let mqttEndpoint: String = "wss://events.genesys.stg.auvious.com/ws"
//            let params: [String: String] = ["username" : username, "password" : password, "grant_type" : "password"]
            
            //GENESYS PROD (customer)
//            let clientId: String = "customer"
//            let baseEndpoint: String = "https://genesys.auvious.com/"
//            let mqttEndpoint: String = "wss://events.genesys.auvious.com/ws"
//            let params: [String: String] = ["username" : username, "password" : password, "grant_type" : "password"]

            //New configuration approach
            var conf = AuviousConferenceConfiguration()
            conf.username = username
            conf.password = password
            conf.clientId = clientId
            
            if let name = participantName, !name.isEmpty {
                conf.participantName = name
            }
            
            conf.conference = conferenceName
            conf.baseEndpoint = baseEndpoint
            conf.mqttEndpoint = mqttEndpoint
            conf.conferenceBackgroundColor = .systemGreen
            conf.enableSpeaker = self.speakerEnabledSwitch.isOn
            switch (self.callMode.selectedSegmentIndex){
            case 0:
                conf.callMode = .audio
                break
            case 1:
                conf.callMode = .video
                break
            case 2:
                conf.callMode = .audioVideo
                break
            default:
                conf.callMode = .audioVideo
            }
            conf.cameraAvailable = self.cameraSwitch.isOn
            conf.microphoneAvailable = self.micSwitch.isOn
            conf.speakerAvailable = self.speakerSwitch.isOn
            conf.pipAvailable = self.pipSwitch.isOn
            conf.screenSharingAvailable = self.screenSharingSwitch.isOn
            
            self.vc = AuviousConferenceVCNew(configuration: conf, delegate: self)
            presentAuviousUI(childVC: self.vc)
        }
    }
    
    // MARK: AuviousSimpleConferenceDelegate
    
    func onScreenSharingStart() {
        //self.minimizeToPiP(childVC: self.vc)
    }
    
    func onScreenSharingStop() {
        //self.restoreFromPiP(childVC: self.vc)
    }
    
    func onConferenceSuccess() {
        self.vc.showAlert(title: "Message", msg: "Conference completed successfully", onSuccess: {
            self.dismiss(animated: true, completion: nil)
        })
    }
    
    func onConferenceError(_ error: AuviousSDKGenericError) {
        self.vc.showAlert(title: "Error", msg: error.localizedDescription, onSuccess: {
            self.dismiss(animated: true, completion: nil)
        })
    }
    
    // MARK: Helpers

    private func validateForm() -> Bool {
        guard let username = usernameTextfield.text, !username.isEmpty else {
            showAlert(title: "Warning", msg: "Please enter your username")
            return false
        }
        
        guard let password = passwordTextfield.text, !password.isEmpty else {
            showAlert(title: "Warning", msg: "Please enter your password")
            return false
        }
        
        guard let conferenceName = conferenceTextfield.text, !conferenceName.isEmpty else {
            showAlert(title: "Warning", msg: "Please enter a conference name")
            return false
        }
        
        return true
    }
    
    //Request for camera/mic permissions if needed
    private func checkPermissions() {
        let cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if cameraAuthorizationStatus != .authorized {
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { accessGranted in
                guard accessGranted == true else {
                    self.checkPermissions()
                    return
                }
            })
        }
        
        let micPermission = AVAudioSession.sharedInstance().recordPermission
        if micPermission != .granted {
            AVAudioSession.sharedInstance().requestRecordPermission({ accessGranted in
                guard accessGranted == true else {
                    self.checkPermissions()
                    return
                }
            })
        }
    }
}

//Various UI helper functions for PIP etc.
extension ViewController {
    private func presentAuviousUI(childVC: UIViewController) {
        // Add as child
        addChild(childVC)
        
        // Set initial frame off-screen (bottom)
        let screenBounds = view.bounds
        childVC.view.frame = CGRect(x: 0, y: screenBounds.height, width: screenBounds.width, height: screenBounds.height)
        
        // Add the view
        view.addSubview(childVC.view)
        
        // Animate into position
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut], animations: {
            childVC.view.frame = screenBounds
        }, completion: { _ in
            childVC.didMove(toParent: self)
        })
    }
}
