//
//  CalendarViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 9/5/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import UIKit
import ParseCore

class CalendarViewController: DiffableCollectionViewController<CalendarRange,
                              CalendarDataSource.ItemType,
                              CalendarDataSource> {
    
    private let segmentGradientView = GradientPassThroughView(with: [ThemeColor.B6.color.cgColor,
                                                                     ThemeColor.B6.color.withAlphaComponent(0.6).cgColor,
                                                                     ThemeColor.B6.color.withAlphaComponent(0.3).cgColor,
                                                                     ThemeColor.B6.color.withAlphaComponent(0.0).cgColor],
                                                              startPoint: .topCenter,
                                                              endPoint: .bottomCenter)
    private let darkBlurView = DarkBlurView()
    let daysOfTheWeekView = MomentsHeaderView.init(frame: .zero)
    
    let person: PersonType
    
    private var ranges: [CalendarRange] = []
    
    init(with person: PersonType) {
        self.person = person
        super.init(with: CalendarCollectionView())
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func initializeViews() {
        super.initializeViews()
        
        self.modalPresentationStyle = .popover
        if let pop = self.popoverPresentationController {
            let sheet = pop.adaptiveSheetPresentationController
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
            sheet.preferredCornerRadius = Theme.screenRadius
        }
        
        self.view.insertSubview(self.darkBlurView, at: 0)
        self.view.insertSubview(self.segmentGradientView, aboveSubview: self.collectionView)
        self.view.insertSubview(self.daysOfTheWeekView, aboveSubview: self.segmentGradientView)
        
        self.collectionView.allowsMultipleSelection = false

        self.ranges = self.getRanges()
        self.loadInitialData()
    }
    
    override func willEnterForeground() {
        super.willEnterForeground()
        
        self.dataSource.reconfigureAllItems()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.collectionView.animationView.isHidden = true 
        
        self.darkBlurView.expandToSuperviewSize()
        
        self.daysOfTheWeekView.width = self.view.width - Theme.ContentOffset.long.value.doubled
        self.daysOfTheWeekView.height = 40
        self.daysOfTheWeekView.pin(.top)
        self.daysOfTheWeekView.centerOnX()
        
        self.segmentGradientView.expandToSuperviewWidth()
        self.segmentGradientView.pin(.top)
        self.segmentGradientView.height = self.daysOfTheWeekView.height + Theme.ContentOffset.xtraLong.value.doubled
    }
    
    override func collectionViewDataWasLoaded() {
        super.collectionViewDataWasLoaded()
        
        guard let last = self.ranges.last else { return }
        
        let ip = IndexPath(item: last.startOfMonth.weekday, section: self.ranges.count - 1)
        
        self.collectionView.scrollToItem(at: ip, at: .top, animated: true)
    }
    
    override func getAnimationCycle(with snapshot: NSDiffableDataSourceSnapshot<CalendarRange, CalendarDataSource.ItemType>)
    -> AnimationCycle? {
        return AnimationCycle(inFromPosition: .inward,
                              outToPosition: .inward,
                              shouldConcatenate: false)
    }
    
    override func getAllSections() -> [CalendarRange] {
        return self.ranges
    }
    
    override func retrieveDataForSnapshot() async -> [CalendarRange : [CalendarDataSource.ItemType]] {
        var data: [CalendarRange : [CalendarDataSource.ItemType]] = [:]
        
        let moments = try? await MomentsStore.shared.getAll(for: self.person)
        
        for range in self.ranges {
            var items: [CalendarDataSource.ItemType] = []
            
            for i in stride(from: range.total, to: 0, by: -1) {
                let index = i + 1
                if index <= range.startOfMonth.weekday {
                    // Days prior to month
                    let model = MomentViewModel(day: index + range.numberOfDays,
                                                month: range.startOfMonth.month,
                                                year: range.startOfMonth.year,
                                                isAvailable: false)
                    items.append(.moment(model))
                    
                } else {
                    // Day is part of month
                    var components = DateComponents()
                    components.day = index - range.startOfMonth.weekday
                    components.month = range.startOfMonth.month
                    components.year = range.startOfMonth.year
                    let date = Date.date(from: components)!
                    
                    if let moment = moments?.first(where: { moment in
                        if let createdAt = moment.createdAt, createdAt.isSameDay(as: date) {
                            return true
                        } else {
                            return false
                        }
                    }) {
                        let model = MomentViewModel(day: date.day,
                                                    month: date.month,
                                                    year: date.year,
                                                    momentId: moment.objectId!,
                                                    isAvailable: true)
                        items.append(.moment(model))
                    } else {
                        let model = MomentViewModel(day: date.day,
                                                    month: date.month,
                                                    year: date.year,
                                                    isAvailable: true)
                        items.append(.moment(model))
                    }
                }
            }
            data[range] = items.reversed()
        }
        return data
    }
    
    func getRanges() -> [CalendarRange] {
        
        let startDate = User.current()?.createdAt ?? Date()
        let endDate = Date()
        
        let months = Calendar.current.dateComponents([.month], from: startDate, to: endDate).month ?? 1
        
        var result: [CalendarRange] = []
                
        for d in 0...months {
            if let dateToAdd = Calendar.current.date(byAdding: .month, value: (d * -1), to: endDate) {
                let components = Calendar.current.dateComponents([.month, .year], from: dateToAdd)
                let numberOfDays = Calendar.current.range(of: .day, in: .month, for: dateToAdd)!.count
                let startOfMonth = Calendar.current.date(from: components)!
                let total = (startOfMonth.weekday - 1) + numberOfDays
                
                let range = CalendarRange(components: components,
                                          startOfMonth: startOfMonth,
                                          numberOfDays: numberOfDays,
                                          total: total)
                result.append(range)
            }
        }
        
        return result.reversed()
    }
}
