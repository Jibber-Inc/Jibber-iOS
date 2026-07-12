//
//  AvatarContextDelegate.swift
//  Jibber
//
//  Created by Benji Dodgson on 1/18/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation

protocol PersonContextDelegate: UIContextMenuInteractionDelegate {
    func getMenu(for person: PersonType) -> UIMenu
    var didTapViewProfile: CompletionOptional { get set }
}

// Objective-C associated-object access is serialized by the UI's main-actor ownership.
private nonisolated(unsafe) var personKey: UInt8 = 0
extension PersonContextDelegate where Self: NSObject {

    var person: PersonType? {
        get {
            return self.getAssociatedObject(&personKey)
        }
        set {
            self.setAssociatedObject(key: &personKey, value: newValue)
        }
    }

    func getMenu(for person: PersonType) -> UIMenu {
        
        let action = UIAction(title: "View Profile",
                              image: ImageSymbol.personCircle.image) { [unowned self] _ in
            self.didTapViewProfile?()
        }
        return UIMenu(title: "", children: [action])
    }
}
