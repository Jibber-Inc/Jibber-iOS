//
//  MediaManager.swift
//  Jibber
//
//  Created by Benji Dodgson on 1/21/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import UIKit
import Photos

/// One-shot Photos callback payload transferred to the requesting task.
struct ImageRequestResult: @unchecked Sendable {
    let data: Data?
    let type: String?
    let orientation: CGImagePropertyOrientation
    let info: [AnyHashable: Any]?
}

private struct RequestedImageTransfer: @unchecked Sendable {
    let image: UIImage
    let info: [AnyHashable: Any]?
}

private struct VideoAssetTransfer: @unchecked Sendable {
    let asset: AVAsset?
}

/// `UIImage` instances received from the picker are treated as immutable and
/// transferred once to the media worker for encoding.
private struct ImmutableImageTransfer: @unchecked Sendable {
    let image: UIImage
}

private actor AttachmentMediaWorker {

    func encode(_ transfer: consuming ImmutableImageTransfer) -> (full: Data, preview: Data)? {
        guard let full = transfer.image.jpegData(compressionQuality: 1.0),
              let preview = transfer.image.jpegData(compressionQuality: 0.5) else {
            return nil
        }
        return (full, preview)
    }

    func loadMovie(at url: URL) throws -> Data {
        try Data(contentsOf: url, options: .mappedIfSafe)
    }

    func write(_ data: Data, fileExtension: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString + ".\(fileExtension)")
        try data.write(to: url, options: .atomic)
        return url
    }

    func videoSnapshotData(from url: URL) async throws -> Data {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let timestamp = CMTime(seconds: 0.5, preferredTimescale: 60)
        let (imageRef, _) = try await generator.image(at: timestamp)
        return UIImage(cgImage: imageRef).jpegData(compressionQuality: 0.5) ?? Data()
    }
}


class PhotoRequestOptions: PHImageRequestOptions {
    
    override init() {
        super.init()
        self.deliveryMode = .highQualityFormat
        self.resizeMode = .exact
        self.isSynchronous = false
        self.isNetworkAccessAllowed = true
    }
}

@MainActor
final class AttachmentsManager {
    
    static let shared = AttachmentsManager()
    private let manager = PHImageManager()
    private let mediaWorker = AttachmentMediaWorker()
    
    private(set) var attachments: [Attachment] = []
    
    var isAuthorized: Bool {
        let status = PHPhotoLibrary.authorizationStatus()
        switch (status) {
        case .authorized, .limited:
            return true
        case .notDetermined:
            return false
        default:
            return false
        }
    }
    
    func requestAttachments() async {
        if !self.isAuthorized {
            guard (try? await self.requestAuthorization()) != nil else { return }
        }
        self.fetchAttachments()
    }
    
    func getMessageKind(for info: [UIImagePickerController.InfoKey : Any],
                        body: String) async -> MessageKind? {

        guard let mediaType = info[.mediaType] as? String else { return nil }

        switch mediaType {
        case "public.image":
            guard let image = info[.editedImage] as? UIImage,
                  let encoded = await self.mediaWorker.encode(ImmutableImageTransfer(image: image)) else {
                return nil
            }

            let data = encoded.full
            let previewData = encoded.preview
            let url = try? await self.mediaWorker.write(data, fileExtension: "")
            let previewURL = try? await self.mediaWorker.write(previewData, fileExtension: "preview")
            let item = PhotoAttachment(url: url,
                                       previewURL: previewURL,
                                       data: data,
                                       info: info)
            return .photo(photo: item, body: body)

        case "public.movie":
            guard let mediaURL = info[.mediaURL] as? URL,
                  let videoData = try? await self.mediaWorker.loadMovie(at: mediaURL),
                  let previewData = try? await self.mediaWorker.videoSnapshotData(from: mediaURL) else {
                return nil
            }

            let url = try? await self.mediaWorker.write(videoData, fileExtension: "mov")
            let previewURL = try? await self.mediaWorker.write(previewData, fileExtension: "")
            let item = VideoAttachment(url: url,
                                       previewURL: previewURL,
                                       previewData: previewData,
                                       data: videoData,
                                       info: info)
            return .video(video: item, body: body)

        default:
            return nil
        }
    }

    func getMessageKind(for attachments: [Attachment], body: String) async -> MessageKind? {
        if attachments.count == 1, let first = attachments.first {
            guard let item = await self.getMediaItem(for: first) else { return nil }

            switch first.asset.mediaType {
            case .image:
                return .photo(photo: item, body: body)
            case .video:
                return .video(video: item, body: body)
            case .audio, .unknown:
                return nil
            @unknown default:
                return nil
            }
        }

        var items: [MediaItem] = []
        for attachment in attachments {
            let item = await self.getMediaItem(for: attachment) ?? EmptyMediaItem(mediaType: .photo)
            items.append(item)
        }
        return .media(items: items, body: body)
    }
    
