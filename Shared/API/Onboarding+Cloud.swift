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
    var forceUpgrade: Bool = false

    @discardableResult
    func makeRequest(andUpdate statusables: [Statusable], viewsToIgnore: [UIView]) async throws -> Any {
        
        let params: [String: Any] = ["passId": self.passId,
                                     "reservationId": self.reservationId,
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
