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
    @IBOutlet weak var environmentControl: UISegmentedControl!
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

    //Background audio switch (created programmatically)
    private let backgroundAudioSwitch = UISwitch()

    //Gradient
    private var gradientLayer = CAGradientLayer()

    var vc: AuviousConferenceVCNew!

    override func viewDidLoad() {
        super.viewDidLoad()

        usernameTextfield.delegate = self
        conferenceTextfield.delegate = self
        participantTextfield.delegate = self

        usernameTextfield.autocorrectionType = .no

        usernameTextfield.attributedPlaceholder = NSAttributedString(string: "Username", attributes: [NSAttributedString.Key.foregroundColor: UIColor.white.withAlphaComponent(0.7)])
        conferenceTextfield.attributedPlaceholder = NSAttributedString(string: "Conference to create/join", attributes: [NSAttributedString.Key.foregroundColor: UIColor.white.withAlphaComponent(0.7)])
        participantTextfield.attributedPlaceholder = NSAttributedString(string: "Participant name (optional)", attributes: [NSAttributedString.Key.foregroundColor: UIColor.white.withAlphaComponent(0.7)])

        usernameTextfield.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        conferenceTextfield.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        participantTextfield.backgroundColor = UIColor.black.withAlphaComponent(0.8)

        usernameTextfield.textColor = .white
        conferenceTextfield.textColor = .white
        participantTextfield.textColor = .white

        // hard code values for faster debugging
        usernameTextfield.text = ""
        conferenceTextfield.text = "" // optional

        gradientLayer.colors = [UIColor(red: 0/255, green: 31/255, blue: 122/255, alpha: 1).cgColor, UIColor(red: 51/255, green: 102/255, blue: 255/255, alpha: 1).cgColor]
        gradientLayer.setAngle(150)

        checkPermissions()
        callButton.layer.cornerRadius = 5.0

        setupConferenceOptionsScrollView()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
    }

    // MARK: - Conference options scroll view

    /// Moves the conference control switches (camera … screen sharing) from the
    /// storyboard layout into a scrollable list between the "audio output" row and
    /// the "Call Now" button, and appends the programmatic "background audio" row.
    private func setupConferenceOptionsScrollView() {
        // Find storyboard labels by their text so we can reparent them
        let storyboardLabels = view.subviews.compactMap { $0 as? UILabel }
        let headerLabel = storyboardLabels.first { $0.text == "Conference controls" }
        let cameraLabel = storyboardLabels.first { $0.text == "camera" }
        let micLabel = storyboardLabels.first { $0.text == "microphone" }
        let speakerLabel = storyboardLabels.first { $0.text == "speaker" }
        let pipLabel = storyboardLabels.first { $0.text == "pip" }
        let screenSharingLabel = storyboardLabels.first { $0.text == "screen sharing" }

        // Collect all items to move (removing from superview deactivates their storyboard constraints)
        let viewsToMove: [UIView?] = [
            headerLabel,
            cameraLabel, cameraSwitch,
            micLabel, micSwitch,
            speakerLabel, speakerSwitch,
            pipLabel, pipSwitch,
            screenSharingLabel, screenSharingSwitch,
        ]
        for v in viewsToMove { v?.removeFromSuperview() }

        // Build option rows: (label text, switch)
        let rows: [(String, UISwitch)] = [
            ("camera", cameraSwitch),
            ("microphone", micSwitch),
            ("speaker", speakerSwitch),
            ("pip", pipSwitch),
            ("screen sharing", screenSharingSwitch),
            ("background audio", backgroundAudioSwitch),
        ]

        // -- Scroll view --
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: speakerEnabledSwitch.bottomAnchor, constant: 15),
            scrollView.bottomAnchor.constraint(equalTo: callButton.topAnchor, constant: -10),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 10),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -10),
        ])

        // -- Stack view inside scroll view --
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])

        // -- Header --
        let header = headerLabel ?? {
            let l = UILabel()
            l.text = "Conference controls"
            l.font = .systemFont(ofSize: 19)
            l.textColor = .systemGray2
            return l
        }()
        header.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(header)

        // -- Option rows --
        for (title, toggle) in rows {
            let row = UIView()
            row.translatesAutoresizingMaskIntoConstraints = false

            let label = UILabel()
            label.text = title
            label.font = .systemFont(ofSize: 17)
            label.textColor = .black
            label.translatesAutoresizingMaskIntoConstraints = false

            toggle.translatesAutoresizingMaskIntoConstraints = false

            row.addSubview(label)
            row.addSubview(toggle)

            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                row.heightAnchor.constraint(equalToConstant: 31),
            ])

            stack.addArrangedSubview(row)
        }
    }

    //MARK: Actions

    @IBAction func switchToggled(_ sender: Any) {
        conferenceLabel.text = createConferenceSwitch.isOn ? "Create conference" : "Join conference"
    }

    @IBAction func callButtonPressed(_ sender: Any) {
        if validateForm() {
            let ticket = usernameTextfield.text!
            let conferenceName = conferenceTextfield.text!.trimmingCharacters(in: .whitespacesAndNewlines)
            let participantName = participantTextfield.text
            let environments = ["auvious.video", "dev.auvious.video", "stg.auvious.video"]
            let selectedEnv = environments[environmentControl.selectedSegmentIndex]
            let baseEndpoint: String = "https://\(selectedEnv)/"
            let mqttEndpoint: String = selectedEnv
           
            //New configuration approach
            var conf = AuviousConferenceConfiguration()
            conf.username = ticket
          
            if let name = participantName, !name.isEmpty {
                conf.participantName = name
            }

            conf.conference = conferenceName
            conf.baseEndpoint = baseEndpoint
            conf.mqttEndpoint = mqttEndpoint
//            conf.conferenceBackgroundColor = .black
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
            conf.backgroundAudioEnabled = self.backgroundAudioSwitch.isOn

            self.vc = AuviousConferenceVCNew(configuration: conf, delegate: self)
            presentAuviousUI(childVC: self.vc)
        }
    }

    // MARK: AuviousSimpleConferenceDelegate

    func onConferenceSuccess() {
        self.vc.showAlert(title: "Message", msg: "Conference completed successfully", onSuccess: {
            self.dismissAuviousUI(childVC: self.vc)
        })
    }

    func onConferenceError(_ error: AuviousSDKGenericError) {
        self.vc.showAlert(title: "Error", msg: error.localizedDescription, onSuccess: {
            self.dismissAuviousUI(childVC: self.vc)
        })
    }

    // MARK: Helpers

    private func validateForm() -> Bool {
        guard let username = usernameTextfield.text, !username.isEmpty else {
            showAlert(title: "Warning", msg: "Please enter your ticket")
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

    private func dismissAuviousUI(childVC: UIViewController) {
        // Make sure it's really a child
        guard childVC.parent == self else { return }

        let screenBounds = view.bounds

        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseIn], animations: {
            // Slide the view down off screen
            childVC.view.frame.origin.y = screenBounds.height
        }, completion: { _ in
            // Clean up after animation completes
            childVC.willMove(toParent: nil)
            childVC.view.removeFromSuperview()
            childVC.removeFromParent()
        })
    }
}

extension ViewController: UITextFieldDelegate {
    // Called when return key is pressed
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder() // dismiss keyboard
            return true
        }
}
