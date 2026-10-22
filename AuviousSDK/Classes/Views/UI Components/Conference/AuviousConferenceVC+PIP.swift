//
//  AuviousConferenceVC+PIP.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 19/11/25.
//

import Foundation

extension AuviousConferenceVCNew {
        
    func minimizeToPiP() {
        guard let pipView = self.view, let container = pipView.superview else { return }

        let oldSize = pipView.frame.size
        let newSize = CGSize(width: ScreenMode.pip.width, height: ScreenMode.pip.height)
        let dx = newSize.width - oldSize.width
        let dy = newSize.height - oldSize.height

        let corner: Corner
        if oldSize == UIScreen.main.bounds.size {
            //While co-browsing the bottom belongs to the co-browse dock
            corner = cobrowseSession != nil ? .topRight : .bottomRight
        } else {
            corner = closestCorner(for: pipView)
        }

        // Adjust center to keep anchor point consistent
        var center = pipView.center
        switch corner {
        case .topLeft:
            center.x += dx / 2
            center.y += dy / 2
        case .topRight:
            center.x -= dx / 2
            center.y += dy / 2
        case .bottomLeft:
            center.x += dx / 2
            center.y -= dy / 2
        case .bottomRight:
            center.x -= dx / 2
            center.y -= dy / 2
        }
        
        currentCorner = corner
        
        // Recalculate final center using shared logic
        let finalCenter = pipAnchorPoint(for: corner, viewSize: newSize, in: container)

        screenMode = .pip

        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut], animations: {
            pipView.bounds.size = newSize
            pipView.center = finalCenter
            pipView.layer.cornerRadius = 12
            pipView.layer.masksToBounds = true
            pipView.setNeedsLayout()
            pipView.layoutIfNeeded()
        })

        toggleSharingBorder(mode: AuviousConferenceSDK.sharedInstance.sharingMyScreen)
        addDragGesture(to: pipView)
        addTapGestures(to: pipView)
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
    
    func toggleSharingBorder(mode: Bool) {
        //Co-browse frames the whole screen instead of the PiP
        if mode && cobrowseSession == nil {
            view.layer.borderWidth = 4
            view.layer.borderColor = UIColor.red.cgColor
            view.layer.masksToBounds = false
        } else {
            view.layer.borderWidth = 0
        }
    }
    
    @objc func keyboardWillShow(_ notification: Notification) {
        //Only the floating PiP window moves out of the keyboard's way, never the full screen call
        guard screenMode != .fullScreen,
              let pipView = self.view,
              currentCorner == .bottomLeft || currentCorner == .bottomRight,
              let userInfo = notification.userInfo,
              let keyboardFrameScreen = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let container = pipView.superview else { return }
        
        currentKeyboardFrame = keyboardFrameScreen
        
        let keyboardFrameInView = container.convert(keyboardFrameScreen, from: nil)
        let margin: CGFloat = 12

        UIView.animate(withDuration: 0.3) {
            // Move just above the keyboard
            var frame = pipView.frame
            frame.origin.y = keyboardFrameInView.origin.y - frame.height - margin
            pipView.frame = frame
        }
    }
    
    @objc func keyboardWillHide(_ notification: Notification) {
        //iOS also sends this when nothing moved the PiP, e.g. when the app comes back after a screenshot.
        //Only a PiP that made way for the keyboard goes back to its corner.
        guard currentKeyboardFrame != nil else { return }
        currentKeyboardFrame = nil

        guard screenMode != .fullScreen,
              let pipView = self.view,
              let container = pipView.superview else { return }

        let center = pipAnchorPoint(for: currentCorner, viewSize: pipView.bounds.size, in: container)

        UIView.animate(withDuration: 0.3) {
            pipView.center = center
        }
    }
}
