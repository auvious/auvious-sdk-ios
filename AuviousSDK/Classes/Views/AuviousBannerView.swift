//
//  AuviousBannerView.swift
//  AuviousSDK
//
//  Created by Auvious on 15/10/26.
//

import UIKit

/**
 The SDK's notification banner, shared by the video call (recording, network) and co-browse.

 Looks like an iOS banner: Liquid Glass on iOS 26 and later, system material before that, so it follows
 light and dark mode. A tinted SF Symbol leads, followed by a title and a secondary message.
 */
internal class AuviousBannerView: UIView {

    static let cornerRadius: CGFloat = 22

    internal let iconView = UIImageView()
    internal let titleLabel = UILabel()
    internal let subtitleLabel = UILabel()

    private let background = UIVisualEffectView(effect: nil)
    private let texts = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpBanner()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpBanner()
    }

    /// Sets the icon, title and message. A nil title shows the message alone.
    /// `image` is a custom template icon, shown instead of `symbol`
    func configure(symbol: String?, image: UIImage? = nil, tint: UIColor?, title: String?, message: String?) {
        if let image = image {
            iconView.image = image
        } else if let symbol = symbol {
            var configuration = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
            //Filled circles (checkmark, record) get a white glyph, instead of one cut out of the circle that shows the banner through
            if symbol.hasSuffix(".circle.fill") {
                configuration = configuration.applying(UIImage.SymbolConfiguration(paletteColors: [.white, tint ?? .secondaryLabel]))
            }
            iconView.image = UIImage(systemName: symbol, withConfiguration: configuration)
        } else {
            iconView.image = nil
        }
        iconView.tintColor = tint ?? .secondaryLabel
        iconView.isHidden = iconView.image == nil

        titleLabel.text = title
        titleLabel.isHidden = title?.isEmpty ?? true
        subtitleLabel.text = message
        subtitleLabel.isHidden = message?.isEmpty ?? true

        //A lone message reads like a title
        subtitleLabel.font = titleLabel.isHidden ? UIFont.systemFont(ofSize: 15, weight: .regular) : UIFont.systemFont(ofSize: 14)
        subtitleLabel.textColor = titleLabel.isHidden ? .label : .secondaryLabel

        isAccessibilityElement = true
        accessibilityLabel = [title, message].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ". ")
    }

    private func setUpBanner() {
        backgroundColor = .clear
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.15
        layer.shadowOffset = CGSize(width: 0, height: 6)
        layer.shadowRadius = 16

        background.translatesAutoresizingMaskIntoConstraints = false
        background.clipsToBounds = true
        background.layer.cornerRadius = AuviousBannerView.cornerRadius
        background.layer.cornerCurve = .continuous
        if #available(iOS 26.0, *) {
            background.effect = UIGlassEffect(style: .regular)
        } else {
            background.effect = UIBlurEffect(style: .systemMaterial)
        }
        addSubview(background)

        iconView.contentMode = .center
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0
        subtitleLabel.font = UIFont.systemFont(ofSize: 14)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0

        texts.axis = .vertical
        texts.spacing = 2
        texts.addArrangedSubview(titleLabel)
        texts.addArrangedSubview(subtitleLabel)

        let row = UIStackView(arrangedSubviews: [iconView, texts])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        background.contentView.addSubview(row)

        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),

            iconView.widthAnchor.constraint(equalToConstant: 30),
            row.topAnchor.constraint(greaterThanOrEqualTo: background.contentView.topAnchor, constant: 12),
            row.bottomAnchor.constraint(lessThanOrEqualTo: background.contentView.bottomAnchor, constant: -12),
            row.centerYAnchor.constraint(equalTo: background.contentView.centerYAnchor),
            row.leadingAnchor.constraint(equalTo: background.contentView.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: background.contentView.trailingAnchor, constant: -16)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: AuviousBannerView.cornerRadius).cgPath
    }
}
