//
//  JoinConferenceRequest.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 29/11/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import Foundation

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
        
        if AuviousConferenceSDK.sharedInstance.uiConfiguration.screenSharingAvailable {
            metaDataDictionary["capabilities"] = ["display-capture"]
        } else {
            metaDataDictionary["capabilities"] = []
        }
        
        metaDataDictionary["language"] = Utilities.getApplicationLanguage()
        metaDataDictionary["type"] = "stream"
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
