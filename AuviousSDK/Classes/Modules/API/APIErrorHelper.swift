//
//  APIErrorHelper.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 03/12/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import Foundation
import Alamofire
import SwiftyJSON

internal final class APIErrorHelper {
    
    static let sharedInstance = APIErrorHelper()
    
    func checkForError(response dataResponse: DefaultDataResponse) -> Error? {
        var userInfo = [String: AnyObject]()
        
        // Check for error encountered while executing or validating the result data response
        if let alamoError = dataResponse.error as NSError? {
            userInfo["errorCode"] = alamoError.code as AnyObject?
            userInfo["errorMessage"] = alamoError.localizedDescription as AnyObject?
            
            if alamoError.code == -1009 {
                return AuviousSDKError.noInternetConnection
            } else {
                return AuviousSDKError.httpError(code: alamoError.code)
            }
        }
        
        if let response = dataResponse.response, let _ = dataResponse.data {
            let isInvalidReply = false
            
            // Check status code
            var errorCode = APIErrorCode.invalidReplyObject.rawValue
            switch response.statusCode {
            case 200, 204:
                if !isInvalidReply {
                    return nil
                }
            case 400:
                if let customErrorCode = userInfo["errorCode"] {
                    errorCode = customErrorCode as! Int
                } else {
                    errorCode = APIErrorCode.error400.rawValue
                }
            case 401:
                return AuviousSDKError.unauthorizedRequest
            case 403:
                errorCode = APIErrorCode.error403.rawValue
            case 404:
                errorCode = APIErrorCode.error404.rawValue
            default:
                return AuviousSDKError.httpError(code: errorCode)
            }
            
            return AuviousSDKError.httpError(code: errorCode)
            
        } else {
            // Unknown error
            return AuviousSDKError.httpError(code: -1000)
        }
    }
}
