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
}

class ConferenceButtonBar: UIView {
    private var configuration: AuviousConferenceConfiguration!
    
    //Buttons
    let speakerButton = ConferenceButton(type: .speakerON)
    let micButton = ConferenceButton(type: .micEnabled)
    let cameraButton = ConferenceButton(type: .camEnabled)
    let cameraSwitchButton = ConferenceButton(type: .camSwitch)
    let hangupButton = ConferenceButton(type: .hangup)
    
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
        
        //Add buttons according to the configuration
        var buttons: [ConferenceButton] = []
       
        if configuration.microphoneAvailable {
            buttons.append(micButton)
        }
        if configuration.speakerAvailable {
            buttons.append(speakerButton)
        }
        if configuration.cameraAvailable {
            buttons.append(cameraButton)
            buttons.append(cameraSwitchButton)
        }
    
        buttons.append(hangupButton)
        
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
            b.widthAnchor.constraint(equalToConstant: 50).isActive = true
            b.heightAnchor.constraint(equalToConstant: 50).isActive = true
        }
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
    
    internal func conferenceOnHold(_ flag: Bool) {
        speakerButton.alpha = flag ? 0.5 : 1
        micButton.alpha = flag ? 0.5 : 1
        cameraButton.alpha = flag ? 0.5 : 1
        cameraSwitchButton.alpha = flag ? 0.5 : 1
        
        speakerButton.isUserInteractionEnabled = !flag
        micButton.isUserInteractionEnabled = !flag
        cameraButton.isUserInteractionEnabled = !flag
        cameraSwitchButton.isUserInteractionEnabled = !flag
    }
}
