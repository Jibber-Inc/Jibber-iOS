//
//  ConversationTimelineSurface.swift
//  Jibber
//
//  Shared conversation presentation primitives used by both the full app and
//  the App Clip. Parse-backed messaging remains an adapter layered on top.
//

import UIKit

/// Optional conversation behaviors that may be enabled for a timeline.
///
/// Onboarding keeps only passive message timestamps. This preserves the exact
/// production message header while preventing interactive messaging affordances
/// from leaking into verification and profile collection.
struct ConversationCapabilities: OptionSet, Sendable {
    let rawValue: UInt16

    static let replies = ConversationCapabilities(rawValue: 1 << 0)
    static let reactions = ConversationCapabilities(rawValue: 1 << 1)
    static let expressions = ConversationCapabilities(rawValue: 1 << 2)
    static let attachments = ConversationCapabilities(rawValue: 1 << 3)
    static let contextMenus = ConversationCapabilities(rawValue: 1 << 4)
    static let typingIndicators = ConversationCapabilities(rawValue: 1 << 5)
    static let unreadControls = ConversationCapabilities(rawValue: 1 << 6)
    static let deliveryMetadata = ConversationCapabilities(rawValue: 1 << 7)
    static let timestamps = ConversationCapabilities(rawValue: 1 << 8)

    static let production: ConversationCapabilities = [
        .replies,
        .reactions,
        .expressions,
        .attachments,
        .contextMenus,
        .typingIndicators,
        .unreadControls,
        .deliveryMetadata,
        .timestamps
    ]
    static let onboarding: ConversationCapabilities = [.timestamps]
}

/// A stable, provider-neutral item in a conversation timeline.
///
/// `message` can be a local pre-auth model or a Parse-backed message. Identity
/// is intentionally separate from the model so temporary items can reconcile
/// with their server equivalents without replacing the visible cell.
struct ConversationTimelineEntry: Hashable, TimeMachineLayoutItemType {
    let id: String
    let date: Date
    let message: Messageable
    let progressOrdinal: Int?

    init(
        id: String? = nil,
        date: Date? = nil,
        message: Messageable,
        progressOrdinal: Int? = nil
    ) {
        self.id = id ?? message.id
        self.date = date ?? message.createdAt
        self.message = message
        self.progressOrdinal = progressOrdinal
    }

    var stableID: String? { self.id }

    static func == (lhs: ConversationTimelineEntry, rhs: ConversationTimelineEntry) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
    }
}

enum ConversationTimelineRefreshPolicy {
    static func shouldApply(
        currentIDs: [String],
        nextIDs: [String],
        containsPersistedEntries: Bool,
        forcesContentRefresh: Bool
    ) -> Bool {
        forcesContentRefresh
            || containsPersistedEntries
            || currentIDs != nextIDs
    }
}

/// Supplies either local or remote messages to the shared Time Machine.
/// Entries must be ordered oldest to newest to match the production rail.
@MainActor
protocol ConversationTimelineProviding: AnyObject {
    var timelineEntries: [ConversationTimelineEntry] { get }
}

/// Shared configuration for the Time Machine geometry. Production supplies its
/// existing message/footer height; onboarding can provide a content-specific
/// height while retaining the identical scale, spacing and snapping behavior.
struct ConversationTimeMachineConfiguration: Equatable, Sendable {
    var itemHeight: CGFloat
    var stackDepth: Int
    var scalingKeyPoints: [CGFloat]
    var spacingKeyPoints: [CGFloat]
    var alphaKeyPoints: [CGFloat]
    var topOfStackY: CGFloat

    init(
        itemHeight: CGFloat,
        stackDepth: Int = 3,
        scalingKeyPoints: [CGFloat] = [1, 0.84, 0.65, 0.4],
        spacingKeyPoints: [CGFloat] = [0, 8, 16, 20],
        alphaKeyPoints: [CGFloat] = [1, 1, 0.75, 0],
        topOfStackY: CGFloat = 0
    ) {
        precondition(itemHeight > 0, "Time Machine items must have a positive height.")
        self.itemHeight = itemHeight
        self.stackDepth = stackDepth
        self.scalingKeyPoints = scalingKeyPoints
        self.spacingKeyPoints = spacingKeyPoints
        self.alphaKeyPoints = alphaKeyPoints
        self.topOfStackY = topOfStackY
    }

    @MainActor
    func apply(to layout: TimeMachineCollectionViewLayout) {
        layout.itemHeight = self.itemHeight
        layout.stackDepth = self.stackDepth
        layout.scalingKeyPoints = self.scalingKeyPoints
        layout.spacingKeyPoints = self.spacingKeyPoints
        layout.alphaKeyPoints = self.alphaKeyPoints
        layout.topOfStackY = self.topOfStackY
    }
}

