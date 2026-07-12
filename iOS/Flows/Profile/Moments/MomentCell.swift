//
//  MomentCell.swift
//  Jibber
//
//  Created by Benji Dodgson on 8/10/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Lottie

struct MomentViewModel: Hashable {
    var day: Int
    var month: Int
    var year: Int
    var momentId: String?
    var isAvailable: Bool
    
    var isToday: Bool {
        let today = Date.today
        return today.day == self.day
        && today.month == self.month
        && today.year == self.year
    }
    
    var isInFuture: Bool {
        let today = Date.today
        if today.year == self.year, today.month == self.month {
            return today.day < self.day
        }
        
        return false
    }
}

protocol MomentCellDelegate: AnyObject {
    func moment(_ cell: MomentCell, didSelect moment: Moment)
    func momentCellDidSelectRecord(_ cell: MomentCell)
}

class MomentCell: CollectionViewManagerCell, ManageableCell {
    typealias ItemType = MomentViewModel
    
    var currentItem: MomentViewModel?
    let label = ThemeLabel(font: .regularBold)
    let videoView = VideoView()
    let animationView = LottieAnimationView.with(animation: .loading)
    private(set) var moment: Moment?
    
    weak var delegate: MomentCellDelegate? 

    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.videoView.shouldPlay = true
        
        self.contentView.addSubview(self.videoView)
        
        self.contentView.layer.cornerRadius = Theme.innerCornerRadius
        self.contentView.layer.masksToBounds = true
        
        self.contentView.addSubview(self.label)
        self.label.textAlignment = .center
        self.label.alpha = 0
        
        self.contentView.addSubview(self.animationView)
        self.animationView.loopMode = .loop
        
        self.contentView.layer.borderColor = ThemeColor.white.color.cgColor
        self.contentView.layer.borderWidth = 0
        
        let interaction = UIContextMenuInteraction(delegate: self)
        self.contentView.addInteraction(interaction)
    }
    
    private var loadTask: Task<Void, Error>?
    
    func configure(with item: MomentViewModel) {
        
        self.label.alpha = item.momentId.exists ? 0 : 1.0
        self.label.setText("\(item.day)")
        
        self.loadTask = Task { [weak self] in
            guard let self else { return }
            
            if let momentId = item.momentId {
                self.animationView.play()
                self.moment = try? await Moment.getObject(with: momentId)
                guard !Task.isCancelled else { return }
                if let previewURL = try? await self.moment?.preview?.retrieveCachedPathURL() {
                    guard !Task.isCancelled else { return }
                    self.videoView.updatePlayer(with: [previewURL])
                }
                self.animationView.stop()
            }
            
            UIView.animate(withDuration: Theme.animationDurationFast) {
                if item.isAvailable {
                    self.label.alpha = item.isInFuture ? 0.1 : 1.0
                } else {
                    self.label.alpha = 0
                }
            }
        }
        
        self.contentView.layer.borderWidth = item.isToday ? 1.0 : 0.0
        
        self.setNeedsLayout()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.videoView.expandToSuperviewSize()
        
        self.label.setSize(withWidth: self.width)
        self.label.centerOnXAndY()
        
        self.animationView.size = CGSize(width: 10, height: 10)
        self.animationView.centerOnXAndY()
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        self.animationView.stop()
        self.label.text = ""
        self.contentView.layer.borderWidth = 0 
        self.videoView.reset()
        self.loadTask?.cancel()
    }
    
    override func updateConfiguration(using state: UICellConfigurationState) {
        guard let currentItem = self.currentItem, currentItem.isAvailable else {
            super.updateConfiguration(using: state)
            return
        }
        
        // Get the system default background configuration for a plain style list cell in the current state.
        var backgroundConfig = UIBackgroundConfiguration.listPlainCell().updated(for: state)

        // Customize the background color to be clear, no matter the state.
        backgroundConfig.backgroundColor = ThemeColor.clear.color
        
        // Apply the background configuration to the cell.
        self.backgroundConfiguration = backgroundConfig
        
        if state.isHighlighted {
            UIView.animate(withDuration: Theme.animationDurationFast) {
                self.label.transform = CGAffineTransform.init(scaleX: 0.5, y: 0.5)
            }
            self.selectionImpact.impactOccurred(intensity: 1.0)
        } else {
            UIView.animate(withDuration: Theme.animationDurationFast) {
                self.label.transform = .identity
            }
        }
    }
}
