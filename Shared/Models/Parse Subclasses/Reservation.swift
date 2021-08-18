//
//  Reservation.swift
//  Benji
//
//  Created by Benji Dodgson on 5/9/20.
//  Copyright © 2020 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Parse
import Combine
import LinkPresentation

enum ReservationKey: String {
    case user
    case createdBy
    case isClaimed
    case reservationId
    case contactId
}

final class Reservation: PFObject, PFSubclassing {

    static func parseClassName() -> String {
        return String(describing: self)
    }

    var isClaimed: Bool {
        return self.getObject(for: .isClaimed) ?? false
    }

    var user: User? {
        return self.getObject(for: .user)
    }

    var createdBy: User? {
        return self.getObject(for: .createdBy)
    }

    var contactId: String? {
        get {
            return self.getObject(for: .contactId)
        }
        set {
            self.setObject(for: .contactId, with: newValue)
        }
    }

    static func getUnclaimedReservationCount(for user: User) async -> Int {
        return await withCheckedContinuation { continuation in
            if let query = Reservation.query() {
                query.whereKey(ReservationKey.createdBy.rawValue, equalTo: user)
                query.whereKey(ReservationKey.isClaimed.rawValue, equalTo: false)
                query.countObjectsInBackground { count, error in
                    if let _ = error {
                        continuation.resume(returning: 0)
                    } else {
                        continuation.resume(returning: Int(count))
                    }
                }
            } else {
                continuation.resume(returning: 0)
            }
        }
    }
}

extension Reservation: Objectable {
    typealias KeyType = ReservationKey

    func getObject<Type>(for key: ReservationKey) -> Type? {
        return self.object(forKey: key.rawValue) as? Type
    }

    func setObject<Type>(for key: ReservationKey, with newValue: Type) {
        self.setObject(newValue, forKey: key.rawValue)
    }

    func getRelationalObject<PFRelation>(for key: ReservationKey) -> PFRelation? {
        return self.relation(forKey: key.rawValue) as? PFRelation
    }
}

private var reservationMetadataKey: UInt8 = 0
private var linkKey: UInt8 = 0
extension Reservation: UIActivityItemSource {

    private(set) var metadata: LPLinkMetadata? {
        get {
            return self.getAssociatedObject(&reservationMetadataKey)
        }
        set {
            self.setAssociatedObject(key: &reservationMetadataKey, value: newValue)
        }
    }

    private(set) var link: String? {
        get {
            return self.getAssociatedObject(&linkKey)
        }
        set {
            self.setAssociatedObject(key: &linkKey, value: newValue)
        }
    }

    var message: String? {
        guard let link = self.link else { return nil }
        return "RSVP code: \(String(optional: self.objectId))\nClaim your RSVP by tapping 👇\n\(link)"
    }

    var reminderMessage: String? {
        guard let link = self.link else { return nil }
        return "RSVP code: \(String(optional: self.objectId))\nOurs an is an exclusive place to be social. I saved you a spot. Tap👇\n\(link)"
    }

    func prepareMetadata(andUpdate statusables: [Statusable]) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let metadataProvider = LPMetadataProvider()

            // Trigger the loading event for all statusables
            for statusable in statusables {
                statusable.handleEvent(status: .loading)
            }

            let domainURL = "https://ourown.chat"
            if let objectId = self.objectId {
                self.link = domainURL + "/reservation?reservationId=\(objectId)"
            }

            if let url = URL(string: domainURL) {
                metadataProvider.startFetchingMetadata(for: url) { [unowned self] (metadata, error) in
                    Task.onMainActor {
                        if let e = error {
                            for statusable in statusables {
                                statusable.handleEvent(status: .error("Error"))
                            }
                            continuation.resume(throwing: e)
                        } else {
                            self.metadata = metadata
                            for statusable in statusables {
                                statusable.handleEvent(status: .complete)
                            }
                            continuation.resume(returning: ())
                        }
                    }
                }
            } else {
                continuation.resume(throwing: ClientError.generic)
            }
        }
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return URL(string: self.link!)!
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        guard let link = self.link else { return nil }
        return "Claim your reservation by tapping 👇\n\(link)"
    }

    func activityViewControllerLinkMetadata(_: UIActivityViewController) -> LPLinkMetadata? {
        return self.metadata
    }
}

