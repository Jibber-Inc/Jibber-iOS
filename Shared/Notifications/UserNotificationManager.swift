//
//  UserNotificationManager.swift
//  Benji
//
//  Created by Benji Dodgson on 9/17/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import UserNotifications
import ParseCore
import Combine

#if IOS
import MessagingContracts
import MessagingPersistence
#endif

protocol UserNotificationManagerDelegate: AnyObject {
    func userNotificationManager(willHandle: DeepLinkable)
}

class UserNotificationManager: NSObject {
    
    static let shared = UserNotificationManager()
    weak var delegate: UserNotificationManagerDelegate?
    
    let center = UNUserNotificationCenter.current()
    private(set) var application: UIApplication?
    
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
        self.application = application
        
        Task {
            let settings = await self.getNotificationSettings()
            
            switch settings.authorizationStatus {
            case .authorized, .provisional, .notDetermined:
                await self.register(with: [.alert, .sound, .badge, .provisional], application: application)
            case .denied, .ephemeral:
                return
            @unknown default:
                return
            }
        }
    }
    
    private var registerTask: Task<Void, Error>?
    
    func register(with options: UNAuthorizationOptions = [.alert, .sound, .badge],
                  application: UIApplication,
                  forceRegistration: Bool = false) async {
        
        // If we already have an register task, wait for it to finish.
        if let registerTask = self.registerTask, !forceRegistration {
            try? await registerTask.value
            return
        }
        
        // Otherwise start a new initialization task and wait for it to finish.
        self.registerTask = Task {
            self.application = application
            let granted = await self.requestAuthorization(with: options)
            if granted {
                await application.registerForRemoteNotifications()  // To update our token
                await self.scheduleMomentReminders()
            }
        }
        
        do {
            try await self.registerTask?.value
        } catch {
            // Dispose of the task because it failed, then pass the error along.
            self.registerTask = nil
        }
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
            logError(error)
            return false
        }
    }
    
    private var registerPushTask: Task<Void, Error>?
        
    func registerPush(from deviceToken: Data) async {
        
        if let registerTask = self.registerPushTask {
            try? await registerTask.value
            return
        }
        
        self.registerTask = Task {
            do {
                let installation = try await PFInstallation.getCurrent()
                installation.badge = 0
                installation.deviceToken = deviceToken.hexString
                installation["user"] = User.current()
                try await installation.saveInBackground()
                
            } catch {
                logError(error)
                
                // HACK: If the installation object was deleted off the server,
                // then clear out the local installation object so we create a new one on next launch.
                // We're using the private string "_currentInstallation" because Parse prevents us from
                // deleting Installations normally.
                if error.code == PFErrorCode.errorObjectNotFound.rawValue {
                    try? PFObject.unpinAllObjects(withName: "_currentInstallation")
                }
            }
        }
        
        do {
            try await self.registerPushTask?.value
        } catch {
            // Dispose of the task because it failed, then pass the error along.
            self.registerPushTask = nil
        }
    }
    
    func scheduleNotification(with content: UNNotificationContent,
                              identifier: String = UUID().uuidString,
                              trigger: UNNotificationTrigger? = nil) async {
        
        let request = UNNotificationRequest(identifier: identifier,
                                            content: content,
                                            trigger: trigger)
        do {
            try await self.center.add(request)
        } catch {
            logError(error)
        }
    }
    
    func getPendingRequests() async -> [UNNotificationRequest] {
        return await withCheckedContinuation({ continuation in
            self.center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        })
    }
    
    // MARK: - Message Event Handling
    
#if IOS
    @MainActor
    func handleRead(message: Messageable) {
        self.handleRead(
            messageIDs: [message.id],
            clientMessageID: message.id
        )
    }

    @MainActor
    func handleRead(message: MessagingMessageSnapshot) {
        self.handleRead(
            messageIDs: [message.stableID, message.canonicalMessageID],
            clientMessageID: message.clientMessageID
        )
    }

    @MainActor
    private func handleRead(
        messageIDs: Set<MessagingMessageID>,
        clientMessageID: MessagingMessageID?
    ) {
        AchievementsManager.shared.createIfNeeded(with: .firstUnreadMessage)
        
        Task { @MainActor [weak self] in
            guard let self else { return }

            let delivered = await self.center.deliveredNotifications()
            var resolvedMessageIDs = messageIDs
            if let clientMessageID = clientMessageID,
               let cached = try? ParseMessagingManager.shared.store?.cachedMessage(
                   clientMessageID: clientMessageID
               ),
               let objectID = cached.objectID {
                resolvedMessageIDs.insert(objectID)
            }

            let identifiers: [String] = delivered.compactMap { note in
                guard let messageID = note.request.content.messageId,
                      resolvedMessageIDs.contains(messageID) else { return nil }
                return note.request.identifier
            }

            self.removeNotifications(with: identifiers)

            await self.synchronizeBadgeCount()
        }
    }

    @MainActor
    func synchronizeBadgeCount() async {
        let deliveredNotifications = await self.center.deliveredNotifications()
        let count = deliveredNotifications.filter { note in
            return note.request.content.interruptionLevel == .timeSensitive
        }.count

        logDebug(count)
        do {
            try await self.center.setBadgeCount(count)
        } catch {
            logError(error)
        }
        UserDefaults(suiteName: Config.shared.environment.groupId)?.set(
            count,
            forKey: "badgeNumber"
        )
    }
