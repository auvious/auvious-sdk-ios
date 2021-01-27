//
//  AuviousSDKBaseProtocol.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 08/05/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import Foundation

public protocol AuviousSDKBaseProtocol {
    
    /**
     Called when the local video track is received.
     
     - Parameter localVideoTrack: The local video track being captured from your device
     */
    func auviousSDK(didReceiveLocalVideoTrack localVideoTrack: RTCVideoTrack!)
    
    /**
     Called when a remote video stream is received.
     
     - Parameter stream: The remote stream being received.
     - Parameter streamId: The id of the remote stream being received.
     - Parameter endpointId: The endpoint of the user sending the remote stream.
     - Parameter type: The type of stream being received
     */
    func auviousSDK(didReceiveRemoteStream stream: RTCMediaStream, streamId: String, endpointId: String, type: StreamType)
    
    /**
     Called when an error is received.
     
     - Parameter error: The error object
     */
    func auviousSDK(onError error: AuviousSDKError)
}

//Adding this to make the methods optional (a simple @obj optional func won't work in this case)
public extension AuviousSDKBaseProtocol {
    
    func auviousSDK(didReceiveLocalVideoTrack localVideoTrack: RTCVideoTrack!) {}
    func auviousSDK(onError error: AuviousSDKError) {}
}
