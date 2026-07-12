//
//  MessageContentView.swift
//  Jibber
//
//  Created by Benji Dodgson on 11/17/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine
import LinkPresentation

/// Transfers the provider-owned metadata into the main-actor presentation view.
private struct LinkMetadataTransfer: @unchecked Sendable {
    let value: LPLinkMetadata
}

@MainActor
protocol MessageContentDelegate: AnyObject {
    func messageContent(_ content: MessageContentView, didTapViewReplies message: Messageable)
    func messageContent(_ content: MessageContentView, didTapMessage message: Messageable)
    func messageContent(_ content: MessageContentView, didTapEditMessage message: Messageable)
    func messageContent(_ content: MessageContentView, didTapAttachmentForMessage message: Messageable)
    func messageContent(_ content: MessageContentView, didTapAddExpressionForMessage message: Messageable)
    func messageContent(_ content: MessageContentView,
                        didTapAddFavorite expression: Expression,
                        toMessage message: Messageable)
    func messageContent(_ content: MessageContentView,
                        didTapExpression expression: ExpressionInfo,
                        forMessage message: Messageable)
}

extension MessageContentDelegate {
    func messageContent(_ content: MessageContentView, didTapViewReplies message: Messageable) {}
    func messageContent(_ content: MessageContentView, didTapMessage message: Messageable) {}
    func messageContent(_ content: MessageContentView, didTapEditMessage message: Messageable) {}
    func messageContent(_ content: MessageContentView, didTapAttachmentForMessage message: Messageable) {}
    func messageContent(_ content: MessageContentView, didTapAddExpressionForMessage message: Messageable) {}
    func messageContent(_ content: MessageContentView,
                        didTapAddFavorite expression: Expression,
                        toMessage message: Messageable) {}
    func messageContent(_ content: MessageContentView,
                        didTapExpression expression: ExpressionInfo,
                        forMessage message: Messageable) {}
}

class MessageContentView: BaseView {
    
    enum Layout {
        case collapsed
        case expanded
        case full
    }

    // Sizing
    // iOS 27 no longer supports the compact devices that used the legacy
    // 148-point layout.
    static let bubbleHeight: CGFloat = 188
    static let collapsedHeight: CGFloat = 94 - MessageContentView.bubbleTailLength
    static var collapsedBubbleHeight: CGFloat {
        return MessageContentView.collapsedHeight - MessageContentView.textViewPadding
    }
    static var fullBubbleHeight: CGFloat {
        guard let window = UIWindow.topWindow() else { return .zero }
        return window.height - MessageContentView.textViewPadding - window.safeAreaInsets.top - window.safeAreaInsets.bottom
    }
    static let authorViewHeight: CGFloat = 38

    static var standardHeight: CGFloat {
        return MessageContentView.bubbleHeight - MessageContentView.textViewPadding
    }
    static let padding = Theme.ContentOffset.standard
    static var textViewPadding: CGFloat { return MessageContentView.padding.value.doubled }

    static let bubbleTailLength: CGFloat = 12

    private(set) var message: Messageable?

    /// A view that provides a safe area for  main message content (margins are already taken into account).
    /// Subviews includes author, attachments, text and date sent views.
    let mainContentArea = UIView()

    /// A speech bubble background view for the message.
    let bubbleView = MessageBubbleView(orientation: .down)
    let authorView = PersonGradientView()
    /// Date view that shows when the message was last updated.
    let dateView = MessageDateLabel(font: .small)
    /// Delivery view that shows how the message was sent
    let deliveryView = SymbolImageView()
    /// Text view for displaying the text of the message.
    let textView = MessageTextView(font: .regular, textColor: .white)
    let imageView = DisplayableImageView()
    let countCircle = CircleCountView()
    let videoImageView = SymbolImageView(symbol: .videoFill)
    let linkView = LPLinkView()
    
    /// A view to blur out the emotions collection view.
    let blurView = BlurView()
    lazy var emotionCollectionView = EmotionCircleCollectionView(cellDiameter: self.cellDiameter)
    
    var layoutState: Layout = .expanded
    private let cellDiameter: CGFloat
    
    /// Delegate
    weak var delegate: MessageContentDelegate?
        
    init(with cellDiameter: CGFloat = 80) {
        self.cellDiameter = cellDiameter
        super.init()
    }
    
    required init?(coder aDecoder: NSCoder) {
        self.cellDiameter = 80
        super.init(coder: aDecoder)
    }
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.addSubview(self.bubbleView)
        self.bubbleView.roundCorners()

        self.bubbleView.addSubview(self.emotionCollectionView)

        self.bubbleView.addSubview(self.blurView)

        self.bubbleView.addSubview(self.mainContentArea)

