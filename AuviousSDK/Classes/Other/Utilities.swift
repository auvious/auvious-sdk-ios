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
    
    private static func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "unknown"
            }
        }
    }
    
    static func generateCustomUserAgent() -> String {
        let device = UIDevice.current
        let osVersion = device.systemVersion
        let platform = device.systemName

        let bundle = Bundle.main
        let appName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "UnknownApp"
        let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"

        let bundleSDK = Bundle(for: AuviousConferenceSDK.self)
        let sdkVersion = bundleSDK.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        
        let deviceModel = Utilities.getDeviceModel()

        return "\(appName)/\(appVersion) AuviousSDK/\(sdkVersion) (\(platform); \(platform)/\(osVersion); \(deviceModel))"
    }
    
    static func getApplicationLanguage() -> String {
        return String(Locale.preferredLanguages.first?.prefix(2) ?? "en")
    }
}
