//
//  Statusable.swift
//  Benji
//
//  Created by Benji Dodgson on 12/3/20.
//  Copyright © 2020 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Lottie
import Combine
import Localization

protocol Statusable: AnyObject {
    func handleEvent(status: EventStatus) async
}

private var currentEventStatusHandlerKey: UInt8 = 0
extension Statusable where Self: NSObject {
    var currentEventStatus: EventStatus? {
        get {
            return self.getAssociatedObject(&currentEventStatusHandlerKey)
        }
        set {
            self.setAssociatedObject(key: &currentEventStatusHandlerKey, value: newValue)
        }
    }
}

/// A type erased wrapper for a Statusable with a weak reference.
/// Can be used to make a collection of weak references to Statusables.
struct WeakAnyStatusable {
    weak var value: Statusable?

    init(_ value: Statusable) {
        self.value = value
    }
}

enum EventStatus: Equatable {

    case initial // Used for empty/default states (ie: an empty text field)
    case valid // Used for temporary validation (ie: handling a valid phone number)
    case invalid // User for temporary validation (ie: invalid email address)
    case loading
    case cancelled
    case error(String) // Temporary state used to communicate an error occured (ie: api returns an error)
    case saved // Temporary state used to communicate an object was saved successfully
    case complete // A permenantent state showing an object is valid and has been saved
    case custom(String)

    var animation: LottieAnimation? {
        let value = String()

        switch self {
        case .initial:
            break
        case .valid:
            break
        case .invalid:
            break
        case .loading:
            break
        case .error(_):
            break
        case .saved:
            break
        case .complete:
            break
        case .custom(_):
            break
        case .cancelled:
            break
        }

        if value.isEmpty {
            return nil
        }

        return LottieAnimation.named(value,
                                     bundle: Bundle.main,
                                     subdirectory: nil,
                                     animationCache: DefaultAnimationCache.sharedCache)
    }

    var randomSavedText: Localized {
        return ["Success! 🎉", "Perfect! 🏆", "Saved! 🤗", "Done! 😁", "Nice Work! 👍"].randomElement()!
    }
}
