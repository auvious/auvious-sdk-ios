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
}

//Popover button (icon + text)
final class ConferencePopoverButton: UIButton {
    init(title: String, iconName: String, backgroundColor: UIColor) {
        super.init(frame: .zero)

        setTitle(title, for: .normal)
        setImage(UIImage(podAssetName: iconName), for: .normal)

        self.backgroundColor = backgroundColor
        self.tintColor = .white
        setTitleColor(.white, for: .normal)
        titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)

        // Layout
        contentHorizontalAlignment = .leading
        imageEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 12)
        titleEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 0)

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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        
        let pipButton = ConferencePopoverButton(
            title: NSLocalizedString("Floating window", comment: ""),
            iconName: "camSwitch",
            backgroundColor: .systemBlue
        )
        
        pipButton.translatesAutoresizingMaskIntoConstraints = false
        pipButton.setTitle(NSLocalizedString("PIP", comment: ""), for: .normal)
        pipButton.addTarget(self, action: #selector(self.pipButtonPressed(_:)), for: .touchUpInside)
        pipButton.backgroundColor = .systemBlue
        
        let shareScreenButton = ConferencePopoverButton(
            title: NSLocalizedString("Share Screen", comment: ""),
            iconName: "camSwitch",
            backgroundColor: .systemPurple
        )
        
        shareScreenButton.translatesAutoresizingMaskIntoConstraints = false
        shareScreenButton.setTitle(NSLocalizedString("Share Screen", comment: ""), for: .normal)
        shareScreenButton.addTarget(self, action: #selector(self.shareScreenButtonPressed(_:)), for: .touchUpInside)
        shareScreenButton.backgroundColor = .systemPurple
        
        //Stack view to hold the buttons
        buttonStackView = UIStackView(frame: .zero)
        buttonStackView.translatesAutoresizingMaskIntoConstraints = false
        buttonStackView.distribution = .fill
        buttonStackView.alignment = .center
        buttonStackView.spacing = 5
        buttonStackView.axis = .vertical
        view.addSubview(buttonStackView)
        
        //Stack view constraints
        buttonStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        buttonStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        
        //Add buttons according to the configuration
        var buttons: [UIButton] = []
        buttons.append(pipButton)
        buttons.append(shareScreenButton)
        
        //Add buttons to stack view
        for b in buttons {
            buttonStackView.addArrangedSubview(b)
            b.widthAnchor.constraint(equalToConstant: 170).isActive = true
            b.heightAnchor.constraint(equalToConstant: 45).isActive = true
        }
    }
    
    @objc private func pipButtonPressed(_ sender: Any) {
        delegate?.didPressPIPButton()
    }
    
    @objc private func shareScreenButtonPressed(_ sender: Any) {
        delegate?.didPressShareScreenButton()
    }
}

extension UIViewController: UIPopoverPresentationControllerDelegate {
  
    public func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle { return .none }
    public func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {}
    public func popoverPresentationControllerShouldDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) -> Bool { return true }
        
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
