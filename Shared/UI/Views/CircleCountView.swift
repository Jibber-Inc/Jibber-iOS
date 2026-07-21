//
//  CircleCountView.swift
//  Jibber
//
//  Shared by media composition and provider-neutral conversation messages.
//

import UIKit

class CircleCountView: BaseView {

    let blurredEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
    let vibrancyEffect = UIVibrancyEffect(blurEffect: UIBlurEffect(style: .regular))
    lazy var vibrancyView = UIVisualEffectView(effect: vibrancyEffect)

    let countLabel = ThemeLabel(font: .smallBold, textColor: .B0)

    override func initializeSubviews() {
        super.initializeSubviews()

        self.addSubview(self.blurredEffectView)
        self.vibrancyView.contentView.addSubview(self.countLabel)
        self.countLabel.textAlignment = .center
        self.blurredEffectView.contentView.addSubview(self.vibrancyView)
    }

    func set(count: Int) {
        self.countLabel.setText("\(count)")
        self.setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        self.squaredSize = 18
        self.makeRound()
        self.blurredEffectView.expandToSuperviewSize()
        self.blurredEffectView.makeRound()
        self.vibrancyView.expandToSuperviewSize()
        self.countLabel.expandToSuperviewSize()
    }
}