#endif
    
    // It was suggested that in order for this to work it needs to be called on a background thread.
    func removeNotifications(with identifiers: [String]) {
        //background code
        self.center.removeDeliveredNotifications(withIdentifiers: identifiers)
        self.center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension UserNotificationManager: UNUserNotificationCenterDelegate {
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        
        // If the app is in the foreground, and is a new message, then check the interruption level to determine whether or not to show a banner. Don't show banners for non time-sensitive messages.
        if let app = self.application,
           await app.applicationState == .active,
           notification.request.content.categoryIdentifier == UserNotificationCategory.newMessage.rawValue {
            
            if notification.request.content.interruptionLevel == .timeSensitive {
                return [.banner, .list, .sound, .badge]
            } else {
                return [.list, .sound, .badge]
            }
        }
        
        return [.banner, .list, .sound, .badge]
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        
        if let suggestion = SuggestedReply.init(rawValue: response.actionIdentifier) {
#if IOS
            self.handle(suggestion: suggestion, response: response, completion: completionHandler)
#else
            completionHandler()
#endif
        } else if let momentAction = MomentAction.init(rawValue: response.actionIdentifier) {
            self.handleMoment(action: momentAction,
                              response: response,
                              completion: completionHandler)
        } else if let target = response.notification.deepLinkTarget {
            var deepLink = DeepLinkObject(target: target)
            deepLink.customMetadata = response.notification.customMetadata
            self.delegate?.userNotificationManager(willHandle: deepLink)
            completionHandler()
        } else {
            completionHandler()
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                openSettingsFor notification: UNNotification?) {}
    
    private func handleMoment(action: MomentAction,
                              response: UNNotificationResponse,
                              completion: @escaping () -> Void) {
        var deepLink = DeepLinkObject(target: action.target)
        deepLink.customMetadata = response.notification.customMetadata
        self.delegate?.userNotificationManager(willHandle: deepLink)
        completion()
    }
    
#if IOS
    private func handle(suggestion: SuggestedReply,
                        response: UNNotificationResponse,
                        completion: @escaping () -> Void) {
        
        switch suggestion {
        case .emoji:
            // Do nothing
            completion()
        case .other:
            // Go to threads
            var deepLink = DeepLinkObject(target: .thread)
            deepLink.customMetadata = response.notification.customMetadata
            self.delegate?.userNotificationManager(willHandle: deepLink)
            completion()
        default:
            guard let messageId = response.notification.messageId,
                  let conversationId = response.notification.conversationId else {
                completion()
                return
            }
            
            Task { @MainActor in
                defer { completion() }

                do {
                    let manager = try await self.messagingManagerForNotificationAction()
                    let deliveryKind = self.deliveryKind(
                        from: response.notification,
                        manager: manager,
                        messageID: messageId
                    )
                    guard let userID = manager.authenticatedUserID else {
                        throw ParseMessagingManagerError.notInitialized
                    }
                    let clientMessageID = MessagingIdempotencyKey.notificationReply(
                        userID: userID,
                        conversationID: conversationId,
                        messageID: messageId,
                        actionID: suggestion.rawValue
                    )
                    let wasAlreadyQueued = try manager.store?.cachedMessage(
                        clientMessageID: clientMessageID
                    ) != nil
                    let draft = MessagingMessageDraft(
                        conversationID: conversationId,
                        clientMessageID: clientMessageID,
                        content: MessagingMessageContent(
                            kind: .text,
                            text: suggestion.text
                        ),
                        replyToMessageID: messageId,
                        deliveryKind: deliveryKind
                    )
                    try manager.send(draft)

                    guard !wasAlreadyQueued else { return }

                    let content = UNMutableNotificationContent()
                    content.title = "You replied:"
                    content.body = suggestion.text
                    content.interruptionLevel = .active
                    content.setData(value: conversationId, for: .conversationId)
                    content.setData(value: messageId, for: .messageId)
                    content.setData(value: DeepLinkTarget.thread.rawValue, for: .target)
                    content.categoryIdentifier = UserNotificationCategory.newMessage.rawValue
                    
                    await self.scheduleNotification(with: content)
                    AnalyticsManager.shared.trackEvent(type: .suggestionSelected, properties: ["value": suggestion.text])
                } catch {
                    await ToastScheduler.shared.schedule(toastType: .error(error))
                }
            }
        }
    }

    @MainActor
    private func messagingManagerForNotificationAction() async throws -> ParseMessagingManager {
        let manager = ParseMessagingManager.shared
        if !manager.isInitialized {
            guard let user = User.current() else {
                throw ParseMessagingManagerError.notInitialized
            }
            try await manager.initialize(for: user)
        }
        return manager
    }

    @MainActor
    private func deliveryKind(
        from notification: UNNotification,
        manager: ParseMessagingManager,
        messageID: MessagingMessageID
    ) -> MessagingDeliveryKind {
        let messaging = notification.request.content.userInfo["messaging"] as? [String: Any]
        let data = notification.request.content.userInfo["data"] as? [String: Any]
        if let rawValue = messaging?["deliveryType"] as? String
            ?? data?["deliveryType"] as? String,
           let kind = MessagingDeliveryKind(rawValue: rawValue) {
            return kind
        }
        if let cached = try? manager.store?.cachedMessage(objectID: messageID) {
            return cached.deliveryKind
        }
        return .respectful
    }

#endif
}
