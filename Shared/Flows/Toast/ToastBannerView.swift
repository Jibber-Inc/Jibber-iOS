//
//  ToastBannerView.swift
//  Jibber
//
//  Created by Benji Dodgson on 5/3/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Localization
import UIKit

class ToastBannerView: ToastView {
    
    private static let personHeight: CGFloat = 38
    private static let padding: Theme.ContentOffset = .long
    private let minimumHeight: CGFloat = ToastBannerView.padding.value.doubled + ToastBannerView.personHeight

    private let blurView = BlurView()
    private let titleLabel = ThemeLabel(font: .regularBold, textColor: .white)
    private let descriptionLabel = ThemeLabel(font: .small, textColor: .white)
    private let imageView = BorderedPersonView()

    let leftAnimator = UIViewPropertyAnimator(duration: 0.35,
                                              dampingRatio: 0.9,
                                              animations: nil)

    let expandAnimator = UIViewPropertyAnimator(duration: 0.35,
                                                dampingRatio: 0.9,
                                                animations: nil)

    private var title: Localized? {
        didSet {
            guard let text = self.title else { return }
            self.titleLabel.setText(text)
            self.layoutNow()
        }
    }

    private var descriptionText: Localized? {
        didSet {
            guard let text = self.descriptionText else { return }
            self.descriptionLabel.setText(text)
            self.layoutNow()
        }
    }

    override func initializeSubviews() {
        super.initializeSubviews()

        self.addSubview(self.blurView)
        self.addSubview(self.imageView)
        self.addSubview(self.descriptionLabel)
        self.addSubview(self.titleLabel)

        self.imageView.imageView.tintColor = ThemeColor.white.color

        self.descriptionLabel.alpha = 0
        self.titleLabel.alpha = 0

        self.descriptionText = localized(self.toast.description)
        self.title = self.toast.title
        self.imageView.displayable = self.toast.displayable
    }

    override func didReveal() {
        self.moveLeft()
    }

    private func moveLeft() {
        self.layoutNow()

        self.leftAnimator.stopAnimation(true)
        self.leftAnimator.addAnimations { [unowned self] in
            self.state = .left
        }

        self.leftAnimator.addCompletion({ [unowned self] (position) in
            if position == .end {
                self.expand()
            }
        })
        self.leftAnimator.startAnimation()
    }

    private func expand() {
        self.layoutNow()

        self.expandAnimator.stopAnimation(true)
        self.expandAnimator.addAnimations { [unowned self] in
            self.state = .expanded
            self.layoutNow()
        }

        self.expandAnimator.addAnimations({ [unowned self] in
            self.state = .alphaIn
        }, delayFactor: 0.5)

        self.expandAnimator.addCompletion({ [unowned self] (position) in
            if position == .end {
                Task {
                    await Task.sleep(seconds: self.toast.duration)

                    guard !Task.isCancelled, self.state != .gone else { return }

                    self.dismiss()
                }.add(to: self.taskPool)
            }
        })

        self.expandAnimator.startAnimation(afterDelay: 0.2)
    }

    override func dismiss() {
        super.dismiss()

        self.expandAnimator.stopAnimation(true)
        self.leftAnimator.stopAnimation(true)
    }

    override func update(for state: ToastState) {
        super.update(for: state)

        #if !NOTIFICATION
        guard let superView = UIWindow.topWindow() else { return }
        let usesCompactScreenLayout = superView.windowScene?.screen.isSmallerThan(screenSize: .tablet)
            ?? (self.traitCollection.userInterfaceIdiom == .phone)
        switch state {
        case .hidden:
            self.width = ToastBannerView.personHeight + ToastBannerView.padding.value.doubled
            self.maxHeight = self.minimumHeight
            self.centerOnX()
        case .left:
            if usesCompactScreenLayout {
                self.left = ToastBannerView.padding.value
            } else {
                self.left = superView.width * 0.175
            }
        case .expanded:
            self.maxHeight = nil
            if usesCompactScreenLayout {
                self.width = superView.width - ToastBannerView.padding.value.doubled
            } else {
                self.width = superView.width * Theme.iPadPortraitWidthRatio
            }
        case .alphaIn:
            self.descriptionLabel.alpha = 1
            self.titleLabel.alpha = 1
        case .present, .dismiss, .gone:
            break 
        }
        #endif
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        self.blurView.expandToSuperviewSize()
        self.blurView.roundCorners()

        self.imageView.setSize(forHeight: ToastBannerView.personHeight)
        self.imageView.pin(.left, offset: ToastBannerView.padding)
        self.imageView.pin(.top, offset: ToastBannerView.padding)

        if self.imageView.displayable is UIImage {
            self.imageView.layer.borderColor = ThemeColor.clear.color.cgColor
            self.imageView.layer.borderWidth = 0
            self.imageView.set(backgroundColor: .clear)
        }
        
        self.imageView.layer.masksToBounds = true
        self.imageView.layer.cornerRadius = 5
        self.imageView.clipsToBounds = true

        let maxTitleWidth: CGFloat
        let usesCompactScreenLayout = self.window?.windowScene?.screen.isSmallerThan(screenSize: .tablet)
            ?? (self.traitCollection.userInterfaceIdiom == .phone)
        if usesCompactScreenLayout {
            maxTitleWidth = self.width - (self.imageView.right + ToastBannerView.padding.value.doubled)
        } else {
            maxTitleWidth = (self.width * Theme.iPadPortraitWidthRatio) - (self.imageView.right + 22)
        }

        self.titleLabel.setSize(withWidth: maxTitleWidth)
        self.titleLabel.match(.left, to: .right, of: self.imageView, offset: ToastBannerView.padding)
        self.titleLabel.match(.top, to: .top, of: self.imageView)

        self.descriptionLabel.setSize(withWidth: maxTitleWidth)
        self.descriptionLabel.match(.left, to: .left, of: self.titleLabel)
        self.descriptionLabel.match(.top, to: .bottom, of: self.titleLabel, offset: .short)
        if self.descriptionLabel.height > self.minimumHeight {
            self.descriptionLabel.height = self.minimumHeight
        }

        if let height = self.maxHeight {
            self.height = height
        } else if self.descriptionLabel.bottom + ToastBannerView.padding.value < self.minimumHeight {
            self.height = self.minimumHeight
        } else {
            self.height = self.descriptionLabel.bottom + ToastBannerView.padding.value
        }
    }
}
