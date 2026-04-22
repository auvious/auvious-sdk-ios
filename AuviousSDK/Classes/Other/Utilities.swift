//
//  Utilities.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 07/12/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation

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

    static func getMediaDevices() -> [[String: Any]] {
        var devices = [[String: Any]]()

        // Video inputs (cameras)
        let videoDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
        for camera in videoDevices {
            devices.append([
                "deviceId": camera.uniqueID,
                "kind": "videoinput",
                "label": camera.localizedName,
                "groupId": ""
            ])
        }

        // Audio inputs
        if let audioInputs = AVAudioSession.sharedInstance().availableInputs {
            for input in audioInputs {
                devices.append([
                    "deviceId": input.uid,
                    "kind": "audioinput",
                    "label": input.portName,
                    "groupId": ""
                ])
            }
        }

        // Audio outputs
        let audioOutputs = AVAudioSession.sharedInstance().currentRoute.outputs
        for output in audioOutputs {
            devices.append([
                "deviceId": output.uid,
                "kind": "audiooutput",
                "label": output.portName,
                "groupId": ""
            ])
        }

        return devices
    }

    static func getDeviceInfo() -> [String: Any] {
        let device = UIDevice.current
        let deviceModel = getDeviceModel()
        let ua = generateCustomUserAgent()

        let bundleSDK = Bundle(for: AuviousConferenceSDK.self)
        let sdkVersion = bundleSDK.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let sdkMajor = sdkVersion.components(separatedBy: ".").first ?? "0"

        var systemInfo = utsname()
        uname(&systemInfo)
        let cpuArchitecture = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "unknown"
            }
        }

        let deviceType: String
        switch device.userInterfaceIdiom {
        case .pad:
            deviceType = "tablet"
        default:
            deviceType = "mobile"
        }

        return [
            "browser": [
                "name": "AuviousSDK",
                "version": sdkVersion,
                "major": sdkMajor
            ],
            "cpu": [
                "architecture": cpuArchitecture
            ],
            "device": [
                "vendor": "Apple",
                "model": deviceModel,
                "type": deviceType
            ],
            "engine": [
                "name": "WebKit",
                "version": ""
            ],
            "os": [
                "name": device.systemName,
                "version": device.systemVersion
            ],
            "ua": ua
        ]
    }
}
