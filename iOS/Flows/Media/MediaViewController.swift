//
//  MediaViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 5/18/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Lightbox
import Lottie
import Coordinator
import Transitions

class MediaViewController: LightboxController, Dismissable, TransitionableViewController {

    var dismissalType: TransitionType {
        return .crossDissolve
    }
    
    var presentationType: TransitionType {
        return .crossDissolve
    }

    var dismissHandlers: [DismissHandler] = []
    
    let message: Messageable
    
    private let pageIndicator = UIPageControl()
    private let bottomGradientView = GradientPassThroughView(with: [ThemeColor.B0.color.cgColor, ThemeColor.B0.color.withAlphaComponent(0.0).cgColor],
                                                  startPoint: .bottomCenter,
                                                  endPoint: .topCenter)
    let messagePreview = MessagePreview()
    
    let menuButton = ThemeButton()
    var didSelectShare: CompletionOptional = nil 

    init(items: [MediaItem],
         startingItem: MediaItem?,
         message: Messageable) {
        
        self.message = message

        let images: [LightboxImage]
        images = items.compactMap({ item in
            guard let url = item.url else { return nil }
            switch item.type {
            case .photo:
                return LightboxImage(imageURL: url, text: "")
            case .video:
                guard let imageURL = item.previewURL else { return nil }
                return LightboxImage(imageURL: imageURL, text: "", videoURL: item.url)
            }
        })

        var startIndex: Int = 0
        if let start = startingItem {
            for (index, item) in items.enumerated() {
                if item.url == start.url {
                    startIndex = index
                    break
                }
            }
        }

        LightboxConfig.PageIndicator.textAttributes = [.font: FontType.xtraSmall.font,
                                                       .foregroundColor: ThemeColor.white.color.withAlphaComponent(0.2)]

        LightboxConfig.InfoLabel.textAttributes = [.font: FontType.small.font,
                                                   .foregroundColor: ThemeColor.white.color]

        LightboxConfig.CloseButton.text = ""
        LightboxConfig.CloseButton.image = ImageSymbol.xMark.image 
        LightboxConfig.CloseButton.size = CGSize(width: 20, height: 18)

        let animationView = LottieAnimationView.with(animation: .loading)
        animationView.loopMode = .loop
        animationView.play()
        animationView.squaredSize = 18

        LightboxConfig.makeLoadingIndicator = {
            animationView
        }

        super.init(images: images, startIndex: startIndex)
        
        // This needs to be here due to some internal setup
        self.dynamicBackground = true
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.footerView.addSubview(self.bottomGradientView)
        
        self.pageDelegate = self
        self.pageIndicator.numberOfPages = self.numberOfPages
        
        self.footerView.addSubview(self.pageIndicator)
        self.pageIndicator.currentPageIndicatorTintColor = ThemeColor.white.color
        self.pageIndicator.pageIndicatorTintColor = ThemeColor.B2.color
        self.pageIndicator.hidesForSinglePage = true
        
        self.headerView.closeButton.tintColor = ThemeColor.white.color
        self.headerView.closeButton.imageView?.contentMode = .scaleAspectFit
        self.footerView.pageLabel.isVisible = false
        self.footerView.separatorView.isVisible = false
        
        self.footerView.addSubview(self.messagePreview)
        self.messagePreview.configure(with: self.message)
        
        if self.message.kind.text.isEmpty {
            self.messagePreview.label.setText("Tap to Reply")
            self.messagePreview.label.alpha = 0.25
        }
        
        self.headerView.addSubview(self.menuButton)
        self.menuButton.set(style: .image(symbol: .ellipsis, palletteColors: [.white], pointSize: 22, backgroundColor: .clear))
        self.menuButton.showsMenuAsPrimaryAction = true
        self.menuButton.menu = self.buildMenu()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        if self.isBeingClosed {
            self.dismissHandlers.forEach { (dismissHandler) in
                dismissHandler.handler?()
            }
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.bottomGradientView.expandToSuperviewSize()
        
        self.pageIndicator.sizeToFit()
        self.pageIndicator.centerOnX()
        self.pageIndicator.pin(.bottom, offset: .xtraLong)
        
        self.messagePreview.width = Theme.getPaddedWidth(with: self.footerView.width)
        self.messagePreview.height = self.footerView.height - self.pageIndicator.top
        self.messagePreview.centerOnX()
        self.messagePreview.pin(.top)
    }
    
    override func configureLayout(_ size: CGSize) {
        super.configureLayout(size)
                
        self.headerView.closeButton.pin(.left, offset: .xtraLong)
        
        self.menuButton.squaredSize = 44
        self.menuButton.pin(.right, offset: .standard)
        self.menuButton.centerY = self.headerView.closeButton.centerY
    }
    
    private func buildMenu() -> UIMenu {
        
        let share = UIAction(title: "Share",
                             image: ImageSymbol.squareAndUp.image,
                             attributes: []) { [unowned self] action in
            self.didSelectShare?()
        }
        
        return UIMenu.init(title: "Menu",
                           image: nil,
                           identifier: nil,
                           options: [],
                           children: [share])
    }
}

extension MediaViewController: LightboxControllerPageDelegate {
    func lightboxController(_ controller: LightboxController, didMoveToPage page: Int) {
        self.pageIndicator.currentPage = page
    }
}
