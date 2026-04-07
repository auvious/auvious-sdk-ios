//
//  AuviousConferenceVC+Gesture.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 19/11/25.
//

import Foundation

extension AuviousConferenceVCNew {
    
    //Toggles the gestures so that they only work outside fullscreen mode
    func updateGestureState(for mode: ScreenMode) {
        let enabled = mode != .fullScreen
        tapGesture?.isEnabled = enabled
        doubleTapGesture?.isEnabled = enabled
        panGesture?.isEnabled = enabled
    }
    
    //Draggable pip view
    func addDragGesture(to view: UIView) {
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        view.addGestureRecognizer(panGesture)
        view.isUserInteractionEnabled = true
    }
    
    //Tappable pip view
    func addTapGestures(to view: UIView) {
        tapGesture = UITapGestureRecognizer(target: self, action: #selector(handlePiPTap(_:)))
        tapGesture.numberOfTapsRequired = 1
        
        doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handlePiPDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        
        tapGesture.require(toFail: doubleTapGesture)
        
        view.addGestureRecognizer(tapGesture)
        view.addGestureRecognizer(doubleTapGesture)
    }
    
    @objc func handlePiPDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard let pipView = gesture.view else { return }
        guard pipView.superview != nil else { return }

        //Remove sharing border and corner radius before layout transition
        view.layer.borderWidth = 0
        pipView.layer.cornerRadius = 0

        //Setting screenMode triggers createConstraints() which animates
        //the layout transition to fullScreen via constraints
        screenMode = .fullScreen
    }
    
    @objc func handlePiPTap(_ gesture: UITapGestureRecognizer) {
        guard let pipView = gesture.view,
              let container = pipView.superview else { return }

        let newSize: CGSize
        switch screenMode {
        case .pip:
            newSize = CGSize(width: ScreenMode.expandedPip.width, height: ScreenMode.expandedPip.height)
            screenMode = .expandedPip
        case .expandedPip:
            newSize = CGSize(width: ScreenMode.pip.width, height: ScreenMode.pip.height)
            screenMode = .pip
        default:
            return
        }

        // Get current anchor corner
        let corner = currentCorner ?? closestCorner(for: pipView)

        // Calculate new center using safe area & keyboard
        let newCenter = pipAnchorPoint(for: corner, viewSize: newSize, in: container)

        UIView.animate(withDuration: 0.3) {
            pipView.bounds.size = newSize
            pipView.center = newCenter
            pipView.setNeedsLayout()
            pipView.layoutIfNeeded()
        }
    }
    
    func closestCorner(for pipView: UIView) -> Corner {
        guard let container = pipView.superview else { return .bottomRight }

        let screenMidX = container.bounds.midX
        let screenMidY = container.bounds.midY

        let center = pipView.center
        let isLeft = center.x < screenMidX
        let isTop = center.y < screenMidY

        switch (isLeft, isTop) {
        case (true, true): return .topLeft
        case (false, true): return .topRight
        case (true, false): return .bottomLeft
        case (false, false): return .bottomRight
        }
    }
    
    //MARK: Drag gesture
    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard screenMode != .fullScreen else { return }
        guard let pipView = gesture.view else { return }
        let translation = gesture.translation(in: view)

        switch gesture.state {
        case .changed:
            pipView.center = CGPoint(
                x: pipView.center.x + translation.x,
                y: pipView.center.y + translation.y
            )
            gesture.setTranslation(.zero, in: view)

        case .ended, .cancelled:
            snapToNearestCorner(pipView)

        default:
            break
        }
    }

    enum Corner {
        case topLeft, topRight, bottomLeft, bottomRight
    }
    
    func pipAnchorPoint(for corner: Corner, viewSize: CGSize, in container: UIView) -> CGPoint {
        let margin: CGFloat = 20
        let containerSize = container.bounds.size

        var bottomY = containerSize.height - viewSize.height / 2 - margin

        if let keyboardFrame = currentKeyboardFrame {
            let kbFrameInView = container.convert(keyboardFrame, from: nil)
            bottomY = min(bottomY, kbFrameInView.origin.y - viewSize.height / 2 - margin)
        }
        
        let safeTop = (container.window?.safeAreaInsets.top ?? container.safeAreaInsets.top)
        let topY = safeTop + margin + viewSize.height / 2
        
        print("safeTop: \(safeTop), topY: \(topY)")
        
        let leftX = margin + viewSize.width / 2
        let rightX = containerSize.width - margin - viewSize.width / 2

        switch corner {
        case .topLeft:
            return CGPoint(x: leftX, y: topY)
        case .topRight:
            return CGPoint(x: rightX, y: topY)
        case .bottomLeft:
            return CGPoint(x: leftX, y: bottomY)
        case .bottomRight:
            return CGPoint(x: rightX, y: bottomY)
        }
    }
    
    func snapToNearestCorner(_ pipView: UIView) {
        guard let container = pipView.superview else { return }
        let viewSize = pipView.bounds.size
        let margin: CGFloat = 20
        let containerSize = container.bounds.size

        // 🧠 Determine the Y for bottom corners
        var bottomY = containerSize.height - viewSize.height / 2 - margin
        if let keyboardFrame = currentKeyboardFrame {
            let kbFrameInView = container.convert(keyboardFrame, from: nil)
            bottomY = kbFrameInView.origin.y - viewSize.height / 2 - margin
        }

        let safeTop = container.safeAreaInsets.top
        let topY = safeTop + viewSize.height / 2
        
        // All four snap points
        let cornerCenters: [(Corner, CGPoint)] = [
            (.topLeft, CGPoint(x: margin + viewSize.width / 2, y: topY)),
            (.topRight, CGPoint(x: containerSize.width - margin - viewSize.width / 2, y: topY)),
            (.bottomLeft, CGPoint(x: margin + viewSize.width / 2, y: bottomY)),
            (.bottomRight, CGPoint(x: containerSize.width - margin - viewSize.width / 2, y: bottomY))
        ]

        // Pick closest
        let currentCenter = pipView.center
        let (nearestCorner, targetCenter) = cornerCenters.min(by: {
            distance(from: currentCenter, to: $0.1) < distance(from: currentCenter, to: $1.1)
        }) ?? (.bottomRight, CGPoint(x: 0, y: 0))

        currentCorner = nearestCorner

        UIView.animate(withDuration: 0.3) {
            pipView.center = targetCenter
        }
    }

    private func distance(from p1: CGPoint, to p2: CGPoint) -> CGFloat {
        hypot(p1.x - p2.x, p1.y - p2.y)
    }
}
