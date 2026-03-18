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
    public var conferenceBackgroundColor: UIColor = .darkGray
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

    //Other
    public var participantName: String? = nil
    
    //Stream properties
    public var callMode: AuviousCallMode = .audioVideo
    
    public init() {
        
    }
}
