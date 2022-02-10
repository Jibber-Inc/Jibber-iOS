//
//  CharacterCountView.swift
//  Benji
//
//  Created by Benji Dodgson on 1/24/20.
//  Copyright © 2020 Benjamin Dodgson. All rights reserved.
//

import Foundation

class CharacterCountView: BaseView {

    let label = ThemeLabel(font: .small, textColor: .T1)

    override func initializeSubviews() {
        super.initializeSubviews()

        self.addSubview(self.label)
        self.label.textAlignment = .center
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        self.label.expandToSuperviewSize()
    }

    func update(with count: Int, max: Int) {
        if count >= max {
            self.alpha = 1.0
            self.label.setText(self.getText(from: count, max: max))
            self.label.setTextColor(.T1)
        } else if count >= max - 20 {
            self.alpha = 1.0
            self.label.setText(self.getText(from: count, max: max))
            self.label.setTextColor(.T1)
        } else {
            self.alpha = 0.0
        }
    }

    private func getText(from count: Int, max: Int) -> String {
        return String("\(String(count)) / \(String(max))")
    }
}
