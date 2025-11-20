//
//  AuviousConferenceVC+Gesture.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 19/11/25.
//

import Foundation

extension AuviousConferenceVCNew {
    
    //Draggable pip view
    func addDragGesture(to view: UIView) {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        view.addGestureRecognizer(panGesture)
        view.isUserInteractionEnabled = true
    }
    
    //Tappable pip view
    func addTapGesture(to view: UIView) {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handlePiPTap(_:)))
        view.addGestureRecognizer(tapGesture)
    }
    
    @objc func handlePiPTap(_ gesture: UITapGestureRecognizer) {
        guard let pipView = gesture.view else { return }

        let isSmall = pipView.tag == 0
        pipView.tag = isSmall ? 1 : 0

        let smallSize = CGSize(width: ScreenMode.pip.width, height: ScreenMode.pip.height)
        let largeSize = CGSize(width: ScreenMode.expandedPip.width, height: ScreenMode.expandedPip.height)
        
        let oldSize = pipView.frame.size
        let newSize = isSmall ? largeSize : smallSize

        let dx = newSize.width - oldSize.width
        let dy = newSize.height - oldSize.height

        let corner = closestCorner(for: pipView)

        // Adjust center to preserve anchor corner
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

        UIView.animate(withDuration: 0.3) {
            pipView.bounds.size = newSize
            pipView.center = center
        }
    }
    
    enum Corner {
        case topLeft, topRight, bottomLeft, bottomRight
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

    func snapToNearestCorner(_ pipView: UIView) {
        guard let containerView = pipView.superview else { return }

        let screenSize = containerView.bounds.size
        let pipSize = pipView.frame.size
        let margin: CGFloat = 16

        let topLeft = CGPoint(x: margin + pipSize.width / 2, y: margin + pipSize.height / 2)
        let topRight = CGPoint(x: screenSize.width - margin - pipSize.width / 2, y: margin + pipSize.height / 2)
        let bottomLeft = CGPoint(x: margin + pipSize.width / 2, y: screenSize.height - margin - pipSize.height / 2)
        let bottomRight = CGPoint(x: screenSize.width - margin - pipSize.width / 2, y: screenSize.height - margin - pipSize.height / 2)

        let corners = [topLeft, topRight, bottomLeft, bottomRight]
        let currentCenter = pipView.center

        let nearest = corners.min(by: {
            distance(from: currentCenter, to: $0) < distance(from: currentCenter, to: $1)
        }) ?? bottomRight

        UIView.animate(withDuration: 0.25) {
            pipView.center = nearest
        }
    }

    private func distance(from p1: CGPoint, to p2: CGPoint) -> CGFloat {
        hypot(p1.x - p2.x, p1.y - p2.y)
    }
}
