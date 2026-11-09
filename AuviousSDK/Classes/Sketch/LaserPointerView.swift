//
//  LaserPointerView.swift
//  AuviousSDK
//
//  Created by Auvious on 15/10/26.
//

import UIKit

/// Renders AR pointer points: a numbered dot with a countdown ring (web: point.component).
internal final class LaserPointerView: UIView {

    private static let dotSize: CGFloat = 30
    /// The ring hugs the dot: a 2.5pt gap between the dot and the ring's inner edge
    private static let ringWidth: CGFloat = 3
    private static let ringRadius: CGFloat = dotSize / 2 + 2.5 + ringWidth / 2

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows a point given in the sender's area coordinates (each axis scaled independently, like the web)
    func show(x: CGFloat, y: CGFloat, areaWidth: CGFloat, areaHeight: CGFloat, color: UIColor, index: Int, ttl: TimeInterval) {
        guard areaWidth > 0, areaHeight > 0 else { return }

        let center = CGPoint(x: x * bounds.width / areaWidth, y: y * bounds.height / areaHeight)
        let container = UIView(frame: CGRect(x: 0, y: 0, width: LaserPointerView.ringRadius * 2 + 8, height: LaserPointerView.ringRadius * 2 + 8))
        container.center = center
        container.isUserInteractionEnabled = false
        addSubview(container)

        let containerCenter = CGPoint(x: container.bounds.midX, y: container.bounds.midY)

        //Countdown ring
        let ring = CAShapeLayer()
        ring.path = UIBezierPath(arcCenter: containerCenter, radius: LaserPointerView.ringRadius, startAngle: -.pi / 2, endAngle: 1.5 * .pi, clockwise: true).cgPath
        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = LaserPointerView.ringColor(for: color).cgColor
        ring.lineWidth = LaserPointerView.ringWidth
        ring.lineCap = .round
        container.layer.addSublayer(ring)

        let countdown = CABasicAnimation(keyPath: "strokeEnd")
        countdown.fromValue = 1
        countdown.toValue = 0
        countdown.duration = ttl
        countdown.fillMode = .forwards
        countdown.isRemovedOnCompletion = false
        ring.add(countdown, forKey: "countdown")

        //Numbered dot
        let dot = UILabel(frame: CGRect(x: 0, y: 0, width: LaserPointerView.dotSize, height: LaserPointerView.dotSize))
        dot.center = containerCenter
        dot.backgroundColor = color
        dot.layer.cornerRadius = LaserPointerView.dotSize / 2
        dot.layer.masksToBounds = true
        dot.text = "\(index)"
        dot.textAlignment = .center
        dot.textColor = .white
        dot.font = CobrowseTheme.font(13, .bold)
        container.addSubview(dot)

        DispatchQueue.main.asyncAfter(deadline: .now() + ttl + 0.3) { [weak container] in
            container?.removeFromSuperview()
        }
    }

    func clear() {
        subviews.forEach { $0.removeFromSuperview() }
    }

    /// The ring is the dot color darkened 20% and desaturated 40%
    private static func ringColor(for color: UIColor) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 1
        guard color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return color
        }
        return UIColor(hue: hue, saturation: saturation * 0.6, brightness: brightness * 0.8, alpha: alpha)
    }
}
