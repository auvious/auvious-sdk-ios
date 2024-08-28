//
//  ConferenceButton.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 24/9/20.
//

import Foundation

enum ConferenceButtonType {
    case micEnabled, micDisabled, camEnabled, camDisabled, camSwitch, camSwitchDisabled, hangup
}

class ConferenceButton: UIButton {
    
    var type: ConferenceButtonType {
        didSet {
            setup()
        }
    }
    private var gradientLayer = CAGradientLayer()
    
    init(type: ConferenceButtonType) {
        self.type = type
        
        super.init(frame: .zero)
        setup()
        layer.insertSublayer(gradientLayer, at: 0)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        gradientLayer.frame = bounds
        layer.cornerRadius = bounds.width / 2
        clipsToBounds = true
        layer.zPosition = 300
    }
    
    func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        
        var image: String = ""
        
        //Background gradient
        switch type {
        case .micEnabled:
            image = "micEnabled"
            gradientLayer.colors = [UIColor(red: 55/255, green: 60/255, blue: 96/255, alpha: 0.85).cgColor, UIColor(red: 27/255, green: 30/255, blue: 47/255, alpha: 0.85).cgColor]
            gradientLayer.setAngle(150)
        case .micDisabled:
            image = "micDisabledDark"
            gradientLayer.colors = [UIColor(red: 225/255, green: 224/255, blue: 230/255, alpha: 0.85).cgColor, UIColor.white.cgColor]
            gradientLayer.setAngle(150)
        case .camEnabled:
            image = "camEnabled"
            gradientLayer.colors = [UIColor(red: 55/255, green: 60/255, blue: 96/255, alpha: 0.85).cgColor, UIColor(red: 27/255, green: 30/255, blue: 47/255, alpha: 0.85).cgColor]
            gradientLayer.setAngle(150)
        case .camDisabled:
            image = "camDisabledDark"
            gradientLayer.colors = [UIColor(red: 225/255, green: 224/255, blue: 230/255, alpha: 0.85).cgColor, UIColor.white.cgColor]
            gradientLayer.setAngle(150)
        case .camSwitch:
            image = "camSwitch"
            gradientLayer.colors = [UIColor(red: 55/255, green: 60/255, blue: 96/255, alpha: 0.85).cgColor, UIColor(red: 27/255, green: 30/255, blue: 47/255, alpha: 0.85).cgColor]
            gradientLayer.setAngle(150)
            imageView?.layer.opacity = 1
            super.isEnabled = true
        case .camSwitchDisabled:
            image = "camSwitch"
            gradientLayer.colors = [UIColor(red: 55/255, green: 60/255, blue: 96/255, alpha: 0.45).cgColor, UIColor(red: 27/255, green: 30/255, blue: 47/255, alpha: 0.45).cgColor]
            gradientLayer.setAngle(150)
            imageView?.layer.opacity = 0.3
            super.isEnabled = false
        case .hangup:
            image = "hangup"
            gradientLayer.colors = [UIColor(red: 245/255, green: 39/255, blue: 107/255, alpha: 0.85).cgColor, UIColor(red: 227/255, green: 23/255, blue: 23/255, alpha: 0.85).cgColor]
            gradientLayer.setAngle(150)
        }
        
        //Background image
        setImage(UIImage(podAssetName: image), for: [])
        contentMode = .center
        imageView?.contentMode = .scaleAspectFit
    }
}



