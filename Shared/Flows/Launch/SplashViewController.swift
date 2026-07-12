//
//  SplashViewController.swift
//  Benji
//
//  Created by Benji Dodgson on 8/20/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Lottie
import StoreKit
import Localization
import Transitions

class SplashViewController: ViewController, TransitionableViewController {    

    // MARK: - Transitionable
    
    var presentationType: TransitionType {
        return .fadeOutIn
    }

    var dismissalType: TransitionType {
        return self.presentationType
    }

    func getFromVCPresentationType(for toVCPresentationType: TransitionType) -> TransitionType {
        return toVCPresentationType
    }

    func getToVCDismissalType(for fromVCDismissalType: TransitionType) -> TransitionType {
        return fromVCDismissalType
    }
    
    /// A view to blur out the emotions collection view.
    let blurView = DarkBlurView()
    private lazy var emotionCollectionView = EmotionCircleCollectionView(cellDiameter: 100)

    let loadingView = LottieAnimationView.with(animation: .loading)

    override func initializeViews() {
        super.initializeViews()

        self.view.addSubview(self.emotionCollectionView)
        self.view.addSubview(self.blurView)

        self.view.addSubview(self.loadingView)
        self.loadingView.contentMode = .scaleAspectFit
        self.loadingView.loopMode = .loop
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        self.emotionCollectionView.expandToSuperviewSize()
        self.blurView.expandToSuperviewSize()

        self.loadingView.size = CGSize(width: 18, height: 18)
        self.loadingView.pinToSafeAreaRight()
        let offset: CGFloat = self.view.safeAreaInsets.bottom == 0 ? Theme.ContentOffset.xtraLong.value : 0
        self.loadingView.pinToSafeArea(.bottom, offset: .custom(offset))
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        self.stopLoadAnimation()
    }

    func startLoadAnimation() {
        self.loadingView.play()

        Task { [weak self] in
            guard let self else { return }
            await Task.sleep(seconds: 0.25)
            
            guard !Task.isCancelled else { return }
            
            await self.animateEmotions()
        }.add(to: self.autocancelTaskPool)
    }

    private func animateEmotions() async {
        guard !Task.isCancelled else { return }
        
        let emotions = Emotion.allCases.random(Int.random(min: 1, max: 4))
        var emotionsCounts: [Emotion : Int] = [:]
        for emotion in emotions {
            emotionsCounts[emotion] = Int.random(min: 1, max: 3)
        }

        self.emotionCollectionView.setEmotionsCounts(emotionsCounts, animated: true)

        await Task.sleep(seconds: 5)

        Task { [weak self] in
            await self?.animateEmotions()
        }.add(to: self.autocancelTaskPool)
    }

    func stopLoadAnimation() {
        self.loadingView.stop()
        self.autocancelTaskPool.cancelAndRemoveAll()
    }
}
