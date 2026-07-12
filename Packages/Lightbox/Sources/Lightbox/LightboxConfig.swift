import UIKit
import AVKit
import AVFoundation
import Foundation

public class LightboxConfig {
  public typealias VideoHandler = @MainActor (UIViewController, URL) -> Void
  public typealias ImageLoader = @MainActor (UIImageView, URL, ((UIImage?) -> Void)?) -> Void
  public typealias LoadingIndicatorFactory = @MainActor () -> UIView

  private static let imageCache = NSCache<NSURL, UIImage>()
  private static let imageRequestIDs = NSMapTable<UIImageView, NSUUID>.weakToStrongObjects()

  @discardableResult
  static func beginImageRequest(for imageView: UIImageView) -> UUID {
    let requestID = UUID()
    imageRequestIDs.setObject(requestID as NSUUID, forKey: imageView)
    return requestID
  }

  static func isCurrentImageRequest(_ requestID: UUID, for imageView: UIImageView) -> Bool {
    imageRequestIDs.object(forKey: imageView) == requestID as NSUUID
  }

  /// Whether to show status bar while Lightbox is presented
  public static var hideStatusBar = true

  /// Provide a closure to handle selected video
  public static var handleVideo: VideoHandler = { from, videoURL in
    let videoController = AVPlayerViewController()
    videoController.player = AVPlayer(url: videoURL)

    from.present(videoController, animated: true) {
      videoController.player?.play()
    }
  }

  /// How to load image onto UIImageView
  public static var loadImage: ImageLoader = { imageView, imageURL, completion in
    let requestID = imageRequestIDs.object(forKey: imageView) as UUID?
      ?? beginImageRequest(for: imageView)

    if let image = imageCache.object(forKey: imageURL as NSURL) {
      guard isCurrentImageRequest(requestID, for: imageView) else { return }
      imageView.image = image
      completion?(image)
      return
    }

    Task { @MainActor [weak imageView] in
      do {
        let request = URLRequest(url: imageURL, cachePolicy: .returnCacheDataElseLoad)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let imageView,
              isCurrentImageRequest(requestID, for: imageView),
              (response as? HTTPURLResponse)?.statusCode ?? 200 < 400,
              let image = UIImage(data: data) else {
          completion?(nil)
          return
        }

        imageCache.setObject(image, forKey: imageURL as NSURL)
        imageView.image = image
        completion?(image)
      } catch {
        completion?(nil)
      }
    }
  }

  /// Indicator is used to show while image is being fetched
  public static var makeLoadingIndicator: LoadingIndicatorFactory = {
    return LoadingIndicator()
  }

  /// Number of images to preload.
  ///
  /// 0 - Preload all images (default).
  public static var preload = 0

  public struct PageIndicator {
    public static var enabled = true
    public static var separatorColor = UIColor(hex: "3D4757")

    public static var textAttributes: [NSAttributedString.Key: Any] = [
      .font: UIFont.systemFont(ofSize: 12),
      .foregroundColor: UIColor(hex: "899AB8"),
      .paragraphStyle: {
        var style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
      }()
    ]
  }

  public struct CloseButton {
    public static var enabled = true
    public static var size: CGSize?
    public static var text = NSLocalizedString("Close", comment: "")
    public static var image: UIImage?

    public static var textAttributes: [NSAttributedString.Key: Any] = [
      .font: UIFont.boldSystemFont(ofSize: 16),
      .foregroundColor: UIColor.white,
      .paragraphStyle: {
        var style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
      }()
    ]
  }

  public struct DeleteButton {
    public static var enabled = false
    public static var size: CGSize?
    public static var text = NSLocalizedString("Delete", comment: "")
    public static var image: UIImage?

    public static var textAttributes: [NSAttributedString.Key: Any] = [
      .font: UIFont.boldSystemFont(ofSize: 16),
      .foregroundColor: UIColor(hex: "FA2F5B"),
      .paragraphStyle: {
        var style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
      }()
    ]
  }

  public struct InfoLabel {
    public static var enabled = true
    public static var textColor = UIColor.white
    public static var ellipsisText = NSLocalizedString("Show more", comment: "")
    public static var ellipsisColor = UIColor(hex: "899AB9")

    public static var textAttributes: [NSAttributedString.Key: Any] = [
      .font: UIFont.systemFont(ofSize: 12),
      .foregroundColor: UIColor(hex: "DBDBDB")
    ]
  }

  public struct Zoom {
    public static var minimumScale: CGFloat = 1.0
    public static var maximumScale: CGFloat = 3.0
  }
}
