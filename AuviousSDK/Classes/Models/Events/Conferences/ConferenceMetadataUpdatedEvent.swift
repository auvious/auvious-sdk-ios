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

    /// The value as sent by the server. Co-browse/sketch keys carry a JSON encoded string.
    public var rawValue: String?

    //Determines if we need to set/remove the call on HOLD
    public var isHold: Bool = false
    public var isRecorder: Bool = false
    public var isMuteToggle: Bool = false

    //Sketch/AR pointer keys, used by co-browse annotations
    public var isSketch: Bool = false
    public var isArPointer: Bool = false
    public var isArPointerColors: Bool = false

    /// Initialiser using a JSON object
    override internal init(fromJson json: JSON!){
        super.init(fromJson: json)

        key = json["key"].stringValue
        operation = MetadataRequestOperation(rawValue: json["operation"].stringValue)
        value = json["value"].boolValue
        rawValue = json["value"].string ?? (json["value"].exists() && json["value"] != JSON.null ? json["value"].rawString() : nil)

        if key == ConferenceMetadataKey.sketch {
            isSketch = true
            return
        } else if key == ConferenceMetadataKey.arPointer {
            isArPointer = true
            return
        } else if key == ConferenceMetadataKey.arPointerColors {
            isArPointerColors = true
            return
        }
        
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
            isMuteToggle = true
        } else if key.starts(with: "ON_HOLD") {
            isHold = true
        } else if key.starts(with: "RECORDER") {
            isRecorder = true
        }
        // todo: add more conference metadata keys
    }
}

/// Conference metadata keys used by the co-browse/sketch feature (shared with the web clients).
internal enum ConferenceMetadataKey {
    static let sketch = "SKETCH"
    static let arPointer = "AR_POINTER"
    static let arPointerColors = "AR_POINTER_COLORS"
}
