//
//  Extensions.swift
//  ExampleSimpleConference
//
//  Created by Jason Kritikos on 22/10/25.
//  Copyright © 2025 CocoaPods. All rights reserved.
//

import Foundation
import UIKit

extension UIViewController {
    
    func showAlert(title:String, msg:String, onSuccess: (()->())? = nil){
        let alert = UIAlertController(title: title, message: msg, preferredStyle: UIAlertController.Style.alert)
        alert.view.tintColor = UIColor.black
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK",comment:""), style: .default, handler: { (action: UIAlertAction!) in
            
            if let callback = onSuccess {
                callback()
            }
        }))
        
        present(alert, animated: true, completion: nil)
    }
}

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