/// Message-aware presentation attributes shared by production and onboarding.
class ConversationMessageCellLayoutAttributes: UICollectionViewLayoutAttributes {

    var brightness: CGFloat = 1 {
        didSet { self.equalityBrightness = self.brightness }
    }
    var detailAlpha: CGFloat = 0 {
        didSet { self.equalityDetailAlpha = self.detailAlpha }
    }

    nonisolated(unsafe) private var equalityBrightness: CGFloat = 1
    nonisolated(unsafe) private var equalityDetailAlpha: CGFloat = 0

    override func copy(with zone: NSZone? = nil) -> Any {
        let copy = super.copy(with: zone) as! ConversationMessageCellLayoutAttributes
        copy.brightness = self.brightness
        copy.detailAlpha = self.detailAlpha
        return copy
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let attributes = object as? ConversationMessageCellLayoutAttributes else {
            return false
        }
        return super.isEqual(object)
            && attributes.equalityBrightness == self.equalityBrightness
            && attributes.equalityDetailAlpha == self.equalityDetailAlpha
    }
}

/// The shared message specialization of the Time Machine layout. Production's
/// layout subclasses this to add new-message auto-follow behavior; onboarding
/// uses it directly, including the exact same brightness/detail interpolation.
class ConversationTimeMachineCollectionViewLayout: TimeMachineCollectionViewLayout {

    override class var layoutAttributesClass: AnyClass {
        ConversationMessageCellLayoutAttributes.self
    }

    var frontmostBrightness: CGFloat = 1
    var backmostBrightness: CGFloat {
        self.frontmostBrightness - CGFloat(self.stackDepth + 1) * 0.2
    }

    override func layoutAttributesForItemAt(
        indexPath: IndexPath,
        withNormalizedZOffset normalizedZOffset: CGFloat
    ) -> UICollectionViewLayoutAttributes? {
        let attributes = super.layoutAttributesForItemAt(
            indexPath: indexPath,
            withNormalizedZOffset: normalizedZOffset
        )
        guard let messageAttributes = attributes as? ConversationMessageCellLayoutAttributes else {
            return attributes
        }

        if normalizedZOffset < 0 {
            messageAttributes.brightness = lerp(
                abs(normalizedZOffset),
                start: self.frontmostBrightness,
                end: self.backmostBrightness
            )
        } else {
            messageAttributes.brightness = self.frontmostBrightness
        }
        messageAttributes.detailAlpha = max(0, 1 - abs(normalizedZOffset) / 0.2)
        return messageAttributes
    }
}

/// The actual vertical rail shared by production and onboarding.
class ConversationTimeMachineCollectionView: CollectionView {

    var timeMachineLayout: TimeMachineCollectionViewLayout {
        guard let layout = self.collectionViewLayout as? TimeMachineCollectionViewLayout else {
            preconditionFailure("ConversationTimeMachineCollectionView requires a Time Machine layout.")
        }
        return layout
    }

    init(layout: TimeMachineCollectionViewLayout) {
        super.init(layout: layout)

        self.clipsToBounds = false
        self.showsVerticalScrollIndicator = false
        self.automaticallyAdjustsScrollIndicatorInsets = true
        self.decelerationRate = .fast
        self.keyboardDismissMode = .interactive
    }

    convenience init(configuration: ConversationTimeMachineConfiguration) {
        let layout = ConversationTimeMachineCollectionViewLayout(
            itemHeight: configuration.itemHeight
        )
        configuration.apply(to: layout)
        self.init(layout: layout)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var continuousFocusedPosition: CGFloat {
        self.timeMachineLayout.continuousFocusedPosition
    }

    func focus(
        itemAt index: Int,
        animated: Bool
    ) {
        guard index >= 0,
              index < self.numberOfItems(inSection: 0) else { return }
        let offset = CGPoint(
            x: self.contentOffset.x,
            y: self.timeMachineLayout.focusPosition(
                for: IndexPath(item: index, section: 0)
            )
        )
        self.setContentOffset(offset, animated: animated)
    }
}

/// Base cell used by both rich Parse messages and lightweight local onboarding
/// turns. Subclasses install their content inside `timelineContentView` and
/// receive the same brightness/detail presentation callbacks.
class ConversationTimelineCell: UICollectionViewCell {

    let timelineContentView = UIView()
    let shadowLayer = CAShapeLayer()

    private(set) var timelineEntry: ConversationTimelineEntry?
    private(set) var capabilities: ConversationCapabilities = .production

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.initializeTimelineCell()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.initializeTimelineCell()
    }

