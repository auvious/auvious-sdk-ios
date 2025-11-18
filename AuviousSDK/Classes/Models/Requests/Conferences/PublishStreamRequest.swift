//
//  PublishStreamRequest.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 29/11/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import Foundation

internal final class PublishStreamRequest {
    
    var conferenceId: String!
    var streamType: StreamType!
    var sdpOffer: String!
    var streamId: String!
    var userEndpointId: String!
    var userId: String!
    var participantName: String?
    
    init(conferenceId: String, streamType: StreamType, sdpOffer: String, streamId: String, userEndpointId: String, userId: String, participantName: String?) {
        self.conferenceId = conferenceId
        self.streamType = streamType
        self.sdpOffer = sdpOffer
        self.streamId = streamId
        self.userEndpointId = userEndpointId
        self.userId = userId
        self.participantName = participantName
    }
    
    func toDictionary() -> [String:Any] {
        var dictionary = [String:Any]()
        
        if conferenceId != nil {
            dictionary["conferenceId"] = conferenceId
        }
        
        if streamType != nil {
            dictionary["conferenceStreamType"] = streamType.rawValue
        }
        
        if sdpOffer != nil {
            dictionary["sdpOffer"] = sdpOffer
        }
        
        if streamId != nil {
            dictionary["streamId"] = streamId
        }
        
        if userEndpointId != nil {
            dictionary["userEndpointId"] = userEndpointId
        }
        
        if userId != nil {
            dictionary["userId"] = userId
        }
        
        //Metadata
        var metaDataDictionary = [String:Any]()
        metaDataDictionary["correlationId"] = streamId
        metaDataDictionary["primary"] = true
        metaDataDictionary["portraitMode"] = false
        metaDataDictionary["participantRoles"] = ["CUSTOMER"]
        if let participantName = participantName {
            metaDataDictionary["participantName"] = participantName
        } else {
            metaDataDictionary["participantName"] = NSNull()
        }
        
        dictionary["metadata"] = metaDataDictionary
        
        return dictionary
    }
}
