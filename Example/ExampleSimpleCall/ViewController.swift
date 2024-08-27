//
//  ViewController.swift
//  ExampleSimpleCall
//
//  Created by Jason Kritikos on 19/07/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import UIKit
import AuviousSDK

class ViewController: UIViewController, AuviousSimpleCallDelegate {
    
    @IBOutlet weak var usernameTextfield: UITextField!
    @IBOutlet weak var passwordTextfield: UITextField!
    @IBOutlet weak var targetTextfield: UITextField!
    @IBOutlet weak var callButton: UIButton!
    
    @IBOutlet weak var devSwitchField: UISwitch!
    @IBOutlet weak var uatSwitchField: UISwitch!
    @IBOutlet weak var prodSwitchField: UISwitch!
    
    var vc: AuviousCallVC!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        callButton.layer.cornerRadius = 5.0
        
        checkPermissions()

        devSwitchField.setOn(false, animated: false)
        uatSwitchField.setOn(false, animated: false)
        prodSwitchField.setOn(false, animated: false)
        
        devSwitchField.addTarget(self, action: #selector(switchChanged), for: UIControl.Event.valueChanged)
        uatSwitchField.addTarget(self, action: #selector(switchChanged), for: UIControl.Event.valueChanged)
        prodSwitchField.addTarget(self, action: #selector(switchChanged), for: UIControl.Event.valueChanged)
        
        devSwitchField.setOn(true, animated: true)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.view.endEditing(true)
    }

    @objc func switchChanged(mySwitch: UISwitch) {
        if (mySwitch.isOn && mySwitch == devSwitchField) {
            uatSwitchField.setOn(false, animated: true)
            prodSwitchField.setOn(false, animated: true)
        }

        if (mySwitch.isOn && mySwitch == uatSwitchField) {
            devSwitchField.setOn(false, animated: true)
            prodSwitchField.setOn(false, animated: true)
        }

        if (mySwitch.isOn && mySwitch == prodSwitchField) {
            devSwitchField.setOn(false, animated: true)
            uatSwitchField.setOn(false, animated: true)
        }
    }

    @IBAction func callButtonPressed(_ sender: Any) {
        
        let username: String = (usernameTextfield.text!.isEmpty) ? "anonymous" : usernameTextfield.text!
        let password: String = (passwordTextfield.text!.isEmpty) ? "letmein" : passwordTextfield.text!
        let target: String = targetTextfield.text!
        let sipHeaders: [String: String] = [
            "X-Genesys-Video_MSISDN": "6971234567",
            "X-Genesys-Video_EMAIL": "test@test.gr",
            "X-Genesys-Video_APPSESSIONID": "something-unique",
            "X-Genesys-Video_OMNIA_DEEP_LINK": "https://www.google.com",
            "X-Genesys-Video_TOPIC": "OnBoarding"
        ]
        
        // var baseEndpoint: String = "https://prxbauviousvideo.praxiabank.com"
        // var mqttEndpoint: String = "wss://prxbauviousvideo.praxiabank.com/ws"
        
        var baseEndpoint: String = "https://test-rtc.stg.auvious.com/"
        var mqttEndpoint: String = "wss://events.test-rtc.stg.auvious.com/ws"

        if (uatSwitchField.isOn) {
            baseEndpoint = "https://prxbauviousvideo-uat.praxiabank.com"
            mqttEndpoint = "wss://prxbauviousvideo-uat.praxiabank.com/ws"
        }
        
        if (prodSwitchField.isOn) {
            baseEndpoint = "https://video.praxiabank.com"
            mqttEndpoint = "wss://video.praxiabank.com/ws"
        }
        
        self.vc = AuviousCallVC(username: username, password: password, target: target, baseEndpoint: baseEndpoint, mqttEndpoint: mqttEndpoint, sipHeaders: sipHeaders, delegate: self, callMode: .audioVideo)
        self.vc.modalPresentationStyle = .fullScreen
        self.navigationController?.present(vc, animated: true, completion: nil)
    }
    
    //MARK: AuviousSimpleCallDelegate
    
    //AuviousSDK Call UI component error callback
    func onCallError(_ error: AuviousSDKGenericError) {
        self.vc.showAlert(title: "Error", msg: error.localizedDescription, onSuccess: {
            self.dismiss(animated: true, completion: nil)
        })
    }
    
    //AuviousSDK Call UI component success callback
    func onCallSuccess() {
        self.vc.showAlert(title: "Message", msg: "Call completed successfully", onSuccess: {
            self.dismiss(animated: true, completion: nil)
        })
    }
    
    //MARK: Helpers
    
    //Request for camera/mic permissions if needed
    func checkPermissions() {
        let cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if cameraAuthorizationStatus != .authorized {
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { accessGranted in
                guard accessGranted == true else {
                    self.checkPermissions()
                    return
                }
            })
        }
        
        let micPermission = AVAudioSession.sharedInstance().recordPermission()
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

extension UIViewController {
    
    func showAlert(title:String, msg:String, onSuccess: (()->())? = nil){
        let alert = UIAlertController(title: title, message: msg, preferredStyle: UIAlertController.Style.alert)
        alert.view.tintColor = UIColor.black
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK",comment:""), style: .default, handler: { (action: UIAlertAction!) in
            
            if let callback = onSuccess {
                callback()
            }
        }))
        
        present(alert, animated: true, completion: nil)
    }
}
