//
//  CobrowseSwiftUIDemo.swift
//  ExampleSimpleConference
//
//  Created by Auvious on 15/10/26.
//  Copyright © 2026 Auvious. All rights reserved.
//

import SwiftUI
import AuviousSDK

/// The co-browse sample form in SwiftUI. In SwiftUI, mask views with the `.auviousMasked()` modifier.
struct CobrowseSwiftUIDemoView: View {

    @State private var account = "GR16 0110 1250 0000 0001 2345"
    @State private var amount = "€ 250.00"
    @State private var iban = "DE89 3704 0044 0532 0130 00"
    @State private var pin = ""

    var body: some View {
        Form {
            Section(header: Text("From account · .auviousMasked()")) {
                TextField("Account", text: $account)
                    .demoMasked()
            }

            Section(header: Text("Amount")) {
                TextField("Amount", text: $amount)
            }

            Section(header: Text("Recipient IBAN · .auviousMasked()")) {
                TextField("IBAN", text: $iban)
                    .demoMasked()
            }

            Section(header: Text("PIN · secure field")) {
                SecureField("PIN", text: $pin)
                    .demoMasked()
            }
        }
    }
}

private extension View {

    /// `.auviousMasked()`, unless marked views are turned off on the main screen
    @ViewBuilder func demoMasked() -> some View {
        if CobrowseDemoSettings.marksViews {
            auviousMasked()
        } else {
            self
        }
    }
}
