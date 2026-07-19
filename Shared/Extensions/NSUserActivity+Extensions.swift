//
//  NSUserActivity+Extensions.swift
//  Jibber
//
//  Created by Benji Dodgson on 11/20/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation

enum AppClipInvocation: Equatable {
    case invite(reservationID: String)
    case moment(momentID: String)

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return nil
        }

        let queryItems = (components.queryItems ?? []).reduce(into: [String: String]()) {
            values, item in
            guard values[item.name] == nil,
                  let value = item.value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                return
            }
            values[item.name] = value
        }

        let host = components.host?.lowercased()
        if host == "appclip.apple.com", components.path == "/id" {
            switch queryItems["kind"] {
            case "invite":
                guard let reservationID = queryItems["reservationId"] else { return nil }
                self = .invite(reservationID: reservationID)
            case "moment":
                guard let momentID = queryItems["momentId"] else { return nil }
                self = .moment(momentID: momentID)
            default:
                return nil
            }
        } else if host == "jibber.wtf" || host == "www.jibber.wtf" {
            switch components.path {
            case "/reservation":
                guard let reservationID = queryItems["reservationId"] else { return nil }
                self = .invite(reservationID: reservationID)
            case "/moment":
                guard let momentID = queryItems["momentId"] else { return nil }
                self = .moment(momentID: momentID)
            default:
                return nil
            }
        } else {
            return nil
        }
    }

    func url(for environment: Environment) -> URL {
        var components = URLComponents(string: "https://appclip.apple.com/id")!
        var queryItems = [
            URLQueryItem(name: "p", value: environment.bundleId + ".Clip")
        ]

        switch self {
        case .invite(let reservationID):
            queryItems.append(URLQueryItem(name: "kind", value: "invite"))
            queryItems.append(URLQueryItem(name: "reservationId", value: reservationID))
        case .moment(let momentID):
            queryItems.append(URLQueryItem(name: "kind", value: "moment"))
            queryItems.append(URLQueryItem(name: "momentId", value: momentID))
        }

        components.queryItems = queryItems
        return components.url!
    }

    var launchActivity: LaunchActivity {
        switch self {
        case .invite(let reservationID):
            return .reservation(reservationId: reservationID)
        case .moment(let momentID):
            var object = DeepLinkObject(target: .moment)
            object.momentId = momentID
            return .deepLink(object)
        }
    }
}

extension NSUserActivity {
    
    var launchActivity: LaunchActivity? {
        
        if self.activityType == NSUserActivityTypeBrowsingWeb,
           let incomingURL = self.webpageURL {
            if let invocation = AppClipInvocation(url: incomingURL) {
                return invocation.launchActivity
            }

            guard let components = URLComponents(url: incomingURL, resolvingAgainstBaseURL: true) else {
                return nil
            }
            let queryItems = (components.queryItems ?? []).reduce(into: [String: String]()) {
                values, item in
                guard values[item.name] == nil, let value = item.value else { return }
                values[item.name] = value
            }

            let path = components.path
            switch path {
            case "/onboarding":
                if let phoneNumber = queryItems["phoneNumber"] ?? components.queryItems?.first?.value {
                    return .onboarding(phoneNumber: phoneNumber)
                }
            case "/pass":
                if let passId = queryItems["passId"] ?? components.queryItems?.first?.value {
                    return .pass(passId: passId)
                }
            default:
                return nil
            }
        }
        return nil
    }
}
