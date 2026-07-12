//
//  AnimationView+Extensions.swift
//  Jibber
//
//  Created by Benji Dodgson on 5/23/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Lottie

private var microAnimationHandlerKey: UInt = 0

extension LottieAnimationView {

    private(set) var microAnimation: MicroAnimation? {
        get {
            return self.getAssociatedObject(&microAnimationHandlerKey)
        }
        set {
            self.setAssociatedObject(key: &microAnimationHandlerKey, value: newValue)
        }
    }

    static func with(animation: MicroAnimation) -> LottieAnimationView {
        let view = LottieAnimationView(name: animation.rawValue)
        view.microAnimation = animation
        return view
    }

    func load(animation: MicroAnimation) {
        self.microAnimation = animation
        self.animation = LottieAnimation.named(animation.rawValue)
    }

    func reset() {
        self.microAnimation = nil 
        self.animation = nil
    }
 }
