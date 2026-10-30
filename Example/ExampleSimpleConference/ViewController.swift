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

    private struct FormSection {
        let title: String?
        let footer: String?
        let cells: [UITableViewCell]
    }

    //Form controls
    private let modeControl = UISegmentedControl(items: ["Video call", "Co-browse"])
    private let ticketTextfield = UITextField()
    private let participantTextfield = UITextField()
    private let environmentButton = UIButton()
    private let conferenceTextfield = UITextField()
    private let callModeButton = UIButton()
    private let speakerEnabledSwitch = UISwitch()
    private let backgroundAudioSwitch = UISwitch()
    private let cameraSwitch = UISwitch()
    private let micSwitch = UISwitch()
    private let speakerSwitch = UISwitch()
    private let pipSwitch = UISwitch()
    private let screenSharingSwitch = UISwitch()
    private let cobrowseInCallSwitch = UISwitch()
    private let arPointerSwitch = UISwitch()
    private let maskMarkedViewsSwitch = UISwitch()
    private let maskIdentifiersSwitch = UISwitch()
    private let maskClassesSwitch = UISwitch()
    private let maskSecureFieldsSwitch = UISwitch()
    private let maskAllTextInputsSwitch = UISwitch()
    private let maskHintsSwitch = UISwitch()
    private let debugMasksSwitch = UISwitch()
    private let callButton = UIButton()

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let bottomBar = UIView()

    //Sections shown in both modes, then the ones only the video call or co-browse needs
    private var commonSections: [FormSection] = []
    private var callSections: [FormSection] = []
    private var cobrowseSections: [FormSection] = []

    private var visibleSections: [FormSection] {
        return commonSections + (isCobrowseMode ? cobrowseSections : callSections)
    }

    private let environments = [
        (title: "PROD", host: "auvious.video"),
        (title: "PROD US", host: "us.auvious.video"),
        (title: "PROD AU", host: "au.auvious.video"),
        (title: "PROD ME", host: "me.auvious.video"),
        (title: "PROD IN", host: "in.auvious.video"),
        (title: "PROD UAE", host: "uae.auvious.video"),
        (title: "DEV", host: "dev.auvious.video"),
        (title: "STG", host: "stg.auvious.video"),
    ]
    private lazy var selectedEnvironment = environments.firstIndex { $0.title == "DEV" } ?? 0

    private let callModes: [(title: String, mode: AuviousCallMode)] = [
        ("Audio", .audio),
        ("Video", .video),
        ("Audio & video", .audioVideo),
    ]
    private var selectedCallMode = 2

    var vc: AuviousConferenceVCNew!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground

        configureControls()
        buildSections()
        setupTableView()
        setupBottomBar()
        updateCallButton()

        // hard code values for faster debugging
        ticketTextfield.text = ""
        conferenceTextfield.text = "" // optional

        checkPermissions()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        //Lets the last rows scroll clear of the call button (and the keyboard)
        let covered = max(0, tableView.frame.maxY - bottomBar.frame.minY - view.safeAreaInsets.bottom)
        if tableView.contentInset.bottom != covered {
            tableView.contentInset.bottom = covered
            tableView.verticalScrollIndicatorInsets.bottom = covered
        }
    }

    // MARK: - Form

    private func configureControls() {
        modeControl.selectedSegmentIndex = 0
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)

        configure(ticketTextfield, placeholder: "Required")
        ticketTextfield.autocapitalizationType = .none
        ticketTextfield.returnKeyType = .next

        configure(participantTextfield, placeholder: "Optional")
        participantTextfield.textContentType = .name
        participantTextfield.autocapitalizationType = .words

        configure(conferenceTextfield, placeholder: "Create or join")
        conferenceTextfield.autocapitalizationType = .none

        configurePopUp(environmentButton, options: environments.map { ($0.title, $0.host) }, selected: selectedEnvironment) { [weak self] index in
            self?.selectedEnvironment = index
        }
        configurePopUp(callModeButton, options: callModes.map { ($0.title, nil) }, selected: selectedCallMode) { [weak self] index in
            self?.selectedCallMode = index
        }

        for toggle in [speakerEnabledSwitch, cameraSwitch, micSwitch, speakerSwitch, pipSwitch, screenSharingSwitch, cobrowseInCallSwitch, arPointerSwitch] {
            toggle.isOn = true
        }

        //Start from the SDK defaults
        let maskingDefaults = AuviousMaskingRules()
        maskMarkedViewsSwitch.isOn = CobrowseDemoSettings.marksViews
        maskIdentifiersSwitch.isOn = true
        maskClassesSwitch.isOn = true
        maskSecureFieldsSwitch.isOn = maskingDefaults.maskSecureTextFields
        maskAllTextInputsSwitch.isOn = maskingDefaults.maskAllTextInputs
        maskHintsSwitch.isOn = AuviousCobrowseConfiguration(ticket: "", baseEndpoint: "", mqttEndpoint: "").showsMaskHints
        debugMasksSwitch.isOn = AuviousCobrowse.shared.debugHighlightMasks

        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.buttonSize = .large
        config.imagePadding = 8
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .preferredFont(forTextStyle: .headline)
            return attributes
        }
        callButton.configuration = config
        callButton.addTarget(self, action: #selector(callButtonPressed(_:)), for: .touchUpInside)
    }

    private func buildSections() {
        commonSections = [
            FormSection(title: nil, footer: nil, cells: [modeCell()]),
            FormSection(title: "Session", footer: nil, cells: [
                row("Ticket", ticketTextfield),
                row("Name", participantTextfield),
                row("Environment", environmentButton),
            ]),
        ]
        callSections = [
            FormSection(title: "Call", footer: nil, cells: [
                row("Conference", conferenceTextfield),
                row("Call mode", callModeButton),
                row("Audio output to speaker", speakerEnabledSwitch),
                row("Background audio", backgroundAudioSwitch),
            ]),
            FormSection(title: "Call controls", footer: "Buttons available during the call.", cells: [
                row("Camera", cameraSwitch),
                row("Microphone", micSwitch),
                row("Speaker", speakerSwitch),
                row("Picture in picture", pipSwitch),
                row("Screen sharing", screenSharingSwitch),
            ]),
            FormSection(title: "AR pointer", footer: "The agent can point and draw on your camera or on your shared screen, and you can annotate back.", cells: [
                row("Allow AR pointer", arPointerSwitch),
            ]),
            FormSection(title: "Co-browse", footer: "The agent can ask to see this app during the call. While you share, the call shrinks to picture in picture. Masking follows the rules in Co-browse mode.", cells: [
                row("Allow co-browse in the call", cobrowseInCallSwitch),
            ]),
        ]
        cobrowseSections = [
            FormSection(title: "Masking", footer: "Masked views are blacked out for the agent. Each rule can be turned off to see what it masks in the sample form. Hints outline masked views on your screen; highlight also labels the rule that matched.", cells: [
                row("Marked views (auviousMasked)", maskMarkedViewsSwitch),
                row("Accessibility identifiers", maskIdentifiersSwitch),
                row("View classes", maskClassesSwitch),
                row("Mask password fields", maskSecureFieldsSwitch),
                row("Mask all text inputs", maskAllTextInputsSwitch),
                row("Show mask hints", maskHintsSwitch),
                row("Highlight masks (debug)", debugMasksSwitch),
            ]),
        ]
    }

    private func setupTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsSelection = false
        tableView.keyboardDismissMode = .interactive
        tableView.backgroundColor = .clear
        //Grouped tables leave an empty gap on top when there is no header view
        tableView.tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: CGFloat.leastNonzeroMagnitude))
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    /// Keeps the call button above the home indicator, and above the keyboard while typing
    private func setupBottomBar() {
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBar)

        if #available(iOS 26.0, *) {
            //The rows scrolling underneath fade out like they do under system bars
            let edgeEffect = UIScrollEdgeElementContainerInteraction()
            edgeEffect.scrollView = tableView
            edgeEffect.edge = .bottom
            bottomBar.addInteraction(edgeEffect)
        } else {
            let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
            blur.translatesAutoresizingMaskIntoConstraints = false
            bottomBar.addSubview(blur)
            NSLayoutConstraint.activate([
                blur.topAnchor.constraint(equalTo: bottomBar.topAnchor),
                blur.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor),
                blur.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
                blur.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            ])
        }

        callButton.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(callButton)

        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            callButton.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 12),
            callButton.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8),
            //Lines up with the edges of the grouped sections
            callButton.leadingAnchor.constraint(equalTo: tableView.layoutMarginsGuide.leadingAnchor),
            callButton.trailingAnchor.constraint(equalTo: tableView.layoutMarginsGuide.trailingAnchor),
            callButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
        ])
    }

    private func configure(_ field: UITextField, placeholder: String) {
        field.placeholder = placeholder
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.textAlignment = .right
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.clearButtonMode = .whileEditing
        field.returnKeyType = .done
        field.delegate = self
    }

    /// A button that shows the selected option and opens a menu with all of them
    private func configurePopUp(_ button: UIButton, options: [(title: String, subtitle: String?)], selected: Int, onSelect: @escaping (Int) -> Void) {
        var config = UIButton.Configuration.plain()
        if #available(iOS 16.0, *) {
            config.indicator = .popup
        }
        config.baseForegroundColor = .secondaryLabel
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 0)
        button.configuration = config
        button.contentHorizontalAlignment = .trailing
        button.menu = UIMenu(children: options.enumerated().map { index, option in
            UIAction(title: option.title, subtitle: option.subtitle, state: index == selected ? .on : .off) { _ in
                onSelect(index)
            }
        })
        button.showsMenuAsPrimaryAction = true
        button.changesSelectionAsPrimaryAction = true
    }

    /// The "Video call | Co-browse" switch, sitting on the background above the sections
    private func modeCell() -> UITableViewCell {
        let cell = UITableViewCell()
        cell.backgroundConfiguration = .clear()

        modeControl.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(modeControl)

        NSLayoutConstraint.activate([
            modeControl.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
            modeControl.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
            modeControl.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
            modeControl.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
        ])
        return cell
    }

    /// A row with a title and a control at the trailing edge. Text fields stretch to fill
    /// the row, so tapping anywhere next to the title starts typing.
    private func row(_ title: String, _ control: UIView) -> UITableViewCell {
        let cell = UITableViewCell()

        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false

        if !(control is UIButton) {
            control.accessibilityLabel = title
        }
        control.translatesAutoresizingMaskIntoConstraints = false

        cell.contentView.addSubview(label)
        cell.contentView.addSubview(control)

        let margins = cell.contentView.layoutMarginsGuide
        let fillRow = control.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 16)
        fillRow.priority = UILayoutPriority(251)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            label.topAnchor.constraint(equalTo: margins.topAnchor),
            label.bottomAnchor.constraint(equalTo: margins.bottomAnchor),
            control.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 16),
            control.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            control.topAnchor.constraint(greaterThanOrEqualTo: cell.contentView.topAnchor),
            fillRow,
        ])
        return cell
    }

    // MARK: - Mode

    private var isCobrowseMode: Bool {
        return modeControl.selectedSegmentIndex == 1
    }

    /// Swaps the call sections for the co-browse ones (and back) below the session details
    @objc private func modeChanged() {
        let callIndexes = IndexSet(integersIn: commonSections.count..<commonSections.count + callSections.count)
        let cobrowseIndexes = IndexSet(integersIn: commonSections.count..<commonSections.count + cobrowseSections.count)
        tableView.performBatchUpdates {
            if isCobrowseMode {
                tableView.deleteSections(callIndexes, with: .fade)
                tableView.insertSections(cobrowseIndexes, with: .fade)
            } else {
                tableView.deleteSections(cobrowseIndexes, with: .fade)
                tableView.insertSections(callIndexes, with: .fade)
            }
        }
        updateCallButton()
    }

    private func updateCallButton() {
        callButton.configuration?.title = isCobrowseMode ? "Start co-browse" : "Call now"
        callButton.configuration?.image = UIImage(systemName: isCobrowseMode ? "rectangle.inset.filled.and.person.filled" : "video.fill")
    }

    //MARK: Actions

    @objc func callButtonPressed(_ sender: Any) {
        if validateForm() {
            let ticket = ticketTextfield.text!
            let conferenceName = conferenceTextfield.text!.trimmingCharacters(in: .whitespacesAndNewlines)
            let participantName = participantTextfield.text
            let selectedEnv = environments[selectedEnvironment].host
            let baseEndpoint: String = "https://\(selectedEnv)/"
            let mqttEndpoint: String = selectedEnv

            if isCobrowseMode {
                startCobrowse(ticket: ticket, participantName: participantName, baseEndpoint: baseEndpoint, mqttEndpoint: mqttEndpoint)
                return
            }

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
            conf.callMode = callModes[selectedCallMode].mode
            conf.cameraAvailable = self.cameraSwitch.isOn
            conf.microphoneAvailable = self.micSwitch.isOn
            conf.speakerAvailable = self.speakerSwitch.isOn
            conf.pipAvailable = self.pipSwitch.isOn
            conf.screenSharingAvailable = self.screenSharingSwitch.isOn
            conf.backgroundAudioEnabled = self.backgroundAudioSwitch.isOn
            conf.cobrowseAvailable = self.cobrowseInCallSwitch.isOn
            conf.arPointerAvailable = self.arPointerSwitch.isOn
            conf.cobrowseMasking = maskingRules()
            conf.cobrowseShowsMaskHints = maskHintsSwitch.isOn
            AuviousCobrowse.shared.debugHighlightMasks = debugMasksSwitch.isOn
            //The ticket is on screen behind the call's PiP
            ticketTextfield.auviousMasked = maskMarkedViewsSwitch.isOn ? true : nil

            view.endEditing(true)
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

    //While co-browsing the call floats above the app, so the sample form can be opened like a standalone co-browse
    func onCobrowseStarted() {
        navigationController?.setNavigationBarHidden(false, animated: true)
        navigationController?.pushViewController(CobrowseDemoViewController(), animated: true)
    }

    //The call goes back into this screen
    func onCobrowseEnded() {
        navigationController?.popToViewController(self, animated: true)
        navigationController?.setNavigationBarHidden(true, animated: true)
    }

    func onConferenceError(_ error: AuviousSDKGenericError) {
        self.vc.showAlert(title: "Error", msg: error.localizedDescription, onSuccess: {
            self.dismissAuviousUI(childVC: self.vc)
        })
    }

    // MARK: Co-browse

    private func startCobrowse(ticket: String, participantName: String?, baseEndpoint: String, mqttEndpoint: String) {
        var configuration = AuviousCobrowseConfiguration(ticket: ticket, baseEndpoint: baseEndpoint, mqttEndpoint: mqttEndpoint)
        if let name = participantName, !name.isEmpty {
            configuration.participantName = name
        }

        configuration.masking = maskingRules()
        configuration.showsMaskHints = maskHintsSwitch.isOn
        AuviousCobrowse.shared.debugHighlightMasks = debugMasksSwitch.isOn

        view.endEditing(true)
        AuviousCobrowse.shared.start(configuration: configuration, delegate: self)

        //Open a sample screen with masked fields; the session keeps running while navigating
        navigationController?.pushViewController(CobrowseDemoViewController(), animated: true)
    }

    /// The masking rules picked in the Masking section, for a co-browse session or a call
    private func maskingRules() -> AuviousMaskingRules {
        var masking = AuviousMaskingRules()

        //Mask by name: any view with these identifiers, and every CardNumberField
        if maskIdentifiersSwitch.isOn {
            masking.accessibilityIdentifiers = ["payment.iban", "card.*"]
        }
        if maskClassesSwitch.isOn {
            masking.viewClasses = [CardNumberField.self]
        }
        //The sample form reads this when it builds its fields
        CobrowseDemoSettings.marksViews = maskMarkedViewsSwitch.isOn

        masking.maskSecureTextFields = maskSecureFieldsSwitch.isOn
        masking.maskAllTextInputs = maskAllTextInputsSwitch.isOn
        return masking
    }

    // MARK: Helpers

    private func validateForm() -> Bool {
        guard let ticket = ticketTextfield.text, !ticket.isEmpty else {
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
    /// The navigation bar is hidden while the call is up, so the call's safe area starts at the
    /// top of the screen and its banners sit under the status bar, not under the bar.
    private func presentAuviousUI(childVC: UIViewController) {
        navigationController?.setNavigationBarHidden(true, animated: true)

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

        navigationController?.setNavigationBarHidden(false, animated: true)

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

extension ViewController: AuviousCobrowseDelegate {

    func cobrowse(didChangeState state: AuviousCobrowseState) {
        print("Co-browse state: \(state)")
    }

    func cobrowse(didFailWith error: AuviousSDKGenericError) {
        navigationController?.popToRootViewController(animated: true)
        showAlert(title: "Co-browse", msg: error.localizedDescription)
    }

    func cobrowseDidEnd(reason: AuviousCobrowseEndReason) {
        if reason != .failed {
            navigationController?.popToRootViewController(animated: true)
        }
    }
}

extension ViewController: UITextFieldDelegate {
    // Called when return key is pressed
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField == ticketTextfield {
            participantTextfield.becomeFirstResponder()
        } else {
            textField.resignFirstResponder() // dismiss keyboard
        }
        return true
    }
}

extension ViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        return visibleSections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return visibleSections[section].cells.count
    }

    //The form is small and fixed, so every row is built once and handed back as is
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        return visibleSections[indexPath.section].cells[indexPath.row]
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return visibleSections[section].title
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return visibleSections[section].footer
    }
}

extension ViewController: UITableViewDelegate {

    //Keeps the mode switch close to the title instead of a full empty header above it
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return section == 0 ? 8 : UITableView.automaticDimension
    }
}
