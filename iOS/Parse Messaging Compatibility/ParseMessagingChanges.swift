//
//  ParseMessagingChanges.swift
//  Jibber
//
//  Vendor-neutral controller change values used while Stream and Parse run
//  side-by-side.
//

import Foundation

enum ParseEntityChange<Value> {
    case create(Value)
    case update(Value)
    case remove(Value)

    func map<Transformed>(_ transform: (Value) -> Transformed) -> ParseEntityChange<Transformed> {
        switch self {
        case .create(let value):
            return .create(transform(value))
        case .update(let value):
            return .update(transform(value))
        case .remove(let value):
            return .remove(transform(value))
        }
    }
}

enum ParseListChange<Value> {
    case insert(Value, index: Int)
    case remove(Value, index: Int)
    case move(Value, fromIndex: Int, toIndex: Int)
    case update(Value, index: Int)
}

enum ParseListDiffer {

    /// Produces stable identity changes in the same index coordinate system as
    /// the old/new arrays. Consumers that apply changes manually should remove
    /// in descending order, then insert/move/update; diffable-data-source users
    /// can treat the values as an invalidation hint and rebuild their snapshot.
    static func changes<Value>(
        from oldValues: [Value],
        to newValues: [Value],
        identifiedBy identifier: (Value) -> String,
        valuesEqual: (Value, Value) -> Bool
    ) -> [ParseListChange<Value>] {
        let oldIndices = Dictionary(uniqueKeysWithValues: oldValues.enumerated().map {
            (identifier($0.element), $0.offset)
        })
        let newIndices = Dictionary(uniqueKeysWithValues: newValues.enumerated().map {
            (identifier($0.element), $0.offset)
        })

        var changes: [ParseListChange<Value>] = []

        for (index, value) in oldValues.enumerated().reversed()
        where newIndices[identifier(value)] == nil {
            changes.append(.remove(value, index: index))
        }

        for (index, value) in newValues.enumerated() {
            let id = identifier(value)
            guard let oldIndex = oldIndices[id] else {
                changes.append(.insert(value, index: index))
                continue
            }

            if oldIndex != index {
                changes.append(.move(value, fromIndex: oldIndex, toIndex: index))
            }
            if !valuesEqual(oldValues[oldIndex], value) {
                changes.append(.update(value, index: index))
            }
        }

        return changes
    }
}

