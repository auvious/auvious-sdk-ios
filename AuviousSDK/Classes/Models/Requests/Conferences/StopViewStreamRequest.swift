//
//  StopViewStreamRequest.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 29/11/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import Foundation

internal final class StopViewStreamRequest {
    
    var conferenceId: String!
    var streamId: String!
    var userEndpointId: String!
    var userId: String!
    var viewerId: String!
    
    init(conferenceId: String, streamId: String, userEndpointId: String, userId: String, viewerId: String) {
        self.conferenceId = conferenceId
        self.streamId = streamId
        self.userEndpointId = userEndpointId
        self.userId = userId
        self.viewerId = viewerId
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
        
        if viewerId != nil {
            dictionary["viewerId"] = viewerId
        }
        
        return dictionary
    }
    
}
