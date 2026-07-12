//
//  SendableType.swift
//  Jibber
//
//  Created by Benji Dodgson on 1/23/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Intents

/// A mutable draft that can be translated into an outgoing message.
///
/// This deliberately avoids the name `Sendable`, which is reserved for
/// Swift's concurrency-safety protocol.
@MainActor
protocol MessageSendable: AnyObject {
    var kind: MessageKind { get set }
    var deliveryType: MessageDeliveryType { get set }
    var expression: Expression? { get set }
    var previousMessage: Messageable? { get set }
    var isSendable: Bool { get }
}

@MainActor
final class SendableObject: MessageSendable {

    var kind: MessageKind
    var deliveryType: MessageDeliveryType
    var previousMessage: Messageable?
    var expression: Expression?

    var isSendable: Bool {
        return self.kind.isSendable || self.expression.exists
    }

    init(kind: MessageKind,
         deliveryType: MessageDeliveryType,
         expression: Expression?,
         previousMessage: Messageable? = nil) {

        self.kind = kind
        self.deliveryType = deliveryType
        self.expression = expression
        self.previousMessage = previousMessage
    }
}
