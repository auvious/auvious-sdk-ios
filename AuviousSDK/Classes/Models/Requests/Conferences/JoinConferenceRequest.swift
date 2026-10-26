//
//  JoinConferenceRequest.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 29/11/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import Foundation

/// Determines how this endpoint presents itself to the other participants when joining a conference.
internal enum JoinProfile {

    /// Regular audio/video call participant
    case stream

    /// Co-browse customer sharing their app screen (agent side treats it as a display-capture participant)
    case displayCapture(originUrl: String, customerMetadata: [String: Any]?)
}

internal final class JoinConferenceRequest {
    
    var conferenceId: String!
    var userEndpointId: String!
    var userId: String!
    var participantName: String?
    
    init(conferenceId: String, userEndpointId: String, userId: String, participantName: String?) {
        self.conferenceId = conferenceId
        self.userEndpointId = userEndpointId
        self.userId = userId
        self.participantName = participantName
    }
    
    func toDictionary() -> [String:Any] {
        var dictionary = [String:Any]()
        
        if conferenceId != nil {
            dictionary["conferenceId"] = conferenceId
        }
        
        if userEndpointId != nil {
            dictionary["userEndpointId"] = userEndpointId
        }
        
        if userId != nil {
            dictionary["userId"] = userId
        }
        
        //Metadata
        var metaDataDictionary = [String:Any]()
        metaDataDictionary["roles"] = ["CUSTOMER"]

        switch AuviousConferenceSDK.sharedInstance.joinProfile {
        case .stream:
            metaDataDictionary["capabilities"] = JoinConferenceRequest.streamCapabilities(AuviousConferenceSDK.sharedInstance.uiConfiguration)
            metaDataDictionary["type"] = "stream"

        case .displayCapture(let originUrl, let customerMetadata):
            //"co-browse" is deliberately not advertised, it would offer the web-only DOM co-browse to the agent.
            //No "ar-pointer" either: the agent can't point at a co-browse screen, only sketch on it.
            metaDataDictionary["capabilities"] = JoinConferenceRequest.displayCaptureCapabilities
            metaDataDictionary["type"] = "displayCapture"
            metaDataDictionary["originUrl"] = originUrl
            metaDataDictionary["customerMetadata"] = customerMetadata ?? NSNull()
        }

        metaDataDictionary["language"] = Utilities.getApplicationLanguage()
        metaDataDictionary["mediaDevices"] = Utilities.getMediaDevices()
        
        if let participantName = participantName {
            metaDataDictionary["name"] = participantName
        } else {
            metaDataDictionary["name"] = NSNull()
        }
        
        metaDataDictionary["avatarUrl"] = NSNull()
        metaDataDictionary["deviceInfo"] = Utilities.getDeviceInfo()
        
        dictionary["metadata"] = metaDataDictionary

        return dictionary
    }

    //MARK: Capabilities

    static let displayCaptureCapabilities = ["display-capture", "sketch"]

    /// What a call participant offers the agent. "sketch" means we render and draw sketches on what we share.
    static func streamCapabilities(_ configuration: AuviousConferenceConfiguration) -> [String] {
        var capabilities: [String] = []
        if configuration.screenSharingAvailable || configuration.cobrowseAvailable {
            capabilities.append("display-capture")
        }
        //Points and sketch on our camera and on a regular screen share
        if configuration.arPointerAvailable {
            capabilities.append("ar-pointer")
        }
        //In-call co-browse: the agent asks this endpoint to share its screen (no ticket, no second endpoint)
        if configuration.cobrowseAvailable {
            capabilities.append("native-co-browse")
        }
        if configuration.arPointerAvailable || configuration.cobrowseAvailable {
            capabilities.append("sketch")
        }
        return capabilities
    }
}
