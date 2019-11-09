//
//  CallIceCandidatesRequest.swift
//  AuviousSDK
//
//  Created by Jace on 03/05/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import Foundation

internal final class CallIceCandidatesRequest {
    
    var callId: String!
    var iceCandidates: [IceCandidate]!
    var userEndpointId: String!
    var userId: String!
    
    init(callId: String, candidates: [IceCandidate], userEndpointId: String, userId: String) {
        self.callId = callId
        self.iceCandidates = candidates
        self.userEndpointId = userEndpointId
        self.userId = userId
    }
    
    func toDictionary() -> [String:Any] {
        var dictionary = [String:Any]()
        
        if callId != nil {
            dictionary["callId"] = callId
        }
        
        if iceCandidates != nil {
            var dictionaryElements = [[String:Any]]()
            for element in iceCandidates {
                dictionaryElements.append(element.toDictionary())
            }
            dictionary["iceCandidates"] = dictionaryElements
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
