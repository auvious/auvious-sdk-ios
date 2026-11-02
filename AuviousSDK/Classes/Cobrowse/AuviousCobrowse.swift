//
//  AuviousCobrowse.swift
//  AuviousSDK
//
//  Created by Auvious on 15/10/26.
//

import Foundation
import UIKit

/**
 Configuration for a mobile co-browse session.

 On mobile, co-browse means the customer shares this app's screen with the agent. Both the agent and the
 customer can draw on the shared screen, and views marked as private are sent as black boxes.
 */
public struct AuviousCobrowseConfiguration {

    //Auth

    /// The co-browse ticket (PIN) created by the agent
    public var ticket: String

    /// OAuth client id
    public var clientId: String = "customer"

    //Server

    /// Base REST endpoint, e.g. "https://auvious.video/"
    public var baseEndpoint: String

    /// MQTT host, e.g. "auvious.video"
    public var mqttEndpoint: String

    //Participant

    /// Optional name shown to the agent
    public var participantName: String?

    /// Optional metadata forwarded to the agent with the join request (customerMetadata)
    public var customerMetadata: [String: Any]?

    //Behaviour

    /// Show a short explanation sheet before the iOS screen recording prompt
    public var showsShareExplainer: Bool = true

    /// Allow the customer to draw on the screen and render the agent's drawings
    public var annotationsEnabled: Bool = true

    //Masking

    /// Which views are blacked out in the shared video. Can also be changed during a session through `AuviousCobrowse.shared.maskingRules`.
    public var masking: AuviousMaskingRules = AuviousMaskingRules()

    /// Outline masked views on the customer's own screen so they know what the agent can't see
    public var showsMaskHints: Bool = true

    //Look

    /// Color of the sharing border, status pill and End button
    public var accentColor: UIColor = CobrowseTheme.defaultAccent

    public init(ticket: String, baseEndpoint: String, mqttEndpoint: String) {
        self.ticket = ticket
        self.baseEndpoint = baseEndpoint
        self.mqttEndpoint = mqttEndpoint
    }
}

/// The state of a co-browse session
public enum AuviousCobrowseState: Equatable {

    /// No session
    case idle

    /// Redeeming the ticket and joining the agent's room
    case connecting

    /// Waiting for the customer to agree to share their screen
    case awaitingConsent

    /// The screen is being shared
    case sharing

    /// Connected, but the screen is not being shared (declined, or the agent stopped viewing)
    case notSharing

    /// The session is over
    case ended
}

/// Why a co-browse session ended
public enum AuviousCobrowseEndReason: Equatable {

    /// The customer tapped End (or the host app called `stop()`)
    case customerEnded

    /// The agent ended the session
    case agentEnded

    /// The session could not continue because of an error
    case failed
}

/// Receives co-browse session updates. All methods are optional and called on the main thread.
public protocol AuviousCobrowseDelegate: AnyObject {

    func cobrowse(didChangeState state: AuviousCobrowseState)

    func cobrowseDidEnd(reason: AuviousCobrowseEndReason)

    func cobrowse(didFailWith error: AuviousSDKGenericError)
}

public extension AuviousCobrowseDelegate {
    func cobrowse(didChangeState state: AuviousCobrowseState) {}
    func cobrowseDidEnd(reason: AuviousCobrowseEndReason) {}
    func cobrowse(didFailWith error: AuviousSDKGenericError) {}
}

/**
 Entry point for mobile co-browse.

 ```
 var config = AuviousCobrowseConfiguration(ticket: pin, baseEndpoint: "https://auvious.video/", mqttEndpoint: "auvious.video")
 config.masking.accessibilityIdentifiers = ["payment.iban", "card.*"]
 AuviousCobrowse.shared.start(configuration: config, delegate: self)
 ```

 The session UI lives in its own window above the app, so the customer can keep navigating while sharing.
 Only one co-browse session can run at a time, and it can't run alongside `AuviousConferenceVCNew`.
 To co-browse during a video call, set `AuviousConferenceConfiguration.cobrowseAvailable` instead.
 */
public final class AuviousCobrowse {

    /// Singleton instance
    public static let shared = AuviousCobrowse()

    /// The current session state
    public private(set) var state: AuviousCobrowseState = .idle

    /// True while a session is connecting or connected
    public var isActive: Bool {
        return controller != nil
    }

    /// The masking rules in effect. Can be changed at any time, also while sharing.
    public var maskingRules: AuviousMaskingRules {
        get { return MaskRegistry.shared.rules }
        set { MaskRegistry.shared.rules = newValue }
    }

    /// Outlines every masked region on the device, labelled with the rule that matched. Use it to check your identifiers.
    public var debugHighlightMasks: Bool {
        get { return MaskRegistry.shared.debugHighlight }
        set { MaskRegistry.shared.debugHighlight = newValue }
    }

    private var controller: CobrowseSessionController?
    private weak var delegate: AuviousCobrowseDelegate?

    private init() {}

    /**
     Redeems the ticket, joins the agent's room and asks the customer to share their screen.

     - Parameter configuration: The session configuration
     - Parameter delegate: Receives state changes, the end of the session and errors
     */
    public func start(configuration: AuviousCobrowseConfiguration, delegate: AuviousCobrowseDelegate?) {
        assert(Thread.isMainThread, "AuviousCobrowse must be used from the main thread")

        guard controller == nil else {
            delegate?.cobrowse(didFailWith: .UNKNOWN_FAILURE)
            return
        }

        guard !configuration.ticket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            delegate?.cobrowse(didFailWith: .INVALID_TICKET(ticketId: configuration.ticket))
            return
        }

        self.delegate = delegate
        MaskRegistry.shared.rules = configuration.masking

        let controller = CobrowseSessionController(configuration: configuration)
        controller.onStateChange = { [weak self] state in
            self?.state = state
            self?.delegate?.cobrowse(didChangeState: state)
        }
        controller.onFailure = { [weak self] error in
            self?.delegate?.cobrowse(didFailWith: error)
        }
        controller.onEnd = { [weak self] reason in
            guard let self = self else { return }
            self.controller = nil
            self.state = .idle
            self.delegate?.cobrowseDidEnd(reason: reason)
        }
        self.controller = controller
        controller.start()
    }

    /// Ends the session, as if the customer tapped End.
    public func stop() {
        controller?.end(reason: .customerEnded)
    }

    /**
     The orientations the app should allow right now. Co-browse is portrait only, also in a video call:
     rotating while the screen is shared stalls it on the agent's side.

     The SDK can't decide the app's orientations itself, so return this from your app delegate.
     It rotates the app to portrait when a session starts and back when it ends.
     ```
     func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
         return AuviousCobrowse.shared.supportedInterfaceOrientations(otherwise: .allButUpsideDown)
     }
     ```
     - Parameter mask: The app's own orientations, used while no session runs
     */
    public func supportedInterfaceOrientations(otherwise mask: UIInterfaceOrientationMask) -> UIInterfaceOrientationMask {
        return CobrowseOverlayWindow.holdsPortrait ? .portrait : mask
    }
}
