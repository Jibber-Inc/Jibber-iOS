//
//  ConversationListViewController.swift
//  Jibber
//
//  Created by Martin Young on 11/12/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine
import Coordinator
import KeyboardManager
import Lottie
import PhotosUI
import Transitions

enum ConversationUIState: String {
    case read // Keyboard is NOT shown
    case write // Keyboard IS shown

    var headerHeight: CGFloat {
        return 46
    }
}

/// A view controller for displaying a single conversation.
class ConversationViewController: InputHandlerViewContoller,
                                  ConversationListCollectionViewLayoutDelegate {
    
    override var analyticsIdentifier: String? {
        return "SCREEN_CONVERSATION_LIST"
    }
    
    lazy var selectionViewController = ConversationSelectionViewController()

    var messageContentDelegate: MessageContentDelegate? {
        get { return self.dataSource.messageContentDelegate}
        set { self.dataSource.messageContentDelegate = newValue }
    }
    
    var blurView = DarkBlurView()
    lazy var dismissInteractionController: PanDismissInteractionController? = nil 

    // Collection View
    lazy var dataSource = ConversationCollectionViewDataSource(collectionView: self.collectionView)
    lazy var collectionView = ConversationListCollectionView()

    let headerVC = ConversationHeaderViewController()
    private let darkBlur = DarkBlurView()

    private(set) var conversationController: ParseConversationController?
    var conversationUpdateCancellable: AnyCancellable?
    var typingInputCancellable: AnyCancellable?
    var typingHeartbeatTask: Task<Void, Never>?
    private var conversationInitializationTask: Task<Void, Never>?
    private var conversationInitializationToken: UUID?

    var swipeableVC: SwipeableInputAccessoryViewController {
        return self.messageInputController
    }

    // Custom Input Accessory View
    lazy var messageInputController: SwipeableInputAccessoryViewController = {
        let inputController = SwipeableInputAccessoryViewController()
        inputController.delegate = self.swipeInputDelegate
        inputController.swipeInputView.textView.restorationIdentifier = "list"
        return inputController
    }()
    
    lazy var swipeInputDelegate = SwipeableInputAccessoryMessageSender(viewController: self,
                                                                       collectionView: self.collectionView)

    override var inputAccessoryViewController: UIInputViewController? {
        return self.presentedViewController.isNil ? self.messageInputController : nil
    }
    
    override var canBecomeFirstResponder: Bool {
        return self.presentedViewController.isNil
    }

    @Published var state: ConversationUIState = .read

    /// The id of the conversation this VC will display.
    @Published var conversationId: String?
    var startingMessageId: String?
    private var openReplies: Bool

    init(conversationId: String?,
         startingMessageId: String?,
         openReplies: Bool) {

        self.conversationId = conversationId
        self.startingMessageId = startingMessageId
        self.openReplies = openReplies

        super.init()
    }

    func setStartingNavigation(messageID: String?, openReplies: Bool) {
        self.startingMessageId = messageID
        self.openReplies = openReplies
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func initializeViews() {
        super.initializeViews()
        
        self.modalPresentationStyle = .popover
        if let pop = self.popoverPresentationController {
            let sheet = pop.adaptiveSheetPresentationController
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = false
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        }
        
        self.view.insertSubview(self.darkBlur, belowSubview: self.collectionView)
                
        self.view.addSubview(self.collectionView)
        self.collectionView.showsVerticalScrollIndicator = false
        self.collectionView.conversationLayout.delegate = self

        self.addChild(viewController: self.headerVC, toView: self.view)
        
        self.subscribeToUIUpdates()
        self.setupInputHandlers()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        guard self.presentedViewController.isNil else { return }
        
        self.darkBlur.expandToSuperviewSize()

        self.headerVC.view.expandToSuperviewWidth()
        self.headerVC.view.height = self.state.headerHeight
        self.headerVC.view.pinToSafeArea(.top, offset: .standard)

        self.collectionView.expandToSuperviewWidth()
        self.collectionView.match(.top, to: .bottom, of: self.headerVC.view, offset: .xtraLong)
        self.collectionView.height = self.view.height - self.headerVC.view.bottom
        
        self.selectionViewController.view.expandToSuperviewSize()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.becomeFirstResponder()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        once(caller: self, token: "initializeCollectionView") {
            
            self.$conversationId
                .removeDuplicates()
                .mainSink { [unowned self] conversationId in
                    self.cancelConversationInitialization()
                    self.conversationUpdateCancellable = nil
                    self.typingInputCancellable = nil

                    if let conversationId = conversationId {
                        // Capture every value that belongs to this selection. A later selection cancels this
                        // task and replaces its token so suspended work cannot apply stale state when it resumes.
                        guard !conversationId.isEmpty,
                              let controller = JibberMessagingClient.shared.conversationController(
                                for: conversationId
                              ) else { return }

                        let startingMessageId = self.startingMessageId
                        let initializationToken = UUID()
                        self.conversationController = controller
                        self.conversationInitializationToken = initializationToken
                        self.collectionView.animationView.play()

                        if self.selectionViewController.parent.exists {
                            UIView.animate(
                                withDuration: Theme.animationDurationFast,
                                animations: {
                                    self.selectionViewController.view.alpha = 0
                                },
                                completion: { [weak self] _ in
                                    guard let self,
                                          self.conversationId == conversationId else { return }

                                    self.selectionViewController.removeFromParent()
                                    self.selectionViewController.view.removeFromSuperview()
                                }
                            )
                        }

                        self.conversationInitializationTask = Task { @MainActor [weak self] in
                            // Do not retain the presented controller while a shared
                            // network/cache synchronization is still in flight.
                            try? await controller.synchronize()

                            guard let self,
                                  self.isCurrentConversationInitialization(
                                    conversationId: conversationId,
                                    controller: controller,
                                    initializationToken: initializationToken
                                  ) else { return }

                            await self.finishDataSourceInitialization(
                                for: conversationId,
                                controller: controller,
                                startingMessageId: startingMessageId,
                                initializationToken: initializationToken
                            )

                            guard self.isCurrentConversationInitialization(
                                conversationId: conversationId,
                                controller: controller,
                                initializationToken: initializationToken
                            ) else { return }

                            self.subscribeToConversationUpdates()
                        }
                    } else {
                        self.conversationController = nil
                        self.selectionViewController.view.alpha = 1.0 
                        self.addChild(self.selectionViewController)
                        self.view.insertSubview(self.selectionViewController.view, aboveSubview: self.headerVC.view)
                        self.view.layoutNow()

                        let initializationToken = UUID()
                        self.conversationInitializationToken = initializationToken
                        self.conversationInitializationTask = Task { @MainActor [weak self] in
                            // Hack to get the input text view to layout correctly
                            await Task.sleep(seconds:0.1)

                            guard !Task.isCancelled,
                                  let self,
                                  self.conversationInitializationToken == initializationToken,
                                  self.conversationId == nil else { return }

                            self.messageInputController.swipeInputView.textView.becomeResponder()
                        }
                    }
                    
                }.store(in: &self.cancellables)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        self.typingHeartbeatTask?.cancel()
        try? self.conversationController?.setTyping(false)
        self.resignFirstResponder()
    }
    
    override func viewWasDismissed() {
        super.viewWasDismissed()

        self.cancelConversationInitialization()
        ConversationsManager.shared.activeConversation = nil
    }

    func updateUI(for state: ConversationUIState, forceLayout: Bool = false) {
        guard self.presentedViewController.isNil || forceLayout else { return }
        
        self.headerVC.update(for: state)
        self.dataSource.uiState = state

        self.dataSource.reconfigureAllItems()
    }

    // MARK: - Message Loading and Updates

    @MainActor
    private func finishDataSourceInitialization(
        for conversationId: String,
        controller: ParseConversationController,
        startingMessageId: String?,
        initializationToken: UUID
    ) async {
        guard self.isCurrentConversationInitialization(
            conversationId: conversationId,
            controller: controller,
            initializationToken: initializationToken
        ) else { return }

        let snapshot = self.dataSource.updatedSnapshot(with: controller)

        let animationCycle = AnimationCycle(inFromPosition: .inward,
                                            outToPosition: .inward,
                                            shouldConcatenate: false)

        await self.dataSource.apply(snapshot,
                                    collectionView: self.collectionView,
                                    animationCycle: animationCycle)

        guard self.isCurrentConversationInitialization(
            conversationId: conversationId,
            controller: controller,
            initializationToken: initializationToken
        ) else { return }

        await self.scrollToConversation(
            with: conversationId,
            messageId: startingMessageId,
            viewReplies: self.openReplies,
            animateScroll: false,
            animateSelection: false,
            initializationToken: initializationToken,
            expectedController: controller
        )

        guard self.isCurrentConversationInitialization(
            conversationId: conversationId,
            controller: controller,
            initializationToken: initializationToken
        ) else { return }

        // Keep intermediate collection offsets covered. Only the selection
        // that successfully completed positioning may dismiss its loader.
        self.collectionView.animationView.stop()
    }

    @MainActor
    func scrollToConversation(with conversationId: String,
                              messageId: String?,
                              viewReplies: Bool = false,
                              animateScroll: Bool = true,
                              animateSelection: Bool = true) async {
        // Message navigation depends on the initial snapshot and the update
        // subscriptions installed by the initialization task. Wait for that
        // work instead of canceling it and potentially returning on a missing
        // index path with a permanently stale screen.
        if let conversationInitializationTask {
            await conversationInitializationTask.value
        }

        await self.scrollToConversation(
            with: conversationId,
            messageId: messageId,
            viewReplies: viewReplies,
            animateScroll: animateScroll,
            animateSelection: animateSelection,
            initializationToken: nil,
            expectedController: nil
        )
    }

    @MainActor
    private func scrollToConversation(with conversationId: String,
                                      messageId: String?,
                                      viewReplies: Bool,
                                      animateScroll: Bool,
                                      animateSelection: Bool,
                                      initializationToken: UUID?,
                                      expectedController: ParseConversationController?) async {

        guard self.canContinueScrolling(
            to: conversationId,
            initializationToken: initializationToken,
            expectedController: expectedController
        ) else { return }

        guard let conversationIndexPath = self.dataSource.indexPath(
            for: .conversation(conversationId)
        ) else { return }

        self.collectionView.layoutIfNeeded()
        if let attributes = self.collectionView.layoutAttributesForItem(at: conversationIndexPath) {
            let targetOffset = CGPoint(
                x: attributes.center.x - self.collectionView.bounds.width.half,
                y: self.collectionView.contentOffset.y
            )
            if animateScroll,
               abs(targetOffset.x - self.collectionView.contentOffset.x) > 1 {
                await UIView.awaitAnimation(with: .standard) {
                    self.collectionView.setContentOffset(targetOffset, animated: false)
                }

                guard self.canContinueScrolling(
                    to: conversationId,
                    initializationToken: initializationToken,
                    expectedController: expectedController
                ) else { return }
            } else {
                self.collectionView.setContentOffset(targetOffset, animated: false)
            }
        } else {
            self.collectionView.scrollToItem(
                at: conversationIndexPath,
                at: .centeredHorizontally,
                animated: false
            )
        }
        self.collectionView.layoutIfNeeded()

        guard let messagesCell = self.collectionView.cellForItem(
            at: conversationIndexPath
        ) as? ConversationMessagesCell else { return }

        await messagesCell.prepareForScrolling(scrollToLatest: messageId == nil)

        guard self.canContinueScrolling(
            to: conversationId,
            initializationToken: initializationToken,
            expectedController: expectedController
        ) else { return }

        guard let messageId else { return }

        guard let conversationController = JibberMessagingClient.shared.conversationController(for: conversationId) else {
            return
        }
        let message: ParseMessage?
        if let loadedMessage = conversationController.messages.lazy
            .flatMap({ [$0] + $0.replies })
            .first(where: { $0.id == messageId || $0.serverID == messageId }) {
            message = loadedMessage
        } else {
            let messageController = conversationController.messageController(
                for: messageId,
                automaticallySynchronize: false
            )
            try? await messageController.synchronize()

            guard self.canContinueScrolling(
                to: conversationId,
                initializationToken: initializationToken,
                expectedController: expectedController
            ) else { return }

            message = messageController.message
        }
        guard let message else { return }

        // Determine if this is a reply message or regular message.
        if let parentMessageId = message.parentMessageId {
            // It's a reply, select the parent message so we can open the thread experience.
            await messagesCell.scrollToMessage(with: parentMessageId,
                                               animateScroll: animateScroll,
                                               animateSelection: animateSelection)

            guard self.canContinueScrolling(
                to: conversationId,
                initializationToken: initializationToken,
                expectedController: expectedController
            ) else { return }

            if let messageCell = messagesCell.getFrontmostCell() {
                self.messageContentDelegate?.messageContent(messageCell.content,
                                                            didTapMessage: message)
            }
        } else if viewReplies {
            // It's not a parent message, but we still want to see the replies.
            await messagesCell.scrollToMessage(with: messageId,
                                               animateScroll: animateScroll,
                                               animateSelection: animateSelection)

            guard self.canContinueScrolling(
                to: conversationId,
                initializationToken: initializationToken,
                expectedController: expectedController
            ) else { return }

            if let messageCell = messagesCell.getFrontmostCell() {
                self.messageContentDelegate?.messageContent(messageCell.content,
                                                            didTapViewReplies: message)
            }
        } else {
            await messagesCell.scrollToMessage(with: messageId,
                                               animateScroll: animateScroll,
                                               animateSelection: animateSelection)

            guard self.canContinueScrolling(
                to: conversationId,
                initializationToken: initializationToken,
                expectedController: expectedController
            ) else { return }
        }
    }

    @MainActor
    private func cancelConversationInitialization() {
        self.conversationInitializationTask?.cancel()
        self.conversationInitializationTask = nil
        self.conversationInitializationToken = nil
        self.collectionView.animationView.stop()
    }

    @MainActor
    private func isCurrentConversationInitialization(
        conversationId: String,
        controller: ParseConversationController,
        initializationToken: UUID
    ) -> Bool {
        !Task.isCancelled
            && self.conversationInitializationToken == initializationToken
            && self.conversationId == conversationId
            && self.conversationController === controller
    }

    @MainActor
    private func canContinueScrolling(
        to conversationId: String,
        initializationToken: UUID?,
        expectedController: ParseConversationController?
    ) -> Bool {
        guard !Task.isCancelled else { return false }
        guard let initializationToken, let expectedController else { return true }

        return self.isCurrentConversationInitialization(
            conversationId: conversationId,
            controller: expectedController,
            initializationToken: initializationToken
        )
    }

    func getCurrentConversationController() -> ParseConversationController? {
        guard let centeredCell
                = self.collectionView.getCentermostVisibleCell() as? ConversationMessagesCell else {
            return nil
        }

        return centeredCell.conversationController
    }

    // MARK: - ConversationListCollectionViewLayoutDelegate

    func conversationListCollectionViewLayout(_ layout: ConversationListCollectionViewLayout,
                                              conversationIdFor indexPath: IndexPath) -> String? {

        let item = self.dataSource.itemIdentifier(for: indexPath)
        switch item {
        case .conversation(let conversationId):
            return conversationId
        case .none:
            return nil
        }
    }

    func conversationListCollectionViewLayout(_ layout: ConversationListCollectionViewLayout,
                                              didUpdateCentered conversationId: String?) {

        self.updateUI(withCenteredConversationId: conversationId)
    }

    /// A task for updating the message input accessory.
    private var messageInputTask: Task<Void, Never>?
    /// A task to become or resign first responder status.
    private var firstResponderTask: Task<Void, Never>?

    private func updateUI(withCenteredConversationId conversationId: String?) {
        self.messageInputTask?.cancel()
        self.firstResponderTask?.cancel()

        // Reset the input accessory view.
        self.messageInputController.updateSwipeHint(shouldPlay: false)

        if let conversationId,
           let controller = JibberMessagingClient.shared.conversationController(for: conversationId) {
            
            // Sets the active conversation
            ConversationsManager.shared.activeConversation = controller.conversation
            ConversationsManager.shared.activeController = controller

            self.messageInputTask = Task { [weak self] in
                guard let conversation = controller.conversation else { return }
                let people = await JibberMessagingClient.shared.getPeople(for: conversation)

                guard !Task.isCancelled else { return }

                self?.messageInputController.swipeInputView.textView.setPlaceholder(for: people,
                                                                                    isReply: false)
                self?.messageInputController.updateSwipeHint(shouldPlay: true)
            }

            self.firstResponderTask = Task { [weak self] in
                await Task.sleep(seconds: 0.25)

                guard !Task.isCancelled else { return }

                // The input accessory view should be shown when centered on a conversation. If there's not
                // already set as first responder, then make the VC first responder.
                if UIResponder.firstResponder.isNil {
                    self?.becomeResponder()
                }
            }
        } else {
            ConversationsManager.shared.activeConversation = nil
            ConversationsManager.shared.activeController = nil

            self.messageInputController.updateSwipeHint(shouldPlay: true)

            self.firstResponderTask = Task {
                await Task.sleep(seconds: 0.25)

                guard !Task.isCancelled else { return }

                // Hide the keyboard and accessory view when we're not centered on a conversation.
                UIResponder.firstResponder?.resignResponder()
            }
        }
    }
}

// MARK: - MessageSendingViewControllerType

extension ConversationViewController: MessageSendingViewControllerType {

    func getCurrentMessageSequence() -> MessageSequence? {
        return self.getCurrentConversationController()?.messageSequence
    }

    func set(messageSequencePreparingToSend: MessageSequence?) {
        self.dataSource.set(conversationPreparingToSend: messageSequencePreparingToSend?.id)
    }

    func sendMessage(_ message: MessageSendable) async throws {
        guard let conversationController = self.getCurrentConversationController() else { return }
        _ = try await conversationController.createNewMessage(with: message)
    }
}

// MARK: - TransitionableViewController

extension ConversationViewController: TransitionableViewController {

    var presentationType: TransitionType {
        return .modal
    }

    func getFromVCPresentationType(for toVCPresentationType: TransitionType) -> TransitionType {
        switch toVCPresentationType {
        case .custom(type: let type, _, _):
            guard type == "message", let messageContent = self.getCentmostMessageCellContent() else { return toVCPresentationType }
            return .custom(type: "message", model: messageContent, duration: Theme.animationDurationSlow)
        default:
            break
        }

        return toVCPresentationType
    }

    func getToVCDismissalType(for fromVCDismissalType: TransitionType) -> TransitionType {
        switch fromVCDismissalType {
        case .custom(type: let type, _, _):
            guard type == "message", let messageContent = self.getCentmostMessageCellContent() else { return fromVCDismissalType }
            return .custom(type: "message", model: messageContent, duration: Theme.animationDurationSlow)
        default:
            break
        }

        return fromVCDismissalType
    }

    func getCentmostMessageCellContent() -> MessageContentView? {
        guard let messagesCell = self.collectionView.getCentermostVisibleCell() as? ConversationMessagesCell else {
            return nil
        }

        return messagesCell.getFrontmostCell()?.content
    }
}

extension ConversationViewController: MessageInteractableController {
    
    var messageContent: MessageContentView? {
        return self.getCentmostMessageCellContent()
    }
    
    func handleDismissal() {}
    func handleInitialDismissal() {}
    func handleFinalPresentation() {}
    func handlePresentationCompleted() {}
    func handleCompletedDismissal() {}
}
