//
//  ConferenceStreamMetadataUpdatedEvent.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 9/11/24.
//

import Foundation
import SwiftyJSON

public final class ConferenceStreamMetadataUpdatedEvent: ConferenceEvent {
    
    /// The id of the stream
    public var portraitMode: Bool!
    
    /// Initialiser using a JSON object
    override internal init(fromJson json: JSON!){
        super.init(fromJson: json)
        
        portraitMode = json["newMetadata"]["portraitMode"].boolValue
    }
}
