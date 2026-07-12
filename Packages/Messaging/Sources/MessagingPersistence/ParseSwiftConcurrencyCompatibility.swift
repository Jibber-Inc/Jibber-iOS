//
//  ParseSwiftConcurrencyCompatibility.swift
//  MessagingPersistence
//

import ParseSwift

// ParseSwift 4.14.2 predates Swift 6 Sendable annotations. These types are
// value builders: each mutation returns a new value, and this module transfers
// each instance into a single async request without concurrent reuse.
extension Query: @retroactive @unchecked Sendable {}
extension ParseOperation: @retroactive @unchecked Sendable {}
extension ParseFile: @retroactive @unchecked Sendable {}
extension Pointer: @retroactive @unchecked Sendable {}
