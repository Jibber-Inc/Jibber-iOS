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
import UIKit

final class AppClipShareItem: NSObject, UIActivityItemSource {

    let invocationURL: URL
    let metadata: LPLinkMetadata

    init(invocationURL: URL, firstName: String, previewImage: UIImage?) {
        self.invocationURL = invocationURL

        let metadata = LPLinkMetadata()
        metadata.title = "Jibber · \(firstName)"
        metadata.url = invocationURL
        metadata.originalURL = invocationURL
        if let previewImage {
            metadata.imageProvider = NSItemProvider(object: previewImage)
        }
        self.metadata = metadata

        super.init()
    }

    func activityViewControllerPlaceholderItem(
        _ activityViewController: UIActivityViewController
    ) -> Any {
        return self.invocationURL
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        return self.invocationURL
    }

    func activityViewControllerLinkMetadata(
        _ activityViewController: UIActivityViewController
    ) -> LPLinkMetadata? {
        return self.metadata
    }
}

enum ReservationKey: String {
    case user
    case createdBy
    case isClaimed
    case contactId
    case conversationCid
    case status
    case sourceKind
    case sourceMoment
    case inviteMessage
    case shareRequestId
    case expiresAt
}

enum ReservationStatus: String {
    case pending
    case accepted
    case declined
}

final class Reservation: PFObject, PFSubclassing, @unchecked Sendable {
    
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

    var status: ReservationStatus {
        guard let rawValue: String = self.getObject(for: .status) else {
            return .pending
        }
        return ReservationStatus(rawValue: rawValue) ?? .pending
    }

    var user: User? {
        return self.getObject(for: .user)
    }

    var inviteMessage: String? {
        get { return self.getObject(for: .inviteMessage) }
        set { self.setObject(for: .inviteMessage, with: newValue) }
    }

    var expiresAt: Date? {
        return self.getObject(for: .expiresAt)
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

// Stable-address tokens used only as Objective-C associated-object keys.
nonisolated(unsafe) private var reservationMetadataKey: UInt8 = 0
nonisolated(unsafe) private var linkKey: UInt8 = 0
nonisolated(unsafe) private var reservationShareItemKey: UInt8 = 0
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

    private(set) var shareItem: AppClipShareItem? {
        get {
            return self.getAssociatedObject(&reservationShareItemKey)
        }
        set {
            self.setAssociatedObject(key: &reservationShareItemKey, value: newValue)
        }
    }

    var message: String? {
        let invitation = "I'd like to connect with you on Jibber."
        guard let inviteMessage, !inviteMessage.isEmpty else { return invitation }
        return "\(invitation)\n\n\(inviteMessage)"
    }

    var reminderMessage: String? {
        let reminder = "Reminder: I'd still like to connect with you on Jibber."
        guard let inviteMessage, !inviteMessage.isEmpty else { return reminder }
        return "\(reminder)\n\n\(inviteMessage)"
    }

    func prepareMetadata() async {
        guard let objectId = self.objectId else { return }

        var inviter = self.createdBy
        if let inviterPointer = inviter {
            inviter = try? await inviterPointer.retrieveDataIfNeeded()
        }

        var previewImage: UIImage?
        if let imageFile = inviter?.smallImage,
           let data = try? await imageFile.retrieveDataInBackground() {
            previewImage = UIImage(data: data)
        }

        let invocation = AppClipInvocation.invite(reservationID: objectId)
        let url = invocation.url(for: Config.shared.environment)
        let inviterName = inviter?.givenName.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstName = (inviterName?.isEmpty == false ? inviterName : nil) ?? "Someone"
        let shareItem = AppClipShareItem(
            invocationURL: url,
            firstName: firstName,
            previewImage: previewImage
        )
        self.link = url.absoluteString
        self.metadata = shareItem.metadata
        self.shareItem = shareItem
    }

    func activityItems(reminder: Bool) -> [Any] {
        guard let shareItem else { return [] }
        let text = reminder ? self.reminderMessage : self.message
        var items: [Any] = [shareItem]
        if let text {
            items.append(text)
        }
        return items
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return self.shareItem?.invocationURL ?? URL(string: Config.domain)!
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return self.shareItem?.invocationURL
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
