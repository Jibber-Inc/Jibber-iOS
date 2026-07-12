import UIKit

/// Used to load assets from Lightbox bundle
class AssetManager {

  static func image(_ named: String) -> UIImage? {
    UIImage(named: "Lightbox.bundle/\(named)", in: .module, compatibleWith: nil)
  }
}
