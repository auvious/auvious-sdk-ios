//
//  AppDelegate.swift
//  ExampleSimpleConference
//
//  Created by Jason Kritikos on 19/6/20.
//  Copyright © 2020 CocoaPods. All rights reserved.
//

import UIKit
import AuviousSDK
import Sentry

// Apps built with the iOS 27 SDK must use the scene life cycle (they don't launch
// otherwise): Info.plist's scene manifest loads Main.storyboard into this scene's window.
// With scenes UIKit no longer calls the UIApplicationDelegate foreground/background
// methods, so the SDK's pause/resume hooks are called from here.
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func sceneDidEnterBackground(_ scene: UIScene) {
        print("sceneDidEnterBackground")
        AuviousConferenceSDK.sharedInstance.onApplicationPause()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        print("sceneDidBecomeActive")
        AuviousConferenceSDK.sharedInstance.onApplicationResume()
    }
}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        //Prevent device locking
        UIApplication.shared.isIdleTimerDisabled = true

        SentrySDK.start { options in
            options.dsn = "https://74765e10688d4f828efd5bc5320c607c@sentry.auvious.com/9"
            options.debug = false
            options.environment = "development"
        }

        return true
    }
}
