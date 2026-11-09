//
//  Enumerations.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 29/11/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import Foundation

/**
    The type of conference.
 */
public enum ConferenceMode: String {
    
    /// Peer to Peer
    case p2p = "P2P"
    
    /// Router
    case router = "ROUTER"
    
    /// Unknown
    case unknown = "UNKNOWN"
}

/**
    The type of a stream used in a conference.
 */
public enum StreamType: String {
    
    /// Microphone
    case mic = "MIC"
    
    /// Camera
    case cam = "CAM"
    
    /// Screen capture
    case screen = "SCREEN"
    
    /// Microphone & Video
    case micAndCam = "MIC_AND_CAM"
    
    /// Unknown
    case unknown = "UNKNOWN"
}

public enum AuviousCallMode {
    case audio, video, audioVideo
}

internal enum APIErrorCode: Int {
    case none = 0
    case invalidReplyObject = -1
    case error400 = 400
    case error401 = 401
    case error403 = 403
    case error404 = 404
}

/**
    The type of event received during a conference.
 */
public enum ConferenceEventType: String {
    
    /// Conference has ended
    case conferenceEnded = "ConferenceEndedEvent"
    
    /// New user joined the conference
    case conferenceJoined = "ConferenceJoinedEvent"
    
    /// User has left the conference
    case conferenceLeft = "ConferenceLeftEvent"
    
    /// A stream was published
    case conferenceStreamPublished = "ConferenceStreamPublishedEvent"
    
    /// A stream was unpublished
    case conferenceStreamUnpublished = "ConferenceStreamUnpublishedEvent"
    
    /// Audio/video muted/unmuted
    case conferenceMetadataUpdatedEvent = "ConferenceMetadataUpdatedEvent"
    
    /// Network indicator stats
    case conferenceNetworkIndicatorEvent = "ConferenceNetworkIndicatorUpdatedEvent"
    
    /// Conference metadata changes
    case conferenceStreamMetadataUpdatedEvent = "ConferenceStreamMetadataUpdatedEvent"
    
    ///Unknown type
    case conferenceUnknownEvent = "-"
}

/**
    A stream's state lifecycle.
 */
@objc public enum StreamEventState: Int {
    
    /// Our local media capture has started
    case localCaptureStarted
    
    /// Our local stream is connecting
    case localStreamIsConnecting
    
    /// Our local stream has established a connection
    case localStreamConnected
    
    /// Our local stream is disconnecting
    case localStreamIsDisconnecting
    
    /// Our local stream has disconnected
    case localStreamDisconnected
    
    /// Our local media capture has stopped
    case localCaptureStoped
    
    /// A remote stream is connecting
    case remoteStreamIsConnecting
    
    /// A remote stream's connection has been established
    case remoteStreamConnected
    
    /// A remote stream is disconnecting
    case remoteStreamIsDisconnecting
    
    /// A remote stream has disconnected
    case remoteStreamDisconnected
}

/**
    Video resolution setting when publishing our stream.
 */
public enum PublishVideoResolution: String {
    
    /// Minimum resolution of 640 * 480
    case min = "640x480"
    
    /// Medium resolution of 960 * 540
    case mid = "960x720"
    
    /// Maximum resolution of 1024 * 768 (always maintain a 1/3 ratio)
    case max = "1920x1080"//"1280x720"
}

/**
    Peer-to-peer user events (sent through `rtc-api/users/endpoints/sendEvent` or by the sketch server)
    that are not conference versioned and are routed outside of the conference event pipeline.
 */
internal enum RtcUserEventType: String {
    
    /// The agent asks the customer to share their screen
    case cobrowseDisplayCaptureRequest = "CobrowseDisplayCaptureRequestEvent"
    
    /// The agent stops viewing the customer's screen (the session stays open)
    case cobrowseDisplayCaptureTerminate = "CobrowseDisplayCaptureTerminateEvent"
    
    /// Sketch operations broadcast by another sketch member
    case sketchCanvasUpdated = "SketchCanvasUpdatedEvent"
    
    /// A new member joined the sketch and expects everyone's items
    case sketchUserJoined = "SketchUserJoinedEvent"
    
    /// A sketch was made available/unavailable for this endpoint
    case sketchAvailabilityChanged = "SketchAvailabilityChangedEvent"
    
    /// A laser pointer point placed by another participant
    case arPointerIndicated = "ArPointerIndicatedEvent"

    /// The agent froze or unfroze the AR pointer target's frame
    case arPointerFreezeFrameChanged = "ArPointerFreezeFrameChangedEvent"

    /// Sketch and AR pointer events, as opposed to the co-browse request/terminate ones
    var isAnnotation: Bool {
        switch self {
        case .sketchCanvasUpdated, .sketchUserJoined, .sketchAvailabilityChanged, .arPointerIndicated, .arPointerFreezeFrameChanged:
            return true
        case .cobrowseDisplayCaptureRequest, .cobrowseDisplayCaptureTerminate:
            return false
        }
    }
}
