//
//  AchievementsManager.swift
//  Jibber
//
//  Created by Benji Dodgson on 3/16/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore
import JibberParseLiveQuery

class AchievementsManager {
    
    static let shared = AchievementsManager()
    
    private(set) var achievements: [Achievement] = []
    private(set) var types: [AchievementType] = []
        
    private var initializeTask: Task<Void, Error>?
    
    func initializeIfNeeded() async throws {
        
        // If we already have an initialization task, wait for it to finish.
        if let initializeTask = self.initializeTask {
            try await initializeTask.value
            return
        }
        
        // Otherwise start a new initialization task and wait for it to finish.
        self.initializeTask = Task { [weak self] in
            guard let self else { return }
            
            if let types = try? await AchievementType.fetchAll() {
                self.types = types
            }
            
            if let achievements = try? await Achievement.fetchAll() {
                await achievements.asyncForEach { achievement in
                    _ = try? await achievement.retrieveDataIfNeeded()
                }
                
                self.achievements = achievements
            }
            
            self.subscribeToUpdates()
        }
        
        do {
            try await self.initializeTask?.value
        } catch {
            // Dispose of the task because it failed, then pass the error along.
            self.initializeTask = nil
            throw error
        }
    }
    
    private func subscribeToUpdates() {
        guard let query = Achievement.query() else { return }
        Client.shared.unsubscribe(query)
        
        query.includeKey("type")
        let subscription = Client.shared.subscribe(query)
        subscription.handleEvent { query, event in
            switch event {
            case .created(let object):
                guard let achievement = object as? Achievement else { return }
                
                Task {
                    await ToastScheduler.shared.schedule(toastType: .achievement(achievement))
                }
                self.achievements.append(achievement)
            default:
                break
            }
        }
    }
    
    func createIfNeeded(with type: AchievementType.LocalType) {

        Task {
            do {
                // If we already have an initialization task, wait for it to finish.
                if let initializeTask = self.initializeTask {
                    try await initializeTask.value
                }

                await self.create(with: type)
            } catch {
                logError(error)
            }
        }
    }
    
    private func create(with type: AchievementType.LocalType) async {
        
        guard let selectedType = self.types.first(where: { t in
            return t.type == type.rawValue
        }) else { return }
        
        var achievement: Achievement?
        
        if selectedType.isRepeatable {
            achievement = await self.createAchievement(with: selectedType)
        } else if self.achievements.first(where: { achievement in
            return achievement.type == selectedType
        }).isNil {
            achievement = await self.createAchievement(with: selectedType)
        }
        
        if let achievement = achievement {
            Task {
                await ToastScheduler.shared.schedule(toastType: .achievement(achievement))
            }
            AnalyticsManager.shared.trackEvent(type: .achievementCreated, properties: ["value": selectedType.type!])
        }
    }
    
    private func createAchievement(with type: AchievementType) async -> Achievement? {
        guard let transaction = try? await Transaction.createTransaction(from: type) else { return nil }
        
        let achievement = Achievement()
        achievement.type = type
        achievement.amount = Double(type.bounty)
        achievement.transaction = transaction
        
        guard let saved = try? await achievement.saveToServer() else { return achievement }
        
        transaction.achievement = saved
        
        _ = try? await transaction.saveToServer()
        
        return achievement
    }
}
