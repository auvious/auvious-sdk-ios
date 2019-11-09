//
//  CallRejectedEvent.swift
//  AuviousSDK
//
//  Created by Jace on 04/05/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import Foundation
import SwiftyJSON

public class CallRejectedEvent: CallEvent {
    
    public var reason: String!
    
    /// Initialiser using a JSON object
    override internal init(fromJson json: JSON!){
        super.init(fromJson: json)
        
        reason = json["reason"].stringValue
    }
}
