//
//  ConferenceButtonBar.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 16/10/20.
//

import Foundation

internal protocol ConferenceButtonBarDelegate: class {
    func micButtonPressed(_ sender: Any)
    func cameraButtonPressed(_ sender: Any)
    func camSwitchButtonPressed(_ sender: Any)
    func hangupButtonPressed(_ sender: Any)
}

class ConferenceButtonBar: UIView {
    
    //Buttons
    let micButton = ConferenceButton(type: .micEnabled)
    let cameraButton = ConferenceButton(type: .camEnabled)
    let cameraSwitchButton = ConferenceButton(type: .camSwitch)
    let hangupButton = ConferenceButton(type: .hangup)
    
    //Container of the buttons
    internal var buttonStackView: UIStackView!
    
    weak var delegate: ConferenceButtonBarDelegate?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
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
        
        //Create buttons handlers
        micButton.addTarget(self, action: #selector(self.micButtonPressed(_:)), for: .touchUpInside)
        cameraButton.addTarget(self, action: #selector(self.cameraButtonPressed(_:)), for: .touchUpInside)
        cameraSwitchButton.addTarget(self, action: #selector(self.camSwitchButtonPressed(_:)), for: .touchUpInside)
        hangupButton.addTarget(self, action: #selector(self.hangupButtonPressed(_:)), for: .touchUpInside)
        let buttons: [ConferenceButton] = [micButton, cameraButton, cameraSwitchButton, hangupButton]
        
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
        micButton.alpha = flag ? 0.5 : 1
        cameraButton.alpha = flag ? 0.5 : 1
        cameraSwitchButton.alpha = flag ? 0.5 : 1
        
        micButton.isUserInteractionEnabled = !flag
        cameraButton.isUserInteractionEnabled = !flag
        cameraSwitchButton.isUserInteractionEnabled = !flag
    }
}
