//
//  Expression.swift
//  Jibber
//
//  Created by Martin Young on 4/28/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore

struct ExpressionInfo: Hashable {
    var authorId: String
    var expressionId: String 
}

enum ExpressionKey: String {
    case author
    case file
    case emotionCounts
    case emojiString
}

final class Expression: PFObject, PFSubclassing, @unchecked Sendable {

    static func parseClassName() -> String {
        return String(describing: self)
    }

    var author: User? {
        get { self.getObject(for: .author) }
        set { self.setObject(for: .author, with: newValue) }
    }
        
    var file: PFFileObject? {
        get { self.getObject(for: .file) }
        set { self.setObject(for: .file, with: newValue) }
    }

    var emotionCounts: [Emotion: Int] {
        get {
            guard let dict: [String: Int] = self.getObject(for: .emotionCounts) else { return [:] }
            var counts: [Emotion: Int] = [:]
            dict.keys.forEach { key in
                if let emotion = Emotion(rawValue: key), let value = dict[key] {
                    counts[emotion] = value
                }
            }
            return counts
        }
        
        set {
            var counts: [String: Int] = [:]
            newValue.keys.forEach { emotion in
                counts[emotion.rawValue] = newValue[emotion]
            }
            
            self.setObject(for: .emotionCounts, with: counts)
        }
    }
    
    var emotions: [Emotion] {
        return Array(self.emotionCounts.keys)
    }

    var emojiString: String? {
        get { self.getObject(for: .emojiString) }
        set { self.setObject(for: .emojiString, with: newValue) }
    }
    
    var info: ExpressionInfo? {
        guard let authorId = self.author?.objectId,
                let objectId = self.objectId else { return nil }
        return ExpressionInfo(authorId: authorId, expressionId: objectId)
    }
}

extension Expression: Objectable {
    typealias KeyType = ExpressionKey

    func getObject<Type>(for key: ExpressionKey) -> Type? {
        return self.object(forKey: key.rawValue) as? Type
    }

    func setObject<Type>(for key: ExpressionKey, with newValue: Type) {
        self.setObject(newValue, forKey: key.rawValue)
    }

    func getRelationalObject<PFRelation>(for key: ExpressionKey) -> PFRelation? {
        return self.relation(forKey: key.rawValue) as? PFRelation
    }
}

extension Expression: ImageDisplayable {

    var image: UIImage? {
        return nil
    }
    
    var imageFileObject: PFFileObject? {
        return self.file 
    }
}
