//
//  ConferenceButtonBar.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 16/10/20.
//

import Foundation

internal protocol ConferenceButtonBarDelegate: class {
    func speakerButtonPressed(_ sender: Any)
    func micButtonPressed(_ sender: Any)
    func cameraButtonPressed(_ sender: Any)
    func camSwitchButtonPressed(_ sender: Any)
    func hangupButtonPressed(_ sender: Any)
    func screenShareButtonPressed(_ sender: Any)
    func optionsButtonPressed(_ sender: Any)
}

class ConferenceButtonBar: UIView {
    private var configuration: AuviousConferenceConfiguration!
    
    //Buttons
    let speakerButton = ConferenceButton(type: .speakerON)
    let micButton = ConferenceButton(type: .micEnabled)
    let cameraButton = ConferenceButton(type: .camEnabled)
    let cameraSwitchButton = ConferenceButton(type: .camSwitch)
    let hangupButton = ConferenceButton(type: .hangup)
    let screenShareButton = ConferenceButton(type: .screenShareDisabled)
    let optionsButton = ConferenceButton(type: .options)
    
    let buttonSeparator = UIView(frame: .zero)
    
    //Container of the buttons
    internal var buttonStackView: UIStackView!
    
    weak var delegate: ConferenceButtonBarDelegate?
    
    init(configuration: AuviousConferenceConfiguration) {
        super.init(frame: .zero)
        
        self.configuration = configuration
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        layer.zPosition = 200
        
        //Respect client configuration
        if !configuration.enableSpeaker {
            speakerButton.type = .speakerOFF
        }
        
        //Create buttons handlers
        micButton.addTarget(self, action: #selector(self.micButtonPressed(_:)), for: .touchUpInside)
        cameraButton.addTarget(self, action: #selector(self.cameraButtonPressed(_:)), for: .touchUpInside)
        cameraSwitchButton.addTarget(self, action: #selector(self.camSwitchButtonPressed(_:)), for: .touchUpInside)
        hangupButton.addTarget(self, action: #selector(self.hangupButtonPressed(_:)), for: .touchUpInside)
        speakerButton.addTarget(self, action: #selector(self.speakerButtonPressed(_:)), for: .touchUpInside)
        screenShareButton.addTarget(self, action: #selector(self.screenShareButtonPressed(_:)), for: .touchUpInside)
        optionsButton.addTarget(self, action: #selector(self.optionsButtonPressed(_:)), for: .touchUpInside)
        
        //Add buttons according to the configuration
        var buttons: [ConferenceButton] = []
       
        if configuration.microphoneAvailable {
            buttons.append(micButton)
        }
        
        if configuration.cameraAvailable {
            buttons.append(cameraButton)
            buttons.append(cameraSwitchButton)
        }
        
        buttons.append(optionsButton)
        
//        if configuration.speakerAvailable {
//            buttons.append(speakerButton)
//        }
                
        //Stack view to hold the buttons
        buttonStackView = UIStackView(frame: .zero)
        buttonStackView.translatesAutoresizingMaskIntoConstraints = false
        buttonStackView.distribution = .equalSpacing
        buttonStackView.alignment = .center
        buttonStackView.spacing = 10
        buttonStackView.axis = .horizontal
        addSubview(buttonStackView)
        
        //Stack view constraints
        buttonStackView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 0).isActive = true
        buttonStackView.centerXAnchor.constraint(equalTo: centerXAnchor, constant: 0).isActive = true
        buttonStackView.heightAnchor.constraint(equalToConstant:55).isActive = true
        
        //Add buttons to stack view
        for b in buttons {
            buttonStackView.addArrangedSubview(b)
            b.widthAnchor.constraint(equalToConstant: 55).isActive = true
            b.heightAnchor.constraint(equalToConstant: 55).isActive = true
        }
        
        let separatorSpacer = makeSeparatorSpacer()
        buttonStackView.addArrangedSubview(separatorSpacer)

        buttonStackView.addArrangedSubview(hangupButton)
        hangupButton.widthAnchor.constraint(equalToConstant: 55).isActive = true
        hangupButton.heightAnchor.constraint(equalToConstant: 55).isActive = true
        
        //Add hangup button
//        addSubview(hangupButton)
//        hangupButton.widthAnchor.constraint(equalToConstant: 50).isActive = true
//        hangupButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
//        hangupButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10).isActive = true
//        hangupButton.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 0).isActive = true
    }
    
    private func makeSeparatorSpacer() -> UIView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        let leftSpacer = UIView()
        let rightSpacer = UIView()
        [leftSpacer, rightSpacer].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                $0.widthAnchor.constraint(equalToConstant: 3)
            ])
        }

        let separator = UIView()
        separator.backgroundColor = .lightGray
        separator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            separator.widthAnchor.constraint(equalToConstant: 1),
            separator.heightAnchor.constraint(equalToConstant: 24)
        ])

        stack.addArrangedSubview(leftSpacer)
        stack.addArrangedSubview(separator)
        stack.addArrangedSubview(rightSpacer)

        return stack
    }
    
    //MARK:-
    //MARK: Actions
    //MARK:-
    
    @objc private func speakerButtonPressed(_ sender: Any) {
        delegate?.speakerButtonPressed(sender)
    }
    
    @objc private func micButtonPressed(_ sender: Any) {
        delegate?.micButtonPressed(sender)
    }
    
    @objc private func cameraButtonPressed(_ sender: Any) {
        delegate?.cameraButtonPressed(sender)
    }
    
    @objc private func camSwitchButtonPressed(_ sender: Any) {
        delegate?.camSwitchButtonPressed(sender)
    }
    
    @objc private func hangupButtonPressed(_ sender: Any) {
        delegate?.hangupButtonPressed(sender)
    }
    
    @objc private func screenShareButtonPressed(_ sender: Any) {
        delegate?.screenShareButtonPressed(sender)
    }
    
    @objc func optionsButtonPressed(_ sender: Any) {
        delegate?.optionsButtonPressed(sender)
    }
    
    func resetOptionsButton() {
        optionsButton.type = .options
    }
    
    internal func conferenceOnHold(_ flag: Bool) {
        speakerButton.alpha = flag ? 0.5 : 1
        micButton.alpha = flag ? 0.5 : 1
        cameraButton.alpha = flag ? 0.5 : 1
        cameraSwitchButton.alpha = flag ? 0.5 : 1
        screenShareButton.alpha = flag ? 0.5 : 1
        
        speakerButton.isUserInteractionEnabled = !flag
        micButton.isUserInteractionEnabled = !flag
        cameraButton.isUserInteractionEnabled = !flag
        cameraSwitchButton.isUserInteractionEnabled = !flag
        screenShareButton.isUserInteractionEnabled = !flag
    }
}