        self.mainContentArea.addSubview(self.imageView)
        self.imageView.imageView.contentMode = .scaleAspectFill
        self.imageView.roundCorners()
        
        self.mainContentArea.addSubview(self.countCircle)
        
        self.mainContentArea.addSubview(self.videoImageView)
        self.videoImageView.tintColor = ThemeColor.white.color
        self.videoImageView.contentMode = .scaleAspectFit

        self.mainContentArea.addSubview(self.textView)
        self.textView.textContainer.lineBreakMode = .byTruncatingTail
        self.textView.textAlignment = .left
        self.textView.isVisible = false
        self.mainContentArea.addSubview(self.linkView)

        // Make sure the author, date and emoji view are on top of the other content
        self.mainContentArea.addSubview(self.authorView)
        self.authorView.set(backgroundColor: .B6)
        self.authorView.layer.cornerRadius = Theme.innerCornerRadius
        
        self.mainContentArea.addSubview(self.deliveryView)
        self.deliveryView.alpha = 0.6
        
        self.mainContentArea.addSubview(self.dateView)
        self.dateView.alpha = 0.6

        self.setupHandlers()
    }
    
    private func setupHandlers() {
        
        self.authorView.didSelect { [unowned self] in
            guard let message = self.message, let expression = self.message?.authorExpression  else { return }
            self.delegate?.messageContent(self, didTapExpression: expression, forMessage: message)
        }

        self.emotionCollectionView.onTappedBackground = { [unowned self] in
            self.setEmotions(areShown: false, animated: true)
        }
        
        self.imageView.didSelect { [unowned self] in
            guard let message = self.message else { return }
            self.delegate?.messageContent(self, didTapAttachmentForMessage: message)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        self.bubbleView.expandToSuperviewSize()

        self.emotionCollectionView.expandToSuperviewSize()

        self.blurView.expandToSuperviewSize()

        self.mainContentArea.pin(.left, offset: MessageContentView.padding)
        self.mainContentArea.pin(.top, offset: MessageContentView.padding)
        self.mainContentArea.expand(.right, padding: MessageContentView.padding.value)
        self.mainContentArea.expand(.bottom, padding: MessageContentView.padding.value)

        // Author and Emoji
        self.authorView.setSize(forHeight: MessageContentView.authorViewHeight)
        self.authorView.pin(.top)
        self.authorView.pin(.left)
        
        // Delivery View
        self.deliveryView.squaredSize = 11
        self.deliveryView.match(.left, to: .right, of: self.authorView, offset: MessageContentView.padding)

        // Date view
        self.dateView.match(.left, to: .right, of: self.deliveryView, offset: .short)
        self.dateView.pin(.top)
        self.dateView.setSize(withWidth: self.mainContentArea.width - self.dateView.left)
        
        self.deliveryView.centerY = self.dateView.centerY
        
        // If full, extend text to far right and move media/links below it
        switch self.layoutState {
        case .collapsed, .expanded:
            self.layoutDefaultContent()
        case .full:
            self.layoutFullContent()
        }
    }
    
    private func layoutFullContent() {
        
        // Text view
        self.textView.size = self.textView.getSize(width: self.mainContentArea.width, layout: self.layoutState)
        self.textView.match(.top, to: .bottom, of: self.dateView, offset: .short)
        self.textView.match(.left, to: .right, of: self.authorView, offset: MessageContentView.padding)
        self.textView.updateFontSize(state: self.layoutState)
        
        // Link view
        if self.textView.isVisible {
            self.linkView.match(.left, to: .right, of: self.authorView, offset: MessageContentView.padding)
            self.linkView.height = MessageContentView.standardHeight
            self.linkView.expand(.right)
            self.linkView.pin(.bottom)
        } else {
            self.linkView.match(.left, to: .right, of: self.authorView, offset: MessageContentView.padding)
            self.linkView.match(.top, to: .bottom, of: self.dateView, offset: .short)
            self.linkView.expand(.right)
            self.linkView.expand(.bottom)
        }

        // Image view
        if self.textView.isVisible {
            self.imageView.match(.left, to: .left, of: self.textView)
            self.imageView.expand(.right)
            self.imageView.height = MessageContentView.standardHeight
            self.imageView.pin(.bottom)
        } else {
            self.imageView.match(.left, to: .right, of: self.authorView, offset: MessageContentView.padding)
            self.imageView.match(.top, to: .bottom, of: self.dateView, offset: .short)
            self.imageView.expand(.bottom)
            self.imageView.expand(.right)
        }
        
        self.countCircle.match(.top, to: .top, of: self.imageView, offset: .short)
        self.countCircle.match(.right, to: .right, of: self.imageView, offset: .negative(.short))
        self.countCircle.showShadow(withOffset: 2)
        
        self.videoImageView.squaredSize = 16
        self.videoImageView.match(.bottom, to: .bottom, of: self.imageView, offset: .negative(.short))
        self.videoImageView.match(.left, to: .left, of: self.imageView, offset: .short)
        self.videoImageView.showShadow(withOffset: 2)
    }
    
    private func layoutDefaultContent() {
        // Link view
        self.linkView.match(.left, to: .right, of: self.authorView, offset: MessageContentView.padding)
        self.linkView.match(.top, to: .bottom, of: self.dateView, offset: .short)
        self.linkView.expand(.right)
        self.linkView.expand(.bottom)

        // Text view
        self.textView.match(.top, to: .bottom, of: self.dateView, offset: .short)
        self.textView.match(.left, to: .right, of: self.authorView, offset: MessageContentView.padding)
        if self.imageView.isVisible {
            self.textView.width = (self.mainContentArea.width - self.textView.left).half
        } else {
            self.textView.expand(.right)
        }
        self.textView.expand(.bottom)
        self.textView.updateFontSize(state: self.layoutState)

        // Image view
        if self.textView.isVisible {
            self.imageView.pin(.top)
            self.imageView.match(.left, to: .right, of: self.textView, offset: .short)
        } else {
            self.imageView.match(.left, to: .right, of: self.authorView, offset: MessageContentView.padding)
            self.imageView.match(.top, to: .bottom, of: self.dateView, offset: .short)
        }
        self.imageView.expand(.right)
        self.imageView.expand(.bottom)
        
        self.countCircle.match(.top, to: .top, of: self.imageView, offset: .short)
        self.countCircle.match(.right, to: .right, of: self.imageView, offset: .negative(.short))
        self.countCircle.showShadow(withOffset: 2)
        
        self.videoImageView.squaredSize = 16
        self.videoImageView.match(.bottom, to: .bottom, of: self.imageView, offset: .negative(.short))
        self.videoImageView.match(.left, to: .left, of: self.imageView, offset: .short)
        self.videoImageView.showShadow(withOffset: 2)
    }

    private var linkProvider: LPMetadataProvider?

    func configure(with message: Messageable) {
        // True we're changing what message to display
        let isDifferentMessage = self.message?.id != message.id

        self.message = message
        
        self.textView.isVisible = message.kind.hasText && !message.kind.isLink
        self.imageView.isVisible = message.kind.hasImage
        self.linkView.isVisible = message.kind.isLink
        self.videoImageView.isVisible = message.kind.hasVideo
        self.countCircle.isVisible = false

        self.dateView.configure(with: message)
        self.deliveryView.set(symbol: message.deliveryType.symbol)

        if message.isDeleted {
            self.textView.text = "DELETED"
        } else {
            self.textView.setText(with: message)

            switch message.kind {
            case .photo(photo: let photo, _):
                // Only reload the picture if it's actually a new message.

                if isDifferentMessage || self.imageView.imageView.image.isNil {
                    if let previewURL = photo.previewURL {
                        self.imageView.displayable = previewURL
                    } else {
                        self.imageView.displayable = photo.url
                    }
                }
            case .video(video: let video, _):
                
                if isDifferentMessage || self.imageView.imageView.image.isNil {
                    if let previewURL = video.previewURL {
                        self.imageView.displayable = previewURL
                    } else {
                        self.imageView.displayable = video.url
                    }
                }
                
            case .media(items: let media, _):
                
                if isDifferentMessage || self.imageView.imageView.image.isNil {
                    if let previewURL = media.first?.previewURL {
                        self.imageView.displayable = previewURL
                    } else {
                        self.imageView.displayable = media.first?.url
                    }
                    
                    self.countCircle.set(count: media.count)
                }
                
                self.countCircle.isVisible = true
                
            case .link(url: let url, _):
                guard isDifferentMessage || url != self.linkView.metadata.originalURL else { break }

                self.linkProvider?.cancel()

                let initialMetadata = LPLinkMetadata()
                initialMetadata.originalURL = url
                self.linkView.metadata = initialMetadata

                self.linkProvider = LPMetadataProvider()
                self.linkProvider?.startFetchingMetadata(for: url) { (metadata, error) in
                    guard let metadata else { return }
                    let transfer = LinkMetadataTransfer(value: metadata)
                    Task.onMainActor {
                        self.linkView.metadata = transfer.value
                        self.setNeedsLayout()
                    }
                }
            case .text, .attributedText, .location, .emoji, .audio, .contact:
                self.imageView.isVisible = false
                self.linkView.isVisible = false
                break
            }
        }
        
        self.loadExpressions(for: message)
    }
    
    /// The currently running task that is loading the expressions.
    private var loadTask: Task<Void, Never>?
    
    private func loadExpressions(for message: Messageable) {
        self.loadTask?.cancel()
        
        self.loadTask = Task { [weak self] in
            if let expressionInfo = message.authorExpression,
               let expression = try? await Expression.getObject(with: expressionInfo.expressionId) {

                guard !Task.isCancelled else { return }

                let emotionCounts = expression.emotionCounts
                self?.emotionCollectionView.setEmotionsCounts(emotionCounts, animated: false)

                self?.authorView.set(expression: expression, person: nil)
            } else if let author = await PeopleStore.shared.getPerson(withPersonId: message.authorId) {

                guard !Task.isCancelled else { return }

                self?.authorView.set(expression: nil, person: author)
                self?.authorView.set(emotionCounts: [:])
            }
            
            self?.setNeedsLayout()
        }
    }

    /// Sets the background color and shows/hides the bubble tail.
    func configureBackground(color: UIColor,
                             textColor: UIColor,
                             brightness: CGFloat,
                             showBubbleTail: Bool,
                             tailOrientation: SpeechBubbleView.TailOrientation) {

        self.textView.textColor = textColor
        self.textView.linkTextAttributes = [.foregroundColor: ThemeColor.D6.color, .underlineStyle: 0]

        self.bubbleView.setBubbleColor(color.withAlphaComponent(brightness), animated: false)
        self.bubbleView.tailLength = showBubbleTail ? MessageContentView.bubbleTailLength : 0
        self.bubbleView.orientation = tailOrientation
    }

    func playReadAnimations() async {
        await self.textView.startReadAnimation()
        await UIView.awaitAnimation(with: .custom(1)) {
            self.imageView.alpha = 1
            self.linkView.alpha = 1
        }
    }

    func setEmotions(areShown: Bool, animated: Bool) {
        if !areShown {
            self.blurView.alpha = 1
        }

        let animationDuration = animated ? Theme.animationDurationStandard : 0
        UIView.animate(withDuration: animationDuration) {
            self.mainContentArea.alpha = areShown ? 0 : 1
            self.blurView.effect = areShown ? nil : Theme.blurEffect
        } completion: { completed in
            if areShown {
                // Set the blur view alpha to 0 so it doesn't interfere with touches.
                self.blurView.alpha = 0
            }
        }
    }

    func getSize(with width: CGFloat) -> CGSize {
        var size = self.textView.getSize(width: width, layout: self.layoutState)
        size.width += MessageContentView.textViewPadding
        switch self.layoutState {
        case .collapsed, .expanded:
            size.height += self.bubbleView.tailLength + MessageContentView.textViewPadding
        case .full:
            size.height += self.bubbleView.tailLength + MessageContentView.textViewPadding
            if self.imageView.isVisible {
                size.height += MessageContentView.standardHeight
                if self.textView.isVisible {
                    size.height += MessageContentView.textViewPadding + MessageContentView.padding.value
                }
            } else if self.linkView.isVisible {
                size.height += MessageContentView.standardHeight
                if self.textView.isVisible {
                    size.height += MessageContentView.textViewPadding + MessageContentView.padding.value
                }
            }
        }
        return size
    }
}

