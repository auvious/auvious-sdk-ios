//
//  CallAnswerRequest.swift
//  AuviousSDK
//
//  Created by Jace on 03/05/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import Foundation

internal final class CallAnswerRequest {
    
    var callId: String!
    var sdpAnswer: String!
    var userEndpointId: String!
    var userId: String!
    
    init(callId: String, sdpAnswer: String, userEndpointId: String, userId: String){
        self.callId = callId
        self.sdpAnswer = sdpAnswer
        self.userEndpointId = userEndpointId
        self.userId = userId
    }
    
    func toDictionary() -> [String:Any] {
        var dictionary = [String:Any]()
        
        if callId != nil {
            dictionary["callId"] = callId
        }
        
        if sdpAnswer != nil {
            dictionary["sdpAnswer"] = sdpAnswer
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
