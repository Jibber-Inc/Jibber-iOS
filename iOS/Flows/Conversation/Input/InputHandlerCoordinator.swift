//
//  InputHandlerCoordinator.swift
//  Jibber
//
//  Created by Benji Dodgson on 3/23/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import PhotosUI
import Photos
import Localization
import Lightbox
import Coordinator
import KeyboardManager

protocol SwipeableInputControllerHandler where Self: ViewController {
    var messageContentDelegate: MessageContentDelegate? { get set }
    var swipeableVC: SwipeableInputAccessoryViewController { get }
    func updateUI(for state: ConversationUIState, forceLayout: Bool)
    func scrollToConversation(with conversationId: String,
                              messageId: String?,
                              viewReplies: Bool,
                              animateScroll: Bool,
                              animateSelection: Bool) async
}

typealias InputHandlerViewContoller = SwipeableInputControllerHandler & ViewController

class InputHandlerCoordinator<Result>: PresentableCoordinator<Result>,
                                       ActiveConversationable,
                                       PHPickerViewControllerDelegate,
                                       UIImagePickerControllerDelegate,
                                       UINavigationControllerDelegate,
                                       MessageContentDelegate {
    
    lazy var captureVC: UIImagePickerController = {
        let vc = UIImagePickerController()
        vc.sourceType = .camera
        vc.mediaTypes = ["public.image", "public.movie"]
        vc.videoQuality = .typeMedium
        vc.videoExportPreset = AVAssetExportPresetHEVC1920x1080
        vc.allowsEditing = true
        vc.delegate = self
        return vc
    }()
    
    let inputHandlerViewController: InputHandlerViewContoller
    
    init(with viewContoller: InputHandlerViewContoller,
         router: CoordinatorRouter,
         deepLink: DeepLinkable?) {
        
        self.inputHandlerViewController = viewContoller
        super.init(router: router, deepLink: deepLink)
    }
    
    override func toPresentable() -> PresentableCoordinator<Void>.DismissableVC {
        return self.inputHandlerViewController
    }
    
    override func start() {
        super.start()
        
        self.inputHandlerViewController.swipeableVC.swipeInputView.addView.didSelect { [unowned self] in
            self.presentAttachments()
        }
        
        self.inputHandlerViewController.swipeableVC.swipeInputView.unreadMessagesCounter
            .didSelect { [unowned self] in
                self.scrollToUnreadMessage()
            }
        
        self.inputHandlerViewController.messageContentDelegate = self 
    }
    
    /// The currently running task that is loading.
    private var loadTask: Task<Void, Never>?
    
    func scrollToUnreadMessage() {
        // Find the oldest unread message.
        guard let conversation = ConversationsManager.shared.activeConversation,
              let unreadMessage = conversation.messages.reversed().first(where: { message in
                  return !message.isFromCurrentUser && !message.isConsumedByMe
              }) else { return }
        
        self.loadTask?.cancel()
        
        self.loadTask = Task { [weak self] in
            guard let self else { return }
            await self.inputHandlerViewController.scrollToConversation(with: conversation.id,
                                                                       messageId: unreadMessage.id,
                                                                       viewReplies: false,
                                                                       animateScroll: true,
                                                                       animateSelection: true)
        }
    }
    
    func presentExpressionCreation(for message: Messageable) {
        let coordinator = ExpressionCoordinator(router: self.router,
                                                deepLink: self.deepLink)
        self.present(coordinator) { result in
            guard let expression = result else { return }
            
            Task {
                await self.add(expression: expression, toMessage: message)
            }
        }
    }
    
    func add(expression: Expression, toMessage message: Messageable) async {
        expression.emotions.forEach { emotion in
            AnalyticsManager.shared.trackEvent(type: .emotionSelected,
                                               properties: ["value": emotion.rawValue])
        }
        
        let controller = MessageController.controller(for: message)
        // Add new or update
        try? await controller?.add(expression: expression)
    }
    
    func presentProfile(for person: PersonType) {}
    
    func presentAttachments() {
        let coordinator = AttachmentsCoordinator(router: self.router, deepLink: self.deepLink)
        self.present(coordinator) { [unowned self] result in
            self.handle(attachmentOption: result)
        }
    }
    
    func present<ChildResult>(_ coordinator: PresentableCoordinator<ChildResult>,
                              finishedHandler: ((ChildResult) -> Void)? = nil,
                              cancelHandler: (() -> Void)? = nil) {
        self.removeChild()
        let previousFirstResponder = UIResponder.firstResponder

        // Because of how the People are presented, we need to properly reset the KeyboardManager.
        coordinator.toPresentable().dismissHandlers.append { [unowned self, weak previousFirstResponder] in
            // Make sure the input view is shown after the presented view is dismissed.
            self.inputHandlerViewController.becomeFirstResponder()
            // If there was a previous first responder, restore its first responder status.
            previousFirstResponder?.becomeFirstResponder()
        }
        
        self.addChildAndStart(coordinator) { [unowned self] result in
            self.inputHandlerViewController.dismiss(animated: true) {
                finishedHandler?(result)
            }
        }
        
        self.inputHandlerViewController.resignFirstResponder()
        self.router.present(coordinator, source: self.inputHandlerViewController, cancelHandler: cancelHandler)
    }
    
    func handle(attachmentOption option: AttachmentOption) {
        switch option {
        case .attachments(let attachments):
            let text = self.inputHandlerViewController.swipeableVC.swipeInputView.textView.text ?? ""
            Task.onMainActorAsync {
                guard let kind
                        = await AttachmentsManager.shared.getMessageKind(for: attachments,
                                                                              body: text) else { return }
                self.inputHandlerViewController.swipeableVC.currentMessageKind = kind
                self.inputHandlerViewController.swipeableVC.inputState = .collapsed
            }
        case .capture:
            self.presentPhotoCapture()
        case .audio:
            break
        case .giphy:
            break
        case .video:
            break
        case .library:
            self.presentPhotoLibrary()
        }
    }
    
    func presentPhotoCapture() {
        let cameraMediaType = AVMediaType.video
        let status = AVCaptureDevice.authorizationStatus(for: cameraMediaType)
        
        switch status {
        case .denied:
            break
        case .authorized:
            self.toPresentable().present(self.captureVC, animated: true, completion: nil)
        case .restricted:
            break
        case .notDetermined:
            // Prompting user for the permission to use the camera.
            Task { @MainActor [weak self] in
                let granted = await AVCaptureDevice.requestAccess(for: cameraMediaType)
                if granted {
                    guard let self else { return }
                    self.toPresentable().present(self.captureVC, animated: true, completion: nil)
                } else {
                    print("Denied access to \(cameraMediaType)")
                }
            }
        @unknown default:
            break
        }
    }
    
    func presentPhotoLibrary() {
        let filter = PHPickerFilter.any(of: [.images, .videos])
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = filter
        config.selectionLimit = 7
        let vc = PHPickerViewController(configuration: config)
        vc.delegate = self
        
        self.toPresentable().present(vc, animated: true) {
            // Important to call as this picker lives outside the current responder chain. 
            self.inputHandlerViewController.resignFirstResponder()
        }
    }
    
    // https://developer.apple.com/documentation/photokit/selecting_photos_and_videos_in_ios
    nonisolated func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        let identifiers = results.compactMap(\.assetIdentifier)

        Task.onMainActorAsync {
            self.inputHandlerViewController.dismiss(animated: true) {
                self.inputHandlerViewController.becomeResponder()
            }
            
            let text = self.inputHandlerViewController.swipeableVC.swipeInputView.textView.text ?? ""
            
            let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
            var attachments: [Attachment] = []
            
            guard result.count > 0 else { return }
                
            for index in 0...result.count - 1 {
                let asset = result.object(at: index)
                attachments.append(Attachment(asset: asset))
            }
                        
            guard let kind = await AttachmentsManager.shared.getMessageKind(for: attachments, body: text) else { return }
            
            self.inputHandlerViewController.swipeableVC.currentMessageKind = kind
            self.inputHandlerViewController.swipeableVC.inputState = .collapsed
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true) { [unowned self] in
            self.toPresentable().becomeFirstResponder()
        }
    }
    
    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {

        picker.dismiss(animated: true) { [unowned self] in
            self.toPresentable().becomeFirstResponder()

            Task.onMainActorAsync {
                let text = self.inputHandlerViewController.swipeableVC.swipeInputView.textView.text ?? ""
                guard let kind
                        = await AttachmentsManager.shared.getMessageKind(for: info, body: text) else {
                    return
                }
                self.inputHandlerViewController.swipeableVC.currentMessageKind = kind
                self.inputHandlerViewController.swipeableVC.inputState = .collapsed
            }
        }
    }
    
    // MARK: - MessageCellDelegate
    
    func messageContent(_ content: MessageContentView, didTapViewReplies message: Messageable) {}

    func messageContent(_ content: MessageContentView, didTapMessage message: Messageable) {}

    func messageContent(_ content: MessageContentView, didTapEditMessage message: Messageable) {}

    func messageContent(_ content: MessageContentView, didTapAttachmentForMessage message: Messageable) {

        switch message.kind {
        case .photo(photo: let photo, _):
            self.presentMediaFlow(for: [photo], startingItem: nil, message: message)
        case .video(video: let video, _):
            self.presentMediaFlow(for: [video], startingItem: nil, message: message)
        case .media(items: let media, _):
            self.presentMediaFlow(for: media, startingItem: nil, message: message)
        case .text, .attributedText, .location, .emoji, .audio, .contact, .link:
            break
        }
    }

    func messageContent(_ content: MessageContentView, didTapAddExpressionForMessage message: Messageable) {
        self.presentExpressionCreation(for: message)
    }
    
    func messageContent(_ content: MessageContentView,
                        didTapAddFavorite expression: Expression,
                        toMessage message: Messageable) {
        Task {
            await self.add(expression: expression, toMessage: message)
        }
    }

    func messageContent(_ content: MessageContentView,
                        didTapExpression expression: ExpressionInfo,
                        forMessage message: Messageable) {
                
        let coordinator = ExpressionDetailCoordinator(router: self.router,
                                                      deepLink: self.deepLink,
                                                      message: message,
                                                      startingExpression: expression,
                                                      expressions: message.expressions)
        self.present(coordinator)
    }
    
    func presentMediaFlow(for mediaItems: [MediaItem],
                          startingItem: MediaItem?,
                          message: Messageable) {
        
        let coordinator = MediaCoordinator(items: mediaItems,
                                           startingItem: startingItem,
                                           message: message,
                                           router: self.router,
                                           deepLink: self.deepLink)
        
        self.present(coordinator) { [unowned self] result in
            switch result {
            case .reply(let message):
                self.router.dismiss(source: coordinator.toPresentable(), animated: true) { [weak self] in
                    guard let self else { return }
                    self.presentThread(for: message, startingReplyId: nil)
                }
            case .none:
                break
            }
        }
    }
    
    func presentThread(for message: Messageable, startingReplyId: String?) {}
}
