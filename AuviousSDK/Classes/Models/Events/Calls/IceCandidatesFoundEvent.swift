//
//  IceCandidatesFoundEvent.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 08/05/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import Foundation
import SwiftyJSON

public class IceCandidatesFoundEvent: CallEvent {
    
    var iceCandidates: [IceCandidate]!
    
    /// Initialiser using a JSON object
    override internal init(fromJson json: JSON!){
        super.init(fromJson: json)
        
        let array = json["iceCandidates"].arrayValue
        if !array.isEmpty {
            iceCandidates = [IceCandidate]()
            
            for item in array {
                iceCandidates.append(IceCandidate(candidate: item["candidate"].stringValue, sdpMLineIndex: Int32(item["sdpMLineIndex"].intValue), sdpMid: item["sdpMid"].stringValue))
            }
        }
    }
    
}