extension MessageTextView {

    func getSize(width: CGFloat, layout: MessageContentView.Layout = .expanded) -> CGSize {
        let maxTextWidth: CGFloat
        var maxTextHeight: CGFloat = MessageContentView.standardHeight
        
        switch layout {
        case .collapsed:
            maxTextHeight = MessageContentView.collapsedBubbleHeight
        case .expanded:
            break
        case .full:
            maxTextHeight = MessageContentView.fullBubbleHeight
        }
        
        if layout == .collapsed {
            maxTextHeight = MessageContentView.collapsedBubbleHeight
        }
        
        maxTextWidth = self.getMaxWidth(with: width)

        return self.getSize(withMaxWidth: maxTextWidth, maxHeight: maxTextHeight)
    }
    
    func getMaxWidth(with width: CGFloat) -> CGFloat {
        let size = CGSize(width: MessageContentView.authorViewHeight,
                          height: MessageContentView.authorViewHeight)
        return width - (size.width + (MessageContentView.textViewPadding + MessageContentView.textViewPadding.half))
    }

    /// Updates the font size to be appropriate for the amount of text displayed.
    fileprivate func updateFontSize(state: MessageContentView.Layout) {
        if state == .collapsed {
            self.font = FontType.regular.font
            return
        }
        
        self.font = FontType.emoji.font

        guard self.numberOfLines > 1 else { return }

        self.font = FontType.medium.font

        guard self.numberOfLines > 1 else { return }

        self.font = FontType.regular.font
    }
}
