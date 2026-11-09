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
    
    /// The roles of the user that joined (e.g. AGENT, CUSTOMER)
    public var roles: [String] = []
    
    /// The display name of the user that joined, if any
    public var name: String?
    
    /// The endpoint type of the user that joined (e.g. participant, stream, displayCapture)
    public var endpointType: String?
    
    /// Initialiser using a JSON object
    override internal init(fromJson json: JSON!){
        super.init(fromJson: json)
        
        if json == JSON.null {
            return
        }
        
        let metadata = json["metadata"]
        roles = metadata["roles"].arrayValue.map { $0.stringValue }
        name = metadata["name"].string
        endpointType = metadata["type"].string
    }
}
