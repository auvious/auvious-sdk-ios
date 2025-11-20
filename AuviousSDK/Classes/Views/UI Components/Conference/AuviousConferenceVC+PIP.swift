//
//  AuviousConferenceVC+PIP.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 19/11/25.
//

import Foundation

extension AuviousConferenceVCNew {
    
    func minimizeToPiP() {
        screenMode = .pip
        
        let screenBounds = view.bounds
        let pipWidth: CGFloat = screenMode.width
        let pipHeight: CGFloat = screenMode.height
        let margin: CGFloat = 20
        
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut], animations: {
            self.view.frame = CGRect(
                x: screenBounds.width - pipWidth - margin,
                y: screenBounds.height - pipHeight - margin,
                width: pipWidth,
                height: pipHeight
            )
            self.view.layer.cornerRadius = 12
            self.view.layer.masksToBounds = true
        })
        
        // Add gestures
        addDragGesture(to: view)
        addTapGestures(to: view)
    }
    
    func enlargePip() {
        screenMode = .expandedPip
        
        let screenBounds = view.bounds
        let pipWidth: CGFloat = screenMode.width
        let pipHeight: CGFloat = screenMode.height
        let margin: CGFloat = 20
        
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut], animations: {
            self.view.frame = CGRect(
                x: screenBounds.width - pipWidth - margin,
                y: screenBounds.height - pipHeight - margin,
                width: pipWidth,
                height: pipHeight
            )
            self.view.layer.cornerRadius = 12
            self.view.layer.masksToBounds = true
        })
    }
    
    func restoreFromPiP(childVC: UIViewController) {
        let screenBounds = view.bounds
        
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut], animations: {
            childVC.view.frame = screenBounds
            childVC.view.layer.cornerRadius = 0
        })
    }
    
}
