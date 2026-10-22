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
    case screenShareDark
    case screenShare
    case screenShareDisabled
    case options
    case optionsTapped
    case pip
    case stopScreenShare
    
    var title: String {
        switch self {
        case .speakerON:
            return NSLocalizedString("Use earpiece", comment: "")
        case .speakerOFF:
            return NSLocalizedString("Use speaker", comment: "")
        case .pip:
            return NSLocalizedString("Floating window", comment: "")
        case .screenShare:
            return NSLocalizedString("Share screen", comment: "")
        case .stopScreenShare:
            return NSLocalizedString("Stop sharing", comment: "")
        default:
            return "Default title"
        }
    }
    
    var imageName: String {
        switch self {
        case .micEnabled:
            return "micEnabled"
        case .micDisabled:
            return "micDisabledDark"
        case .camEnabled:
            return "camEnabled"
        case .camDisabled:
            return "camDisabledDark"
        case .camSwitch:
            return "camSwitch"
        case .camSwitchDisabled:
            return "camSwitch"
        case .hangup:
            return "hangup"
        case .speakerON:
            return "speakerON"
        case .speakerOFF:
            return "speakerOFF"
        case .screenShareDark:
            return "screenShareON"
        case .screenShare:
            return "screenShareOFF"
        case .screenShareDisabled:
            return "screenShareON"
        case .options:
            return "moreOptions"
        case .optionsTapped:
            return "moreOptionsPressed"
        case .pip:
            return "pip"
        case .stopScreenShare:
            return "stopSharing"
        }
    }
}

class ConferenceButton: UIButton {
    
    var type: ConferenceButtonType {
        didSet {
            setup()
        }
    }
    
    private var gradientLayer = CAGradientLayer()

    //Before iOS 26: black at 60% to 80%, the web client's --av-color-primary
    private static let darkGradient = [UIColor.black.withAlphaComponent(0.6).cgColor, UIColor.black.withAlphaComponent(0.8).cgColor]
    private static let darkGradientDisabled = [UIColor.black.withAlphaComponent(0.3).cgColor, UIColor.black.withAlphaComponent(0.4).cgColor]

    //Liquid Glass background on iOS 26 and later (the gradient is used before that)
    private let glassView = UIVisualEffectView()
    
    init(type: ConferenceButtonType) {
        self.type = type
        
        super.init(frame: .zero)
        glassView.isUserInteractionEnabled = false
        insertSubview(glassView, at: 0)
        setup()
        layer.insertSublayer(gradientLayer, at: 0)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        gradientLayer.frame = bounds
        glassView.frame = bounds
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
            gradientLayer.colors = ConferenceButton.darkGradient
            gradientLayer.setAngle(150)
        case .micDisabled:
            gradientLayer.colors = [UIColor(red: 225/255, green: 224/255, blue: 230/255, alpha: 0.85).cgColor, UIColor.white.cgColor]
            gradientLayer.setAngle(150)
        case .camEnabled:
            gradientLayer.colors = ConferenceButton.darkGradient
            gradientLayer.setAngle(150)
        case .camDisabled:
            gradientLayer.colors = [UIColor(red: 225/255, green: 224/255, blue: 230/255, alpha: 0.85).cgColor, UIColor.white.cgColor]
            gradientLayer.setAngle(150)
        case .camSwitch:
            gradientLayer.colors = ConferenceButton.darkGradient
            gradientLayer.setAngle(150)
            imageView?.layer.opacity = 1
            super.isEnabled = true
        case .camSwitchDisabled:
            gradientLayer.colors = ConferenceButton.darkGradientDisabled
            gradientLayer.setAngle(150)
            imageView?.layer.opacity = 0.3
            super.isEnabled = false
        case .hangup:
            gradientLayer.colors = [UIColor(red: 245/255, green: 39/255, blue: 107/255, alpha: 0.85).cgColor, UIColor(red: 227/255, green: 23/255, blue: 23/255, alpha: 0.85).cgColor]
            gradientLayer.setAngle(150)
        case .speakerON:
            gradientLayer.colors = [UIColor(red: 225/255, green: 224/255, blue: 230/255, alpha: 0.85).cgColor, UIColor.white.cgColor]
            gradientLayer.setAngle(150)
        case .speakerOFF:
            gradientLayer.colors = ConferenceButton.darkGradient
            gradientLayer.setAngle(150)
            
        case .screenShareDisabled:
            gradientLayer.colors = ConferenceButton.darkGradientDisabled
            gradientLayer.setAngle(150)
            imageView?.layer.opacity = 0.3
            super.isEnabled = false
        
        case .screenShareDark:
            gradientLayer.colors = [UIColor(red: 225/255, green: 224/255, blue: 230/255, alpha: 0.85).cgColor, UIColor.white.cgColor]
            gradientLayer.setAngle(150)
        
        case .screenShare:
            gradientLayer.colors = ConferenceButton.darkGradient
            gradientLayer.setAngle(150)
            imageView?.layer.opacity = 1
            super.isEnabled = true
            
        case .options:
            gradientLayer.colors = ConferenceButton.darkGradient
            gradientLayer.setAngle(150)
        case .optionsTapped:
            gradientLayer.colors = [UIColor(red: 225/255, green: 224/255, blue: 230/255, alpha: 0.85).cgColor, UIColor.white.cgColor]
            gradientLayer.setAngle(150)
        case .pip:
            gradientLayer.colors = ConferenceButton.darkGradient
            gradientLayer.setAngle(150)
        case .stopScreenShare:
            gradientLayer.colors = ConferenceButton.darkGradient
            gradientLayer.setAngle(150)
        }
        
