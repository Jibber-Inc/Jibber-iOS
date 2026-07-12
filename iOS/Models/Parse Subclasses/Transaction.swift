//
//  Transaction.swift
//  Jibber
//
//  Created by Benji Dodgson on 2/4/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore

enum TransactionKey: String {
    case to
    case from
    case note
    case amount
    case eventType
    case achievement
}

final class Transaction: PFObject, PFSubclassing {

    static func parseClassName() -> String {
        return String(describing: self)
    }
    
    var to: User? {
        get { self.getObject(for: .to) }
        set { self.setObject(for: .to, with: newValue) }
    }
    
    var from: User? {
        get { self.getObject(for: .from) }
        set { self.setObject(for: .from, with: newValue)}
    }
    
    var nonMeUser: User? {
        if let to = to, !to.isCurrentUser {
            return to
        }
        
        return from
    }
    
    var achievement: Achievement? {
        get { self.getObject(for: .achievement) }
        set { self.setObject(for: .achievement, with: newValue)}
    }
    
    var amount: Double {
        get { self.getObject(for: .amount) ?? 0 }
        set { self.setObject(for: .amount, with: newValue) }
    }
    
    var note: String {
        get { self.getObject(for: .note) ?? "" }
        set { self.setObject(for: .note, with: newValue) }
    }
    
    static func fetchAllCurrentTransactions() async throws -> [Transaction] {
        let objects: [Transaction] = try await withCheckedThrowingContinuation { continuation in
            guard let query = self.query() else {
                continuation.resume(throwing: ClientError.apiError(detail: "Query was nil"))
                return
            }
            query.whereKey("to", equalTo: User.current()!)
            query.findObjectsInBackground { objects, error in
                if let objs = objects as? [Transaction] {
                    continuation.resume(returning: objs)
                } else if let e = error {
                    continuation.resume(throwing: e)
                } else {
                    continuation.resume(returning: [])
                }
            }
        }

        return objects
    }
    
    static func fetchAllConnectionsTransactions() async throws -> [Transaction] {
        guard let connections = try? await GetAllConnections().makeRequest(andUpdate: [], viewsToIgnore: []) else { return [] }
        
        let connectionIds: [String] = connections.filter({ connection in
            return connection.status == .accepted
        }).compactMap({ connection in
            return connection.nonMeUser?.objectId
        })
        
        let objects: [Transaction] = try await withCheckedThrowingContinuation { continuation in
            
            guard let query = self.query() else {
                continuation.resume(throwing: ClientError.apiError(detail: "Query was nil"))
                return
            }
            query.whereKey("to", containedIn: connectionIds)
            query.findObjectsInBackground { objects, error in
                if let objs = objects as? [Transaction] {
                    continuation.resume(returning: objs)
                } else if let e = error {
                    continuation.resume(throwing: e)
                } else {
                    continuation.resume(returning: [])
                }
            }
        }

        return objects
    }
    
    static func createTransaction(from type: AchievementType) async throws -> Transaction? {
        guard let updated = try? await type.retrieveDataIfNeeded() else { return nil }
        let transaction = Transaction()
        transaction.to = User.current()
        transaction.from = User.current()
        transaction.amount = Double(updated.bounty)
        transaction.note = updated.descriptionText
        return try await transaction.saveToServer()
    }
}

extension Transaction: Objectable {
    typealias KeyType = TransactionKey

    func getObject<Type>(for key: TransactionKey) -> Type? {
        return self.object(forKey: key.rawValue) as? Type
    }

    func setObject<Type>(for key: TransactionKey, with newValue: Type) {
        self.setObject(newValue, forKey: key.rawValue)
    }

    func getRelationalObject<PFRelation>(for key: TransactionKey) -> PFRelation? {
        return self.relation(forKey: key.rawValue) as? PFRelation
    }
}

struct TransactionsCalculator {
    
    /// 1 Jib earned each day with a value of $0.01
    /// Number of jibs earned per day
    private let interestRate: Double = 1.0
    /// Value of 1 jib earned in dollars
    private let conversationRate: Double = 0.01
    
    func calculateJibsEarned(for transactions: [Transaction]) async throws -> Double {
        let transactions: [Transaction] = try await transactions.asyncMap { transaction in
            return try await transaction.retrieveDataIfNeeded()
        }
        
        var total: Double = 0.0
        transactions.forEach { transaction in
            total += transaction.amount
        }
        
        return total
    }
    
    func calculateInterestEarned() -> Double {
        
        guard let latestCreatedAt = AchievementsManager.shared.achievements.first(where: { achievement in
            achievement.type?.type == "INTEREST_PAYMENT"
        })?.createdAt else { return 0.0 }
        
        let timeSince = -latestCreatedAt.timeIntervalSinceNow
        let jibsEarned = (timeSince / 86400) * self.interestRate
        return jibsEarned
    }
    
    func calculateCreditBalanceForJibs(for total: Double) -> Double {
        return total * self.conversationRate
    }
}
