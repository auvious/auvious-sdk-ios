//
//  IceCandidate.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 29/11/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import Foundation

final class IceCandidate {
    var candidate: String!
    var sdpMLineIndex: Int32!
    var sdpMid: String!
    
    init(candidate: String, sdpMLineIndex: Int32, sdpMid: String) {
        self.candidate = candidate
        self.sdpMLineIndex = sdpMLineIndex
        self.sdpMid = sdpMid
    }
    
    func toDictionary() -> [String:Any] {
        var dictionary = [String:Any]()
        
        if candidate != nil {
            dictionary["candidate"] = candidate
        }
        
        if sdpMLineIndex != nil {
            dictionary["sdpMLineIndex"] = sdpMLineIndex
        }
        
        if sdpMid != nil {
            dictionary["sdpMid"] = sdpMid
        }
        
        return dictionary
    }
}
