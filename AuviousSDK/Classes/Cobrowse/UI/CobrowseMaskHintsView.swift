//
//  CobrowseMaskHintsView.swift
//  AuviousSDK
//
//  Created by Auvious on 15/10/26.
//

import UIKit

/// Outlines masked views on the customer's own screen ("Private"), so they know what the agent can't see.
/// In debug mode it fills every masked region and labels it with the rule that matched.
/// These hints are captured too, but they sit inside the masked regions, so they arrive black.
internal final class CobrowseMaskHintsView: UIView {

    private let outlineLayer = CAShapeLayer()
    private var badges: [UIView] = []

    var showsHints = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear

        outlineLayer.fillColor = UIColor.clear.cgColor
        outlineLayer.lineWidth = 1.5
        outlineLayer.lineDashPattern = [5, 4]
        layer.addSublayer(outlineLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        outlineLayer.frame = bounds
    }

    /// - Parameter regions: masked regions in screen points
    func update(regions: [MaskRegion], debug: Bool) {
        badges.forEach { $0.removeFromSuperview() }
        badges = []

        let visible = debug ? regions : (showsHints ? regions.filter { !$0.isKeyboard } : [])
        let path = UIBezierPath()

        for region in visible {
            let rect = convert(region.rect, from: window?.screen.coordinateSpace ?? UIScreen.main.coordinateSpace).insetBy(dx: -4, dy: -4)
            path.append(UIBezierPath(roundedRect: rect, cornerRadius: 10))

            let badge = makeBadge(text: debug ? region.reason : CobrowseStrings.privateField, debug: debug)
            let size = badge.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            //Inside the masked area, so the badge itself never shows up in the shared video
            badge.frame = CGRect(x: max(rect.minX + 4, rect.maxX - size.width - 6), y: rect.minY + 6, width: size.width, height: size.height)
            addSubview(badge)
            badges.append(badge)
        }

        outlineLayer.path = path.cgPath
        outlineLayer.strokeColor = (debug ? UIColor.systemRed : CobrowseTheme.maskHint).cgColor
        outlineLayer.fillColor = debug ? UIColor.systemRed.withAlphaComponent(0.25).cgColor : UIColor.clear.cgColor
        outlineLayer.lineDashPattern = debug ? nil : [5, 4]
    }

    private func makeBadge(text: String, debug: Bool) -> UIView {
        let icon = UIImageView(image: CobrowseTheme.symbol("eye.slash", size: 10, weight: .semibold))
        icon.isHidden = debug

        let label = UILabel()
        label.text = text
        label.font = CobrowseTheme.font(11, .semibold)

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 1, left: 6, bottom: 1, right: 6)
        stack.layer.cornerRadius = 6

        if debug {
            stack.backgroundColor = .systemRed
            label.textColor = .white
        } else {
            stack.backgroundColor = .systemBackground
            label.textColor = .secondaryLabel
            icon.tintColor = .secondaryLabel
        }
        return stack
    }
}
