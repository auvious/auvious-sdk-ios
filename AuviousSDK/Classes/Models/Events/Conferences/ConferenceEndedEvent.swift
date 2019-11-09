//
//  ConferenceEndedEvent.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 07/12/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import Foundation
import SwiftyJSON

/**
 Raised when the conference ends.
*/
public final class ConferenceEndedEvent: ConferenceEvent {
    
    /// The reason for ending the conference
    public var reason:String!
    
    /// Initialiser using a JSON object
    override internal init(fromJson json: JSON!){
        super.init(fromJson: json)
        
        reason = json["reason"].stringValue
    }
    
}
