//
//  CobrowseToastView.swift
//  AuviousSDK
//
//  Created by Auvious on 15/10/26.
//

import UIKit

/// A co-browse notice ("Session ended", "Your agent stopped viewing your screen") in the SDK's shared
/// banner style. Slides in from the top; tap or swipe up to dismiss early.
internal final class CobrowseToastView: AuviousBannerView {

    enum Style {
        /// The session is over
        case ended
        /// A state change the customer should know about
        case info
        /// Something didn't work
        case warning

        var symbol: String {
            switch self {
            case .ended:
                return "checkmark.circle.fill"
            case .info:
                return "eye.slash.fill"
            case .warning:
                return "exclamationmark.triangle.fill"
            }
        }

        var tint: UIColor {
            switch self {
            case .ended:
                return .systemGreen
            case .info:
                return .secondaryLabel
            case .warning:
                return .systemOrange
            }
        }
    }

    private var completion: (() -> Void)?
    private var isDismissing = false

    init(style: Style, title: String?, message: String) {
        super.init(frame: .zero)
        configure(symbol: style.symbol, tint: style.tint, title: title, message: message)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissTapped)))
        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(dismissTapped))
        swipe.direction = .up
        addGestureRecognizer(swipe)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows the notice under the given anchor and removes it after `duration`.
    func show(in container: UIView, below anchor: NSLayoutYAxisAnchor, duration: TimeInterval, completion: (() -> Void)? = nil) {
        self.completion = completion

        translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: anchor, constant: 8),
            leadingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.leadingAnchor, constant: 10),
            trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 60)
        ])
        container.layoutIfNeeded()

        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: -(frame.maxY + 20))
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0, options: [.allowUserInteraction], animations: {
            self.alpha = 1
            self.transform = .identity
        })
        UIAccessibility.post(notification: .announcement, argument: accessibilityLabel)

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.dismiss()
        }
    }

    @objc private func dismissTapped() {
        dismiss()
    }

    private func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true

        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseIn], animations: {
            self.alpha = 0
            self.transform = CGAffineTransform(translationX: 0, y: -(self.frame.maxY + 20))
        }, completion: { _ in
            self.removeFromSuperview()
            let completion = self.completion
            self.completion = nil
            completion?()
        })
    }
}
