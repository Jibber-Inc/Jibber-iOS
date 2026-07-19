//
//  Onboarding+CloudCalls.swift
//  Benji
//
//  Created by Benji Dodgson on 2/11/20.
//  Copyright © 2020 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore
import PhoneNumberKit

struct SendCode: CloudFunction {
    
    typealias ReturnType = Any
    
    let phoneNumber: PhoneNumber
    let region: String
    let installationId: String
    
    func makeRequest(andUpdate statusables: [Statusable] = [],
                     viewsToIgnore: [UIView] = []) async throws -> Any {

        let phoneString = PhoneKit.shared.format(self.phoneNumber, toType: .e164)
        
        let params = ["phoneNumber": phoneString,
                      "installationId": self.installationId,
                      "region": self.region]
        
        let result = try await self.makeRequest(andUpdate: statusables,
                                                params: params,
                                                callName: "sendCode",
                                                delayInterval: 0.0,
                                                viewsToIgnore: viewsToIgnore)
        return result
    }
}

struct VerifyCode: CloudFunction {

    typealias ReturnType = [String: String]
    
    let code: String
    let phoneNumber: PhoneNumber
    let installationId: String

    func makeRequest(andUpdate statusables: [Statusable] = [],
                     viewsToIgnore: [UIView] = []) async throws -> [String: String] {
        
        let params: [String: Any] = ["authCode": self.code,
                                     "installationId": self.installationId,
                                     "phoneNumber": PhoneKit.shared.format(self.phoneNumber, toType: .e164)]
        
        let result = try await self.makeRequest(andUpdate: statusables,
                                                params: params,
                                                callName: "validateCode",
                                                viewsToIgnore: viewsToIgnore)
        
        if let dict = result as? [String: String],
           let token = dict["sessionToken"],
           !token.isEmpty {
            return dict
        } else if let token = result as? String {
            var dict: [String: String] = [:]
            dict["sessionToken"] = token
            return dict
        } else {
            throw(ClientError.apiError(detail: "Verify code error"))
        }
    }
}

struct FinalizeOnboarding: CloudFunction {

    typealias ReturnType = Any
    
    let reservationId: String
    let passId: String
    let momentId: String
    var forceUpgrade: Bool

    init(
        reservationId: String,
        passId: String,
        momentId: String = "",
        forceUpgrade: Bool = false
    ) {
        self.reservationId = reservationId
        self.passId = passId
        self.momentId = momentId
        self.forceUpgrade = forceUpgrade
    }

    @discardableResult
    func makeRequest(andUpdate statusables: [Statusable], viewsToIgnore: [UIView]) async throws -> Any {
        
        let params: [String: Any] = ["passId": self.passId,
                                     "reservationId": self.reservationId,
                                     "momentId": self.momentId,
                                     "forceUpgrade": self.forceUpgrade]
        
        _ = try await self.makeRequest(andUpdate: statusables,
                                       params: params,
                                       callName: "finalizeUserOnboarding",
                                       delayInterval: 0.0,
                                       viewsToIgnore: viewsToIgnore)

        guard let user = User.current() else {
            throw ClientError.message(detail: "No user found.")
        }

        // Refresh the user so it's activation status is properly reflected.
        return try await user.fetchInBackground()
    }

}

struct PreparePersonInvitation: CloudFunction {

    typealias ReturnType = [String: Any]

    let message: String
    let requestId: String
    let reservationId: String?

    func makeRequest(
        andUpdate statusables: [Statusable] = [],
        viewsToIgnore: [UIView] = []
    ) async throws -> [String: Any] {
        var params: [String: Any] = [
            "message": self.message,
            "requestId": self.requestId
        ]
        if let reservationId {
            params["reservationId"] = reservationId
        }

        let result = try await self.makeRequest(
            andUpdate: statusables,
            params: params,
            callName: "preparePersonInvitation",
            delayInterval: 0.0,
            viewsToIgnore: viewsToIgnore
        )
        guard let invitation = result as? [String: Any] else {
            throw ClientError.apiError(detail: "Invalid invitation response")
        }
        return invitation
    }
}

struct AcceptMomentInvitation: CloudFunction {

    typealias ReturnType = [String: Any]

    let momentId: String

    func makeRequest(
        andUpdate statusables: [Statusable] = [],
        viewsToIgnore: [UIView] = []
    ) async throws -> [String: Any] {
        let result = try await self.makeRequest(
            andUpdate: statusables,
            params: ["momentId": self.momentId],
            callName: "acceptMomentInvitation",
            delayInterval: 0.0,
            viewsToIgnore: viewsToIgnore
        )
        guard let invitation = result as? [String: Any] else {
            throw ClientError.apiError(detail: "Invalid Moment invitation response")
        }
        return invitation
    }
}

struct GetAppClipShareContext: CloudFunction {

    typealias ReturnType = [String: Any]

    enum Kind: String {
        case invite
        case moment
    }

    let kind: Kind
    let id: String

    func makeRequest(
        andUpdate statusables: [Statusable] = [],
        viewsToIgnore: [UIView] = []
    ) async throws -> [String: Any] {
        let result = try await self.makeRequest(
            andUpdate: statusables,
            params: ["kind": self.kind.rawValue, "id": self.id],
            callName: "getAppClipShareContext",
            delayInterval: 0.0,
            viewsToIgnore: viewsToIgnore
        )
        guard let context = result as? [String: Any] else {
            throw ClientError.apiError(detail: "Invalid App Clip share context")
        }
        return context
    }
}

struct RespondToReservationInvitation: CloudFunction {

    enum Decision: String {
        case accepted
        case declined
    }

    typealias ReturnType = Any

    let reservationId: String
    let decision: Decision

    func makeRequest(andUpdate statusables: [Statusable] = [],
                     viewsToIgnore: [UIView] = []) async throws -> Any {
        let params = ["reservationId": self.reservationId,
                      "decision": self.decision.rawValue]

        return try await self.makeRequest(
            andUpdate: statusables,
            params: params,
            callName: "respondToReservationInvitation",
            delayInterval: 0.0,
            viewsToIgnore: viewsToIgnore
        )
    }
}
