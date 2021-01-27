//
//  APIRequest.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 26/11/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import Foundation
import Alamofire
import os
 
/// This struct defines all the REST calls, including their path & parameters.
internal struct APIRequest {
    
    enum Router: URLRequestConvertible {
        
        // Authentication
        case loginUser(object: LoginRequest)
        case refreshToken(token: String)
        case loginUserOAuth(object: LoginRequest)
        
        //IceSupport
        case getIceServers(Void)
        
        // Calls
        case call(object: CallRequest)
        case answerCall(object: CallAnswerRequest)
        case rejectCall(object: CallRejectRequest)
        case callRinging(object: CallRingingRequest)
        case callHangup(object: CallHangupRequest)
        case callCancel(object: CallCancelRequest)
        case addCallIceCandidates(object: CallIceCandidatesRequest)
        
        //Conferences
        case getConferences(Void)
        case getConferenceDetails(id: String)
        case getConferenceSimpleView(id: String)
        case getConferenceSummary(id: String)
        case addPublishStreamIceCandidates(object: PublishStreamIceCandidatesRequest)
        case addViewStreamIceCandidates(object: ViewStreamIceCandidatesRequest)
        case createConference(object: CreateConferenceRequest)
        case endConference(object: EndConferenceRequest)
        case joinConference(object: JoinConferenceRequest)
        case leaveConference(object: LeaveConferenceRequest)
        case publishStream(object: PublishStreamRequest)
        case stopViewStream(object: StopViewStreamRequest)
        case unpublishStream(object: UnpublishStreamRequest)
        case viewStream(object: ViewStreamRequest)
        case updateConferenceMetadata(object: UpdateMetadataRequest)
        
        //Endpoints
        case getEndpoints(Void)
        case createEndpoint(object: CreateEndpointRequest)
        case getEndpointDetails(id: String)
        case keepAlive(object: KeepAliveRequest)
        case unregisterEndpoint(object: UnregisterEndpointRequest)
        
        //Snapshots
        case cameraRequestRespond(object: SnapshotCameraRQRPRequest)
        
