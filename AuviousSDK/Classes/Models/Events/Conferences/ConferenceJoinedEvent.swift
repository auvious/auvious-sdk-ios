//
//  ConferenceJoinedEvent.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 07/12/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import Foundation
import SwiftyJSON

/**
 Raised when a peer joins the conference.
*/
public final class ConferenceJoinedEvent: ConferenceEvent {
    
    /// Initialiser using a JSON object
    override internal init(fromJson json: JSON!){
        super.init(fromJson: json)
    }
}
