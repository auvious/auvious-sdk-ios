//
//  CobrowseDemoViewController.swift
//  ExampleSimpleConference
//
//  Created by Auvious on 15/10/26.
//  Copyright © 2026 Auvious. All rights reserved.
//

import UIKit
import SwiftUI
import AuviousSDK

/// Example-only switches for the sample form, set from the main screen before co-browse starts
enum CobrowseDemoSettings {
    /// When false, the sample form leaves `auviousMasked` unset, so only the rules decide
    static var marksViews = true
}

/// A text field type masked by class rule (`AuviousMaskingRules.viewClasses`)
final class CardNumberField: UITextField {}

/**
 A sample "Send money" screen to try co-browse masking. It shows the three ways to mask content:
 - the account field is marked with `auviousMasked = true`,
 - the IBAN field is masked by its accessibility identifier ("payment.iban"),
 - the card field is masked by its class (`CardNumberField`),
 - the PIN field is a secure text field (masked by default, with the keyboard while editing).
 */
final class CobrowseDemoViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let referenceField = UITextField()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Send money"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .always

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)

        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        let accountField = makeField(placeholder: "Account", text: "GR16 0110 1250 0000 0001 2345")
        if CobrowseDemoSettings.marksViews {
            accountField.auviousMasked = true
        }

        let amountField = makeField(placeholder: "Amount", text: "€ 250.00")
        amountField.keyboardType = .decimalPad

        let ibanField = makeField(placeholder: "IBAN", text: "DE89 3704 0044 0532 0130 00")
        ibanField.accessibilityIdentifier = "payment.iban"

        let cardField = CardNumberField()
        configure(cardField, placeholder: "Card number", text: "4111 1111 1111 1111")
        cardField.keyboardType = .numberPad

        configure(referenceField, placeholder: "Reference", text: "Rent, October")
        //Opted out: stays visible even in "mask all text inputs" mode
        if CobrowseDemoSettings.marksViews {
            referenceField.auviousMasked = false
        }

        let pinField = makeField(placeholder: "PIN", text: "")
        pinField.isSecureTextEntry = true
        pinField.keyboardType = .numberPad

        stack.addArrangedSubview(section("From account · auviousMasked = true", accountField))
        stack.addArrangedSubview(section("Amount", amountField))
        stack.addArrangedSubview(section("Recipient IBAN · identifier rule", ibanField))
        stack.addArrangedSubview(section("Card · class rule", cardField))
        stack.addArrangedSubview(section("Reference · auviousMasked = false", referenceField))
        stack.addArrangedSubview(section("PIN · secure field", pinField))

        stack.addArrangedSubview(toggleRow("Mask all text inputs", isOn: AuviousCobrowse.shared.maskingRules.maskAllTextInputs, action: #selector(maskAllToggled(_:))))
        stack.addArrangedSubview(toggleRow("Highlight masks (debug)", isOn: AuviousCobrowse.shared.debugHighlightMasks, action: #selector(debugToggled(_:))))

        let swiftUIButton = UIButton(type: .system)
        swiftUIButton.setTitle("Open the SwiftUI version", for: .normal)
        swiftUIButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        swiftUIButton.addTarget(self, action: #selector(openSwiftUI), for: .touchUpInside)
        stack.addArrangedSubview(swiftUIButton)

        let continueButton = UIButton(type: .system)
        continueButton.setTitle("Continue", for: .normal)
        continueButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        continueButton.setTitleColor(.white, for: .normal)
        continueButton.backgroundColor = UIColor(red: 14/255, green: 124/255, blue: 102/255, alpha: 1)
        continueButton.layer.cornerRadius = 27
        continueButton.translatesAutoresizingMaskIntoConstraints = false
        continueButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)
        view.addSubview(continueButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: continueButton.topAnchor, constant: -12),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),

            continueButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            continueButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            continueButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            continueButton.heightAnchor.constraint(equalToConstant: 54)
        ])
    }

    //MARK: Builders

    private func makeField(placeholder: String, text: String) -> UITextField {
        let field = UITextField()
        configure(field, placeholder: placeholder, text: text)
        return field
    }

    private func configure(_ field: UITextField, placeholder: String, text: String) {
        field.placeholder = placeholder
        field.text = text
        field.borderStyle = .roundedRect
        field.font = .systemFont(ofSize: 16)
        field.autocorrectionType = .no
        field.heightAnchor.constraint(equalToConstant: 48).isActive = true
    }

    private func section(_ title: String, _ field: UIView) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabel

        let section = UIStackView(arrangedSubviews: [label, field])
        section.axis = .vertical
        section.spacing = 6
        return section
    }

    private func toggleRow(_ title: String, isOn: Bool, action: Selector) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 16)

        let toggle = UISwitch()
        toggle.isOn = isOn
        toggle.addTarget(self, action: action, for: .valueChanged)

        let row = UIStackView(arrangedSubviews: [label, toggle])
        row.axis = .horizontal
        row.alignment = .center
        return row
    }

    //MARK: Actions

    @objc private func maskAllToggled(_ sender: UISwitch) {
        AuviousCobrowse.shared.maskingRules.maskAllTextInputs = sender.isOn
    }

    @objc private func debugToggled(_ sender: UISwitch) {
        AuviousCobrowse.shared.debugHighlightMasks = sender.isOn
    }

    @objc private func openSwiftUI() {
        let controller = UIHostingController(rootView: CobrowseSwiftUIDemoView())
        controller.title = "Send money (SwiftUI)"
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func continueTapped() {
        view.endEditing(true)
        navigationController?.pushViewController(CobrowseReviewViewController(), animated: true)
    }
}

/// A second screen, to show that the co-browse session survives navigation
final class CobrowseReviewViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Review"
        view.backgroundColor = .systemGroupedBackground

        let summary = UILabel()
        summary.numberOfLines = 0
        summary.font = .systemFont(ofSize: 17)
        summary.text = "You're sending € 250.00 to DE89 •••• 3000.\n\nThe agent can still see this screen and draw on it."
        summary.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(summary)

        NSLayoutConstraint.activate([
            summary.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            summary.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            summary.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20)
        ])
    }
}
