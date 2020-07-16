//
//  ErrorMessages.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 27/11/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import Foundation

/**
    Defines the states of stream publishing. Useful for debugging.
*/
public enum AuviousSDKPublishStreamError: Int {
    
    /// Make offer state
    case makeOfferPublishStream = 0
    
    /// Set local description state
    case localDescriptionPublishStream = 1
    
    /// Set remote description state
    case remoteDescriptionPublishStream = 2
    
    /// Publish stream request state
    case publishStreamRequest = 3
    
    /// Publish ICE candidates request
    case publishStreamIceCandidatesRequest = 4
    
    /// Unpublishing of stream
    case unpublishStream = 5
}

/**
    Defines the states of stream receiving. Useful for debugging.
*/
public enum AuviousSDKViewStreamError: Int {
    
    /// Make offer state
    case makeOfferRemoteStream = 0
    
    /// Set local description state
    case localDescriptionRemoteStream = 1
    
    /// Set remote description state
    case remoteDescriptionRemoteStream = 2
    
    /// View ICE candidates request
    case remoteStreamIceCandidatesRequest = 3
    
    /// View stream request
    case remoteStreamRequest = 4
    
    /// Stop viewing stream
    case stopRemoteStreamRequest = 5
}

public enum AuviousSDKGenericError: Error {
    case CALL_REJECTED
    case PERMISSION_REQUIRED
    case AUTHENTICATION_FAILURE
    case NETWORK_ERROR
    case UNKNOWN_FAILURE
    case CONFERENCE_MISSING
}

extension AuviousSDKGenericError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .CALL_REJECTED:
            return NSLocalizedString("Your call was not answered", comment: "Error description")
        case .AUTHENTICATION_FAILURE:
            return NSLocalizedString("Authentication failure", comment: "Error description")
        case .PERMISSION_REQUIRED:
            return NSLocalizedString("Video/Audio permission is disabled", comment: "Error description")
        case .NETWORK_ERROR:
            return NSLocalizedString("Network connection error", comment: "Error description")
        case .UNKNOWN_FAILURE:
            return NSLocalizedString("An error has occurred during your call", comment: "Error description")
        case .CONFERENCE_MISSING:
            return NSLocalizedString("Conference name not specified", comment: "Error description")
        }
    }
}

/**
    These are the various errors that may be thrown while using the SDK.
*/
public enum AuviousSDKError: Error {
    
    /// Thrown when an SDK function is called without having already configured your credentials
    case missingSDKCredentials
    
    case missingCallTarget
    
    case callNotAnswered
    
    /// Thrown when an SDK function is called without having logged in before
    case notLoggedIn
    
    /// Thrown when an SDK function is called without having already created an endpoint
    case endpointNotCreated
    
    /// Thrown when an SDK function is called without having already joined a conference
    case notInConference
    
    /// Internal error, thrown when the connection for the specified stream id has failed
    case missingPeerConnection(streamId: String)
    
    /// No video permission when trying to access the device camera
    case videoPermissionIsDisabled
    
    /// No audio permission when trying to access the device microphone
    case audioPermissionIsDisabled
    
    /// Error when trying to access the device camera and/or microphone
    case startCaptureFailure
    
    /// Error encountered while publishing a stream.
    /// - Parameter fragment: An enumeration of the various stages while publishing a stream, useful for debugging
    /// - Parameter output: The actual error description
    case publishStreamFailure(fragment: AuviousSDKPublishStreamError, output: String)
    
    /// Error encountered while receiving a remote stream.
    /// - Parameter fragment: An enumeration of the various stages while receiving a stream, useful for debugging
    /// - Parameter output: The actual error description
    case remoteStreamFailure(fragment: AuviousSDKViewStreamError, output: String)
    
    /// Connection error
    case connectionError
    
    /// HTTP errors, handled internally by the SDK
    case httpError(code: Int)
    
    /// HTTP Unauthorized request, handled internally by the SDK
    case unauthorizedRequest //http 401
    
    /// No internet connection error
    case noInternetConnection
    
    /// Internal error thrown when message processing fails - most likely not to be encountered
    case internalError
    
    case callError
    
}

/**
    Error descriptions
*/
extension AuviousSDKError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingSDKCredentials:
            return NSLocalizedString("You have not configured the Auvious SDK credentials", comment: "Error description")
        case .callNotAnswered:
            return NSLocalizedString("Your call was not answered", comment: "Error description")
        case .missingCallTarget:
            return NSLocalizedString("You have not specified a user to call", comment: "Error description")
        case .notLoggedIn:
            return NSLocalizedString("You are not logged in", comment: "Error description")
        case .endpointNotCreated:
            return NSLocalizedString("You have not created a user endpoint", comment: "Error description")
        case .notInConference:
            return NSLocalizedString("You have not joined a conference", comment: "Error description")
        case .missingPeerConnection(_):
            return NSLocalizedString("Could not get peer connection", comment: "Error description")
        case .videoPermissionIsDisabled:
            return NSLocalizedString("Video permission is disabled", comment: "Error description")
        case .audioPermissionIsDisabled:
            return NSLocalizedString("Audio permission is disabled", comment: "Error description")
        case .startCaptureFailure:
            return NSLocalizedString("Could not find device camera", comment: "Error description")
        case .publishStreamFailure(_, _):
            return NSLocalizedString("Publish stream failure", comment: "Error description")
        case .remoteStreamFailure(_, _):
            return NSLocalizedString("Remote stream failure", comment: "Error description")
        case .connectionError:
            return NSLocalizedString("Network connection error", comment: "Error description")
        case .httpError(let code):
            return NSLocalizedString("HTTP Error \(code)", comment: "Error description")
        case .unauthorizedRequest:
            return NSLocalizedString("Unauthorized request - please login", comment: "Error Message")
        case .noInternetConnection:
            return NSLocalizedString("No Internet connection", comment: "Error description")
        case .internalError:
            return NSLocalizedString("An internal error has occurred", comment: "Error description")
        case .callError:
            return NSLocalizedString("An error has occurred during your call", comment: "Error description")
        }
    }
}
