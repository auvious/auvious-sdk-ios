//
//  UnpublishStreamRequest.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 29/11/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import Foundation

internal final class UnpublishStreamRequest {
    
    var conferenceId: String!
    var streamId: String!
    var userEndpointId: String!
    var userId: String!
    
    init(conferenceId: String, streamId: String, userEndpointId: String, userId: String) {
        self.conferenceId = conferenceId
        self.streamId = streamId
        self.userEndpointId = userEndpointId
        self.userId = userId
    }
    
    func toDictionary() -> [String:Any] {
        var dictionary = [String:Any]()
        
        if conferenceId != nil {
            dictionary["conferenceId"] = conferenceId
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
        
        return dictionary
    }
    
}
