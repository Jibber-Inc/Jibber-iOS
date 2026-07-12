//
//  ParseMessagingAttachmentUploadCache.swift
//  MessagingPersistence
//

import Foundation
import ParseSwift

/// Persists completed ParseFile uploads before the message write. A retry after
/// process termination therefore reuses uploaded files instead of creating
/// duplicates or losing its place in a multi-attachment send.
public protocol ParseMessagingAttachmentUploadCaching: AnyObject {
    func uploadedFile(
        clientMessageID: String,
        attachmentKey: String
    ) throws -> ParseFile?

    func storeUploadedFile(
        _ file: ParseFile,
        clientMessageID: String,
        attachmentKey: String
    ) throws

    func removeUploadedFiles(clientMessageID: String) throws
}

