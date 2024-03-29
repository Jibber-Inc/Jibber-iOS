//
//  MessageKind.swift
//  Benji
//
//  Created by Benji Dodgson on 7/3/20.
//  Copyright © 2020 Benjamin Dodgson. All rights reserved.
//

import Foundation
import class CoreLocation.CLLocation
import UIKit

/// An enum representing the kind of message and its underlying kind.
enum MessageKind {

    /// A standard text message.
    case text(String)

    /// A message with attributed text.
    case attributedText(NSAttributedString)

    /// A photo message.
    case photo(photo: MediaItem, body: String)

    /// A video message.
    case video(video: MediaItem, body: String)
    
    // A message with multiple media items.
    case media(items: [MediaItem], body: String)

    /// A location message.
    case location(LocationItem)

    /// An emoji message.
    case emoji(String)

    /// An audio message.
    case audio(AudioItem)

    /// A contact message.
    case contact(ContactItem)

    /// A single url based link without any other content.
    case link(url: URL, stringURL: String)

    var isSendable: Bool {
        switch self {
        case .text(let body):
            return !body.isEmpty
        default:
            return true
        }
    }

    var text: String {
        switch self {
        case .text(let body):
            return body
        case .attributedText(let body):
            return body.string
        case .photo(_, body: let body):
            return body
        case .video(_, body: let body):
            return body
        case .emoji(let emoji):
            return emoji
        case .link(_, let stringURL):
            return stringURL
        case .media(_, let body):
            return body
        default:
            return String()
        }
    }
}

extension MessageKind: Equatable {
    
    static func == (lhs: MessageKind, rhs: MessageKind) -> Bool {
        switch (lhs, rhs) {
        case (.text(let lhsText), .text(let rhsText)):
            return lhsText == rhsText
        case (.attributedText(let lhsText), .attributedText(let rhsText)):
            return lhsText == rhsText
        case (.photo(let lhsMedia, let lhsText), .photo(let rhsMedia, let rhsText)):
            return lhsMedia == rhsMedia && lhsText == rhsText
        case (.video(let lhsMedia, let lhsText), .video(let rhsMedia, let rhsText)):
            return lhsMedia == rhsMedia && lhsText == rhsText
        case (.location(let lhsLocation), .location(let rhsLocation)):
            return lhsLocation == rhsLocation
        case (.emoji(let lhsEmoji), .emoji(let rhsEmoji)):
            return lhsEmoji == rhsEmoji
        case (.audio(let lhsAudio), .audio(let rhsAudio)):
            return lhsAudio == rhsAudio
        case (.contact(let lhsContact), .contact(let rhsContact)):
            return lhsContact == rhsContact
        case (.link(let lhsURL, let lhsStringURL), .link(let rhsURL, let rhsStringURL)):
            return lhsURL == rhsURL && lhsStringURL == rhsStringURL
        case (.media(let lhsMedia, _), .media(let rhsMedia, _)):
            return lhsMedia.first?.url == rhsMedia.first?.url
        default:
            return false
        }
    }
}

// MARK: - Convenience Variables

extension MessageKind {

    var hasText: Bool {
        return !self.text.isEmpty
    }
    
    var hasVideo: Bool {
        switch self {
        case .video:
            return true
        case .media(items: let items, _):
            guard let first = items.first else { return false }
            return first.type == .video
        default:
            return false
        }
    }

    var hasImage: Bool {
        switch self {
        case .photo, .video, .media:
            return true
        default:
            return false
        }
    }

    var isLink: Bool {
        switch self {
        case .link:
            return true
        default:
            return false
        }
    }
}


enum MediaType: String {
    case photo = "image/jpeg"
    case video
}

struct EmptyMediaItem: MediaItem {

    var mediaType: MediaType

    var url: URL? {
        return nil
    }
    
    var previewURL: URL?

    var image: UIImage? {
        return nil
    }

    var size: CGSize {
        return .zero
    }

    var fileName: String {
        return String()
    }

    var type: MediaType{
        return self.mediaType
    }

    var data: Data? {
        return nil
    }
}

/// A protocol used to represent the data for a media message.
protocol MediaItem: ImageDisplayable {

    /// The url where the media is located.
    var url: URL? { get }
    
    var previewURL: URL? { get }

    /// The image.
    var image: UIImage? { get }

    /// The size of the media item.
    var size: CGSize { get }

    var fileName: String { get }

    var type: MediaType { get }

    var data: Data? { get }
}

private func ==(lhs: MediaItem, rhs: MediaItem) -> Bool {
    return lhs.url == rhs.url
    && lhs.previewURL == rhs.previewURL
    && lhs.image == rhs.image
    && lhs.size == rhs.size
    && lhs.fileName == rhs.fileName
    && lhs.type == rhs.type
    && lhs.data == rhs.data
}

/// A protocol used to represent the data for a location message.
protocol LocationItem {

    /// The location.
    var location: CLLocation { get }

    /// The size of the location item.
    var size: CGSize { get }
}

private func ==(lhs: LocationItem, rhs: LocationItem) -> Bool {
    return lhs.location == rhs.location &&
    lhs.size == rhs.size
}

/// A protocol used to represent the data for an audio message.
protocol AudioItem {

    /// The url where the audio file is located.
    var url: URL { get }

    /// The audio file duration in seconds.
    var duration: Float { get }

    /// The size of the audio item.
    var size: CGSize { get }
}

private func ==(lhs: AudioItem, rhs: AudioItem) -> Bool {
    return lhs.url == rhs.url &&
    lhs.duration == rhs.duration &&
    lhs.size == rhs.size
}


/// A protocol used to represent the data for a contact message.
protocol ContactItem {

    /// contact displayed name
    var displayName: String { get }

    /// initials from contact first and last name
    var initials: String { get }

    /// contact phone numbers
    var phoneNumbers: [String] { get }

    /// contact emails
    var emails: [String] { get }
}

private func ==(lhs: ContactItem, rhs: ContactItem) -> Bool {
    return lhs.displayName == rhs.displayName &&
    lhs.initials == rhs.initials &&
    lhs.phoneNumbers == rhs.phoneNumbers &&
    lhs.emails == rhs.emails
}
