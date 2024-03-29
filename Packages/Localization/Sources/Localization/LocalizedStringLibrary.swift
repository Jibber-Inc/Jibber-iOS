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

public struct LocalizedStringLibrary {

    public static var shared = LocalizedStringLibrary()
    
    /// Used to access IDs for strings that have just been localized
    public var didLocalizeStringWithID: ((String)->())?

    public var library: Dictionary<String, String> {
        didSet {
            self.addToPlist(dictionary: self.library)
        }
    }

    init() {
        let documentDirectory = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] as String
        let path = documentDirectory.appending("/localization.plist")
        if let dict = NSDictionary(contentsOfFile: path),
            let library = dict as? Dictionary<String, String> {
            self.library = library
        } else {
            self.library = [:]
        }
    }

    internal func getLocalizedString(for localized: Localized) -> String {
        var localizedString: String
        if let string = self.library[localized.identifier] {
            localizedString = string
        } else {
            localizedString = String(optional: localized.defaultString)
        }

        let localizedArguments = localized.arguments.map { (argument) -> String in
            return LocalizedStringLibrary.shared.getLocalizedString(for: argument)
        }

        let mutableString = NSMutableAttributedString(string: localizedString)
        mutableString.replace(arguments: localizedArguments)

        self.didLocalizeStringWithID?(localized.identifier)
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
