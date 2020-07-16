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
    @IBOutlet weak var createConferenceSwitch: UISwitch!
    @IBOutlet weak var conferenceLabel: UILabel!
    @IBOutlet weak var callButton: UIButton!
    
    var vc: AuviousConferenceVC!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        checkPermissions()
        callButton.layer.cornerRadius = 5.0
    }
    
    //MARK: Actions
    
    @IBAction func switchToggled(_ sender: Any) {
        conferenceLabel.text = createConferenceSwitch.isOn ? "Create conference" : "Join conference"
    }
    
    @IBAction func callButtonPressed(_ sender: Any) {
        if validateForm() {
            let username = usernameTextfield.text!
            let password = passwordTextfield.text!
            let conferenceName = conferenceTextfield.text!
            
            let baseEndpoint: String = "https://test-rtc.stg.auvious.com/"
            let mqttEndpoint: String = "wss://events.test-rtc.stg.auvious.com/ws"
            
            self.vc = AuviousConferenceVC(username: username, password: password, conference: conferenceName, baseEndpoint: baseEndpoint, mqttEndpoint: mqttEndpoint, delegate: self)
            self.vc.modalPresentationStyle = .fullScreen
            self.navigationController?.present(vc, animated: true, completion: nil)
        }
    }
    
    // MARK: AuviousSimpleConferenceDelegate
    
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
