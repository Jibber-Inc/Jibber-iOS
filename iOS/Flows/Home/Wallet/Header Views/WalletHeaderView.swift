//
//  WalletHeaderView.swift
//  Jibber
//
//  Created by Benji Dodgson on 2/4/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import StoreKit

class WalletHeaderView: BaseView {
    
    private let jibsDetailView = JibsDetailView()
    
    var didTapDetail: CompletionOptional = nil
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.addSubview(self.jibsDetailView)
        
        self.jibsDetailView.didSelect { [unowned self] in
            self.didTapDetail?()
        }
    }
    
    func configure(with items: [Transaction]) {
        self.jibsDetailView.subtitleLabel.setText("Earned for activity")
        self.startCalculatingInterest(for: items)
        self.layoutNow()
    }

    private var interestTask: Task<Void, Never>?

    func startCalculatingInterest(for transactions: [Transaction]) {
        self.interestTask?.cancel()
        
        let calculator = TransactionsCalculator()
        
        self.interestTask = Task { [weak self] in
            guard let self else { return }
            guard let jibsEarned = try? await calculator.calculateJibsEarned(for: transactions),
                  !Task.isCancelled else { return }
            
            let projectedInterest = calculator.calculateInterestEarned()
            let totalEarned = jibsEarned + projectedInterest
            
            self.jibsDetailView.configure(with: totalEarned)
            
            self.layoutNow()
            
            await Task.snooze(seconds: 1.0)
            
            guard !Task.isCancelled else { return }
            self.startCalculatingInterest(for: transactions)
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.jibsDetailView.centerOnX()
        self.jibsDetailView.centerY = self.height * 0.7
    }
}
