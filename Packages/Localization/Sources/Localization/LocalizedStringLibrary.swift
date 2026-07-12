//
//  File.swift
//  
//
//  Created by Benji Dodgson on 12/11/21.
//

import Foundation

public func localized(_ localized: Localized) -> String {
    return LocalizedStringLibrary.shared.getLocalizedString(for: localized)
}

public final class LocalizedStringLibrary: @unchecked Sendable {

    public static let shared = LocalizedStringLibrary()

    private let lock = NSLock()
    private var storedDidLocalizeStringWithID: (@Sendable (String) -> Void)?
    private var storedLibrary: [String: String]

    /// Used to access IDs for strings that have just been localized.
    public var didLocalizeStringWithID: (@Sendable (String) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedDidLocalizeStringWithID
        }
        set {
            lock.lock()
            storedDidLocalizeStringWithID = newValue
            lock.unlock()
        }
    }

    public var library: [String: String] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedLibrary
        }
        set {
            lock.lock()
            storedLibrary = newValue
            addToPlist(dictionary: newValue)
            lock.unlock()
        }
    }

    private init() {
        let documentDirectory = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] as String
        let path = documentDirectory.appending("/localization.plist")
        if let dict = NSDictionary(contentsOfFile: path),
            let library = dict as? Dictionary<String, String> {
            self.storedLibrary = library
        } else {
            self.storedLibrary = [:]
        }
    }

    internal func getLocalizedString(for localized: Localized) -> String {
        lock.lock()
        let localizedString = storedLibrary[localized.identifier]
            ?? String(optional: localized.defaultString)
        let callback = storedDidLocalizeStringWithID
        lock.unlock()

        let localizedArguments = localized.arguments.map { (argument) -> String in
            return LocalizedStringLibrary.shared.getLocalizedString(for: argument)
        }

        let mutableString = NSMutableAttributedString(string: localizedString)
        mutableString.replace(arguments: localizedArguments)

        callback?(localized.identifier)
        return mutableString.string
    }

    private func addToPlist(dictionary: Dictionary<String, String>) {
        guard let documentDirectory = NSSearchPathForDirectoriesInDomains(.documentDirectory,
                                                                          .userDomainMask, true)
            .first else { return }
        let path = documentDirectory.appending("/localization.plist")
        let plistContent = NSDictionary(dictionary: dictionary)
        plistContent.write(toFile: path, atomically: true)
    }
}
