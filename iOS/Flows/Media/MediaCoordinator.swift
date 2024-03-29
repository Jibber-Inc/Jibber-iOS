//
//  ImageViewCoordinator.swift
//  Jibber
//
//  Created by Martin Young on 3/23/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Lightbox
import Lottie
import Coordinator

enum MediaResult {
    case reply(Messageable)
    case none
}

class MediaCoordinator: PresentableCoordinator<MediaResult> {
    
    let items: [MediaItem]
    let startingItem: MediaItem?

    let message: Messageable
    
    lazy var mediaViewController = MediaViewController(items: self.items,
                                                       startingItem: self.startingItem,
                                                       message: self.message)

    override func toPresentable() -> PresentableCoordinator<Void>.DismissableVC {
        return self.mediaViewController
    }

    init(items: [MediaItem],
         startingItem: MediaItem?,
         message: Messageable,
         router: CoordinatorRouter,
         deepLink: DeepLinkable?) {

        self.items = items
        self.startingItem = startingItem
        self.message = message

        super.init(router: router, deepLink: deepLink)
    }
    
    override func start() {
        super.start()
        
        self.mediaViewController.transitioningDelegate = self.router.modalTransitionRouter
        
        self.mediaViewController.messagePreview.didSelect { [unowned self] in
            self.finishFlow(with: .reply(self.message))
        }
        
        self.mediaViewController.didSelectShare = { [unowned self] in
            Task {
                
                var itemsToShare: [Any] = []
                let configuration = URLSessionConfiguration.default
                configuration.requestCachePolicy = .returnCacheDataElseLoad
                let session = URLSession(configuration: configuration)
                
                await self.items.asyncForEach { item in
                    switch item.type {
                    case .photo:
                        if let url = item.url,
                           let data: Data = try? await session.dataTask(with: url).0,
                           let image = UIImage(data: data) {
                            itemsToShare.append(image)
                        }
                    case .video:
                        if let url = item.url {
                            itemsToShare.append(url)
                        }
                    }
                }
                
                self.didTapShare(items: itemsToShare)
            }
        }
    }
    
    private func didTapShare(items: [Any]) {
        
        let activityViewController = UIActivityViewController(activityItems: items, applicationActivities: nil)
        
        // present the view controller
        self.router.topmostViewController.present(activityViewController, animated: true)
    }
}
