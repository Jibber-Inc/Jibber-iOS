//
//  File.swift
//  
//
//  Created by Benji Dodgson on 12/11/21.
//

import Foundation

public protocol Localized: Sendable {
    var identifier: String { get }
    var arguments: [Localized] { get }
    var defaultString: String? { get }
    var isEmpty: Bool { get }
}

public func ==(lhs: Localized, rhs: Localized) -> Bool {
    guard type(of: lhs) == type(of: rhs) else { return false }
    return lhs.identifier == rhs.identifier
}
