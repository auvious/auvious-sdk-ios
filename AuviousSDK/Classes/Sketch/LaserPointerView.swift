//
//  LaserPointerView.swift
//  AuviousSDK
//
//  Created by Auvious on 15/10/26.
//

import UIKit

/// Renders the agent's laser pointer indications: a pulsing numbered dot with a countdown ring (web: point.component).
internal final class LaserPointerView: UIView {

    private static let dotSize: CGFloat = 30
    private static let ringRadius: CGFloat = 25

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
        ring.lineWidth = 4
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

        //Pulse
        let pulse = CALayer()
        pulse.frame = dot.frame
        pulse.cornerRadius = LaserPointerView.dotSize / 2
        pulse.borderColor = UIColor.white.cgColor
        pulse.borderWidth = 2
        container.layer.insertSublayer(pulse, below: dot.layer)

        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 1
        grow.toValue = 1.6
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = 1
        group.repeatCount = .infinity
        pulse.add(group, forKey: "pulse")

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
