//
//  LoginVC.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 12/12/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import UIKit
import SPPermissions
import SVProgressHUD
import AuviousSDK

class LoginVC: UIViewController, UITextFieldDelegate {

    //UI components
    @IBOutlet weak var usernameTextfield: UITextField!
    @IBOutlet weak var passwordTextfield: UITextField!
    @IBOutlet weak var organizationTextfield: UITextField!
    @IBOutlet weak var oAuthSwitch: UISwitch!
    @IBOutlet weak var loginBtn: UIButton!
    
    var baseEndpoint: String!
    var mqttEndpoint: String!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Login"
        
        usernameTextfield.text = "panos.lapousis@gmail.com"
        passwordTextfield.text = "123456q!"
        organizationTextfield.text = "boomar"
        
        baseEndpoint = "https://staging-rtc.auvious.com"
        mqttEndpoint = "wss://staging-mqtt.auvious.com/ws"
        //baseEndpoint = "https://test-rtc.auvious.com"
        //mqttEndpoint = "wss://test-rtc.auvious.com/ws"
        //let baseEndpoint: String = "https://prxbauviousvideo.praxiabank.com/"
        //let mqttEndpoint: String = "wss://prxbauviousvideo.praxiabank.com/ws"
        
        loginBtn.layer.cornerRadius = 5.0
        
        let tapGesture: UITapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(LoginVC.endEditing(_:)))
        self.view.addGestureRecognizer(tapGesture)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        //Request permissions if necessary
        if !SPPermission.isAllowed(.camera) || !SPPermission.isAllowed(.microphone) {
            SPPermission.Dialog.request(with: [.camera, .microphone], on: self)
        }
    }
    
    @objc func endEditing(_ gesture: UITapGestureRecognizer){
        dismisKeyboard()
    }
    
    func dismisKeyboard(){
        UIView.animate(withDuration: 0.3, delay: 0.0, options: UIView.AnimationOptions.curveEaseIn, animations: { () -> Void in
            self.view.frame.origin.y = 0
        }, completion: { (finished) -> Void in})
        self.view.endEditing(true)
    }

    //Login button handler
    @IBAction func loginButtonPressed(_ sender: Any) {
        
        dismisKeyboard()
        
        let isFormValid = validate()
        
        if isFormValid, let u = usernameTextfield.text, let p = passwordTextfield.text, let o = organizationTextfield.text {
            AuviousCallSDK.sharedInstance.configure(username: u, password: p, organization: o, baseEndpoint: baseEndpoint, mqttEndpoint: mqttEndpoint)
            
            SVProgressHUD.show(withStatus: NSLocalizedString("Please wait...", comment: "General"))
            
            AuviousCallSDK.sharedInstance.login(oAuth: oAuthSwitch.isOn, onLoginSuccess: {(endpointId) in
                SVProgressHUD.dismiss()
                
                if let _ = endpointId {
                    self.dismiss(animated: true, completion: nil)
                }
            }, onLoginFailure: {(error) in
                SVProgressHUD.dismiss()
                self.showAlert(title: "Error", msg: error.localizedDescription)
            })
        }
    }
    
    //Login form validation
    private func validate() -> Bool {
        
        if let username = usernameTextfield.text, username.isEmpty {
            showAlert(title: "Warning", msg: "Username is required")
            return false
        }
        
        if let password = passwordTextfield.text, password.isEmpty {
            showAlert(title: "Warning", msg: "Password is required")
            return false
        }
        
        if let organization = organizationTextfield.text, organization.isEmpty {
            showAlert(title: "Warning", msg: "Organization is required")
            return false
        }
        
        return true
    }
    
    //MARK: Textfield delegate
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        
        var originY: CGFloat = 0
        
        if textField == usernameTextfield {
            originY = 0
            passwordTextfield.becomeFirstResponder()
        } else if textField == passwordTextfield {
            originY = 0
            organizationTextfield.becomeFirstResponder()
        } else if textField == organizationTextfield {
            originY = -148
        }  else {
            originY = 0
            textField.resignFirstResponder()
        }
        
        UIView.animate(withDuration: 0.3, delay: 0.0, options: UIView.AnimationOptions.curveEaseIn, animations: { () -> Void in
            self.view.frame.origin.y = originY
        }, completion: { (finished) -> Void in})
        
        return true
    }
    
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        
        var originY: CGFloat = 0
        
        if textField == usernameTextfield {
            originY = 0
        } else if textField == passwordTextfield {
            originY = 0
        } else if textField == organizationTextfield {
            originY = 0
        } else {
            originY = 0
        }
        
        UIView.animate(withDuration: 0.3, delay: 0.0, options: UIView.AnimationOptions.curveEaseIn, animations: { () -> Void in
            self.view.frame.origin.y = originY
        }, completion: { (finished) -> Void in})
        
        return true
    }
}
