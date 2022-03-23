//
//  UIExtensions.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 24/9/20.
//

import Foundation

extension CAGradientLayer {
    func setAngle(_ angle: Float = 0) {
        let alpha: Float = angle / 360
        let startPointX = powf(
            sinf(2 * Float.pi * ((alpha + 0.75) / 2)),
            2
        )
        let startPointY = powf(
            sinf(2 * Float.pi * ((alpha + 0) / 2)),
            2
        )
        let endPointX = powf(
            sinf(2 * Float.pi * ((alpha + 0.25) / 2)),
            2
        )
        let endPointY = powf(
            sinf(2 * Float.pi * ((alpha + 0.5) / 2)),
            2
        )

        endPoint = CGPoint(x: CGFloat(endPointX),y: CGFloat(endPointY))
        startPoint = CGPoint(x: CGFloat(startPointX), y: CGFloat(startPointY))
    }
}

extension UIView {
    func roundCorners(_ corners: UIRectCorner, radius: CGFloat) {
         let path = UIBezierPath(roundedRect: self.bounds, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
         let mask = CAShapeLayer()
         mask.path = path.cgPath
         self.layer.mask = mask
    }
    
    //iOS-safe safe area layout guide
    var saferAreaLayoutGuide: UILayoutGuide {
        get {
            if #available(iOS 11.0, *) {
                return self.safeAreaLayoutGuide
            } else {
                return self.layoutMarginsGuide
            }
        }
    }
    
    //Returns a screenshot of the view
    func screenshot(afterScreenUpdates: Bool = true) -> UIImage {
        return UIGraphicsImageRenderer(size: bounds.size).image { _ in
            drawHierarchy(in: CGRect(origin: .zero, size: bounds.size), afterScreenUpdates: afterScreenUpdates)
        }
    }
    
    //Creates rounded corners at the specified corner for the specified radii
    func cornerRadius(usingCorners corners: UIRectCorner, cornerRadii: CGSize) {
        let path = UIBezierPath(roundedRect: self.bounds, byRoundingCorners: corners, cornerRadii: cornerRadii)
        let maskLayer = CAShapeLayer()
        maskLayer.path = path.cgPath
        
        self.layer.mask = maskLayer
    }
}

extension UIImage {
    //Constructor for assets found with the pod's bundle
    convenience init?(podAssetName: String) {
        let podBundle = Bundle(for: ConferenceButton.self)

        // A given class within your Pod framework
        guard let url = podBundle.url(forResource: "AuviousSDKAssets", withExtension: "bundle") else {
            return nil
        }

        self.init(named: podAssetName, in: Bundle(url: url), compatibleWith: nil)
    }
    
    var grayscaled: UIImage? {
        let ciImage = CIImage(image: self)
        let grayscale = ciImage?.applyingFilter("CIColorControls",
                                                parameters: [ kCIInputSaturationKey: 0.0 ])
        if let gray = grayscale {
            return UIImage(ciImage: gray)
        }
        else {
            return nil
        }
    }
}