        if #available(iOS 26.0, *) {
            applyGlass()
        }
        
        //Background image
        image = type.imageName
        setImage(UIImage(podAssetName: image), for: [])
        contentMode = .center
        imageView?.contentMode = .scaleAspectFit
        if let imageView = imageView {
            bringSubviewToFront(imageView)
        }
    }

    //The options menu opens above the button bar instead of over it
    override func menuAttachmentPoint(for configuration: UIContextMenuConfiguration) -> CGPoint {
        return CGPoint(x: bounds.midX, y: -12)
    }

    //The options button looks pressed while its menu is open
    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willDisplayMenuFor configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?) {
        super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
        if type == .options {
            type = .optionsTapped
        }
    }

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willEndFor configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?) {
        super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
        if type == .optionsTapped {
            type = .options
        }
    }

    /// Almost black glass for the controls, white glass while a control is toggled (mic or camera
    /// off, speaker on, options open) and the SDK red for hang up
    @available(iOS 26.0, *)
    private func applyGlass() {
        let tint: UIColor
        //Dark glass picks up less of the video behind it, so the dark buttons stay almost black
        var style: UIUserInterfaceStyle = .dark
        switch type {
        case .hangup:
            tint = UIColor(red: 236/255, green: 31/255, blue: 65/255, alpha: 0.7)
        case .micDisabled, .camDisabled, .speakerON, .screenShareDark, .optionsTapped:
            tint = UIColor.white.withAlphaComponent(0.85)
            style = .light
        case .camSwitchDisabled, .screenShareDisabled:
            tint = UIColor(white: 0.02, alpha: 0.3)
        default:
            //Light enough for the glass to show, dark enough to read as almost black
            tint = UIColor(white: 0.02, alpha: 0.5)
        }

        let glass = UIGlassEffect(style: .regular)
        glass.tintColor = tint
        glassView.overrideUserInterfaceStyle = style
        glassView.effect = glass
        glassView.cornerConfiguration = .capsule()
        gradientLayer.colors = nil
    }
}

enum PIPButtonType {
    case micEnabled, micDisabled
}

final class PIPButton: UIButton {
    var type: PIPButtonType {
        didSet {
            setup()
        }
    }
    
    init(type: PIPButtonType) {
        self.type = type
        
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        var image: String = ""
        
        switch type {
        case .micDisabled:
            image = "micDisabled"
        case .micEnabled:
            image = "micEnabled"
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

    var title: String? {
        get { return label.text }
        set { label.text = newValue }
    }

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
        stack.isUserInteractionEnabled = false
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

        //Capsule, like the co-browse End button
        layer.cornerCurve = .continuous
        clipsToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = gradientView.bounds
        layer.cornerRadius = bounds.height / 2
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
