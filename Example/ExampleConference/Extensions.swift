//
//  Extensions.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 24/12/2018.
//  Copyright © 2018 Auvious. All rights reserved.
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

extension UIColor {
    static var random: UIColor {
        return UIColor(red: .random(in: 0...1),
                       green: .random(in: 0...1),
                       blue: .random(in: 0...1),
                       alpha: 1.0)
    }
}

extension String {
    
    func trim() -> String {
        return self.trimmingCharacters(in: CharacterSet.whitespaces)
    }
}
