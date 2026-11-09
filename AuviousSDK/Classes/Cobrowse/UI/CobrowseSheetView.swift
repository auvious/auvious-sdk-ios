//
//  CobrowseSheetView.swift
//  AuviousSDK
//
//  Created by Auvious on 15/10/26.
//

import UIKit

/// A bottom sheet over a dimmed scrim, used for the share explainer and the end confirmation.
/// Built as a plain view (not a presented view controller) so the overlay window never needs to become key.
internal final class CobrowseSheetView: UIView {

    struct Content {
        var iconSymbol: String?
        var title: String
        var body: String?
        var bullets: [String] = []
        var primaryTitle: String
        var secondaryTitle: String
        var footnote: String?
    }

    var onPrimary: (() -> Void)?
    var onSecondary: (() -> Void)?

    private let scrim = UIView()
    private let card = UIView()
    private var cardBottomConstraint: NSLayoutConstraint!

    init(content: Content, accentColor: UIColor) {
        super.init(frame: .zero)

        scrim.backgroundColor = UIColor(red: 10/255, green: 12/255, blue: 18/255, alpha: 0.5)
        scrim.alpha = 0
        scrim.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrim)

        card.backgroundColor = .systemBackground
        card.layer.cornerRadius = 28
        card.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let grabber = UIView()
        grabber.backgroundColor = UIColor.tertiaryLabel
        grabber.layer.cornerRadius = 2.5
        grabber.translatesAutoresizingMaskIntoConstraints = false
        let grabberRow = UIView()
        grabberRow.addSubview(grabber)
        NSLayoutConstraint.activate([
            grabber.widthAnchor.constraint(equalToConstant: 36),
            grabber.heightAnchor.constraint(equalToConstant: 5),
            grabber.centerXAnchor.constraint(equalTo: grabberRow.centerXAnchor),
            grabber.topAnchor.constraint(equalTo: grabberRow.topAnchor),
            grabber.bottomAnchor.constraint(equalTo: grabberRow.bottomAnchor)
        ])
        stack.addArrangedSubview(grabberRow)

        //Header: optional icon + title
        let titleLabel = UILabel()
        titleLabel.text = content.title
        titleLabel.font = CobrowseTheme.font(21, .bold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0
        titleLabel.accessibilityTraits = .header

        if let symbol = content.iconSymbol {
            let header = UIStackView()
            header.axis = .horizontal
            header.alignment = .center
            header.spacing = 12

            let iconBackground = UIView()
            iconBackground.backgroundColor = accentColor.withAlphaComponent(0.12)
            iconBackground.layer.cornerRadius = 26
            iconBackground.translatesAutoresizingMaskIntoConstraints = false
            let icon = UIImageView(image: CobrowseTheme.symbol(symbol, size: 24))
            icon.tintColor = accentColor
            icon.translatesAutoresizingMaskIntoConstraints = false
            iconBackground.addSubview(icon)
            NSLayoutConstraint.activate([
                iconBackground.widthAnchor.constraint(equalToConstant: 52),
                iconBackground.heightAnchor.constraint(equalToConstant: 52),
                icon.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
                icon.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor)
            ])

            let titles = UIStackView()
            titles.axis = .vertical
            titles.spacing = 2
            titles.addArrangedSubview(titleLabel)

            header.addArrangedSubview(iconBackground)
            header.addArrangedSubview(titles)
            stack.addArrangedSubview(header)
        } else {
            stack.addArrangedSubview(titleLabel)
        }

        if let body = content.body {
            let bodyLabel = UILabel()
            bodyLabel.text = body
            bodyLabel.font = CobrowseTheme.font(15)
            bodyLabel.textColor = .label
            bodyLabel.numberOfLines = 0
            stack.addArrangedSubview(bodyLabel)
        }

