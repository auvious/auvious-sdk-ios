//
//  ConferenceButton.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 24/9/20.
//

import Foundation

enum ConferenceButtonType {
    case micEnabled
    case micDisabled
    case camEnabled
    case camDisabled
    case camSwitch
    case camSwitchDisabled
    case hangup
    case speakerON
    case speakerOFF
    case screenShareEnabled
    case screenShareDisabled
    case options
    case optionsTapped
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
        case .speakerON:
            image = "speakerON"
            gradientLayer.colors = [UIColor(red: 225/255, green: 224/255, blue: 230/255, alpha: 0.85).cgColor, UIColor.white.cgColor]
            gradientLayer.setAngle(150)
        case .speakerOFF:
            image = "speakerOFF"
            gradientLayer.colors = [UIColor(red: 55/255, green: 60/255, blue: 96/255, alpha: 0.85).cgColor, UIColor(red: 27/255, green: 30/255, blue: 47/255, alpha: 0.85).cgColor]
            gradientLayer.setAngle(150)
        case .screenShareEnabled:
            image = "screenShareON"
            gradientLayer.colors = [UIColor(red: 225/255, green: 224/255, blue: 230/255, alpha: 0.85).cgColor, UIColor.white.cgColor]
            gradientLayer.setAngle(150)
        case .screenShareDisabled:
            image = "screenShareOFF"
            gradientLayer.colors = [UIColor(red: 55/255, green: 60/255, blue: 96/255, alpha: 0.85).cgColor, UIColor(red: 27/255, green: 30/255, blue: 47/255, alpha: 0.85).cgColor]
            gradientLayer.setAngle(150)
        case .options:
            image = "moreOptions"
            gradientLayer.colors = [UIColor(red: 55/255, green: 60/255, blue: 96/255, alpha: 0.85).cgColor, UIColor(red: 27/255, green: 30/255, blue: 47/255, alpha: 0.85).cgColor]
            gradientLayer.setAngle(150)
        case .optionsTapped:
            image = "moreOptionsPressed"
            gradientLayer.colors = [UIColor(red: 225/255, green: 224/255, blue: 230/255, alpha: 0.85).cgColor, UIColor.white.cgColor]
            gradientLayer.setAngle(150)
        }
        
        //Background image
        setImage(UIImage(podAssetName: image), for: [])
        contentMode = .center
        imageView?.contentMode = .scaleAspectFit
    }
}

final class LargeButton: UIButton {
    private let gradientView = UIView()
    private let gradientLayer = CAGradientLayer()
    private let iconView = UIImageView()
    private let label = UILabel()

    init(title: String, iconName: String) {
        super.init(frame: .zero)

        // Setup gradient
        gradientView.isUserInteractionEnabled = false
        gradientView.translatesAutoresizingMaskIntoConstraints = false
        insertSubview(gradientView, at: 0)
        gradientLayer.colors = [
            UIColor(red: 245/255, green: 39/255, blue: 107/255, alpha: 0.85).cgColor,
            UIColor(red: 227/255, green: 23/255, blue: 23/255, alpha: 0.85).cgColor
        ]
        gradientLayer.setAngle(150)
        gradientView.layer.addSublayer(gradientLayer)

        // Setup icon
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = UIImage(podAssetName: iconName)
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .white

        // Setup label
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)

        let stack = UIStackView(arrangedSubviews: [iconView, label])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            gradientView.topAnchor.constraint(equalTo: topAnchor),
            gradientView.bottomAnchor.constraint(equalTo: bottomAnchor),
            gradientView.leadingAnchor.constraint(equalTo: leadingAnchor),
            gradientView.trailingAnchor.constraint(equalTo: trailingAnchor),

            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),

            iconView.widthAnchor.constraint(equalToConstant: 25),
            iconView.heightAnchor.constraint(equalToConstant: 25)
        ])

        layer.cornerRadius = 8
        clipsToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = gradientView.bounds
    }

    override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? 0.6 : 1.0
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