    private func getMediaItem(for attachment: Attachment) async -> MediaItem? {
        switch attachment.asset.mediaType {
        case .image:
            let result = await self.manager.requestImageData(for: attachment.asset, options: PhotoRequestOptions())
            
            let url = try? await self.getAssetURL(for: attachment.asset)
            let item = PhotoAttachment(url: url,
                                       previewURL: nil,
                                       data: result.data,
                                       info: result.info)
            return item
        case .video:
            if let url = try? await self.getAssetURL(for: attachment.asset),
               let previewData = try? await self.mediaWorker.videoSnapshotData(from: url) {
                
                let previewURL = try? await self.mediaWorker.write(previewData, fileExtension: "")
                let item = VideoAttachment(url: url,
                                           previewURL: previewURL,
                                           previewData: previewData,
                                           data: nil,
                                           info: attachment.attributes)
                return item
            } else {
                return nil
            }
            
        case .audio:
            return nil
        default:
            return nil
        }
    }
    
    private func getAssetURL(for asset: PHAsset) async throws -> URL {
        return try await withCheckedThrowingContinuation({ continuation in
            if asset.mediaType == .image {
                let options: PHContentEditingInputRequestOptions = PHContentEditingInputRequestOptions()
                options.canHandleAdjustmentData = {(adjustmeta: PHAdjustmentData) -> Bool in
                    // Returns the URL with the edited asset
                    return false
                }
                asset.requestContentEditingInput(with: options, completionHandler: { (contentEditingInput, info) in
                    if let input = contentEditingInput, let url = input.fullSizeImageURL {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: ClientError.message(detail: "No URL for image"))
                    }
                })
            } else if asset.mediaType == .video {
                let options: PHVideoRequestOptions = PHVideoRequestOptions()
                options.version = .original
                self.manager.requestAVAsset(forVideo: asset, options: options, resultHandler: { (asset, audioMix, info) in
                    if let urlAsset = asset as? AVURLAsset {
                        let localVideoUrl = urlAsset.url
                        continuation.resume(returning: localVideoUrl)
                    } else {
                        continuation.resume(throwing: ClientError.message(detail: "No URL for Video"))
                    }
                })
            }
        })
    }
    
    func getImage(for attachment: Attachment,
                  contentMode: PHImageContentMode = .aspectFill,
                  size: CGSize) async throws -> (UIImage, [AnyHashable: Any]?) {
        
        let transfer: RequestedImageTransfer = try await withCheckedThrowingContinuation { continuation in
            let options = PhotoRequestOptions()
            
            self.manager.requestImage(for: attachment.asset,
                                         targetSize: size,
                                         contentMode: contentMode,
                                         options: options) { (image, info) in
                if let img = image {
                    continuation.resume(returning: RequestedImageTransfer(image: img, info: info))
                } else {
                    continuation.resume(throwing: ClientError.message(detail: "Failed to retrieve image"))
                }
            }
        }
        
        return (transfer.image, transfer.info)
    }
    
    func getVideoAsset(for attachment: Attachment) async -> AVAsset? {
        let transfer: VideoAssetTransfer = await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.deliveryMode = .fastFormat
            self.manager.requestAVAsset(forVideo: attachment.asset, options: options) { asset, audioMix, info in
                continuation.resume(returning: VideoAssetTransfer(asset: asset))
            }
        }
        return transfer.asset
    }
    
    private func requestAuthorization() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.requestAuthorization({ (status) in
                switch status {
                case .authorized, .limited:
                    continuation.resume(returning: ())
                default:
                    continuation.resume(throwing: ClientError.message(detail: "Failed to authorize"))
                }
            })
        }
    }
    
    private func fetchAttachments() {
        let options = PHFetchOptions()
        options.fetchLimit = 20
        let videoPredicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
        let imagePredicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [videoPredicate, imagePredicate])
        options.predicate = predicate
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: options)
        
        var attachments: [Attachment] = []
        
        var assets: [PHAsset] = []
        
        for index in 0...result.count - 1 {
            let asset = result.object(at: index)
            assets.append(asset)
            let attachment = Attachment(asset: asset)
            attachments.append(attachment)
        }
        
        self.attachments = attachments
    }
}

extension PHImageManager {
    
    func requestImageData(for asset: PHAsset, options: PHImageRequestOptions?) async -> ImageRequestResult {
        return await withCheckedContinuation({ continuation in
            self.requestImageDataAndOrientation(for: asset, options: options) { data, type, orientation, info in
                continuation.resume(returning: ImageRequestResult(data: data, type: type, orientation: orientation, info: info))
            }
        })
    }
}
