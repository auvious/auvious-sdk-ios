//
//  CallAnsweredEvent.swift
//  AuviousSDK
//
//  Created by Jace on 04/05/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import Foundation
import SwiftyJSON

public final class CallAnsweredEvent: CallEvent {
    
    var sdpAnswer: String!
    
    /// Initialiser using a JSON object
    override internal init(fromJson json: JSON!){
        super.init(fromJson: json)
        
        sdpAnswer = json["sdpAnswer"].stringValue
    }
}
