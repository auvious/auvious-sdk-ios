//
//  ConferencePopoverVC.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 18/11/25.
//

import Foundation
import UIKit

protocol ConferencePopoverDelegate: class {
    func didPressPIPButton()
    func didPressShareScreenButton()
}

internal class ConferencePopoverVC: UIViewController {
    
    private var pipButton: UIButton = UIButton(frame: .zero)
    private var shareScreenButton: UIButton = UIButton(frame: .zero)
    
    weak var delegate: ConferencePopoverDelegate?
    
    //Container of the buttons
    private var buttonStackView: UIStackView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        
        pipButton.translatesAutoresizingMaskIntoConstraints = false
        pipButton.setTitle(NSLocalizedString("PIP", comment: ""), for: .normal)
        pipButton.addTarget(self, action: #selector(self.pipButtonPressed(_:)), for: .touchUpInside)
        pipButton.backgroundColor = .systemBlue
        
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
            b.widthAnchor.constraint(equalToConstant: 140).isActive = true
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
