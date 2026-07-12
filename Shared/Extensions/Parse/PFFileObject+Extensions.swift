//
//  PFFileObject+Extensions.swift
//  Jibber
//
//  Created by Benji Dodgson on 5/1/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore
import Combine

extension PFFileObject: ImageDisplayable {

    var image: UIImage? {
        return nil
    }

    var imageFileObject: PFFileObject? {
        return self
    }
    
    func retrieveCachedPathURL() async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in

            self.getFilePathInBackground { path, error in
                if let e = error {
                    continuation.resume(throwing: e)
                } else if let path = path {
                    continuation.resume(returning: URL(fileURLWithPath: path))
                } else {
                    continuation.resume(throwing: ClientError.apiError(detail: "No error or data returned for file."))
                }
            }
        }
    }

    func retrieveDataInBackground(progressHandler: ((Int) -> Void)? = nil) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in

            self.getDataInBackground { data, error in
                if let e = error {
                    continuation.resume(throwing: e)
                } else if let data = data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: ClientError.apiError(detail: "No error or data returned for file."))
                }
            } progressBlock: { progress in
                progressHandler?(Int(progress))
            }
        }
    }
}

extension PFFileObject {
    
    func saveDataInBackground(progressHandler: ((Int) -> Void)? = nil) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            self.saveInBackground { success, error in
                if let e = error {
                    continuation.resume(throwing: e)
                } else if success {
                    continuation.resume(returning: ())
                }
            } progressBlock: { progress in
                progressHandler?(Int(progress))
            }
        }
    }
}
