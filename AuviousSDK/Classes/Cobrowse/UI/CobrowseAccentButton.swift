//
//  CobrowseAccentButton.swift
//  AuviousSDK
//
//  Created by Auvious on 15/10/26.
//

import UIKit

/// Capsule button for End / Start sharing. Uses the SDK's red gradient (same as the video call's
/// "Stop sharing" button) unless the host app set its own accent color.
internal final class CobrowseAccentButton: UIButton {

    private let gradient = CAGradientLayer()

    var accentColor: UIColor = CobrowseTheme.defaultAccent {
        didSet { applyFill() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        CobrowseTheme.applyRedGradient(to: gradient)
        layer.insertSublayer(gradient, at: 0)
        layer.cornerCurve = .continuous
        clipsToBounds = true
        setTitleColor(.white, for: .normal)
        tintColor = .white
        applyFill()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        layer.cornerRadius = bounds.height / 2
    }

    override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? 0.7 : 1
        }
    }

    private func applyFill() {
        let usesGradient = CobrowseTheme.usesRedGradient(accentColor)
        gradient.isHidden = !usesGradient
        backgroundColor = usesGradient ? .clear : accentColor
    }
}
