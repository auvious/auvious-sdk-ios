//
//  ConferenceStreamPublishedEvent.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 07/12/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import Foundation
import SwiftyJSON

/**
    Raised when a stream is published in a conference.
*/
public final class ConferenceStreamPublishedEvent: ConferenceEvent {
    
    /// The id of the stream
    public var streamId: String!
    
    /// The stream type (mic, cam, mic & cam etc.)
    public var streamType: StreamType!
    
    /// Initialiser using a JSON object
    override internal init(fromJson json: JSON!){
        super.init(fromJson: json)
        
        streamId = json["streamId"].stringValue
        streamType = StreamType(rawValue: json["streamType"].stringValue)
    }
}
