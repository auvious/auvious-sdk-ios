//
//  ConferencePopoverVC.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 18/11/25.
//

import Foundation
import UIKit

//Delegation of popover button taps
protocol ConferencePopoverDelegate: class {
    func didPressPIPButton()
    func didPressShareScreenButton()
    func didPressSpeakerButton()
}

//Popover button (icon + text)
final class ConferencePopoverButton: UIButton {
    var type: ConferenceButtonType!
    
    init(type: ConferenceButtonType) {
        self.type = type
        
        super.init(frame: .zero)

        setTitle(type.title, for: .normal)
        let image = UIImage(podAssetName: type.imageName)?.withRenderingMode(.alwaysTemplate)
        setImage(image, for: .normal)

        self.backgroundColor = .clear
        self.tintColor = .black
        setTitleColor(.systemBlue, for: .normal)
        titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)

        // Layout
        contentHorizontalAlignment = .leading
        imageEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 18)
        titleEdgeInsets = UIEdgeInsets(top: 0, left: 18, bottom: 0, right: 0)

        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 8
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

//Popover with PIP/Share screen options
internal class ConferencePopoverVC: UIViewController {
    
    weak var delegate: ConferencePopoverDelegate?
    
    //Container of the buttons
    private var buttonStackView: UIStackView!
    
    //Buttons
    private var buttons: [ConferencePopoverButton] = []
    
    override var preferredContentSize: CGSize {
        get {
            //3 buttons
            if buttons.count == 3 {
                return CGSize(width: 200, height: 185)
            }
            
            //2 buttons
            return CGSize(width: 200, height: 112)//140)
            //return view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        }
        set {
            super.preferredContentSize = newValue
        }
    }
    
    init(buttons: [ConferencePopoverButton]) {
        self.buttons = buttons
        super.init(nibName: nil, bundle: Bundle(for: ConferencePopoverVC.self))
        
        //Listen for agent screen share notifications
        NotificationCenter.default.addObserver(self, selector: #selector(self.agentStoppedScreenShare(_:)), name: NSNotification.Name(rawValue: AuviousNotification.shared.agentStoppedScreenShare), object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.agentStartedScreenShare(_:)), name: NSNotification.Name(rawValue: AuviousNotification.shared.agentStartedScreenShare), object: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        
        for b in buttons {
            b.translatesAutoresizingMaskIntoConstraints = false
            
            if b.type == .speakerON {
                b.addTarget(self, action: #selector(self.pipButtonPressed(_:)), for: .touchUpInside)
            } else if b.type == .pip {
                b.addTarget(self, action: #selector(self.pipButtonPressed(_:)), for: .touchUpInside)
            } else if b.type == .screenShare {
                b.addTarget(self, action: #selector(self.shareScreenButtonPressed(_:)), for: .touchUpInside)
            }
        }
        
        //Stack view to hold the buttons
        buttonStackView = UIStackView(frame: .zero)
        buttonStackView.translatesAutoresizingMaskIntoConstraints = false
        buttonStackView.distribution = .fillEqually
        buttonStackView.alignment = .center
        buttonStackView.spacing = 12
        buttonStackView.axis = .vertical
        view.addSubview(buttonStackView)
        
        //Stack view constraints
        buttonStackView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor).isActive = true
        buttonStackView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor).isActive = true
        //buttonStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        buttonStackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10).isActive = true
        buttonStackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10).isActive = true
        
        //Add buttons to stack view
        for b in buttons {
            buttonStackView.addArrangedSubview(b)
            b.widthAnchor.constraint(equalToConstant: 180).isActive = true
            b.heightAnchor.constraint(equalToConstant: 45).isActive = true
        }
    }
    
    //Enable screen share button
    @objc func agentStoppedScreenShare(_ notification: Notification) {
        toggleScreenShareButton()
    }
    
    //Disable screen share button
    @objc func agentStartedScreenShare(_ notification: Notification) {
        toggleScreenShareButton()
    }
    
    @objc private func speakerButtonPressed(_ sender: Any) {
        delegate?.didPressSpeakerButton()
    }
    
    @objc private func pipButtonPressed(_ sender: Any) {
        delegate?.didPressPIPButton()
    }
    
    @objc private func shareScreenButtonPressed(_ sender: Any) {
        delegate?.didPressShareScreenButton()
    }
    
    private func toggleScreenShareButton() {
        if let shareButton = buttons.filter({$0.type == .screenShare}).first {
            shareButton.type = .screenShareDisabled
            shareButton.layer.opacity = 0.3
            shareButton.isUserInteractionEnabled = false
        } else if let shareButton = buttons.filter({$0.type == .screenShareDisabled}).first {
            shareButton.type = .screenShare
            shareButton.layer.opacity = 1
            shareButton.isUserInteractionEnabled = true
        }
    }
}

extension AuviousConferenceVCNew: UIPopoverPresentationControllerDelegate {
  
    public func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle { return .none }
    
    public func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
        self.isAnimatingPopover = false
    }
    
    public func popoverPresentationControllerShouldDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) -> Bool {
        self.buttonContainerView.optionsButtonPressed("")
        return true
    }
        
    func preparePopUp(sourceRect : CGRect, sourceView: UIView, vc: UIViewController) -> UIViewController {
        let popoverContentController = vc
        popoverContentController.modalPresentationStyle = .popover
        if let popoverPresentationController = popoverContentController.popoverPresentationController {
            popoverPresentationController.permittedArrowDirections = .init([.up,.down])
            popoverPresentationController.sourceView = sourceView
            popoverPresentationController.sourceRect = sourceRect
            popoverPresentationController.delegate = self
            return popoverContentController
        }
       
       return vc
    }
}
