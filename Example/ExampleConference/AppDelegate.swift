//
//  AppDelegate.swift
//  ExampleConference
//
//  Created by Jace on 02/05/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import UIKit
import SVProgressHUD
import Sentry
import AuviousSDK

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        
        let conferenceSelectionVC = ConferenceSelectionVC()
        let navController = UINavigationController(rootViewController: conferenceSelectionVC)
        
        window!.rootViewController = navController
        window!.backgroundColor = UIColor(red: 250/255, green: 250/255, blue: 250/255, alpha: 1.0)
        window!.makeKeyAndVisible()
        
        SVProgressHUD.setDefaultStyle(.dark)
        
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
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        AuviousConferenceSDK.sharedInstance.onApplicationPause()
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        print("applicationDidBecomeActive")
        AuviousConferenceSDK.sharedInstance.onApplicationResume()
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        
    }
}

