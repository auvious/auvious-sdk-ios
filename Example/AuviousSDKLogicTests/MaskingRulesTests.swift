//
//  MaskingRulesTests.swift
//  AuviousSDKLogicTests
//
//  Created by Auvious on 15/10/26.
//

import XCTest
import UIKit

private final class CardNumberField: UITextField {}
private final class PremiumCardNumberField: UITextField {}
private final class SpecialCardField: CardNumberFieldBase {}
private class CardNumberFieldBase: UITextField {}

final class MaskingRulesTests: XCTestCase {

    private let registry = MaskRegistry.shared
    private var savedRules = AuviousMaskingRules()

    override func setUp() {
        super.setUp()
        savedRules = registry.rules
        registry.rules = AuviousMaskingRules()
    }

    override func tearDown() {
        registry.rules = savedRules
        super.tearDown()
    }

    func testIdentifiersMatchExactlyOrByPrefix() {
        var rules = AuviousMaskingRules()
        rules.accessibilityIdentifiers = ["payment.iban", "card.*"]

        XCTAssertTrue(rules.matches(identifier: "payment.iban"))
        XCTAssertFalse(rules.matches(identifier: "payment.iban.label"))
        XCTAssertTrue(rules.matches(identifier: "card.number"))
        XCTAssertTrue(rules.matches(identifier: "card."))
        XCTAssertFalse(rules.matches(identifier: "cards"))
    }

    func testNothingIsMaskedByDefault() {
        XCTAssertNil(registry.matchReason(for: UIView()))
        XCTAssertNil(registry.matchReason(for: UITextField()))
    }

    func testExplicitFlagsWin() {
        registry.rules.accessibilityIdentifiers = ["secret"]

        let view = UIView()
        view.accessibilityIdentifier = "secret"
        XCTAssertEqual(registry.matchReason(for: view), "id: secret")

        view.auviousMasked = false
        XCTAssertNil(registry.matchReason(for: view), "Explicit false beats every rule")

        view.auviousMasked = true
        XCTAssertEqual(registry.matchReason(for: view), "explicit")

        view.auviousMasked = nil
        XCTAssertEqual(registry.matchReason(for: view), "id: secret")
    }

    func testClassRulesIncludeSubclasses() {
        registry.rules.viewClasses = [CardNumberFieldBase.self, CardNumberField.self]

        XCTAssertNotNil(registry.matchReason(for: CardNumberField()))
        XCTAssertNotNil(registry.matchReason(for: SpecialCardField()))
        XCTAssertNil(registry.matchReason(for: PremiumCardNumberField()))
    }

    func testSecureFieldsAreMaskedByDefault() {
        let pin = UITextField()
        pin.isSecureTextEntry = true
        XCTAssertEqual(registry.matchReason(for: pin), "secure")

        registry.rules.maskSecureTextFields = false
        XCTAssertNil(registry.matchReason(for: pin))
    }

    func testMaskAllTextInputsWithOptOut() {
        registry.rules.maskAllTextInputs = true

        XCTAssertEqual(registry.matchReason(for: UITextField()), "text input")
        XCTAssertEqual(registry.matchReason(for: UITextView()), "text input")
        XCTAssertNil(registry.matchReason(for: UILabel()))

        let reference = UITextField()
        reference.auviousMasked = false
        XCTAssertNil(registry.matchReason(for: reference))
    }
}
