//
//  AuviousSDKDelegate.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 07/05/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import Foundation

/**
 This is the protocol that you should rely on to handle incoming and outgoing streams.
 */
public protocol AuviousSDKConferenceDelegate: AuviousSDKBaseProtocol {
    
    func auviousSDK(trackUnmuted type: StreamType, endpointId: String)
    
    func auviousSDK(trackMuted type: StreamType, endpointId: String)
    
    /**
     Called when a conference is put on hold or resumed
     
     - Parameter event: The event received.
     */
    func auviousSDK(conferenceOnHold flag: Bool)
    
    /**
     Called when a conference event is received.
     
     - Parameter event: The event received.
     */
    func auviousSDK(didReceiveConferenceEvent event: ConferenceEvent)
    
    /**
     Called when an automatic rejoin of a conference takes place.
     This happens when the application is foregrounded.
     
     - Parameter conference: The conference that was rejoined.
     */
    func auviousSDK(didRejoinConference conference: ConferenceSimpleView)
    
    
    /**
        When we receive a conference metadata updated event
     */
    func auviousSDK(recorderStateChanged toActive: Bool)
    
    /**
     Called when a certain stream's state is changed.
     
     - Parameter newState: The current state of the stream
     - Parameter streamId: The id of the stream
     - Parameter streamType: The type of the stream (mic, cam, mic and cam etc.)
     */
    func auviousSDK(didChangeState newState: StreamEventState, streamId: String, streamType: StreamType, endpointId: String)
    
    /**
        When we receive a conference stream metadata updated event
     - Parameter flag: The current state of the portrait mode
     */
    func auviousSDK(agentPortraitMode flag: Bool, endpointId: String)
    
    func auviousSDK(screenSharingStarted: Bool)
    func auviousSDK(screenSharingStopped: Bool)

    /// Called when the app returns from background with audio still active (no rejoin needed).
    func auviousSDK(didResumeFromBackground withActiveAudio: Bool)

    /**
     Our stream lost its connection and was published again under a new stream ID (the capture keeps
     running). Use the new ID from now on, e.g. to mute or unpublish it.
     */
    func auviousSDK(didRepublishLocalStream oldStreamId: String, as newStreamId: String)

    /**
     A participant's stream lost its connection and is being rebuilt (`.reconnecting`), was given up
     (`.failed`), or is fine again (nil).
     - Parameter endpointId: The participant's endpoint, ours when `isLocal`
     */
    func auviousSDK(streamConnectionChanged state: StreamRecoveryState?, endpointId: String, isLocal: Bool)
}

public extension AuviousSDKConferenceDelegate {
    func auviousSDK(didResumeFromBackground withActiveAudio: Bool) {}
    func auviousSDK(didRepublishLocalStream oldStreamId: String, as newStreamId: String) {}
    func auviousSDK(streamConnectionChanged state: StreamRecoveryState?, endpointId: String, isLocal: Bool) {}
}

