//
//  API2.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 7/3/25.
//

import Foundation
import SwiftyJSON
import os

/// Types adopting the `URLRequestConvertible` protocol can be used to construct URL requests.
public protocol URLRequestConvertible2 {
    /// Returns a URL request or throws if an `Error` was encountered.
    ///
    /// - throws: An `Error` if the underlying `URLRequest` is `nil`.
    ///
    /// - returns: A URL request.
    func asURLRequest() throws -> URLRequest
}

internal final class API2 {
    
    static let sharedInstance = API2()
    
    //URLSession
    var session: URLSession
    
    //Cached tasks
    var cachedTasks: [TransactionElementNew] = []
    
    //Auth tokens
    var tokenRefreshTimer: Timer!
    var authenticationToken = ""
    var refreshToken: String?
    var authTokenExpiresIn: Int? {
        didSet {
            startTokenRefreshTimer()
        }
    }
    
    //Token refresh related
    var isRefreshing = false
    var refreshTokenAttempts = 0
    
    typealias TransactionElementNew = (request: URLRequestConvertible2, onSuccess: (JSON?)->(), onFailure: (Error)->(), needsToken: Bool)
    
    init() {
        let cookies = HTTPCookieStorage.shared
        cookies.removeCookies(since: Date())
        
        let userAgent = Utilities.generateCustomUserAgent()
        
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = cookies
        cfg.httpMaximumConnectionsPerHost = 10
        cfg.timeoutIntervalForRequest = 24.0
        cfg.httpAdditionalHeaders = ["User-Agent": userAgent]

        session = URLSession(configuration: cfg)
    }
    
    private func synced(_ lock: AnyObject, closure: () -> ()) {
        objc_sync_enter(lock)
        closure()
        objc_sync_exit(lock)
    }
    
    // MARK: Token Refresh
    
    func startTokenRefreshTimer() {
        var executeIn: Int = 3
        if authTokenExpiresIn! - 40 > executeIn {
            executeIn = authTokenExpiresIn! - 40
        }

        tokenRefreshTimer = Timer.scheduledTimer(timeInterval: Double(executeIn), target: self, selector: #selector(self.handleTokenRefresh), userInfo: nil, repeats: false)
    }

    func stopTokenRefreshTimer() {
        tokenRefreshTimer?.invalidate()
        tokenRefreshTimer = nil
    }
    
    @objc func handleTokenRefresh() {
        self.refreshToken()
    }
    
    //Refreshes the OAuth token and consumes pending transactions
    private func refreshToken(_ completion: ((Bool) -> Void)? = nil) {
        guard let refreshToken = refreshToken else {
            refreshTokenDidFail({ (_) in
                completion?(false)
            })
            
            return
        }
        
        self.isRefreshing = true
        self.refreshAuthToken(refreshToken, onSuccess: { (json) -> () in
            sdkLog("%@", log: Log.api, type: .debug, "REFRESHED TOKEN!")
            self.isRefreshing = false
            self.refreshTokenAttempts = 0
            
            //Keep a copy of the new tokens
            if let data = json {
                self.authenticationToken = data["access_token"].stringValue
                self.refreshToken = data["refresh_token"].stringValue
                self.authTokenExpiresIn = data["expires_in"].intValue
                
                //Trigger a reconnect with the new token
                ServerConfiguration.mqttPass = self.authenticationToken
                MQTTModule2.sharedInstance.disconnectAndReconnect()
                
                //self.consumePendingTransactions()
                completion?(true)
            }
            
            completion?(false)
        }, onFailure: { (error)  -> () in
            self.refreshTokenDidFail({ (_) in
                completion?(false)
            })
        })
    }
    
    //Refresh token failure handler
    private func refreshTokenDidFail(_ completion: ((Bool) -> Void)? = nil) {
        self.isRefreshing = false
        self.cachedTasks.removeAll(keepingCapacity: false)
        completion?(false)
    }
    
    /// - Parameter validateStatus: when true, non-2xx responses are reported through `onFailure` with
    ///   `AuviousSDKError.httpError(code:)` even if the response body is valid JSON.
    private func fireRequest(_ transaction: TransactionElementNew, validateStatus: Bool = false) {
        
        let cachedRequest = transaction
//        if self.isRefreshing && transaction.needsToken == true {
//            synced(self, closure: {
//                self.cachedTasks.append(cachedRequest)
//            })
//
//            return
//        }
        
        do {
            let request = try transaction.request.asURLRequest()
            sdkLog("%@", log: Log.api, type: .debug, "FIRING REQUEST \(request.debugDescription)")
            let task = session.dataTask(with: request) { (data, response, error) in
                var responseCode = 0
                if let httpResponse = response as? HTTPURLResponse {
                    responseCode = httpResponse.statusCode
                }
                
                // Check for error
//                if let errorReply = APIErrorHelper.sharedInstance.checkForError(response: response) {
//                
//                    switch errorReply {
//                    case AuviousSDKError.unauthorizedRequest:
//                        // Session expired
//                        if transaction.needsToken == true {
//                            self.synced(self, closure: {
//                                self.cachedTasks.append(cachedRequest)
//                            })
//                            
//                            //Only attempt to refresh token if we've successfully logged in before
//                            if self.isRefreshing == false && self.refreshTokenAttempts < 3 && !self.authenticationToken.isEmpty {
//                                self.refreshTokenAttempts += 1
//                                
//                                self.refreshToken({ (success) in
//                                    guard !success else {
//                                        return
//                                    }
//                                    
//                                    transaction.onFailure(errorReply)
//                                })
//                                
//                                return
//                            }
//                        }
//                    default:
//                        transaction.onFailure(errorReply)
//                        return
//                    }
//                    
//                    transaction.onFailure(errorReply)
//                    return
//                }
                
//                if response.error != nil {
//                    sdkLog("response error: %@", log: Log.api, type: .error, String(describing: response.error))
//                }
                
                DispatchQueue.main.async {
                    if validateStatus && !(200..<300).contains(responseCode) {
                        transaction.onFailure(AuviousSDKError.httpError(code: responseCode))
                        return
                    }

                    if let responseData = data {
                        
                        do {
                            let jsonResponse = try JSON(data: responseData)
                            sdkLog("%@", log: Log.api, type: .debug, "RESPONSE SUCCESS \(jsonResponse)")
                            
                            transaction.onSuccess(jsonResponse)
                            return
                        } catch {
                            //Handle empty responses, like KeepAlive
                            if responseCode == 200 || responseCode == 204 {
                                transaction.onSuccess(JSON())
                                return
                            }
                        }
                    }
                    
                    let error = AuviousSDKError.httpError(code: responseCode)
                    transaction.onFailure(error)
                }
            }
                
            // Start the request
            task.resume()
            
        } catch let error {
            sdkLog("%@", log: Log.api, type: .error, "API2 INVALID URLREQUEST")
        }
    }
    
    // MARK: API Implementation
    
    func loginUser(_ object: LoginRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.loginUserOAuth(object: object), onSuccess, onFailure, false)
        fireRequest(transaction)
    }
    
