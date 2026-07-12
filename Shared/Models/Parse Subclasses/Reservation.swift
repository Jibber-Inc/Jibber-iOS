//
//  Reservation.swift
//  Benji
//
//  Created by Benji Dodgson on 5/9/20.
//  Copyright © 2020 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore
import Combine
import LinkPresentation

enum ReservationKey: String {
    case user
    case createdBy
    case isClaimed
    case contactId
    case conversationCid
}

final class Reservation: PFObject, PFSubclassing {
    
    static func parseClassName() -> String {
        return String(describing: self)
    }

    var isClaimed: Bool {
        return self.getObject(for: .isClaimed) ?? false
    }

    var createdBy: User? {
        return self.getObject(for: .createdBy)
    }

    var conversationCid: String? {
        get { return self.getObject(for: .conversationCid) }
        set { self.setObject(for: .conversationCid, with: newValue) }
    }

    var contactId: String? {
        get { return self.getObject(for: .contactId) }
        set { self.setObject(for: .contactId, with: newValue) }
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
        return "Get the Jibber app so we can communicate with empathy.\nRSVP by tapping 👇\n\(link)"
    }

    var reminderMessage: String? {
        guard let link = self.link else { return nil }
        return "Reminder! Get the Jibber app so we can communicate with empathy.\nRSVP by tapping 👇\n\(link)"
    }

    func prepareMetadata() async {
        if let objectId = self.objectId {
            self.link = Config.domain + "/reservation?reservationId=\(objectId)"
        }

        guard let link = self.link, let url = URL(string: link) else { return }
        self.metadata = try? await LPMetadataProvider().startFetchingMetadata(for: url)
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

    /// Returns all reservations that are unclaimed.
    static func getAllUnclaimed() async -> [Reservation] {
        let query = Reservation.allUnclaimedQuery()
        do {
            let objects = try await query.findObjectsInBackground()
            if let reservations = objects as? [Reservation] {
                return reservations
            } else {
                return []
            }
        } catch {
            await ToastScheduler.shared.schedule(toastType: .error(error))
            return []
        }
    }

    static func allUnclaimedQuery() -> PFQuery<PFObject> {
        let query = Reservation.query()!
        query.whereKey(ReservationKey.createdBy.rawValue, equalTo: User.current()!)
        query.whereKey(ReservationKey.isClaimed.rawValue, equalTo: false)
        return query
    }

    /// Returns a parse query that gets unclaimed reservations that have a related contact id.
    static func allUnclaimedWithContactQuery() -> PFQuery<PFObject> {
        let query = Reservation.query()!
        query.whereKey(ReservationKey.createdBy.rawValue, equalTo: User.current()!)
        query.whereKey(ReservationKey.isClaimed.rawValue, equalTo: false)
        query.whereKeyExists(ReservationKey.contactId.rawValue)
        return query
    }
}