        func asURLRequest() throws -> URLRequest {
            
            var baseURL = ServerConfiguration.baseRTC
            var query = ""
            let queryParams: [String: Any]? = nil
            var bodyParams: [String: Any]?
            var httpMethod = Alamofire.HTTPMethod.get
            
            var sendAuthenticationHeader: Bool = true
            var sendBasicAuthHeader: Bool = false
            var useFormEncoding: Bool = false
            
            switch self {
                
            // Authentication
            case .loginUser(let object):
                sendAuthenticationHeader = false
                baseURL = ServerConfiguration.baseMeeting
                query = "security/authenticate/login"
                httpMethod = Alamofire.HTTPMethod.post
                bodyParams = [:]
                bodyParams?["username"] = object.username as AnyObject?
                bodyParams?["password"] = object.password as AnyObject?
                bodyParams?["clientId"] = object.clientId as AnyObject?
                
            case .loginUserOAuth(let object):
                sendBasicAuthHeader = true
                sendAuthenticationHeader = false
                useFormEncoding = true
                
                query = "security/oauth/token"
                httpMethod = Alamofire.HTTPMethod.post
                bodyParams = [:]
                
                if let loginParams = object.params {
                    for key in loginParams.keys {
                        let value = loginParams[key] as AnyObject?
                        bodyParams?[key] = value
                    }
                }
                
            case .refreshToken(let token):
                sendBasicAuthHeader = true
                sendAuthenticationHeader = false
                useFormEncoding = true
                
                baseURL = ServerConfiguration.baseMeeting
                query = "security/oauth/token"
                httpMethod = Alamofire.HTTPMethod.post
                bodyParams = [:]
                bodyParams?["refresh_token"] = token as AnyObject?
                bodyParams?["grant_type"] = "refresh_token" as AnyObject?
            
            //IceSupport
            case .getIceServers():
                query = "rtc-api/iceServers"
                
            //Calls
            case .call(let object):
                query = "rtc-api/calls/call"
                httpMethod = Alamofire.HTTPMethod.post
                bodyParams = object.toDictionary() as [String : AnyObject]
            
            case .answerCall(let object):
                query = "rtc-api/calls/answer"
                httpMethod = Alamofire.HTTPMethod.post
                bodyParams = object.toDictionary() as [String : AnyObject]
            
            case .rejectCall(let object):
                query = "rtc-api/calls/reject"
                httpMethod = Alamofire.HTTPMethod.post
                bodyParams = object.toDictionary() as [String : AnyObject]
                
            case .callRinging(let object):
                query = "rtc-api/calls/ringing"
                httpMethod = Alamofire.HTTPMethod.post
                bodyParams = object.toDictionary() as [String : AnyObject]
                
            case .callHangup(let object):
                query = "rtc-api/calls/hangup"
                httpMethod = Alamofire.HTTPMethod.post
                bodyParams = object.toDictionary() as [String : AnyObject]
                
            case .callCancel(let object):
                query = "rtc-api/calls/cancel"
                httpMethod = Alamofire.HTTPMethod.post
                bodyParams = object.toDictionary() as [String : AnyObject]
                
            case .addCallIceCandidates(let object):
                query = "rtc-api/calls/addIceCandidates"
                httpMethod = Alamofire.HTTPMethod.post
                bodyParams = object.toDictionary() as [String : AnyObject]
                
            //Conferences
            case .getConferences():
                query = "rtc-api/conferences"
                
            case .getConferenceDetails(let id):
                query = "rtc-api/conferences/" + id
                
            case .getConferenceSimpleView(let id):
                query = "rtc-api/conferences/" + id + "/simpleView"
                
            case .getConferenceSummary(let id):
                query = "rtc-api/conferences/" + id + "/summary"
                
            case .addPublishStreamIceCandidates(let object):
                query = "rtc-api/conferences/addPublishStreamIceCandidates"
                httpMethod = Alamofire.HTTPMethod.post
                bodyParams = object.toDictionary() as [String : AnyObject]
                
            case .addViewStreamIceCandidates(let object):
                query = "rtc-api/conferences/addViewStreamIceCandidates"
                httpMethod = Alamofire.HTTPMethod.post
                bodyParams = object.toDictionary() as [String : AnyObject]
                
            case .createConference(let object):
                query = "rtc-api/conferences/create"
                httpMethod = Alamofire.HTTPMethod.post
                bodyParams = object.toDictionary() as [String : AnyObject]
                
            case .endConference(let object):
                query = "rtc-api/conferences/end"
                httpMethod = Alamofire.HTTPMethod.post
                bodyParams = object.toDictionary() as [String : AnyObject]
                
            case .joinConference(let object):
                query = "rtc-api/conferences/join"
                httpMethod = Alamofire.HTTPMethod.post
                bodyParams = object.toDictionary() as [String : AnyObject]
            
            case .leaveConference(let object):
                query = "rtc-api/conferences/leave"
                httpMethod = Alamofire.HTTPMethod.post
                bodyParams = object.toDictionary() as [String : AnyObject]
                
            case .publishStream(let object):
                query = "rtc-api/conferences/publishStream"
                httpMethod = Alamofire.HTTPMethod.post
                bodyParams = object.toDictionary() as [String : AnyObject]
                
            case .stopViewStream(let object):
                query = "rtc-api/conferences/stopViewStream"
                httpMethod = Alamofire.HTTPMethod.post
                bodyParams = object.toDictionary() as [String : AnyObject]
                
            case .unpublishStream(let object):
                query = "rtc-api/conferences/unpublishStream"
                httpMethod = Alamofire.HTTPMethod.post
                bodyParams = object.toDictionary() as [String : AnyObject]
                
            case .viewStream(let object):
                query = "rtc-api/conferences/viewStream"
                httpMethod = Alamofire.HTTPMethod.post
                bodyParams = object.toDictionary() as [String : AnyObject]
            
            case .updateConferenceMetadata(let object):
                query = "rtc-api/conferences/updateMetadata"
                httpMethod = Alamofire.HTTPMethod.post
                bodyParams = object.toDictionary() as [String : AnyObject]
                
            //Endpoints
            case .getEndpoints():
                query = "rtc-api/users/endpoints"
                
            case .createEndpoint(let object):
                query = "rtc-api/users/endpoints/register"
                httpMethod = Alamofire.HTTPMethod.post
                bodyParams = [:]
                bodyParams = object.toDictionary() as [String : AnyObject]
                
            case .getEndpointDetails(let id):
                query = "rtc-api/users/endpoints/" + id
                
            case .keepAlive(let object):
                query = "rtc-api/users/endpoints/keepalive"
                httpMethod = Alamofire.HTTPMethod.post
                bodyParams = object.toDictionary() as [String : AnyObject]
                
            case .unregisterEndpoint(let object):
                query = "rtc-api/users/endpoints/unregister"
                httpMethod = Alamofire.HTTPMethod.post
                bodyParams = object.toDictionary() as [String : AnyObject]
                
            //Snapshots
            case .cameraRequestRespond(let object):
                query = "/rtc-api/snapshots/cameraRequestRespond"
                httpMethod = Alamofire.HTTPMethod.post
                bodyParams = object.toDictionary() as [String : AnyObject]
            }
            
            //print("http body:")
            //print(bodyParams)
            
            var urlRequest = try URLRequest(url: URL(string: baseURL)!.appendingPathComponent(query), method: httpMethod, headers: nil)
            
            os_log("REQUEST %@", log: Log.api, type: .debug, urlRequest.debugDescription)
            
            // Set headers
            urlRequest.addValue("application/json", forHTTPHeaderField: "Accept")
            
            //Standard authentication
            if sendAuthenticationHeader {
                urlRequest.addValue("Bearer " + API.sharedInstance.authenticationToken, forHTTPHeaderField: "Authorization")
            }
            
            //Basic authentication
            if sendBasicAuthHeader {
                if let authorizationHeader = Request.authorizationHeader(user: ServerConfiguration.clientId, password: "") {
                    urlRequest.addValue(authorizationHeader.value, forHTTPHeaderField: authorizationHeader.key)
                }
                
                urlRequest.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                
            } else {
                urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            
            // Encoding URL Request
            urlRequest = try Alamofire.URLEncoding.default.encode(urlRequest, with: queryParams)
            if useFormEncoding {
                urlRequest.httpBody = try Alamofire.URLEncoding.default.encode(urlRequest, with: bodyParams).httpBody
            } else {
                urlRequest.httpBody = try Alamofire.JSONEncoding.default.encode(urlRequest, with: bodyParams).httpBody
            }
            
            let allowedCharacterSet = (CharacterSet(charactersIn: ",").inverted)
            
            urlRequest.url = URL(string: urlRequest.url!.absoluteString.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet)!)
            
            return urlRequest
        }
    }
}
