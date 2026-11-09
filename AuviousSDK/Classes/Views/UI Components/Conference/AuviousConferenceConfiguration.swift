//
//  AuviousConferenceConfiguration.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 7/10/24.
//

import Foundation

public struct AuviousConferenceConfiguration {
    
    //Auth
    public var username: String = ""
    public var password: String = ""
    public var grantType: String = "password"
    
    //Conference
    public var clientId: String = "customer"
    public var conference: String = ""
    public var baseEndpoint: String = ""
    public var mqttEndpoint: String = ""
    
    //UI
    public var conferenceBackgroundColor: UIColor = UIColor(red: 0x23/255, green: 0x29/255, blue: 0x31/255, alpha: 1) // #232931
    public var enableSpeaker = true
    public var cameraAvailable = true
    public var microphoneAvailable = true
    public var speakerAvailable = true
    public var pipAvailable: Bool = true
    public var screenSharingAvailable: Bool = true
    
    //Background
    /// When true, audio continues in background instead of leaving the conference.
    /// Host app must add UIBackgroundModes "audio" to Info.plist.
    public var backgroundAudioEnabled: Bool = false

    //Co-browse
    /// Lets the agent ask to co-browse this app during the call. The customer shares the app's screen
    /// (masked like a standalone co-browse session) and the call shrinks to PiP while sharing.
    public var cobrowseAvailable: Bool = false

    /// Which views are blacked out in the co-browse screen share
    public var cobrowseMasking: AuviousMaskingRules = AuviousMaskingRules()

    /// Allow the customer to draw on the shared screen and render the agent's drawings
    public var cobrowseAnnotationsEnabled: Bool = true

    /// Outline masked views on the customer's own screen so they know what the agent can't see
    public var cobrowseShowsMaskHints: Bool = true

    /// Show a short explanation sheet before the iOS screen recording prompt
    public var cobrowseShowsShareExplainer: Bool = true

    //AR pointer
    /// Lets the agent point and draw on this customer's camera and on a regular screen share
    /// (never on a co-browse screen). The customer sees the points and ink and can annotate back.
    public var arPointerAvailable: Bool = true

    //Other
    public var participantName: String? = nil
    
    //Stream properties
    public var callMode: AuviousCallMode = .audioVideo
    
    public init() {
        
    }
}
