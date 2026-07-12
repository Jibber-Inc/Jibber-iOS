//
//  AppDelegate.swift
//  Benji
//
//  Created by Benji Dodgson on 12/25/18.
//  Copyright © 2018 Benjamin Dodgson. All rights reserved.
//

import UIKit
import SwiftUI

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }

    #if !APPCLIP
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task {
            await UserNotificationManager.shared.registerPush(from: deviceToken)
        }
    }
    
    func applicationSignificantTimeChange(_ application: UIApplication) {
        if let user = User.current(), user.isAuthenticated {
            // Update the timeZone
            user.timeZone = TimeZone.current.identifier
            user.saveEventually()
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        
        print("DID FAIL TO REGISTER FOR PUSH \(error)")
    }
    #endif
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    
    var window: UIWindow?
    var mainCoordinator: MainCoordinator?

#if IOS
    private var badgeSynchronizationTask: Task<Void, Never>?
#endif
    
    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        
        guard let windowScene = scene as? UIWindowScene else { return }
        
        let activity = connectionOptions.userActivities.first { activity in
            return activity.activityType == NSUserActivityTypeBrowsingWeb
        }
        
        var launchDeepLink: DeepLinkable?
        if let launchActivity = activity?.launchActivity,
            case LaunchActivity.deepLink(let deepLink) = launchActivity {
            launchDeepLink = deepLink
        }
        
#if !NOTIFICATION
        let rootNavController = RootNavigationController()
        self.initializeKeyWindow(with: rootNavController, for: windowScene)
        self.initializeMainCoordinator(with: rootNavController, deepLink: launchDeepLink)
        _ = UserNotificationManager.shared
#endif
        
        // Must be done after maincoordinator is initialized so delegate get set
        if let activity = activity, launchDeepLink.isNil {
            LaunchManager.shared.continueUser(activity: activity)
        }
    }
    
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        LaunchManager.shared.continueUser(activity: userActivity)
    }
        
    func initializeKeyWindow(with rootViewController: UIViewController, for scene: UIWindowScene) {
        self.window = UIWindow(windowScene: scene)
        self.window?.rootViewController = rootViewController
        self.window?.makeKeyAndVisible()
    }

    func initializeMainCoordinator(with rootNavController: RootNavigationController, deepLink: DeepLinkable?) {
        let router = Router(navController: rootNavController)
        self.mainCoordinator = MainCoordinator(router: router, deepLink: deepLink)
        self.mainCoordinator?.start()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
#if IOS
        self.badgeSynchronizationTask?.cancel()
        self.badgeSynchronizationTask = Task { @MainActor in
            await UserNotificationManager.shared.synchronizeBadgeCount()
        }
#endif
    }
}
