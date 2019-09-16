//
//  TimeHump.swift
//  Benji
//
//  Created by Martin Young on 8/27/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ReactiveSwift

class TimeHumpView: View {

    let sliderView = View()
    var amplitude: CGFloat {
        return self.height * 0.5
    }

    let percentage = MutableProperty<CGFloat>(0)

    override func initialize() {
        super.initialize()

        self.set(backgroundColor: .green)

        self.sliderView.set(backgroundColor: Color.white)
        self.sliderView.size = CGSize(width: 30, height: 30)
        self.addSubview(self.sliderView)

        self.onPan { [unowned self] (panRecognizer) in
            self.handlePan(panRecognizer)
        }

        self.percentage.producer.on { [unowned self] (percentage) in
            self.setNeedsLayout()
        }.start()
    }

    // MARK: Layout

    override func draw(_ rect: CGRect) {
        super.draw(rect)

        let path = UIBezierPath()
        path.move(to: CGPoint())

        for percentage in stride(from: 0, through: 1.0, by: 0.01) {
            let point = self.getPoint(normalizedX: CGFloat(percentage))
            path.addLine(to: point)
        }

        UIColor.black.setStroke()
        path.stroke()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let sliderCenter = self.getPoint(normalizedX: clamp(self.percentage.value, 0, 1))
        self.sliderView.center = sliderCenter
    }

    func getPoint(normalizedX: CGFloat) -> CGPoint {

        let angle = normalizedX * twoPi

        let x = self.width * normalizedX
        let y = (self.height * 0.5) - (sin(angle - halfPi) * self.amplitude)

        return CGPoint(x: x, y: y)
    }

    // MARK: Touch Input

    private var startPanPercentage: CGFloat = 0

    private func handlePan(_ panRecognizer: UIPanGestureRecognizer) {

        switch panRecognizer.state {
        case .began:
            self.startPanPercentage = self.percentage.value
        case .changed:
            let translation = panRecognizer.translation(in: self)
            let normalizedTranslationX = translation.x/self.width
            self.percentage.value = clamp(self.startPanPercentage + normalizedTranslationX, 0, 1)
        case .ended:
            let velocity = panRecognizer.velocity(in: self)
            self.animateToFinalPosition(withCurrentVelocity: velocity.x)
        case .possible, .cancelled, .failed:
            break
        @unknown default:
            break
        }
    }

    private func animateToFinalPosition(withCurrentVelocity velocity: CGFloat) {
        self.animateToPercentage(percentage: self.percentage.value + (velocity/1000.0) * 0.05)
    }

    func animateToPercentage(percentage: CGFloat) {

        UIView.animate(withDuration: 0.25,
                       delay: 0,
                       options: UIView.AnimationOptions.curveEaseOut,
                       animations: {
                        self.percentage.value = clamp(percentage, 0, 1)
                        self.layoutIfNeeded()
        })
    }
}
