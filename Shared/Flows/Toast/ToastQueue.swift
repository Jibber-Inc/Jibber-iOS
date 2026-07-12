//
//  ToastQue.swift
//  Jibber
//
//  Created by Benji Dodgson on 5/3/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import UIKit

@MainActor
class ToastQueue {
    static let shared = ToastQueue()

    private let toaster = Toaster()
    private(set) var allViewed: [String] = []
    private var scheduled: [Toast] = []

    func add(toast: Toast) {
        if !self.scheduled.isEmpty || self.toaster.isPresenting {
            self.scheduled.append(toast)
            self.scheduled = self.scheduled.sorted { (lhs, rhs) -> Bool in
                return lhs.priority > rhs.priority
            }
        } else {
            self.present(toast: toast)
        }
    }

    private func present(toast: Toast) {
        guard !self.allViewed.contains(toast.id) else {
            self.scheduled.remove(object: toast)
            if let next = self.scheduled.last {
                self.present(toast: next)
            }
            return
        }

        self.toaster.add(toast: toast)
        self.allViewed.append(toast.id)

        self.toaster.didDismiss = { [unowned self] _ in
            if let nextToast = self.scheduled.last  {
                self.present(toast: nextToast)
                self.scheduled.remove(object: nextToast)
            }
        }
    }
}

@MainActor
fileprivate class Toaster {

    var items: [ToastViewable] = []
    var didDismiss: (String) -> Void = {_ in }
    var isPresenting: Bool = false

    func add(toast: Toast) {
        var toastView: ToastViewable

        switch toast.type {
        case .banner:
            toastView = ToastBannerView(with: toast)
        case .success, .error:
            toastView = ToastStatusView(with: toast)
        }

        if let current = self.items.first {
            current.dismiss()
        }
        self.items.append(toastView)

        if self.items.count == 1 {
            self.isPresenting = true
            toastView.didPrepareForPresentation = {
                toastView.reveal()
            }
        }

        toastView.didDismiss = { [unowned self] in
            self.didDismiss(toastView: toastView)
            self.didDismiss(toast.id)
        }

        toastView.didTap = { [unowned self] in
            self.reportButtonTap(for: toast)
        }
    }

    func didDismiss(toastView: ToastViewable) {
        if let view = toastView as? UIView {
            view.removeFromSuperview()
        }

        var indexToRemove: Int?
        for (index, item) in self.items.enumerated() {
            if item.toast.id == toastView.toast.id {
                indexToRemove = index
            }
        }
        if let i = indexToRemove {
            self.items.remove(at: i)
        }

        self.isPresenting = false

        if !self.items.isEmpty, let nextView = self.items[safe: 0] {
            nextView.reveal()
        }
    }

    private func reportButtonTap(for toast: Toast) {
//        let eventName = toast.analyticsID + ".Tapped"
//        self.reportEvent(for: eventName)
    }

    private func reportEvent(for eventName: String) {
        //Add reporting here
    }
}
