//
//  MessagingCapabilities.swift
//  MessagingContracts
//

import Foundation

public struct MessagingCapabilities: Codable, Hashable {
    public static let supportedSchemaVersion = 1

    public var available: Bool
    public var minimumAppVersion: String?
    public var schemaVersion: Int
    public var features: [String: Bool]

    public init(
        available: Bool,
        minimumAppVersion: String? = nil,
        schemaVersion: Int,
        features: [String: Bool] = [:]
    ) {
        self.available = available
        self.minimumAppVersion = minimumAppVersion
        self.schemaVersion = schemaVersion
        self.features = features
    }
}

public protocol MessagingCapabilitiesRepository {
    func capabilities() async throws -> MessagingCapabilities
}
