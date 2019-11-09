//
//  CallCreatedEvent.swift
//  AuviousSDK
//
//  Created by Jace on 04/05/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import Foundation
import SwiftyJSON

public class CallCreatedEvent: CallEvent {
    
    var sdpOffer: String!
    var target: String!
    
    /// Initialiser using a JSON object
    override internal init(fromJson json: JSON!){
        super.init(fromJson: json)
        
        sdpOffer = json["sdpOffer"].stringValue
        target = json["target"].stringValue
    }
}
