//
//  ParseMessagingAuthentication.swift
//  MessagingPersistence
//

import Foundation
import MessagingContracts
import ParseSwift

/// Activates ParseSwift with the already-authenticated Objective-C Parse
/// session token. The application supplies that token through a
/// `MessagingSessionProviding` adapter backed by PFUser.
public struct ParseSwiftMessagingSessionActivator: MessagingSessionActivating {
    public init() {}

    @discardableResult
    public func activateMessagingSession(
        _ session: MessagingAuthSession
    ) async throws -> MessagingUserID {
        if let current = MessagingParseUser.current,
           current.objectId == session.userID,
           current.sessionToken == session.sessionToken {
            return session.userID
        }
        let user = try await MessagingParseUser().become(sessionToken: session.sessionToken)
        guard user.objectId == session.userID else {
            throw MessagingModelError.identityMismatch(
                expected: session.userID,
                actual: user.objectId
            )
        }
        return session.userID
    }
}

public struct MessagingAuthenticationCoordinator {
    private let sessionProvider: MessagingSessionProviding
    private let sessionActivator: MessagingSessionActivating

    public init(
        sessionProvider: MessagingSessionProviding,
        sessionActivator: MessagingSessionActivating = ParseSwiftMessagingSessionActivator()
    ) {
        self.sessionProvider = sessionProvider
        self.sessionActivator = sessionActivator
    }

    @discardableResult
    public func synchronizeSession() async throws -> MessagingUserID? {
        guard let session = try sessionProvider.currentMessagingSession() else {
            return nil
        }
        return try await sessionActivator.activateMessagingSession(session)
    }
}
