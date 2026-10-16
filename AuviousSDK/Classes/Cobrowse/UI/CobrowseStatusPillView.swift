//
//  CobrowseStatusPillView.swift
//  AuviousSDK
//
//  Created by Auvious on 15/10/26.
//

import UIKit

/// The pill under the status bar / Dynamic Island that tells the customer what is happening.
internal final class CobrowseStatusPillView: UIView {

    enum Mode: Equatable {
        case connecting
        case sharing(since: Date)
        case drawing
        case notSharing
    }

    /// Called when the customer taps Share in the not sharing state
    var onShare: (() -> Void)?

    var accentColor: UIColor = CobrowseTheme.defaultAccent {
        didSet { applyMode() }
    }

    /// Shown when the pill is expanded ("Sharing with Anna")
    var agentName: String? {
        didSet { applyMode() }
    }

    private(set) var mode: Mode = .connecting

    private let gradient = CAGradientLayer()
    private let stack = UIStackView()
    private let dot = UIView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let separatorLabel = UILabel()
    private let timerLabel = UILabel()
    private let shareButton = UIButton(type: .system)

    private var trailingConstraint: NSLayoutConstraint!
    private var timer: Timer?
    private var isExpanded = false
    private var collapseWorkItem: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)

        layer.cornerRadius = 16
        layer.masksToBounds = true

        //Sharing uses the SDK's red gradient, like the End button
        CobrowseTheme.applyRedGradient(to: gradient)
        gradient.isHidden = true
        layer.insertSublayer(gradient, at: 0)

        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        dot.backgroundColor = .white
        dot.layer.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false

        spinner.color = .white
        spinner.hidesWhenStopped = true

        iconView.tintColor = UIColor(red: 247/255, green: 162/255, blue: 52/255, alpha: 1)
        iconView.image = CobrowseTheme.penIcon(size: 15, stroke: 1.2)
        iconView.contentMode = .scaleAspectFit

        for label in [titleLabel, separatorLabel, timerLabel] {
            label.textColor = .white
            label.font = CobrowseTheme.font(14, .semibold)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        separatorLabel.text = "·"
        separatorLabel.alpha = 0.7
        timerLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)

        shareButton.setTitle(CobrowseStrings.share, for: .normal)
        shareButton.titleLabel?.font = CobrowseTheme.font(13, .semibold)
        shareButton.setTitleColor(CobrowseTheme.dock, for: .normal)
        shareButton.backgroundColor = .white
        shareButton.layer.cornerRadius = 12
        shareButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)

        for view in [dot, spinner, iconView, titleLabel, separatorLabel, timerLabel, shareButton] {
            stack.addArrangedSubview(view)
        }

        trailingConstraint = stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14)

        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            shareButton.heightAnchor.constraint(equalToConstant: 24),
            heightAnchor.constraint(equalToConstant: 32),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            trailingConstraint
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(pillTapped)))
        isAccessibilityElement = false
        applyMode()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        timer?.invalidate()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
    }

    func setMode(_ mode: Mode) {
        self.mode = mode
        applyMode()
    }

    private func applyMode() {
        timer?.invalidate()
        timer = nil
        spinner.stopAnimating()
        gradient.isHidden = true

        dot.isHidden = true
        iconView.isHidden = true
        separatorLabel.isHidden = true
        timerLabel.isHidden = true
        shareButton.isHidden = true
        trailingConstraint.constant = -14

        switch mode {
        case .connecting:
            backgroundColor = CobrowseTheme.neutralPill
            spinner.startAnimating()
            titleLabel.text = CobrowseStrings.connecting

        case .sharing:
            backgroundColor = accentColor
            gradient.isHidden = !CobrowseTheme.usesRedGradient(accentColor)
            dot.isHidden = false
            dot.backgroundColor = .white
            dot.layer.borderWidth = 0
            separatorLabel.isHidden = false
            timerLabel.isHidden = false
            titleLabel.text = isExpanded ? CobrowseStrings.sharingWith(agentName) : CobrowseStrings.sharing
            updateTimer()
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                self?.updateTimer()
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer

        case .drawing:
            backgroundColor = CobrowseTheme.dock
            iconView.isHidden = false
            titleLabel.text = CobrowseStrings.drawing

        case .notSharing:
            backgroundColor = CobrowseTheme.neutralPill
            dot.isHidden = false
            dot.backgroundColor = .clear
            dot.layer.borderColor = UIColor.white.cgColor
            dot.layer.borderWidth = 2
            titleLabel.text = CobrowseStrings.notSharing
            shareButton.isHidden = false
            //The Share button sits close to the pill's edge
            trailingConstraint.constant = -4
        }

        accessibilityLabel = [titleLabel.text, timerLabel.isHidden ? nil : timerLabel.text].compactMap { $0 }.joined(separator: ", ")
    }

    private func updateTimer() {
        guard case .sharing(let since) = mode else { return }
        let elapsed = max(0, Int(Date().timeIntervalSince(since)))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60
        timerLabel.text = hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%02d:%02d", minutes, seconds)
    }

    @objc private func shareTapped() {
        onShare?()
    }

    @objc private func pillTapped() {
        guard case .sharing = mode else { return }

        isExpanded = true
        applyMode()

        collapseWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.isExpanded = false
            self?.applyMode()
        }
        collapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
    }
}
