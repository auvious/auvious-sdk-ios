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
    public var clientId: String = ""
    public var conference: String = ""
    public var baseEndpoint: String = ""
    public var mqttEndpoint: String = ""
    
    //UI
    public var conferenceBackgroundColor: UIColor = .gray
    public var enableSpeaker = true
    public var cameraAvailable = true
    public var microphoneAvailable = true
    public var speakerAvailable = true
    
    //Stream properties
    public var callMode: AuviousCallMode = .audioVideo
    
    public init() {
        
    }
}
