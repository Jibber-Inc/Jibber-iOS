//
//  ThreadViewController.swift
//  Benji
//
//  Created by Benji Dodgson on 12/27/18.
//  Copyright © 2018 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Coordinator
import ParseCore
import Combine
import KeyboardManager
import Transitions

class ThreadViewController: DiffableCollectionViewController<MessageSequenceSection,
                            MessageSequenceItem,
                            RepliesSequenceCollectionViewDataSource>,
                            MessageInteractableController,
                            SwipeableInputControllerHandler {
    
    
    var swipeableVC: SwipeableInputAccessoryViewController {
        return self.messageInputController
    }
    
    var blurView = DarkBlurView()
    let parentMessageView = MessageContentView()
    private lazy var parentMessageContextMenuDelegate = MessageContentContextMenuDelegate(
        content: self.parentMessageView,
        allowsThreadNavigation: false
    )
    
    var isPresentingImage: Bool = false
    
    var messageContent: MessageContentView? {
        if let first = self.collectionView.indexPathsForSelectedItems?.first,
           let cell = self.collectionView.cellForItem(at: first) as? MessageCell {
            return cell.content
        } else {
            return self.parentMessageView
        }
    }

    weak var messageContentDelegate: MessageContentDelegate? {
        get { return self.dataSource.messageContentDelegate }
        set {
            self.dataSource.messageContentDelegate = newValue
            self.parentMessageView.delegate = newValue
        }
    }

    /// If true we should scroll to the last item in the collection in layout subviews.
    private var scrollToLastItemOnLayout: Bool = true
    
    private let threadCollectionView = ThreadCollectionView()

    /// A controller for the message that all the replies in this thread are responding to.
    let messageController: ParseMessageController
    var parentMessage: ParseMessage? {
        return self.messageController.message
    }
    /// The reply to show when this view controller initially loads its data.
    private let startingReplyId: String?
    private var resolvedStartingReplyId: String?

    private(set) var conversationController: ParseConversationController?
    let pullView = PullView()

    var indexPathForEditing: IndexPath?

    var inputTextView: InputTextView {
        return self.messageInputController.swipeInputView.textView
    }

    // Custom Input Accessory View
    lazy var messageInputController: SwipeableInputAccessoryViewController = {
        let inputController = SwipeableInputAccessoryViewController()
        inputController.delegate = self.swipeInputDelegate
        inputController.swipeInputView.textView.restorationIdentifier = "thread"
        return inputController
    }()
    lazy var swipeInputDelegate
    = SwipeableInputAccessoryMessageSender(viewController: self, collectionView: self.threadCollectionView)

    override var inputAccessoryViewController: UIInputViewController? {
        return self.messageInputController
    }

    override var canBecomeFirstResponder: Bool {
        return self.presentedViewController.isNil
    }

    lazy var dismissInteractionController: PanDismissInteractionController? = PanDismissInteractionController(viewController: self)

    @Published var state: ConversationUIState = .read

    init(message: Messageable, startingReplyId: String?) {
       
        guard let controller = ParseMessageController.controller(for: message) else {
            preconditionFailure("A thread requires a valid Parse conversation and message ID.")
        }
        ConversationsManager.shared.activeController = controller
        self.messageController = controller
        
        self.conversationController = ParseConversationController.controller(for: message.conversationId)

        self.startingReplyId = startingReplyId
        self.resolvedStartingReplyId = nil
        
        super.init(with: self.threadCollectionView)

        self.dataSource.messageSequenceController = self.messageController
        self.threadCollectionView.threadLayout.messageDataSource = self.dataSource
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func initializeViews() {
        super.initializeViews()
                
        self.modalPresentationStyle = .overCurrentContext

        self.view.insertSubview(self.blurView, belowSubview: self.collectionView)
        self.view.addSubview(self.parentMessageView)
        self.parentMessageView.bubbleView.addInteraction(
            UIContextMenuInteraction(delegate: self.parentMessageContextMenuDelegate)
        )
        
        self.view.addSubview(self.pullView)

        self.collectionView.clipsToBounds = false
        self.configureCollectionLayout(for: .read)

        self.dismissInteractionController?.handleCollectionViewPan(for: self.collectionView)
        self.dismissInteractionController?.handlePan(for: self.parentMessageView)
        self.dismissInteractionController?.handlePan(for: self.pullView)
        
        KeyboardManager.shared.$currentEvent
            .mainSink { [weak self] currentEvent in
                guard let self else { return }
                switch currentEvent {
                case .willShow:
                    self.state = .write
                case .willHide:
                    self.state = .read
                default:
                    break
                }
            }.store(in: &self.cancellables)
        
        self.$state
            .removeDuplicates()
            .mainSink { [unowned self] state in
                self.updateUI(for: state, forceLayout: false)
            }.store(in: &self.cancellables)
        
        self.collectionView.allowsMultipleSelection = false
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        self.blurView.expandToSuperviewSize()
        
        self.pullView.pin(.top, offset: .standard)
        self.pullView.centerOnX()

        self.parentMessageView.match(.top, to: .bottom, of: self.pullView)
        self.parentMessageView.centerOnX()
    }

    override func layoutCollectionView(_ collectionView: UICollectionView) {
        collectionView.expandToSuperviewHeight()
        collectionView.width = self.view.width - Theme.ContentOffset.xtraLong.value.doubled
        collectionView.centerOnX()

        if self.scrollToLastItemOnLayout {
            self.scrollToLastItemOnLayout = false
            self.threadCollectionView.threadLayout.prepare()
            let maxOffset = self.threadCollectionView.threadLayout.maxZPosition
            self.threadCollectionView.setContentOffset(CGPoint(x: 0, y: maxOffset), animated: false)
            self.threadCollectionView.threadLayout.invalidateLayout()
        }
    }
    
    @MainActor
    func scrollToConversation(with conversationId: String,
                              messageId: String?,
                              viewReplies: Bool = false,
                              animateScroll: Bool,
                              animateSelection: Bool) async {
        guard let messageId = messageId else { return }

        try? await self.messageController.loadPreviousReplies(including: messageId)
        guard let resolvedMessageID = self.messageController
            .getMessage(withId: messageId)?.id else { return }
        let messageItem = MessageSequenceItem.message(messageId: resolvedMessageID)

        guard let messageIndexPath = self.dataSource.indexPath(for: messageItem) else { return }

        let threadLayout = self.threadCollectionView.threadLayout
        let yOffset = threadLayout.focusPosition(for: messageIndexPath)

        self.collectionView.setContentOffset(CGPoint(x: 0, y: yOffset), animated: animateScroll)

        if animateSelection, let cell = self.collectionView.cellForItem(at: messageIndexPath) {
            await UIView.awaitAnimation(with: .fast, animations: {
                cell.transform = CGAffineTransform.init(scaleX: 1.05, y: 1.05)
            })

            await UIView.awaitAnimation(with: .fast, animations: {
                cell.transform = .identity
            })
        }
    }
    
    func updateUI(for state: ConversationUIState, forceLayout: Bool) {
        guard !self.isBeingOpen && !self.isBeingClosed else { return }

        self.configureCollectionLayout(for: state)

        Task {
            await self.dataSource.reconfigureAllItems()
            if state == .write {
                let maxOffset = self.threadCollectionView.threadLayout.maxZPosition
                self.collectionView.setContentOffset(CGPoint(x: 0, y: maxOffset), animated: true)
            }
        }
    }

    private func configureCollectionLayout(for state: ConversationUIState) {
        let threadLayout = self.threadCollectionView.threadLayout
        threadLayout.itemHeight
        = MessageContentView.bubbleHeight + Theme.ContentOffset.long.value
        
        switch state {
        case .read:
            let topOfStack = UIWindow.topWindow()!.safeAreaInsets.top + PullView.height + threadLayout.itemHeight + 20
            threadLayout.topOfStackY = topOfStack
            threadLayout.spacingKeyPoints = [0, 20, 40, 64]
            
            UIView.animate(withDuration: Theme.animationDurationFast) {
                self.parentMessageView.alpha = 1.0
            } completion: { _ in
                self.view.bringSubviewToFront(self.parentMessageView)
                self.view.bringSubviewToFront(self.pullView)
            }

        case .write:
            let topOfStack = self.pullView.bottom
            threadLayout.topOfStackY = topOfStack
            threadLayout.spacingKeyPoints = [0, 8, 14, 16]
            
            UIView.animate(withDuration: Theme.animationDurationFast) {
                self.parentMessageView.alpha = 0
            } completion: { _ in
                self.view.bringSubviewToFront(self.collectionView)
                self.view.bringSubviewToFront(self.pullView)
            }
        }
    }

    // MARK: Data Loading

    override func getAllSections() -> [MessageSequenceSection] {
        return [.messages]
    }

    override func retrieveDataForSnapshot() async -> [MessageSequenceSection : [MessageSequenceItem]] {
        var data: [MessageSequenceSection: [MessageSequenceItem]] = [:]

        do {
            try await self.messageController.loadPreviousReplies()

            if let startingReplyId = self.startingReplyId {
                try await self.messageController.loadPreviousReplies(including: startingReplyId)
                self.resolvedStartingReplyId = self.messageController
                    .getMessage(withId: startingReplyId)?.id
            }

            // Thread replies are loaded after the data source is constructed.
            // Refresh its message index before applying the initial diffable
            // snapshot so every item identifier can synchronously resolve a
            // cell when UICollectionView asks for it.
            self.dataSource.messageSequenceController = self.messageController

            let messages = self.messageController.replies.map { message in
                return MessageSequenceItem.message(messageId: message.id)
            }
            data[.messages] = Array(messages)
        } catch {
            await ToastScheduler.shared.schedule(toastType: .error(error))
            logError(error)
        }
        
        return data
    }

    override func collectionViewDataWasLoaded() {
        super.collectionViewDataWasLoaded()

        self.subscribeToUpdates()
        
        if let replyId = self.resolvedStartingReplyId {
            Task {
                await self.scrollToConversation(with: self.messageController.conversation!.id,
                                                messageId: replyId,
                                                animateScroll: false,
                                                animateSelection: false)
            }
        }
        
        self.scrollToLastItemOnLayout = self.resolvedStartingReplyId == nil
        self.view.layoutNow()
    }

    override func getAnimationCycle(with snapshot: NSDiffableDataSourceSnapshot<MessageSequenceSection,
                                    MessageSequenceItem>) -> AnimationCycle? {

        let startMessageIndex: Int
        if let startingReplyId = self.resolvedStartingReplyId {
            startMessageIndex
            = snapshot.indexOfItem(.message(messageId: startingReplyId)) ?? 0
        } else {
            startMessageIndex = self.messageController.replies.count - 1
        }

        let layout = self.threadCollectionView.threadLayout
        let scrollToOffset = CGPoint(x: 0, y: layout.itemHeight * CGFloat(startMessageIndex))
        return AnimationCycle(inFromPosition: nil,
                              outToPosition: nil,
                              shouldConcatenate: false,
                              scrollToOffset: scrollToOffset)
    }
}
// MARK: - Messaging

extension ThreadViewController: MessageSendingViewControllerType {

    func getCurrentMessageSequence() -> MessageSequence? {
        return self.parentMessage
    }

    func set(messageSequencePreparingToSend: MessageSequence?) {
        self.dataSource.shouldPrepareToSend = messageSequencePreparingToSend.exists

        self.dataSource.set(messagesController: self.messageController)
    }

    func sendMessage(_ message: MessageSendable) async throws {
        try await self.messageController.createNewReply(with: message)
    }
}

// MARK: - TransitionableViewController

extension ThreadViewController: TransitionableViewController {

    var presentationType: TransitionType {
        return .custom(type: "message", model: self.parentMessageView, duration: Theme.animationDurationSlow)
    }

    var dismissalType: TransitionType {
        return .custom(type: "message", model: self.parentMessageView, duration: Theme.animationDurationSlow)
    }

    func getFromVCPresentationType(for toVCPresentationType: TransitionType) -> TransitionType {
        switch toVCPresentationType {
        case .custom(type: let type, _, _):
            guard type == "message",
                  !self.isPresentingImage,
                  let first = self.collectionView.indexPathsForSelectedItems?.first,
                  let cell = self.collectionView.cellForItem(at: first) as? MessageCell else { return toVCPresentationType }
            return .custom(type: "message", model: cell.content, duration: Theme.animationDurationSlow)
        default:
            break
        }
        
        return toVCPresentationType
    }

    func getToVCDismissalType(for fromVCDismissalType: TransitionType) -> TransitionType {
        switch fromVCDismissalType {
        case .custom(type: let type, _, _):
            guard type == "message",
                  !self.isPresentingImage,
                  let first = self.collectionView.indexPathsForSelectedItems?.first,
                  let cell = self.collectionView.cellForItem(at: first) as? MessageCell
            else { return fromVCDismissalType }
            return .custom(type: "message", model: cell.content, duration: Theme.animationDurationSlow)
        default:
            break
        }
        
        return fromVCDismissalType
    }
    
    func handleFinalPresentation() { }
    
    func handlePresentationCompleted() {
        guard self.messageController.message.exists else { return }
        self.loadInitialData()
    }
    
    func handleInitialDismissal() {
        self.collectionView.alpha = 0
        self.pullView.alpha = 0.0
    }
    
    func handleDismissal() {
        self.pullView.bottom = self.parentMessageView.top
    }
    
    func handleCompletedDismissal() {
        if let selectedIndexPath = self.collectionView.indexPathsForSelectedItems?.first {
            self.collectionView.deselectItem(at: selectedIndexPath, animated: false)
        }
    }
}

// MARK: - Updates and Subscription

extension ThreadViewController {

    func subscribeToUpdates() {
        self.collectionView.backView.didSelect { [unowned self] in
            if self.messageInputController.swipeInputView.textView.isFirstResponder {
                self.messageInputController.swipeInputView.textView.resignFirstResponder()
            } else {
                self.messageInputController.swipeInputView.textView.becomeFirstResponder()
            }
        }

        self.messageInputController.swipeInputView.textView.$inputText
            .map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .throttle(for: .seconds(3), scheduler: DispatchQueue.main, latest: true)
            .mainSink { [unowned self] isTyping in
                do {
                    try self.conversationController?.setTyping(isTyping)
                } catch {
                    logError(error)
                }
            }.store(in: &self.cancellables)

        self.messageController.messageChangePublisher.mainSink { [unowned self] _ in
            guard let msg = self.messageController.message else { return }
            self.parentMessageView.configure(with: msg)
        }.store(in: &self.cancellables)

        self.messageController.repliesChangesPublisher.mainSink { [unowned self] changes in
            var itemsToReconfigure: [MessageSequenceItem] = []

            for change in changes {
                switch change {
                case .update(let message, _):
                    guard !message.isDeleted else { break }
                    itemsToReconfigure.append(.message(messageId: message.id))
                default:
                    break
                }
            }

            self.dataSource.set(messagesController: self.messageController,
                                itemsToReconfigure: itemsToReconfigure)
        }.store(in: &self.cancellables)

        let members = self.messageController.message?.threadParticipants.filter { member in
            return member.personId != User.current()?.objectId
        } ?? []

        self.messageInputController.swipeInputView.textView.setPlaceholder(for: members, isReply: true)
    }
}
