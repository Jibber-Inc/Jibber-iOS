//
//  LoadMoreMessagesCell.swift
//  Jibber
//
//  Created by Martin Young on 9/27/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation

class LoadMoreMessagesCell: UICollectionViewCell {

    var handleLoadMoreMessages: CompletionOptional = nil

    private(set) var label = ThemeLabel(font: .regular, textColor: .white)

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.initializeViews()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.initializeViews()
    }

    private func initializeViews() {
        self.contentView.addSubview(self.label)

        self.label.textAlignment = .center
        self.label.setText("Load more")

        self.contentView.didSelect { [unowned self] in
            self.handleLoadMoreMessages?()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        self.label.size = CGSize(width: 200, height: 34)
        self.label.centerOnXAndY()
    }
}
