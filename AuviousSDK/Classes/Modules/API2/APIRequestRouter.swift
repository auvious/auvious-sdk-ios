//
//  APIRequestRouter.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 7/3/25.
//

import Foundation
import os

enum Router: URLRequestConvertible2 {
    
    //Authentication
    case loginUserOAuth(object: LoginRequest)
    
    //Endpoints
    case createEndpoint(object: CreateEndpointRequest)
    
    func encodeWithURLComponents(_ parameters: [String: Any]) -> String {
        var components = URLComponents()
        components.queryItems = parameters.map { key, value in
            URLQueryItem(name: key, value: "\(value)")
        }
        return components.percentEncodedQuery ?? ""
    }
    
    func authorizationHeader(user: String, password: String) -> (key: String, value: String)? {
        guard let data = "\(user):\(password)".data(using: .utf8) else { return nil }

        let credential = data.base64EncodedString(options: [])

        return (key: "Authorization", value: "Basic \(credential)")
    }
    
    func asURLRequest() throws -> URLRequest {
        var baseURL = ServerConfiguration.baseRTC
        var query = ""
        let queryParams: [String: Any]? = nil
        var bodyParams: [String: Any]?
        var httpMethod = "GET"
        
        var sendAuthenticationHeader: Bool = true
        var sendBasicAuthHeader: Bool = false
        var useFormEncoding: Bool = false
        
        guard let url = URL(string: baseURL + query) else {
            throw AuviousSDKError.internalError
        }
        
        switch self {
            //Authentication
        case .loginUserOAuth(let object):
            sendBasicAuthHeader = true
            sendAuthenticationHeader = false
            useFormEncoding = true
            
            query = "security/oauth/token"
            httpMethod = "POST"
            bodyParams = [:]
            
            if let loginParams = object.params {
                for key in loginParams.keys {
                    let value = loginParams[key] as AnyObject?
                    bodyParams?[key] = value
                }
            }
            
        case .createEndpoint(let object):
            query = "rtc-api/users/endpoints/register"
            httpMethod = "POST"
            bodyParams = [:]
            bodyParams = object.toDictionary() as [String : AnyObject]
        }
        
        var urlRequest = URLRequest(url: url.appendingPathComponent(query))
        urlRequest.httpMethod = httpMethod
        
        os_log("NEW REQUEST %@", log: Log.api, type: .debug, urlRequest.debugDescription)
        
        // Set headers
        urlRequest.addValue("application/json", forHTTPHeaderField: "Accept")
        
        //Standard authentication
        if sendAuthenticationHeader {
            urlRequest.addValue("Bearer " + API.sharedInstance.authenticationToken, forHTTPHeaderField: "Authorization")
        }
        
        //Basic authentication
        if sendBasicAuthHeader {
            if let authorizationHeader = authorizationHeader(user: ServerConfiguration.clientId, password: "") {
                urlRequest.addValue(authorizationHeader.value, forHTTPHeaderField: authorizationHeader.key)
            }
            
            urlRequest.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            
        } else {
            urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        
        // Encoding URL Request
//        urlRequest = try Alamofire.URLEncoding.default.encode(urlRequest, with: queryParams)
        if useFormEncoding {
//            urlRequest.httpBody = try Alamofire.URLEncoding.default.encode(urlRequest, with: bodyParams).httpBody
            urlRequest.httpBody = encodeWithURLComponents(bodyParams!).data(using: .utf8)
        } else {
            do {
                urlRequest.httpBody = try JSONSerialization.data(withJSONObject: bodyParams)
            }
        }
        
        let allowedCharacterSet = (CharacterSet(charactersIn: ",").inverted)
        
        urlRequest.url = URL(string: urlRequest.url!.absoluteString.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet)!)
        
        return urlRequest
    }
    
}
