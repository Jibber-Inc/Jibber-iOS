//
//  Pass.swift
//  Jibber
//
//  Created by Benji Dodgson on 10/15/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore
import LinkPresentation

enum PassKey: String {
    case owner
    case attributes
    case connections
}

final class Pass: PFObject, PFSubclassing {

    static func parseClassName() -> String {
        return String(describing: self)
    }

    var owner: User? {
        return self.getObject(for: .owner)
    }

    var attributes: [String: Any]? {
        return self.getObject(for: .attributes)
    }

    var connections: PFRelation<Connection>? {
        return self.getRelationalObject(for: .connections)
    }
}

extension Pass: Objectable {

    typealias KeyType = PassKey

    func getObject<Type>(for key: PassKey) -> Type? {
        return self.object(forKey: key.rawValue) as? Type
    }

    func setObject<Type>(for key: PassKey, with newValue: Type) {
        self.setObject(newValue, forKey: key.rawValue)
    }

    func getRelationalObject<PFRelation>(for key: PassKey) -> PFRelation? {
        return self.relation(forKey: key.rawValue) as? PFRelation
    }
}

private var passMetadataKey: UInt8 = 0
private var linkKey: UInt8 = 0
extension Pass: UIActivityItemSource {
    
    private(set) var metadata: LPLinkMetadata? {
        get {
            return self.getAssociatedObject(&passMetadataKey)
        }
        set {
            self.setAssociatedObject(key: &passMetadataKey, value: newValue)
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
    
    func prepareMetadata() async {
        return await withCheckedContinuation { continuation in
            let metadataProvider = LPMetadataProvider()
            
            if let objectId = self.objectId {
                self.link = Config.domain + "/pass?passId=\(objectId)"
            }
            
            if let link = self.link, let url = URL(string: link) {
                metadataProvider.startFetchingMetadata(for: url) { [unowned self] (metadata, error) in
                    self.metadata = metadata
                    continuation.resume(returning: ())
                }
            }
        }
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return URL(string: self.link!)!
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        guard let link = self.link else { return nil }
        return "Join me on Jibber 👇\n\(link)"
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return ""
    }
    
    func activityViewControllerLinkMetadata(_: UIActivityViewController) -> LPLinkMetadata? {
        return self.metadata
    }
    
    static func fetchPass() async throws -> Pass {
        return try await withCheckedThrowingContinuation { continuation in
            guard let query = self.query() else {
                continuation.resume(throwing: ClientError.apiError(detail: "Query was nil"))
                return
            }
            query.whereKey("owner", equalTo: User.current()!)
            query.getFirstObjectInBackground { object, error in
                if let pass = object as? Pass {
                    continuation.resume(returning: pass)
                } else if let e = error {
                    continuation.resume(throwing: e)
                }
            }
        }
    }
}
