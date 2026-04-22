//
//  ConferenceHoldView.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 18/10/20.
//

import Foundation

class ConferenceHoldView: UIImageView {

    internal var blurView: UIVisualEffectView!
    private var topLabel: UILabel!
    private var bottomLabel: UILabel!
    private var pauseImageHeightConstraint: NSLayoutConstraint!
    private var pauseImageCenterYConstraint: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        contentMode = .scaleAspectFill
        clipsToBounds = true

        let darkBlur = UIBlurEffect(style: UIBlurEffect.Style.dark)
        blurView = UIVisualEffectView(effect: darkBlur)
        blurView.frame = .zero
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.alpha = 0
        addSubview(blurView)

        blurView.topAnchor.constraint(equalTo: topAnchor, constant: 0).isActive = true
        blurView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 0).isActive = true
        blurView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0).isActive = true
        blurView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 0).isActive = true

        let pauseImage = UIImageView(frame: .zero)
        pauseImage.translatesAutoresizingMaskIntoConstraints = false
        pauseImage.image = UIImage(podAssetName: "conferenceHold")
        pauseImage.contentMode = .scaleAspectFit
        addSubview(pauseImage)
        pauseImage.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        pauseImageCenterYConstraint = pauseImage.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -50)
        pauseImageCenterYConstraint.isActive = true
        pauseImageHeightConstraint = pauseImage.heightAnchor.constraint(equalToConstant: 50)
        pauseImageHeightConstraint.isActive = true

        topLabel = UILabel(frame: .zero)
        topLabel.translatesAutoresizingMaskIntoConstraints = false
        topLabel.text = "Your call is on hold"
        topLabel.textAlignment = .center
        topLabel.textColor = UIColor.lightGray
        topLabel.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        addSubview(topLabel)
        topLabel.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        topLabel.topAnchor.constraint(equalTo: pauseImage.bottomAnchor, constant: 20).isActive = true

        bottomLabel = UILabel(frame: .zero)
        bottomLabel.translatesAutoresizingMaskIntoConstraints = false
        bottomLabel.text = "Please wait"
        bottomLabel.textAlignment = .center
        bottomLabel.textColor = UIColor.lightGray
        bottomLabel.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        addSubview(bottomLabel)
        bottomLabel.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        bottomLabel.topAnchor.constraint(equalTo: topLabel.bottomAnchor, constant: 12).isActive = true

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 0
        animation.duration = 1
        animation.repeatCount = .infinity
        animation.autoreverses = true
        bottomLabel.layer.add(animation, forKey: nil)
    }

    func configurePiP(_ isPiP: Bool) {
        topLabel.isHidden = isPiP
        bottomLabel.isHidden = isPiP
        pauseImageCenterYConstraint.constant = isPiP ? 0 : -50
        pauseImageHeightConstraint.constant = isPiP ? 20 : 50
        layer.cornerRadius = isPiP ? 12 : 0
        clipsToBounds = isPiP
        layoutIfNeeded()
    }
}
