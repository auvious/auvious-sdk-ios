//
//  CallHangupRequest.swift
//  AuviousSDK
//
//  Created by Jace on 03/05/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import Foundation

internal final class CallHangupRequest {
    
    var callId: String!
    var reason: String!
    var userEndpointId: String!
    var userId: String!
    
    init(callId: String, reason: String, userEndpointId: String, userId: String){
        self.callId = callId
        self.reason = reason
        self.userEndpointId = userEndpointId
        self.userId = userId
    }
    
    func toDictionary() -> [String:Any] {
        var dictionary = [String:Any]()
        
        if callId != nil {
            dictionary["callId"] = callId
        }
        
        if reason != nil {
            dictionary["reason"] = reason
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
