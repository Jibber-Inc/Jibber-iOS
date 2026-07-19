//
//  Config.swift
//  Benji
//
//  Created by Benji Dodgson on 12/29/20.
//  Copyright © 2020 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore

enum Environment: String {

    case staging = "staging"
    case production = "production"

    var url: String {
        switch self {
        case .staging: return "https://jibber-staging-api.b4a.io"
        case .production: return "https://jibber-api.b4a.io"
        }
    }

    var appId: String {
        switch self {
        case .staging: return "hePp5QCoCdRygkKOmIGqyporjgo2LIrdhMuf687m"
        case .production: return "4qvd8tYEda8zwXGWXSXcRzyQ4EShmqvdJLDJznsD"
        }
    }

    var clientKey: String {
        switch self {
        case .staging: return "SbXSsqeVf9jGoc029WauVSXWMzfDY0oOK0xSu55t"
        case .production: return "lcT9US7v82eAQXHGXpu6mgpu7pOtVu7fQjJAUDJA"
        }
    }

    var bundleId: String {
        switch self {
        case .staging:
            return "com.Jibber-Inc.iOS-staging"
        case .production:
            return "com.Jibber-Inc.iOS"
        }
    }

    var displayName: String {
        switch self {
        case .staging: return "stag"
        case .production: return "prod"
        }
    }

    var groupId: String {
        switch self {
        case .staging:
            return "group.Jibber-staging"
        case .production:
            return "group.Jibber"
        }
    }

}

enum BuildType: String, CaseIterable {
    case release = "release"
    case debug = "debug"
}

var isRelease: Bool {
    return Config.shared.buildType == .release
}

final class Config: NSObject, @unchecked Sendable {

    static let shared = Config.init()
    private let parseInitializationLock = NSLock()
    
    static let domain = "https://jibber.wtf"

    let environment: Environment = {
        var environmentToReturn = Environment.production

        if let bundledApiTargetString = Bundle.main.infoDictionary!["API_TARGET"] as? String,
            let bundledApiTargetEnum = Environment(rawValue: bundledApiTargetString.lowercased()) {
            environmentToReturn = bundledApiTargetEnum
        } else {
            fatalError("Info.plist (Or Info-dev.plist) not properly configured to have "
                + "API_TARGET set, crashing because you screwed something up.")
        }

        return environmentToReturn
    }()

    let buildType: BuildType = {
        var buildTypeToReturn = BuildType.release

        if let bundledBuildTypeString = Bundle.main.infoDictionary!["RELEASE_TYPE"] as? String,
            let bundledBuildTypeEnum = BuildType(rawValue: bundledBuildTypeString.lowercased()) {
            buildTypeToReturn = bundledBuildTypeEnum
        } else {
            fatalError("Info.plist (Or Info-dev.plist) not properly configured to have "
                + "RELEASE_TYPE set, crashing because you screwed something up.")
        }

        return buildTypeToReturn
    }()

    private(set) var appVersion: String = {
        var version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
        version = version.trimmingCharacters(in: CharacterSet(charactersIn: "0123456789.").inverted)
        return version
    }()
    
    func initializeParseIfNeeded(includeBundleId: Bool = true) {
        parseInitializationLock.lock()
        defer { parseInitializationLock.unlock() }

        if Parse.currentConfiguration.isNil  {
            Parse.initialize(with: ParseClientConfiguration(block: { (configuration: ParseMutableClientConfiguration) in
                let sessionConfiguration = URLSessionConfiguration.default
                sessionConfiguration.httpAdditionalHeaders = [
                    "X-Jibber-App-Version": self.appVersion,
                    "X-Jibber-Messaging-Schema": "1"
                ]

                configuration.applicationGroupIdentifier = self.environment.groupId
                configuration.clientKey = self.environment.clientKey
                configuration.server = self.environment.url
                configuration.applicationId = self.environment.appId
                configuration.isLocalDatastoreEnabled = true
                configuration.urlSessionConfiguration = sessionConfiguration
                if includeBundleId {
                    configuration.containingApplicationBundleIdentifier = self.environment.bundleId
                }
            }))
            User.registerSubclass()
        }
    }
}