        if !content.bullets.isEmpty {
            let bullets = UIStackView()
            bullets.axis = .vertical
            bullets.spacing = 12
            for text in content.bullets {
                let row = UIStackView()
                row.axis = .horizontal
                row.alignment = .top
                row.spacing = 12
                let check = UIImageView(image: CobrowseTheme.symbol("checkmark", size: 15, weight: .bold))
                check.tintColor = UIColor(red: 14/255, green: 124/255, blue: 102/255, alpha: 1)
                check.setContentHuggingPriority(.required, for: .horizontal)
                check.translatesAutoresizingMaskIntoConstraints = false
                check.widthAnchor.constraint(equalToConstant: 20).isActive = true
                let label = UILabel()
                label.text = text
                label.font = CobrowseTheme.font(15)
                label.textColor = .label
                label.numberOfLines = 0
                row.addArrangedSubview(check)
                row.addArrangedSubview(label)
                bullets.addArrangedSubview(row)
            }
            stack.addArrangedSubview(bullets)
        }

        //Buttons
        let primary = CobrowseAccentButton(type: .custom)
        primary.accentColor = accentColor
        primary.setTitle(content.primaryTitle, for: .normal)
        primary.titleLabel?.font = CobrowseTheme.font(17, .semibold)
        primary.heightAnchor.constraint(equalToConstant: 54).isActive = true
        primary.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)

        let secondary = UIButton(type: .system)
        secondary.setTitle(content.secondaryTitle, for: .normal)
        secondary.titleLabel?.font = CobrowseTheme.font(16, .medium)
        secondary.setTitleColor(.label, for: .normal)
        secondary.heightAnchor.constraint(equalToConstant: 48).isActive = true
        secondary.addTarget(self, action: #selector(secondaryTapped), for: .touchUpInside)

        let buttons = UIStackView(arrangedSubviews: [primary, secondary])
        buttons.axis = .vertical
        buttons.spacing = 8
        stack.addArrangedSubview(buttons)
        stack.setCustomSpacing(20, after: stack.arrangedSubviews[stack.arrangedSubviews.count - 2])

        if let footnote = content.footnote {
            let footnoteLabel = UILabel()
            footnoteLabel.text = footnote
            footnoteLabel.font = CobrowseTheme.font(12)
            footnoteLabel.textColor = .secondaryLabel
            footnoteLabel.textAlignment = .center
            footnoteLabel.numberOfLines = 0
            stack.addArrangedSubview(footnoteLabel)
        }

        cardBottomConstraint = card.bottomAnchor.constraint(equalTo: bottomAnchor)

        //Full width on phones, capped and centered on iPad. Required, so long text wraps instead of widening the card.
        let fullWidth = card.widthAnchor.constraint(equalTo: widthAnchor)
        fullWidth.priority = .required - 1

        NSLayoutConstraint.activate([
            scrim.topAnchor.constraint(equalTo: topAnchor),
            scrim.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrim.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: trailingAnchor),

            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            card.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            fullWidth,
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 600),
            cardBottomConstraint,

            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: card.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])

        accessibilityViewIsModal = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(in container: UIView) {
        translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: container.topAnchor),
            bottomAnchor.constraint(equalTo: container.bottomAnchor),
            leadingAnchor.constraint(equalTo: container.leadingAnchor),
            trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        container.layoutIfNeeded()

        card.transform = CGAffineTransform(translationX: 0, y: card.bounds.height)
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: [.curveEaseOut], animations: {
            self.scrim.alpha = 1
            self.card.transform = .identity
        }, completion: { _ in
            UIAccessibility.post(notification: .screenChanged, argument: self.card)
        })
    }

    func dismiss(completion: (() -> Void)? = nil) {
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseIn], animations: {
            self.scrim.alpha = 0
            self.card.transform = CGAffineTransform(translationX: 0, y: self.card.bounds.height)
        }, completion: { _ in
            self.removeFromSuperview()
            completion?()
        })
    }

    @objc private func primaryTapped() {
        onPrimary?()
    }

    @objc private func secondaryTapped() {
        onSecondary?()
    }
}
