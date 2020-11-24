//
//  FeedCollectionViewManager.swift
//  Benji
//
//  Created by Benji Dodgson on 7/28/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation

class FeedManager: NSObject {

    private var items: [FeedType] = []

    var didComplete: (FeedType) -> Void = { _ in }
    var didFinish: CompletionOptional = nil
    var didShowCardAtIndex: ((Int) -> Void)?
    private var currentCard: FeedView?

    override init() {
        super.init()
        self.initialize()
    }

    private func initialize() {

    }

    func set(items: [FeedType]) {
        self.items = items
//        self.collectionView.reloadData()
//        self.collectionView.layoutNow()
    }

    func reload() {
//        self.collectionView.resetCurrentCardIndex()
//        self.collectionView.reloadData()
    }
}

//extension FeedManager: KolodaViewDataSource {

//    func kolodaNumberOfCards(_ koloda: KolodaView) -> Int {
//        return self.items.count
//    }
//
//    func kolodaSpeedThatCardShouldDrag(_ koloda: KolodaView) -> DragSpeed {
//        return .slow
//    }
//
//    func koloda(_ koloda: KolodaView, viewForCardAt index: Int) -> UIView {
//        guard let item = self.items[safe: index] else { return UIView() }
//
//        let feedView = FeedView()
//        feedView.configure(with: item)
//
//        feedView.didComplete = {
//            koloda.swipe(.right)
//            self.didComplete(item)
//        }
//        return feedView
//    }
//}

//extension FeedManager: KolodaViewDelegate {

//    func koloda(_ koloda: KolodaView, allowedDirectionsForIndex index: Int) -> [SwipeResultDirection] {
//        return [.left, .right]
//    }
//
//    func koloda(_ koloda: KolodaView, didSelectCardAt index: Int) {}
//
//    func koloda(_ koloda: KolodaView, didSwipeCardAt index: Int, in direction: SwipeResultDirection) { }
//
//    func kolodaShouldApplyAppearAnimation(_ koloda: KolodaView) -> Bool {
//        return false
//    }
//
//    func kolodaDidRunOutOfCards(_ koloda: KolodaView) {
//        self.didFinish?()
//    }
//
//    func koloda(_ koloda: KolodaView, didShowCardAt index: Int) {
//        if let view = koloda.viewForCard(at: index) {
//            view.layoutNow()
//        }
//        self.didShowCardAtIndex?(index)
//    }
//
//    func koloda(_ koloda: KolodaView, viewForCardOverlayAt index: Int) -> OverlayView? {
//        return nil
//    }
//
//    func kolodaShouldTransparentizeNextCard(_ koloda: KolodaView) -> Bool {
//        return false
//    }
//}
