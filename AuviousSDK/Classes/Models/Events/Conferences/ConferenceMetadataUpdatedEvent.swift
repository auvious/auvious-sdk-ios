//
//  ConferenceMetadataUpdatedEvent.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 30/9/20.
//

import Foundation
import SwiftyJSON

/**
    Raised when a audio/video track is muted/unmuted in a conference.
*/
public final class ConferenceMetadataUpdatedEvent: ConferenceEvent {
    
    public var key: String!
    public var operation: MetadataRequestOperation!
    public var streamType: MetadataRequestType?
    public var value: Bool!
    public var streamId: String?
    
    //Determines if we need to set/remove the call on HOLD
    public var isHold: Bool = false
    
    /// Initialiser using a JSON object
    override internal init(fromJson json: JSON!){
        super.init(fromJson: json)
        
        key = json["key"].stringValue
        operation = MetadataRequestOperation(rawValue: json["operation"].stringValue)
        value = json["value"].boolValue
        
        //Convenience fields
        if key.contains("video") {
            streamType = .video
        } else if key.contains("audio") {
            streamType = .audio
        }
        
        if key.starts(with: "TRACK_MUTED") {
            let parts = key.split(separator: "/")
            if parts.count == 3 {
                streamId = String(parts[2])
            }
        } else if key.starts(with: "ON_HOLD") {
            isHold = true
        }
    }
}
