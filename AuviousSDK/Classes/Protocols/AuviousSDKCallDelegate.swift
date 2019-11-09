//
//  AuviousSDKCallDelegate.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 07/05/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import Foundation

public protocol AuviousSDKCallDelegate: AuviousSDKBaseProtocol {

    /**
     Called when a call event is received.
     
     - Parameter event: The event received.
     */
    func auviousSDK(didReceiveCallEvent event: CallEvent)
    
    /**
     Called when a call's stream's state is changed.
     
     - Parameter newState: The current state of the stream
     - Parameter callId: The id of the stream
     - Parameter streamType: The type of the stream (mic, cam, mic and cam etc.)
     */
    func auviousSDK(didChangeState newState: StreamEventState, callId: String, streamType: StreamType)
    
    func auviousSDK(didReceiveScreenshot image: UIImage)
    
    func auviousSDK(agentSwitchedCamera toFront: Bool)
}

