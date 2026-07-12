//
//  AttachmentsViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 3/18/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine

class AttachmentsViewController: DiffableCollectionViewController<AttachmentsCollectionViewDataSource.SectionType,
                                 AttachmentsCollectionViewDataSource.ItemType,
                                 AttachmentsCollectionViewDataSource> {
    
    var selectedAttachments: [Attachment] {
        return self.selectedItems.compactMap { type in
            guard case AttachmentsCollectionViewDataSource.ItemType.attachment(let attachment) = type else { return nil }
            return attachment
        }
    }
    
    private let segmentGradientView = GradientPassThroughView(with: [ThemeColor.B0.color.cgColor,
                                                          ThemeColor.B0.color.cgColor,
                                                          ThemeColor.B0.color.cgColor,
                                                          ThemeColor.B0.color.withAlphaComponent(0.0).cgColor],
                                                   startPoint: .topCenter,
                                                   endPoint: .bottomCenter)
    
    private let topGradientView = GradientPassThroughView(with: [ThemeColor.B0.color.cgColor,
                                                      ThemeColor.B0.color.withAlphaComponent(0.0).cgColor],
                                               startPoint: .topCenter,
                                               endPoint: .bottomCenter)
    
    private let bottomGradientView = GradientPassThroughView(with: [ThemeColor.B0.color.cgColor, ThemeColor.B0.color.withAlphaComponent(0.0).cgColor],
                                                  startPoint: .bottomCenter,
                                                  endPoint: .topCenter)
    
    let doneButton = ThemeButton()
    
    init() {
        super.init(with: AttachmentsCollectionView())
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func initializeViews() {
        super.initializeViews()
        
        self.modalPresentationStyle = .popover
        if let pop = self.popoverPresentationController {
            let sheet = pop.adaptiveSheetPresentationController
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        }
        
        self.view.set(backgroundColor: .B0)
        
        self.view.addSubview(self.bottomGradientView)
        self.view.addSubview(self.topGradientView)
        
        self.view.addSubview(self.doneButton)
        self.collectionView.allowsMultipleSelection = true
        
        self.$selectedItems.mainSink { [unowned self] _ in
            self.updateButton()
        }.store(in: &self.cancellables)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.loadInitialData()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.topGradientView.expandToSuperviewWidth()
        self.topGradientView.pin(.top)
        self.topGradientView.height = Theme.ContentOffset.xtraLong.value.doubled
        
        self.bottomGradientView.expandToSuperviewWidth()
        self.bottomGradientView.height = 94
        self.bottomGradientView.pin(.bottom)
        
        self.doneButton.setSize(with: self.view.width)
        self.doneButton.centerOnX()

        if self.selectedAttachments.isEmpty {
            self.doneButton.top = self.view.height
        } else {
            self.doneButton.pinToSafeAreaBottom()
        }
    }
    
    private func updateButton() {
        let text: String
        if self.selectedAttachments.count == 1 {
            text = "Attach 1 item"
        } else {
            text = "Attach \(self.selectedAttachments.count) items"
        }
        self.doneButton.set(style: .custom(color: .white, textColor: .B0, text: text))
        
        UIView.animate(withDuration: Theme.animationDurationFast) {
            self.view.layoutNow()
        }
    }
    
    override func getAllSections() -> [AttachmentsCollectionViewDataSource.SectionType] {
        return AttachmentsCollectionViewDataSource.SectionType.allCases
    }
    
    override func retrieveDataForSnapshot() async -> [AttachmentsCollectionViewDataSource.SectionType : [AttachmentsCollectionViewDataSource.ItemType]] {
        
        var data: [AttachmentsCollectionViewDataSource.SectionType : [AttachmentsCollectionViewDataSource.ItemType]] = [:]
        
        await AttachmentsManager.shared.requestAttachments()
        
        data[.photoVideo] = AttachmentsManager.shared.attachments.compactMap({ attachment in
            return .attachment(attachment)
        })
        
        data[.photoVideo]?.insert(.option(.capture), at: 0)
        
        data[.other] = [.option(.audio), .option(.giphy)]
        
        return data
    }
}
