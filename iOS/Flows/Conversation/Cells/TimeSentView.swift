//
//  TimeSentHeaderView.swift
//  Jibber
//
//  Created by Benji Dodgson on 11/1/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation

class TimeSentView: UICollectionReusableView {

    let timeOfDayLabel = MessageTimeLabel()
    let daysAgoLabel = MessageDateLabel()

    override init(frame: CGRect) {
        super.init(frame: .zero)
        self.initializeSubviews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func initializeSubviews() {
        self.addSubview(self.timeOfDayLabel)
        self.addSubview(self.daysAgoLabel)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        self.daysAgoLabel.setSize(withWidth: self.width)
        self.daysAgoLabel.pin(.left, padding: Theme.contentOffset)
        self.daysAgoLabel.centerOnY()

        self.timeOfDayLabel.setSize(withWidth: self.width)
        self.timeOfDayLabel.pin(.right, padding: Theme.contentOffset)
        self.timeOfDayLabel.centerOnY()
    }

    func configure(with message: Messageable?) {
        if let message = message {
            self.timeOfDayLabel.set(date: message.createdAt)
            self.daysAgoLabel.set(date: message.createdAt)

        } else {
            self.timeOfDayLabel.text = nil
            self.daysAgoLabel.text = nil
        }

        self.setNeedsLayout()
    }
}