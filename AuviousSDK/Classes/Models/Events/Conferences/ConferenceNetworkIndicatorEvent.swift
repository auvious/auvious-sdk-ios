//
//  ConferenceNetworkIndicatorEvent.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 19/11/20.
//

import Foundation
import SwiftyJSON

public class ConferenceNetworkIndicatorEvent: ConferenceEvent {
    
    //Network quality
    public var networkQuality: Int = 0
    
    //Network statistics
    public var data: [String: NetworkStatistics] = [:]
    
    /// Initialiser using a JSON object
    internal override init(fromJson json: JSON!){
        super.init(fromJson: json)
        
        networkQuality = json["averageNetworkQuality"].intValue
        
        let stats = json["participantIndicatorMap"].dictionaryValue
        for k in stats.keys {
            data[k] = NetworkStatistics(fromJson: stats[k])
        }
    }
}

public class NetworkStatistics {
    
    public var avgJitter: Int = 0
    public var avgRtt: Int = 0
    public var avgNetworkQuality = 0
    public var grade: NetworkGrade = .optimal
    
    /// Initialiser using a JSON object
    internal init(fromJson json: JSON!){
        if json == JSON.null {
            return
        }
        
        avgJitter = json["averageJitter"].intValue
        avgRtt = json["averageRtt"].intValue
        avgNetworkQuality = json["averageNetworkQuality"].intValue
        if let ng = NetworkGrade(rawValue: json["grade"].stringValue) {
            grade = ng
        }
    }
}

public enum NetworkGrade: String {
    case optimal = "OPTIMAL"
    case suboptimal = "SUBOPTIMAL"
    case bad = "BAD"
    
    var color: UIColor {
        switch self {
        case .optimal:
            return .green
        case .suboptimal:
            return .yellow
        case .bad:
            return .red
        }
    }
}
