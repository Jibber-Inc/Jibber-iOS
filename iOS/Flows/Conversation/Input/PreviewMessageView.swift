//
//  PreviewMessageView.swift
//  Benji
//
//  Created by Benji Dodgson on 8/24/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine

class PreviewMessageView: SpeechBubbleView {

    private let minHeight: CGFloat = 52
    let textView = ExpandingTextView()
    private let imageView = DisplayableImageView()
    private let deliveryTypeView = MessageDeliveryTypeBadgeView()

    var deliveryType: MessageDeliveryType? {
        get {
            return self.deliveryTypeView.deliveryType
        }
        set {
            self.deliveryTypeView.deliveryType = newValue
            self.setNeedsLayout()
        }
    }
    @Published var messageKind: MessageKind?
    private var cancellables = Set<AnyCancellable>()

    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.tailLength = 0

        self.addSubview(self.textView)
        self.textView.textAlignment = .left
        self.textView.textContainer.lineBreakMode = .byTruncatingTail
        self.addSubview(self.imageView)
        
        self.imageView.layer.borderColor = ThemeColor.whiteWithAlpha.color.cgColor
        self.imageView.layer.borderWidth = 2
        self.imageView.layer.masksToBounds = true
        self.imageView.layer.cornerRadius = Theme.innerCornerRadius

        self.addSubview(self.deliveryTypeView)
        // Start the delivery type invisible so it doesn't briefly flicker on screen.
        self.deliveryTypeView.alpha = 0

        self.$messageKind.mainSink { [unowned self] (kind) in
            guard let messageKind = kind else { return }

            switch messageKind {
            case .text(let body):
                self.textView.text = body
            case .attributedText(let body):
                self.textView.text = body.string
            case .photo(photo: let photo, body: let body):
                self.textView.text = body
                self.imageView.displayable = photo.image
            case .video(video: let video, body: let body):
                self.textView.text = body
                self.imageView.displayable = video.image
            case .location(_):
                break
            case .emoji(_):
                break
            case .audio(_):
                break
            case .contact(_):
                break
            case .link(_, let stringURL):
                self.textView.text = stringURL
            }
            
            self.imageView.isVisible = self.imageView.displayable.exists

            self.layoutNow()
        }.store(in: &self.cancellables)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        var maxWidth: CGFloat = self.width - self.imageView.width - Theme.ContentOffset.long.value
        
        if self.imageView.isHidden {
            maxWidth = self.width - Theme.ContentOffset.long.value.doubled
        }
        
        self.textView.setSize(withMaxWidth: maxWidth, maxHeight: self.height)
        self.textView.pin(.left, offset: .long)
        self.textView.center.y = self.halfHeight
        
        self.imageView.squaredSize = 40
        self.imageView.centerOnX()
        self.imageView.pin(.bottom, offset: .custom(12))
        self.imageView.pin(.right, offset: .long)

        self.deliveryTypeView.centerOnX()
        self.deliveryTypeView.pin(.top, offset: .custom(-self.deliveryTypeView.height * 0.5))
    }
}
