//
//  User+INPerson.swift
//  Jibber
//
//  Created by Benji Dodgson on 6/18/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Intents
import ParseCore
import UIKit

extension User {

    var iNPerson: INPerson? {
        return INPerson(personHandle: self.inHandle,
                        nameComponents: self.nameComponents,
                        displayName: self.fullName,
                        image: self.inImage,
                        contactIdentifier: nil,
                        customIdentifier: self.objectId,
                        isMe: User.current()?.objectId == self.objectId,
                        suggestionType: .instantMessageAddress)
    }

    private var inImage: INImage? {
        do {
            if let data = try? self.smallImage?.getData() {
                return INImage(imageData: data)
            } else {
                return nil
            }
        }
    }

    private var inHandle: INPersonHandle {
        return INPersonHandle(value: self.phoneNumber, type: .phoneNumber, label: .iPhone)
    }

    private var nameComponents: PersonNameComponents? {
        var components = PersonNameComponents()
        components.givenName = self.givenName
        components.familyName = self.familyName
        return components
    }

    private var inSuggestionType: INPersonSuggestionType {
        return INPersonSuggestionType.instantMessageAddress
    }
}

extension UIImage {
    func rotate(radians: CGFloat) -> UIImage {
        let rotatedSize = CGRect(origin: .zero, size: size)
            .applying(CGAffineTransform(rotationAngle: CGFloat(radians)))
            .integral.size
        UIGraphicsBeginImageContext(rotatedSize)
        if let context = UIGraphicsGetCurrentContext() {
            let origin = CGPoint(x: rotatedSize.width / 2.0,
                                 y: rotatedSize.height / 2.0)
            context.translateBy(x: origin.x, y: origin.y)
            context.rotate(by: radians)
            draw(in: CGRect(x: -origin.y, y: -origin.x,
                            width: size.width, height: size.height))
            let rotatedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            return rotatedImage ?? self
        }

        return self
    }
}
