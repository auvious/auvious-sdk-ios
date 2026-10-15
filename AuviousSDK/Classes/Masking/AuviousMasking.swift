//
//  AuviousMasking.swift
//  AuviousSDK
//
//  Created by Auvious on 15/10/26.
//

import UIKit
import SwiftUI

/**
 Decides which parts of the screen are sent as black boxes while the customer shares their screen.

 A view is masked when, in order of precedence:
 1. it is explicitly marked with `auviousMasked = false` → never masked (beats every rule below),
 2. it is explicitly marked with `auviousMasked = true`,
 3. its `accessibilityIdentifier` matches `accessibilityIdentifiers`,
 4. it is an instance (or subclass instance) of one of `viewClasses`,
 5. one of the defaults applies (`maskSecureTextFields`, `maskAllTextInputs`).

 The whole frame of a masked view is covered, including its subviews. Mask the smallest container
 that holds the sensitive content (the field, not the form).
 */
public struct AuviousMaskingRules {

    /// Exact identifiers, or prefixes ending with `*` (e.g. `"card.*"`)
    public var accessibilityIdentifiers: Set<String> = []

    /// View classes to mask, subclasses included (e.g. a custom `CardNumberField`)
    public var viewClasses: [UIView.Type] = []

    /// Mask password fields, and the keyboard while one is being edited
    public var maskSecureTextFields: Bool = true

    /// Privacy-first mode: mask every `UITextField` and `UITextView` unless it is marked `auviousMasked = false`
    public var maskAllTextInputs: Bool = false

    public init() {}

    /// True when the identifier matches one of the configured identifiers or prefixes
    internal func matches(identifier: String) -> Bool {
        if accessibilityIdentifiers.contains(identifier) {
            return true
        }
        for pattern in accessibilityIdentifiers where pattern.hasSuffix("*") {
            if identifier.hasPrefix(String(pattern.dropLast())) {
                return true
            }
        }
        return false
    }
}

private var auviousMaskedKey: UInt8 = 0

public extension UIView {

    /**
     Explicitly masks (`true`) or un-masks (`false`) this view in the co-browse screen share.
     `nil` (the default) leaves the decision to `AuviousCobrowse.shared.maskingRules`.

     The mask follows the view's frame on every frame, so it can be set once when the view is created.
     */
    var auviousMasked: Bool? {
        get {
            return (objc_getAssociatedObject(self, &auviousMaskedKey) as? NSNumber)?.boolValue
        }
        set {
            objc_setAssociatedObject(self, &auviousMaskedKey, newValue.map { NSNumber(value: $0) }, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

@available(iOS 13.0, *)
public extension View {

    /**
     Masks (`true`) or explicitly un-masks (`false`) this view in the co-browse screen share.
     The masked area is the view's frame.
     */
    func auviousMasked(_ masked: Bool = true) -> some View {
        return background(AuviousMaskAnchor(masked: masked))
    }
}

/// A UIKit anchor sized to the SwiftUI view it backs, so the UIKit-based mask registry can find it
@available(iOS 13.0, *)
private struct AuviousMaskAnchor: UIViewRepresentable {

    let masked: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.auviousMasked = masked
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.auviousMasked = masked
    }
}
