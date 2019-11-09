//
//  APIRequestHandler.swift
//  AuviousSDK
//
//  Created by Epimenidis Voutsakis on 09/09/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import Foundation
import Alamofire

class APIRequestHandler: RequestAdapter, RequestRetrier {
    // [Request url: Number of times retried]
    private var retriedRequests: [String: Int] = [:]

    /// Inspects and adapts the specified `URLRequest` in some manner if necessary and returns the result.
    ///
    /// - parameter urlRequest: The URL request to adapt.
    ///
    /// - throws: An `Error` if the adaptation encounters an error.
    ///
    /// - returns: The adapted `URLRequest`.
    func adapt(_ urlRequest: URLRequest) throws -> URLRequest {
        return urlRequest;
    }

    /// Determines whether the `Request` should be retried by calling the `completion` closure.
    ///
    /// This operation is fully asynchronous. Any amount of time can be taken to determine whether the request needs
    /// to be retried. The one requirement is that the completion closure is called to ensure the request is properly
    /// cleaned up after.
    ///
    /// - parameter manager:    The session manager the request was executed on.
    /// - parameter request:    The request that failed due to the encountered error.
    /// - parameter error:      The error encountered when executing the request.
    /// - parameter completion: The completion closure to be executed when retry decision has been determined.
    func should(_ manager: SessionManager, retry request: Request, with error: Error, completion: @escaping RequestRetryCompletion) {
        guard
            request.task?.response == nil,
            let url = request.request?.url?.absoluteString
            else {
                removeCachedUrlRequest(url: request.request?.url?.absoluteString)
                completion(false, 0.0) // don't retry
                return
        }

        let code = (error as NSError).code
        
        guard let retryCount = retriedRequests[url] else {
            if code == -1005 {
                retriedRequests[url] = 1
                completion(true, 1.0) // retry after 1 second
            }
            
            return
        }

        if code == -1005 && retryCount <= 3 {
            retriedRequests[url] = retryCount + 1
            completion(true, 1.0) // retry after 1 second
        } else {
            removeCachedUrlRequest(url: url)
            completion(false, 0.0) // don't retry
        }
    }

    private func removeCachedUrlRequest(url: String?) {
        guard let url = url else {
            return
        }
        retriedRequests.removeValue(forKey: url)
    }
}
