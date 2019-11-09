//
//  Utilities.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 07/12/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import Foundation

internal final class Utilities {
    
    static var eventDateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
    
    static var eventDateFormatter: DateFormatter {
        get {
            let formatter = DateFormatter()
            formatter.dateFormat = eventDateFormat
            
            return formatter
        }
    }
}
