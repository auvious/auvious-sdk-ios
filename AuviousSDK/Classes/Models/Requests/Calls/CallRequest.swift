//
//  CallRequest.swift
//  AuviousSDK
//
//  Created by Jace on 03/05/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import Foundation

internal final class CallRequest {
    
    var callId: String!
    var sdpOffer: String!
    var target: String!
    var userEndpointId: String!
    var userId: String!
    var sipHeaders: [String : String]?
    
    init(callId: String, sdpOffer: String, target: String, userEndpointId: String, userId: String, sipHeaders: [String : String]? = nil){
        self.callId = callId
        self.sdpOffer = sdpOffer
        self.target = target
        self.userEndpointId = userEndpointId
        self.userId = userId
        self.sipHeaders = sipHeaders
    }
    
    func toDictionary() -> [String:Any] {
        var dictionary = [String:Any]()
        
        if callId != nil {
            dictionary["callId"] = callId
        }
        
        if sdpOffer != nil {
            dictionary["sdpOffer"] = sdpOffer
        }
        
        if userEndpointId != nil {
            dictionary["userEndpointId"] = userEndpointId
        }
        
        if userId != nil {
            dictionary["userId"] = userId
        }
        
        if target != nil {
            dictionary["target"] = target
        }
        
        if sipHeaders != nil {
            dictionary["sipHeaders"] = sipHeaders
        }

        return dictionary
    }
}
