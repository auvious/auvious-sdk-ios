//
//  CobrowseEdgeGlowView.swift
//  AuviousSDK
//
//  Created by Auvious on 15/10/26.
//

import UIKit

/// The border drawn around the whole screen while it is being shared.
internal final class CobrowseEdgeGlowView: UIView {

    private let borderLayer = CAShapeLayer()

    var color: UIColor = CobrowseTheme.defaultAccent {
        didSet {
            borderLayer.strokeColor = color.cgColor
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear

        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.strokeColor = color.cgColor
        borderLayer.lineWidth = CobrowseTheme.glowWidth
        layer.addSublayer(borderLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let inset = CobrowseTheme.glowWidth / 2
        let radius = max(0, CobrowseTheme.displayCornerRadius(for: window) - inset)
        borderLayer.frame = bounds
        borderLayer.path = UIBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset), cornerRadius: radius).cgPath
    }

    func setVisible(_ visible: Bool, animated: Bool) {
        let changes = {
            self.alpha = visible ? 1 : 0
        }
        if animated {
            UIView.animate(withDuration: 0.25, animations: changes)
        } else {
            changes()
        }
    }
}
