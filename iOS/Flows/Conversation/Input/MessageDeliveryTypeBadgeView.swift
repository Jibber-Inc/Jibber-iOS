//
//  DeliveryTypeBadgeView.swift
//  Jibber
//
//  Created by Martin Young on 3/31/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine

class MessageDeliveryTypeBadgeView: BaseView {

    @Published var deliveryType: MessageDeliveryType?

    private let imageView = SymbolImageView()
    private let label = ThemeLabel(font: .small)

    override func initializeSubviews() {
        super.initializeSubviews()

        self.addSubview(self.imageView)
        self.addSubview(self.label)

        self.set(backgroundColor: .badgeHighlightTop)

        self.$deliveryType
            .removeDuplicates()
            .mainSink { [unowned self] deliveryType in
                self.update(for: deliveryType)
            }.store(in: &self.cancellables)
    }
    
    /// The currently running task.
    private var animateTask: Task<Void, Never>?
        
    private func update(for type: MessageDeliveryType?) {
        self.animateTask?.cancel()

        self.animateTask = Task { [weak self] in
            guard let self else { return }
            guard let type else {
                await UIView.awaitAnimation(with: .fast, animations: {
                    self.alpha = 0.0
                })
                return
            }

            await UIView.awaitAnimation(with: .fast, animations: {
                self.label.alpha = 0.0
                self.imageView.alpha = 0.0
            })

            guard !Task.isCancelled else { return }

            self.imageView.set(symbol: type.symbol)
            self.label.setText(type.description)
            self.label.alpha = 1
            self.imageView.alpha = 1

            self.layoutNow()

            await UIView.awaitAnimation(with: .fast, animations: {
                self.alpha = 1.0
            })
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.label.setSize(withWidth: 200)
        self.height = 24
        self.width = 24 + Theme.ContentOffset.short.value.doubled + self.label.width + Theme.ContentOffset.short.value
        self.imageView.squaredSize = 12.5
        self.imageView.pin(.left, offset: .standard)
        self.label.match(.left, to: .right, of: self.imageView, offset: .short)
        
        self.imageView.centerOnY()
        self.label.centerY = self.imageView.centerY

        self.layer.cornerRadius = self.halfHeight
    }
}
