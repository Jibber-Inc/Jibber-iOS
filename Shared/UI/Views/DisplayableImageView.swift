//
//  DisplayableImageView.swift
//  Benji
//
//  Created by Benji Dodgson on 2/4/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore
import UIKit
import Combine
import Lottie

/// A private struct that represents a snapshot of an ImageDisplayable's state.
/// This can be used to determine if the current image needs to be updated when a new displayable is assigned.
private struct ImageDisplayableState: ImageDisplayable {
    var image: UIImage?
    var url: URL?
    var imageFileObject: PFFileObject?

    var isNil: Bool {
        return self.image.isNil
        && self.url.isNil
        && self.imageFileObject.isNil
    }

    /// Returns true if the two states will result in the same image being displayed.
    func isEqual(to otherState: ImageDisplayableState) -> Bool {
        return self.image == otherState.image
        && self.url == otherState.url
        && self.imageFileObject?.url == otherState.imageFileObject?.url
    }
}

class DisplayableImageView: BaseView {

    enum State {
        case initial
        case loading
        case error
        case success
    }

    @Published var state: State = .initial

    private(set) var imageView = UIImageView()
    let blurView = BlurView()
    private let animationView = AnimationView()

    /// The current task that is asynchronously setting the displayable.
    private var displayableTask: Task<Void, Never>?
    
    var thumbnailSizeMultiplier: CGFloat = 3

    private var displayableState: ImageDisplayableState = ImageDisplayableState() {
        didSet {
            // Don't load the displayable again if it hasn't changed.
            if self.displayableState.isEqual(to: oldValue) {
                return
            }

            self.displayableTask?.cancel()

            // A nil displayable can be applied immediately without creating a task.
            guard !self.displayableState.isNil else {
                self.imageView.image = nil
                self.state = .initial
                return
            }

            let displayableStateRef = self.displayableState

            self.displayableTask = Task { [weak self] in
                guard let self else { return }
                await self.updateImageView(with: displayableStateRef)
            }
        }
    }

    var displayable: ImageDisplayable? {
        didSet {
            self.displayableState = ImageDisplayableState(image: self.displayable?.image,
                                                          url: self.displayable?.url,
                                                          imageFileObject: self.displayable?.imageFileObject)
        }
    }

    /// A custom configured url session for retrieving displayables with a url and caching the data.
    private lazy var urlSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: configuration)
    }()

    // MARK: - Life cycle

    override func initializeSubviews() {
        super.initializeSubviews()

        self.addSubview(self.imageView)
        self.imageView.contentMode = .scaleAspectFill

        self.addSubview(self.blurView)
        self.blurView.contentView.addSubview(self.animationView)

        self.$state.mainSink { [weak self] state in
            guard let self else { return }

            switch state {
            case .initial:
                self.animationView.reset()
                self.animationView.stop()
                self.blurView.showBlur(true)
            case .loading:
                UIView.animate(withDuration: Theme.animationDurationFast) {
                    self.blurView.showBlur(true)
                }
                if self.animationView.isAnimationPlaying {
                    self.animationView.stop()
                }
            case .error:
                if self.animationView.isAnimationPlaying {
                    self.animationView.stop()
                }
                self.animationView.load(animation: .error)
                self.animationView.loopMode = .loop
                self.animationView.play()
                UIView.animate(withDuration: Theme.animationDurationFast) {
                    self.blurView.showBlur(true)
                }
            case .success:
                if self.animationView.isAnimationPlaying {
                    self.animationView.stop()
                }
                self.animationView.reset()

                UIView.animate(withDuration: Theme.animationDurationFast) {
                    self.blurView.showBlur(false)
                }
            }
        }.store(in: &self.cancellables)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        self.imageView.expandToSuperviewSize()
        self.imageView.layer.cornerRadius = Theme.innerCornerRadius
        self.imageView.layer.masksToBounds = true
        self.imageView.clipsToBounds = true

        self.blurView.expandToSuperviewSize()
        self.blurView.layer.cornerRadius = Theme.innerCornerRadius
        self.blurView.layer.masksToBounds = true
        self.imageView.clipsToBounds = true 

        self.animationView.squaredSize = 20
        self.animationView.centerOnXAndY()
    }

    // MARK: - Image Retrieval/Setting

    private func updateImageView(with displayable: ImageDisplayable?) async {
        if let image = displayable?.image {
            await self.set(image: image, state: .success)
        } else if let imageFileObject = displayable?.imageFileObject {
            await self.downloadAndSetImage(for: imageFileObject)
        } else if let url = displayable?.url  {
            await self.downloadAndSetImage(for: url)
        } else {
            await self.set(image: nil, state: .initial)
        }
    }

    private func downloadAndSetImage(for file: PFFileObject) async {
        do {
            guard !Task.isCancelled else { return }

            if !file.isDataAvailable {
                self.state = .loading
            }

            let data = try await file.retrieveDataInBackground { _ in }
            
            guard !Task.isCancelled else { return }

            let image = UIImage(data: data)
            
            await self.set(image: image, state: image.exists ? .success : .error)
        } catch {
            guard !Task.isCancelled else { return }

            await self.set(image: nil, state: .error)
        }
    }

    private func downloadAndSetImage(for url: URL) async {
        do {
            guard !Task.isCancelled else { return }

            self.state = .loading

            let data: Data = try await self.urlSession.dataTask(with: url).0

            guard !Task.isCancelled else { return }
                        
            // Contruct the image from the returned data
            guard let image = UIImage(data: data) else { return }
            
            await self.set(image: image, state: .success)
        } catch {
            guard !Task.isCancelled else { return }

            await self.set(image: nil, state: .error)
        }
    }

    @MainActor
    func set(image: UIImage?, state: State) async {
        self.state = state

        let size = CGSize(width: self.size.width * self.thumbnailSizeMultiplier,
                          height: self.height * self.thumbnailSizeMultiplier)
        
        if let preparedImage = await image?.byPreparingThumbnail(ofSize: size) {
            self.imageView.image = preparedImage
        } else {
            self.imageView.image = image
        }
        
        self.setNeedsLayout()
    }
}
