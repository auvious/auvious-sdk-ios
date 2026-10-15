//
//  SceneDelegate.swift
//  ExampleSimpleConference
//
//  Created by Auvious on 15/10/26.
//  Copyright © 2026 Auvious. All rights reserved.
//

import UIKit
import AuviousSDK

/// Apps built with the iOS 27 SDK must adopt the UIScene life cycle.
/// The window and root view controller come from Main.storyboard (UISceneStoryboardFile).
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