    //Token refresh
    func refreshAuthToken(_ token: String, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.refreshToken(token: token), onSuccess, onFailure, false)
        fireRequest(transaction)
    }
    
    //IceSupport
    func getIceServers(onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.getIceServers(()), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    //Conferences
    func getConferences(onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.getConferences(()), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func getConferenceDetails(_ id: String, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.getConferenceDetails(id: id), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func getConferenceSimpleView(_ id: String, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.getConferenceSimpleView(id: id), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func getConferenceSummary(_ id: String, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.getConferenceSummary(id: id), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func addPublishStreamIceCandidates(_ object: PublishStreamIceCandidatesRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.addPublishStreamIceCandidates(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func addViewStreamIceCandidates(_ object: ViewStreamIceCandidatesRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.addViewStreamIceCandidates(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func createConference(_ object: CreateConferenceRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.createConference(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func endConference(_ object: EndConferenceRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.endConference(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func joinConference(_ object: JoinConferenceRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.joinConference(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func leaveConference(_ object: LeaveConferenceRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.leaveConference(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func publishStream(_ object: PublishStreamRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.publishStream(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func stopViewStream(_ object: StopViewStreamRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.stopViewStream(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func unpublishStream(_ object: UnpublishStreamRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.unpublishStream(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func viewStream(_ object: ViewStreamRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.viewStream(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func updateConferenceMetadata(_ object: UpdateMetadataRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.updateConferenceMetadata(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    //Endpoints
    func getEndpoints(onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.getEndpoints(()), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func createEndpoint(_ object: CreateEndpointRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.createEndpoint(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func getEndpointDetails(_ id: String, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.getEndpointDetails(id:id), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func keepAlive(_ object: KeepAliveRequest, validateStatus: Bool = false, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.keepAlive(object: object), onSuccess, onFailure, true)
        fireRequest(transaction, validateStatus: validateStatus)
    }
    
    func unregisterEndpoint(_ object: UnregisterEndpointRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.unregisterEndpoint(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }

    func sendEvent(_ object: SendEventRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.sendEvent(object: object), onSuccess, onFailure, true)
        fireRequest(transaction, validateStatus: true)
    }

    //Tickets
    func getTicket(_ id: String, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.getTicket(id: id), onSuccess, onFailure, false)
        fireRequest(transaction, validateStatus: true)
    }

    //Sketch
    func joinSketch(_ id: String, object: SketchMemberRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.joinSketch(id: id, object: object), onSuccess, onFailure, true)
        fireRequest(transaction, validateStatus: true)
    }

    func broadcastSketch(_ id: String, body: [String: Any], onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.broadcastSketch(id: id, body: body), onSuccess, onFailure, true)
        fireRequest(transaction, validateStatus: true)
    }
}