    private func initializeTimelineCell() {
        self.contentView.layer.insertSublayer(self.shadowLayer, at: 0)
        self.contentView.addSubview(self.timelineContentView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.timelineContentView.frame = self.contentView.bounds
    }

    func configure(
        with entry: ConversationTimelineEntry,
        capabilities: ConversationCapabilities
    ) {
        self.timelineEntry = entry
        let previousCapabilities = self.capabilities
        self.capabilities = capabilities
        self.didConfigure(
            with: entry.message,
            capabilitiesChanged: previousCapabilities != capabilities
        )
    }

    /// Subclasses render the provider-neutral model here. No Parse cast is
    /// required, allowing pre-auth local messages to use the shared cell shell.
    func didConfigure(
        with message: Messageable,
        capabilitiesChanged: Bool
    ) {}

    override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)
        self.layer.zPosition = CGFloat(layoutAttributes.zIndex)

        guard let attributes = layoutAttributes as? ConversationMessageCellLayoutAttributes else {
            return
        }
        self.applyTimelinePresentation(
            brightness: attributes.brightness,
            detailAlpha: attributes.detailAlpha
        )
    }

    func applyTimelinePresentation(
        brightness: CGFloat,
        detailAlpha: CGFloat
    ) {}

    override func prepareForReuse() {
        super.prepareForReuse()
        self.timelineEntry = nil
        self.capabilities = .production
    }
}

/// Provider-neutral rich message presentation shared with the production
/// `MessageCell`. It deliberately contains no Parse controller, reaction
/// mutation, reply, consumption, or context-menu behavior.
class ConversationMessagePresentationCell: ConversationTimelineCell {

    private struct AppliedPresentation: Equatable {
        let brightness: CGFloat
        let detailAlpha: CGFloat
    }

    let content = MessageContentView()

    private(set) var presentedMessage: Messageable?
    private(set) var messageTextColor: UIColor = ThemeColor.clear.color
    private var appliedPresentation: AppliedPresentation?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.initializeMessagePresentation()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.initializeMessagePresentation()
    }

    private func initializeMessagePresentation() {
        self.shadowLayer.shadowColor = ThemeColor.D6.color.cgColor
        self.shadowLayer.shadowOpacity = 1
        self.shadowLayer.shadowOffset = .zero
        self.shadowLayer.shadowRadius = 8
        self.timelineContentView.addSubview(self.content)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.content.frame = self.timelineContentView.bounds
        self.shadowLayer.shadowPath = UIBezierPath(rect: self.content.bounds).cgPath
    }

    override func didConfigure(
        with message: Messageable,
        capabilitiesChanged: Bool
    ) {
        let shouldConcealUnreadContent = self.capabilities.contains(.unreadControls)
            && message.canBeConsumed
        self.messageTextColor = shouldConcealUnreadContent
            ? ThemeColor.clear.color
            : ThemeColor.white.color

        if self.hasPresentationChanges(
            from: self.presentedMessage,
            to: message
        ) {
            self.content.configure(with: message)
        }
        self.presentedMessage = message

        self.content.textView.textColor = self.messageTextColor
        self.content.imageView.alpha = shouldConcealUnreadContent ? 0 : 1
        self.content.linkView.alpha = shouldConcealUnreadContent ? 0 : 1
        self.shadowLayer.opacity = shouldConcealUnreadContent ? 1 : 0
        self.applyMessageCapabilities()
    }

    /// Provider-neutral messages are cheap and few, and their guide/avatar can
    /// change without changing the stable message fields covered by the legacy
    /// `Messageable` equality operator. Production overrides this with its
    /// richer Parse snapshot comparison.
    func hasPresentationChanges(
        from previousMessage: Messageable?,
        to message: Messageable
    ) -> Bool {
        true
    }

    override func applyTimelinePresentation(
        brightness: CGFloat,
        detailAlpha: CGFloat
    ) {
        let presentation = AppliedPresentation(
            brightness: brightness,
            detailAlpha: detailAlpha
        )
        guard presentation != self.appliedPresentation else { return }
        self.appliedPresentation = presentation

        self.content.configureBackground(
            color: ThemeColor.B6.color,
            textColor: self.messageTextColor,
            brightness: brightness,
            showBubbleTail: false,
            tailOrientation: .down
        )
        self.content.isUserInteractionEnabled = detailAlpha == 1
        if detailAlpha < 0.5 {
            self.content.setEmotions(areShown: false, animated: true)
        }
    }

    func applyMessageCapabilities() {
        self.content.authorView.isUserInteractionEnabled = self.capabilities.contains(.expressions)
        self.content.imageView.isUserInteractionEnabled = self.capabilities.contains(.attachments)
        self.content.linkView.isUserInteractionEnabled = self.capabilities.contains(.attachments)
        self.content.deliveryView.isVisible = self.capabilities.contains(.deliveryMetadata)
        self.content.dateView.isVisible = self.capabilities.contains(.timestamps)

        if self.capabilities.contains(.reactions), let message = self.presentedMessage {
            self.content.reactionsView.configure(with: message.reactionGroups)
        } else {
            self.content.reactionsView.isVisible = false
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.content.authorView.displayable = nil
        self.content.imageView.displayable = nil
        self.content.emotionCollectionView.setEmotionsCounts([:], animated: false)
        self.content.setEmotions(areShown: false, animated: false)
        self.presentedMessage = nil
        self.messageTextColor = ThemeColor.clear.color
        self.appliedPresentation = nil
    }
}

