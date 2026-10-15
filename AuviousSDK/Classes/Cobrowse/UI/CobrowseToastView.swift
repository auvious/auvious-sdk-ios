//
//  CobrowseToastView.swift
//  AuviousSDK
//
//  Created by Auvious on 15/10/26.
//

import UIKit

/// A short notice that slides in from the top ("Session ended", "Your agent stopped viewing your screen").
internal final class CobrowseToastView: UIView {

    enum Style {
        /// Navy card with a green check, for the end of the session
        case confirmation
        /// Light card with an info icon, for state changes the customer should know about
        case info
    }

    init(style: Style, title: String?, message: String) {
        super.init(frame: .zero)

        layer.cornerRadius = 16

        let icon = UIImageView()
        icon.contentMode = .center
        icon.translatesAutoresizingMaskIntoConstraints = false

        let iconContainer = UIView()
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.layer.cornerRadius = 16
        iconContainer.addSubview(icon)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = CobrowseTheme.font(15, .semibold)
        titleLabel.numberOfLines = 0
        titleLabel.isHidden = title == nil

        let messageLabel = UILabel()
        messageLabel.text = message
        messageLabel.numberOfLines = 0

        switch style {
        case .confirmation:
            backgroundColor = CobrowseTheme.dock
            iconContainer.backgroundColor = CobrowseTheme.success
            icon.image = CobrowseTheme.symbol("checkmark", size: 15, weight: .bold)
            icon.tintColor = .white
            titleLabel.textColor = .white
            messageLabel.textColor = UIColor(red: 201/255, green: 205/255, blue: 216/255, alpha: 1)
            messageLabel.font = CobrowseTheme.font(13)
        case .info:
            backgroundColor = .systemBackground
            layer.borderWidth = 1
            layer.borderColor = UIColor.separator.cgColor
            iconContainer.backgroundColor = .clear
            icon.image = CobrowseTheme.symbol("exclamationmark.circle", size: 18, weight: .regular)
            icon.tintColor = .secondaryLabel
            titleLabel.textColor = .label
            messageLabel.textColor = .label
            messageLabel.font = CobrowseTheme.font(14)
        }

        let texts = UIStackView(arrangedSubviews: [titleLabel, messageLabel])
        texts.axis = .vertical
        texts.spacing = 2

        let row = UIStackView(arrangedSubviews: [iconContainer, texts])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 32),
            iconContainer.heightAnchor.constraint(equalToConstant: 32),
            icon.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14)
        ])

        isAccessibilityElement = true
        accessibilityLabel = [title, message].compactMap { $0 }.joined(separator: ". ")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows the toast under the given anchor and removes it after `duration`.
    func show(in container: UIView, below anchor: NSLayoutYAxisAnchor, duration: TimeInterval, completion: (() -> Void)? = nil) {
        translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: anchor, constant: 8),
            leadingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor, constant: -20)
        ])

        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: -12)
        UIView.animate(withDuration: 0.25) {
            self.alpha = 1
            self.transform = .identity
        }
        UIAccessibility.post(notification: .announcement, argument: accessibilityLabel)

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self = self else {
                completion?()
                return
            }
            UIView.animate(withDuration: 0.25, animations: {
                self.alpha = 0
            }, completion: { _ in
                self.removeFromSuperview()
                completion?()
            })
        }
    }
}
