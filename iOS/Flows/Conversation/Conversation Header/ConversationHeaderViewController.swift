//
//  ConversationHeaderView.swift
//  Jibber
//
//  Created by Benji Dodgson on 9/27/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine
import Coordinator
import Lottie
import UIKit

class ConversationHeaderViewController: ViewController, ActiveConversationable {

    let addImageView = SymbolImageView(symbol: .personBadgePlus)
    let stackedView = StackedPersonView()
    let button = ThemeButton()
    let topicLabel = ThemeLabel(font: .small)
    
    let closeButton = ThemeButton()
    
    private var state: ConversationUIState = .read
        
    override func initializeViews() {
        super.initializeViews()

        self.view.clipsToBounds = false
        
        self.view.addSubview(self.addImageView)
        self.addImageView.tintColor = ThemeColor.white.color
        self.addImageView.contentMode = .scaleAspectFit
        self.addImageView.isVisible = false
        
        self.view.addSubview(self.stackedView)
        self.stackedView.max = 9
        
        self.view.addSubview(self.topicLabel)
        self.topicLabel.textAlignment = .center
        
        self.view.addSubview(self.button)
        
        self.view.addSubview(self.closeButton)
        self.closeButton.set(style: .image(symbol: .chevronDownCircle,
                                           palletteColors: [.whiteWithAlpha],
                                           pointSize: 22,
                                           backgroundColor: .clear))
        
        ConversationsManager.shared.$activeConversation
            .removeDuplicates()
            .mainSink { [unowned self] conversation in
                guard let convo = conversation else {
                    self.startLoadDataTask(with: nil)
                    self.topicLabel.text = nil
                    self.topicLabel.isVisible = false
                    self.stackedView.isVisible = false
                    self.closeButton.isVisible = false
                    return
                }
                
                self.startLoadDataTask(with: convo)
                self.closeButton.isVisible = true 
                self.stackedView.isVisible = true
                self.topicLabel.isVisible = true
                self.view.layoutNow()
            }.store(in: &self.cancellables)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.closeButton.squaredSize = 44
        self.closeButton.pin(.right)
        self.closeButton.pin(.top)
        
        self.stackedView.centerY = self.closeButton.centerY
        self.stackedView.centerOnX()
        
        self.topicLabel.setSize(withWidth: Theme.getPaddedWidth(with: self.view.width))
        self.topicLabel.centerOnX()
        self.topicLabel.match(.top, to: .bottom, of: self.stackedView, offset: .short)
        
        self.addImageView.squaredSize = 24
        self.addImageView.centerY = self.closeButton.centerY
        self.addImageView.centerOnX()
        
        self.button.height = self.view.height
        self.button.width = 200
        self.button.centerOnXAndY()
    }
    
    func update(for state: ConversationUIState) {
        self.state = state
        
        UIView.animate(withDuration: Theme.animationDurationStandard) {
            self.view.layoutNow()
        } completion: { completed in
            
        }
    }
    
    // Mark: Members
    
    var conversationController: ParseConversationController?
    
    /// A task for loading data and subscribing to conversation updates.
    private var loadDataTask: Task<Void, Never>?
    
    private func startLoadDataTask(with conversation: ParseConversation?) {
        self.loadDataTask?.cancel()
        self.loadPeopleTask?.cancel()
        self.conversationCancellables.removeAll()

        if let conversation {
            self.conversationController = ParseConversationController.controller(for: conversation)
        } else {
            self.conversationController = nil
        }

        self.loadDataTask = Task { [weak self] in
            guard let conversationController = self?.conversationController else {
                // If there's no current conversation, then there's nothing to show.
                self?.setConversation(nil)
                return
            }

            self?.subscribeToUpdates(for: conversationController)

            self?.setConversation(conversationController.conversation ?? conversation)

            guard !Task.isCancelled else { return }
        }
    }
    
    /// A task for loading data and subscribing to conversation updates.
    private var loadPeopleTask: Task<Void, Never>?
    
    private func setConversation(_ conversation: ParseConversation?) {
        self.setTopic(for: conversation)
        self.setMembers(for: conversation)
    }

    private func setTopic(for conversation: ParseConversation?) {
        self.topicLabel.setText(conversation?.title)
    }

    private func setMembers(for conversation: ParseConversation?) {
        guard let conversation = conversation else {
            self.addImageView.isVisible = true
            self.stackedView.configure(with: [])
            return
        }
        self.loadPeopleTask?.cancel()
        
        self.loadPeopleTask = Task { [weak self] in
            guard let self else { return }
            let members = await self.getPeople(for: conversation)
            self.addImageView.isVisible = members.count == 0
            self.stackedView.configure(with: members)
            self.view.setNeedsLayout()
        }
    }

    /// The subscriptions for the current conversation.
    private var conversationCancellables = Set<AnyCancellable>()

    private func subscribeToUpdates(for conversationController: ParseConversationController) {
        // Clear out previous subscriptions.
        self.conversationCancellables.removeAll()
        
        conversationController
            .conversationChangePublisher
            .mainSink { [weak self] change in
                switch change {
                case .create(let conversation), .update(let conversation):
                    self?.setConversation(conversation)
                case .remove:
                    self?.setConversation(nil)
                }
            }.store(in: &self.conversationCancellables)

        conversationController
            .membersChangesPublisher
            .mainSink(receiveValue: { [weak self] changes in
                guard !changes.isEmpty else { return }
                self?.setMembers(for: conversationController.conversation)
            }).store(in: &self.conversationCancellables)
    }

    private func getPeople(for conversation: ParseConversation) async -> [PersonType] {
        var peopleByID: [String: PersonType] = [:]

        for member in conversation.activeMembers where !member.isCurrentUser {
            guard let person = await PeopleStore.shared.getPerson(withPersonId: member.userID) else {
                continue
            }
            peopleByID[person.personId] = person
        }

        for (_, reservation) in PeopleStore.shared.unclaimedReservations {
            guard reservation.conversationCid == conversation.id,
                  let contactID = reservation.contactId,
                  let person = await PeopleStore.shared.getPerson(withPersonId: contactID) else {
                continue
            }
            peopleByID[person.personId] = person
        }

        return Array(peopleByID.values)
            .sorted { $0.givenName.localizedCaseInsensitiveCompare($1.givenName) == .orderedAscending }
    }
}