/// A provider-driven controller for local/App Clip timelines. The production
/// conversation cell uses the same collection view and layout with its existing
/// diffable datasource adapter.
@MainActor
final class ConversationTimelineViewController: UIViewController,
                                                UICollectionViewDelegate,
                                                TimeMachineCollectionViewLayoutDataSource {

    typealias CellProvider = (
        _ collectionView: UICollectionView,
        _ indexPath: IndexPath,
        _ entry: ConversationTimelineEntry,
        _ capabilities: ConversationCapabilities
    ) -> UICollectionViewCell

    let collectionView: ConversationTimeMachineCollectionView
    var provider: ConversationTimelineProviding {
        didSet {
            guard self.isViewLoaded else { return }
            self.reloadTimeline(animatingDifferences: false)
        }
    }
    var capabilities: ConversationCapabilities {
        didSet { self.reloadTimeline(animatingDifferences: false) }
    }
    var didScrollToPosition: ((CGFloat) -> Void)?
    var didSettleOnEntry: ((ConversationTimelineEntry) -> Void)?

    private let cellProvider: CellProvider
    private var entriesByID: [String: ConversationTimelineEntry] = [:]
    private lazy var dataSource = UICollectionViewDiffableDataSource<Int, String>(
        collectionView: self.collectionView
    ) { [weak self] collectionView, indexPath, itemID in
        guard let self,
              let entry = self.entriesByID[itemID] else { return nil }
        return self.cellProvider(collectionView, indexPath, entry, self.capabilities)
    }

    init(
        provider: ConversationTimelineProviding,
        configuration: ConversationTimeMachineConfiguration,
        capabilities: ConversationCapabilities,
        cellProvider: @escaping CellProvider
    ) {
        let collectionView = ConversationTimeMachineCollectionView(configuration: configuration)
        self.collectionView = collectionView
        self.provider = provider
        self.capabilities = capabilities
        self.cellProvider = cellProvider
        super.init(nibName: nil, bundle: nil)
        collectionView.timeMachineLayout.dataSource = self
        collectionView.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        self.view = self.collectionView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.reloadTimeline(animatingDifferences: false)
    }

    func reloadTimeline(
        animatingDifferences: Bool = true,
        completion: (() -> Void)? = nil
    ) {
        let entries = self.provider.timelineEntries
        let previouslyAppliedIDs = Set(self.dataSource.snapshot().itemIdentifiers)
        self.entriesByID = entries.reduce(into: [:]) { entriesByID, entry in
            entriesByID[entry.id] = entry
        }

        var seenIDs = Set<String>()
        let orderedIDs = entries.compactMap { entry -> String? in
            guard seenIDs.insert(entry.id).inserted else { return nil }
            return entry.id
        }

        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(orderedIDs, toSection: 0)
        snapshot.reconfigureItems(orderedIDs.filter(previouslyAppliedIDs.contains))
        self.dataSource.apply(
            snapshot,
            animatingDifferences: animatingDifferences,
            completion: completion
        )
    }

    /// Resolves an entry against the snapshot that is actually on screen.
    /// Provider order can advance again while an asynchronous Parse refresh is
    /// applying, so callers that restore focus should not index the provider
    /// directly after the diffable completion fires.
    func appliedIndex(forEntryID entryID: String) -> Int? {
        self.dataSource.snapshot().itemIdentifiers.firstIndex(of: entryID)
    }

    func getTimeMachineItem(forItemAt indexPath: IndexPath) -> TimeMachineLayoutItemType {
        guard let itemID = self.dataSource.itemIdentifier(for: indexPath),
              let entry = self.entriesByID[itemID] else {
            return MissingTimelineItem()
        }
        return entry
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        self.didScrollToPosition?(self.collectionView.continuousFocusedPosition)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !decelerate else { return }
        self.notifySettledEntry()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        self.notifySettledEntry()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        self.notifySettledEntry()
    }

    private func notifySettledEntry() {
        guard let indexPath = self.collectionView.timeMachineLayout.getFrontmostIndexPath(),
              let itemID = self.dataSource.itemIdentifier(for: indexPath),
              let entry = self.entriesByID[itemID] else { return }
        self.didSettleOnEntry?(entry)
    }
}

private struct MissingTimelineItem: TimeMachineLayoutItemType {
    let date: Date = .distantPast
    let stableID: String? = nil
}
