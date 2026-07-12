//
//  UIImage+Extensions.swift
//  Benji
//
//  Created by Benji Dodgson on 2/4/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore
import AVFoundation

extension UIImage {

    func grayscaleImage() -> UIImage? {
        let ciImage = CIImage(image: self)
        guard let grayscale = ciImage?.applyingFilter("CIColorControls",
                                                      parameters: [ kCIInputSaturationKey: 0.0 ]) else {
            return nil
        }
        
        return UIImage(ciImage: grayscale)
    }

    static func imageWithColor(color: UIColor, size: CGSize = CGSize(width: 1, height: 1)) -> UIImage {
        let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        UIGraphicsBeginImageContext(rect.size)
        let context = UIGraphicsGetCurrentContext()

        context!.setFillColor(color.cgColor)
        context!.fill(rect)

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return image!
    }

    /// Returns a new version of this image scaled proportionally so no side is greater than maxSideLength.
    func imageWith(maxSideLength: CGFloat) -> UIImage {
        let scale: CGFloat

        if self.size.width > self.size.height {
            scale = min(maxSideLength/self.size.width, 1)
        } else {
            scale = min(maxSideLength/self.size.height, 1)
        }

        let newSize = CGSize(width: scale * self.size.width,
                             height: scale * self.size.height)

        let image = UIGraphicsImageRenderer(size: newSize).image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }

        return image.withRenderingMode(self.renderingMode)
    }

    var heicData: Data? {
        return try? self.imageWith(maxSideLength: 200).heicData(compressionQuality: 0.6)
    }
}

extension UIImage: ImageDisplayable {

    var image: UIImage? {
        return self
    }
}


// MARK: - HEIC Compression

extension UIImage {

    enum HEICError: Error {
        case heicNotSupported
        case cgImageMissing
        case couldNotFinalize
    }

    // Taken from https://www.raywenderlich.com/4726843-heic-image-compression-for-ios
    func heicData(compressionQuality: CGFloat) throws -> Data {
        let data = NSMutableData()
        guard let imageDestination
                = CGImageDestinationCreateWithData(data, AVFileType.heic as CFString, 1, nil) else {
            throw HEICError.heicNotSupported
        }

        guard let cgImage = self.cgImage else { throw HEICError.cgImageMissing }

        let options: NSDictionary = [kCGImageDestinationLossyCompressionQuality : compressionQuality]

        CGImageDestinationAddImage(imageDestination, cgImage, options)
        guard CGImageDestinationFinalize(imageDestination) else {
            throw HEICError.couldNotFinalize
        }

        return data as Data
    }
}
