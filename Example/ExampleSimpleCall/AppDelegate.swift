//
//  AppDelegate.swift
//  ExampleSimpleCall
//
//  Created by Jason Kritikos on 19/07/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import UIKit
import Sentry
import AuviousSDK

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        //Prevent device locking
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Create a Sentry client and start crash handler
        do {
            Client.shared = try Client(dsn: "https://74765e10688d4f828efd5bc5320c607c@sentry.auvious.com/9")
            try Client.shared?.startCrashHandler()
        } catch let error {
            print("\(error)")
        }

        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
        print("applicationWillResignActive")
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        print("applicationDidEnterBackground")
        AuviousCallSDK.sharedInstance.onApplicationPause()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        print("applicationDidBecomeActive")
        AuviousCallSDK.sharedInstance.onApplicationResume()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }


}

