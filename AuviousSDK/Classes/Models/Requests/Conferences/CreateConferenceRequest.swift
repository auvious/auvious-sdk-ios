//
//  CreateConferenceRequest.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 29/11/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import Foundation

internal final class CreateConferenceRequest {
    
    var conferenceId: String!
    var creatorId: String!
    var creatorEndpoint: String!
    var mode: ConferenceMode!
    
    init(conferenceId: String, creatorId: String, creatorEndpoint: String, mode: ConferenceMode) {
        self.conferenceId = conferenceId
        self.creatorId = creatorId
        self.creatorEndpoint = creatorEndpoint
        self.mode = mode
    }
    
    func toDictionary() -> [String:Any] {
        var dictionary = [String:Any]()
        
        if conferenceId != nil {
            dictionary["conferenceId"] = conferenceId
        }
        
        if creatorId != nil {
            dictionary["creator"] = creatorId
        }
        
        if creatorEndpoint != nil {
            dictionary["creatorEndpoint"] = creatorEndpoint
        }
        
        if mode != nil {
            dictionary["mode"] = mode.rawValue
        }
        
        return dictionary
    }
    
}
