//
//  UserNotificationManager.swift
//  Benji
//
//  Created by Benji Dodgson on 9/17/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import UserNotifications
import TMROLocalization
import Parse
import Combine
import StreamChat

protocol UserNotificationManagerDelegate: AnyObject {
    func userNotificationManager(willHandle: DeepLinkable)
}

class UserNotificationManager: NSObject {

    static let shared = UserNotificationManager()
    weak var delegate: UserNotificationManagerDelegate?

    private let center = UNUserNotificationCenter.current()

    var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()

        self.center.delegate = self
    }

    func getNotificationSettings() async -> UNNotificationSettings {
        let result: UNNotificationSettings = await withCheckedContinuation { continuation in
            self.center.getNotificationSettings { (settings) in
                continuation.resume(returning:  settings)
            }
        }

        return result
    }

    func silentRegister(withApplication application: UIApplication) {
        Task {
            let settings = await self.getNotificationSettings()

            switch settings.authorizationStatus {
            case .authorized:
                await application.registerForRemoteNotifications()  // To update our token
            case .provisional:
                await application.registerForRemoteNotifications()  // To update our token
            case .notDetermined:
                await self.register(with: [.alert, .sound, .badge, .provisional], application: application)
            case .denied, .ephemeral:
                return
            @unknown default:
                return
            }
        }
    }

    @discardableResult
    func register(with options: UNAuthorizationOptions = [.alert, .sound, .badge],
                  application: UIApplication) async -> Bool {

        let granted = await self.requestAuthorization(with: options)
        if granted {
            await application.registerForRemoteNotifications()  // To update our token
        }
        return granted
    }

    private func requestAuthorization(with options: UNAuthorizationOptions = [.alert, .sound, .badge]) async -> Bool {
        do {
            let granted = try await self.center.requestAuthorization(options: options)
            if granted {
                let userCategories = UserNotificationCategory.allCases.map { userCategory in
                    return userCategory.category
                }
                let categories: Set<UNNotificationCategory> = Set.init(userCategories)
                self.center.setNotificationCategories(categories)
            }

            return granted
        } catch {
            logDebug(error)
            return false
        }
    }

    func removeNonEssentialPendingNotifications() {
        self.center.getPendingNotificationRequests { requests in

            var identifiers: [String] = []

            requests.forEach { request in
                if let category = UserNotificationCategory(rawValue: request.content.categoryIdentifier) {
                    if category != .connectionRequest {
                        identifiers.append(request.identifier)
                    }
                } else {
                    identifiers.append(request.identifier)
                }
            }

            self.center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    func removeAllPendingNotificationRequests() {
        self.center.removeAllPendingNotificationRequests()
    }

#if !NOTIFICATION
    func resetBadgeCount() {
        let count = UIApplication.shared.applicationIconBadgeNumber
        UIApplication.shared.applicationIconBadgeNumber = 0
        UIApplication.shared.applicationIconBadgeNumber = count
    }
#endif

    @discardableResult
    func handle(userInfo: [AnyHashable: Any]) -> Bool {
        guard let data = userInfo["data"] as? [String: Any],
              let note = UserNotificationFactory.createNote(from: data) else { return false }

        Task {
            await self.schedule(note: note)
        }

        return true
    }

    func schedule(note: UNNotificationRequest) async {
        try? await self.center.add(note)
    }

    func registerPush(from deviceToken: Data) async {

        // Leaving this here if we need to test notifications from stream

//        #if IOS
//        return await withCheckedContinuation({ continuation in
//            ChatClient.shared.currentUserController().reloadUserIfNeeded { _ in
//                ChatClient.shared.currentUserController().addDevice(token: deviceToken) { error in
//                    if let e = error {
//                        continuation.resume(returning: ())
//                    } else {
//                        continuation.resume(returning: ())
//                    }
//                }
//            }
//        })
//        #endif 

        do {
            let installation = try await PFInstallation.getCurrent()
            installation.badge = 0
            installation.setDeviceTokenFrom(deviceToken)
            if installation["userId"].isNil {
                installation["userId"] = User.current()?.objectId
            }
            
            try await installation.saveInBackground()
        } catch {
            print(error)
        }
    }
}
