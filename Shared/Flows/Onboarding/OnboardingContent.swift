//
//  OnboardingContent.swift
//  Benji
//
//  Created by Benji Dodgson on 1/14/20.
//  Copyright © 2020 Benjamin Dodgson. All rights reserved.
//

import Foundation
import UIKit
import Localization
import ParseCore

enum OnboardingContent: Switchable {

    case welcome(WelcomeViewController)
    case invitation(WelcomeViewController)
    case momentInvitation(WelcomeViewController)
    case phone(PhoneViewController)
    case code(CodeViewController)
    case name(NameViewController)
    case photo(ProfilePhotoCaptureViewController)

    var viewController: UIViewController & Sizeable {
        switch self {
        case .welcome(let vc), .invitation(let vc), .momentInvitation(let vc):
            return vc
        case .phone(let vc):
            return vc
        case .code(let vc):
            return vc
        case .name(let vc):
            return vc
        case .photo(let vc):
            return vc
        }
    }

    @MainActor
    func getDescription(with user: User?) -> Localized? {
        switch self {
        case .welcome(_):
            return LocalizedString(id: "",
                                   arguments: [],
                                   default: "Welcome! Jibber is an invite only messaging experience redesigned to encourage empathy, establish privacy and promote community ownership/participation. If you don't have an invite, you can join the waitlist below.")
        case .invitation(_):
            if let user {
                return LocalizedString(
                    id: "",
                    arguments: [],
                    default: "\(user.givenName.capitalized) invited you to connect on Jibber. Accept to verify your number and finish setting up your account."
                )
            }
            return LocalizedString(
                id: "",
                arguments: [],
                default: "You've been invited to connect on Jibber."
            )
        case .momentInvitation(_):
            if let user {
                return LocalizedString(
                    id: "",
                    arguments: [],
                    default: "Connect with \(user.givenName.capitalized) to continue. You can return to the Moment without making any changes by choosing Not Now."
                )
            }
            return LocalizedString(
                id: "",
                arguments: [],
                default: "Connect to continue, or return to the Moment without making any changes."
            )
        case .phone(_):
            if let user = user, user.objectId != PFConfig.current().adminUserId {
                return LocalizedString(id: "",
                                       arguments: [],
                                       default: "Confirm your number, to claim your spot")
            } else {
                return LocalizedString(id: "",
                                       arguments: [],
                                       default: "Confirm your number")
            }
        case .code(_):
            return LocalizedString(id: "",
                                   arguments: [],
                                   default: "Enter the code Jibber texted you")
        case .name(let vc):
            switch vc.state {
            case .noName:
                return LocalizedString(id: "",
                                       arguments: [],
                                       default: "Jibber uses real names. What's yours?")
            case .givenNameValid:
                return LocalizedString(id: "",
                                       arguments: [],
                                       default: "Now add your last name.")
            case .validFullName:
                return LocalizedString(id: "",
                                       arguments: [],
                                       default: "\(vc.textEntry.textField.text!) is it? Tap next to continue.")
            }
            
        case .photo(_):
            return nil
        }
    }
}
