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
            if AuviousConferenceSDK.sharedInstance.uiConfiguration.screenSharingAvailable {
                metaDataDictionary["capabilities"] = ["display-capture"]
            } else {
                metaDataDictionary["capabilities"] = []
            }
            metaDataDictionary["type"] = "stream"

        case .displayCapture(let originUrl, let customerMetadata):
            //"co-browse" is deliberately not advertised, it would offer the web-only DOM co-browse to the agent
            metaDataDictionary["capabilities"] = ["display-capture", "ar-pointer"]
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
}
