//
//  Moment.swift
//  Jibber
//
//  Created by Benji Dodgson on 8/3/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore
import LinkPresentation

 enum MomentKey: String {
     case author
     case expression
     case file
     case preview
     case caption
     case location
     case messagingConversationId
 }

 final class Moment: PFObject, PFSubclassing, @unchecked Sendable {

     static func parseClassName() -> String {
         return String(describing: self)
     }
     
     @MainActor
     var isAvailable: Bool {
         guard let user = User.current() else { return true }
         
         if MomentsStore.shared.hasRecordedToday {
             return true
         }
         
         if self.isFromCurrentUser {
             return true
         }
         
         if !user.isOnboarded {
             return true
         }
         
         if user.status == .waitlist {
             return true
         }
         
         return false
    }
     
     var isFromCurrentUser: Bool {
         return self.author?.objectId == User.current()?.objectId
     }
     
     var commentsId: String {
         if let messagingConversationId = self.messagingConversationId,
            !messagingConversationId.isEmpty {
             return messagingConversationId
         }
         guard let objectId = self.objectId else { return "" }
         return "moment:" + objectId
     }

     var messagingConversationId: String? {
         get { self.getObject(for: .messagingConversationId) }
         set { self.setObject(for: .messagingConversationId, with: newValue) }
     }

     var author: User? {
         get { self.getObject(for: .author) }
         set { self.setObject(for: .author, with: newValue) }
     }

     var expression: Expression? {
         get { self.getObject(for: .expression) }
         set { self.setObject(for: .expression, with: newValue) }
     }

     var file: PFFileObject? {
         get { self.getObject(for: .file) }
         set { self.setObject(for: .file, with: newValue) }
     }
     
     var preview: PFFileObject? {
         get { self.getObject(for: .preview) }
         set { self.setObject(for: .preview, with: newValue) }
     }
     
     var caption: String? {
         get { self.getObject(for: .caption) }
         set { self.setObject(for: .caption, with: newValue) }
     }
     
     var location: PFGeoPoint? {
         get { self.getObject(for: .location) }
         set { self.setObject(for: .location, with: newValue) }
     }
 }

 extension Moment: Objectable {
     typealias KeyType = MomentKey

     func getObject<Type>(for key: MomentKey) -> Type? {
         return self.object(forKey: key.rawValue) as? Type
     }

     func setObject<Type>(for key: MomentKey, with newValue: Type) {
         self.setObject(newValue, forKey: key.rawValue)
     }

     func getRelationalObject<PFRelation>(for key: MomentKey) -> PFRelation? {
         return self.relation(forKey: key.rawValue) as? PFRelation
     }
 }

 extension Moment: ImageDisplayable {

     var image: UIImage? {
         return nil
     }

     var imageFileObject: PFFileObject? {
         return self.file
     }
 }

// Stable-address token used only as an Objective-C associated-object key.
nonisolated(unsafe) private var urlKey: UInt8 = 0
nonisolated(unsafe) private var momentShareItemKey: UInt8 = 0
extension Moment: UIActivityItemSource {
    
    private(set) var previewURL: URL? {
        get {
            return self.getAssociatedObject(&urlKey)
        }
        set {
            self.setAssociatedObject(key: &urlKey, value: newValue)
        }
    }

    private(set) var shareItem: AppClipShareItem? {
        get {
            return self.getAssociatedObject(&momentShareItemKey)
        }
        set {
            self.setAssociatedObject(key: &momentShareItemKey, value: newValue)
        }
    }
    
    func prepareMetadata() async {
        _ = try? await self.retrieveDataIfNeeded()
        self.previewURL = try? await self.preview?.retrieveCachedPathURL()

        guard let objectId = self.objectId else { return }

        var momentAuthor = self.author
        if let authorPointer = momentAuthor {
            momentAuthor = try? await authorPointer.retrieveDataIfNeeded()
        }

        var previewImage: UIImage?
        if let previewFile = self.preview,
           let data = try? await previewFile.retrieveDataInBackground() {
            previewImage = UIImage(data: data)
        }

        let authorName = momentAuthor?.givenName.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstName = (authorName?.isEmpty == false ? authorName : nil) ?? "Someone"
        self.shareItem = AppClipShareItem(
            invocationURL: AppClipInvocation.moment(momentID: objectId)
                .url(for: Config.shared.environment),
            firstName: firstName,
            previewImage: previewImage
        )
    }

    func activityItems() -> [Any] {
        guard let shareItem else { return [] }
        var items: [Any] = [shareItem]
        let authorName = self.author?.givenName.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstName = (authorName?.isEmpty == false ? authorName : nil) ?? "Someone"
        var text = "\(firstName) shared a Moment with you on Jibber."
        if let caption = self.caption?.trimmingCharacters(in: .whitespacesAndNewlines),
           !caption.isEmpty {
            text += "\n\n\(caption)"
        }
        items.append(text)
        return items
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return self.shareItem?.invocationURL ?? URL(string: Config.domain)!
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return self.shareItem?.invocationURL
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return ""
    }
    
    func activityViewControllerLinkMetadata(_: UIActivityViewController) -> LPLinkMetadata? {
        return self.shareItem?.metadata
    }
}
