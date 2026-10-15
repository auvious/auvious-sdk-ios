//
//  CobrowseTheme.swift
//  AuviousSDK
//
//  Created by Auvious on 15/10/26.
//

import UIKit

/// Colors and metrics of the co-browse overlay (direction B: edge glow and dock)
internal enum CobrowseTheme {

    /// The SDK's red gradient, shared with the video call's "Stop sharing" button (150°)
    static let redGradientStart = UIColor(red: 245/255, green: 39/255, blue: 107/255, alpha: 1)
    static let redGradientEnd = UIColor(red: 227/255, green: 23/255, blue: 23/255, alpha: 1)

    /// Solid stand-in for the gradient (its midpoint), used for the sharing border and as the default accent
    static let defaultAccent = UIColor(red: 236/255, green: 31/255, blue: 65/255, alpha: 1)

    /// Fills a layer with the red gradient at 150° (same as `CAGradientLayer.setAngle(150)`)
    static func applyRedGradient(to gradient: CAGradientLayer) {
        gradient.colors = [redGradientStart.cgColor, redGradientEnd.cgColor]
        gradient.startPoint = CGPoint(x: 0.25, y: 0.933)
        gradient.endPoint = CGPoint(x: 0.75, y: 0.067)
    }

    /// The gradient is used unless the host app picked its own accent color
    static func usesRedGradient(_ accentColor: UIColor) -> Bool {
        return accentColor == defaultAccent
    }

    /// Dock tint and dark chrome (#1F2433)
    static let dock = UIColor(red: 31/255, green: 36/255, blue: 51/255, alpha: 1)

    /// Secondary dock buttons on the glass dock (translucent, so the glass shows through)
    static let dockGlassButton = UIColor.white.withAlphaComponent(0.14)

    /// Neutral pill, used while connecting or not sharing (#3A3F4F)
    static let neutralPill = UIColor(red: 58/255, green: 63/255, blue: 79/255, alpha: 1)

    /// Positive confirmation (#2F6B4F)
    static let success = UIColor(red: 47/255, green: 107/255, blue: 79/255, alpha: 1)

    /// Mask hint outline (#6B7180)
    static let maskHint = UIColor(red: 107/255, green: 113/255, blue: 128/255, alpha: 1)

    /// Width of the sharing border
    static let glowWidth: CGFloat = 4

    /// Height of the dock buttons (touch target)
    static let dockButtonHeight: CGFloat = 48

    /// Distance of the dock from the safe area edge
    static let dockMargin: CGFloat = 12

    static func font(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
        return UIFont.systemFont(ofSize: size, weight: weight)
    }

    /// SF Symbol, sized for the dock
    static func symbol(_ name: String, size: CGFloat = 18, weight: UIImage.SymbolWeight = .semibold) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: size, weight: weight)
        return UIImage(systemName: name, withConfiguration: configuration)
    }

    /// Approximate display corner radius, so the border follows the screen's rounded corners.
    /// Uses the screen size because the exact radius is only available through private API.
    static func displayCornerRadius(for window: UIWindow?) -> CGFloat {
        guard let window = window, window.safeAreaInsets.bottom > 0 else {
            return 0
        }

        //Screen height in points -> display corner radius
        let knownRadii: [Int: CGFloat] = [
            780: 44,     //12/13 mini
            812: 39,     //X, XS, 11 Pro
            844: 47.33,  //12, 13, 14, 16e
            852: 55,     //14 Pro, 15, 16
            874: 62,     //16 Pro, 17, 17 Pro
            896: 41.5,   //XR, 11, XS Max, 11 Pro Max
            912: 62,     //Air
            926: 53.33,  //12/13 Pro Max, 14 Plus
            932: 55,     //14 Pro Max, 15 Plus/Pro Max, 16 Plus
            956: 62      //16 Pro Max, 17 Pro Max
        ]
        let longSide = Int(max(window.bounds.width, window.bounds.height).rounded())
        return knownRadii[longSide] ?? 44
    }
}
