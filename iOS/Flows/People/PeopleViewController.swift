//
//  PeopleViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 2/17/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Contacts
import UIKit
import Localization
import KeyboardManager
import Combine

class PeopleViewController: DiffableCollectionViewController<PeopleCollectionViewDataSource.SectionType,
                            PeopleCollectionViewDataSource.ItemType,
                            PeopleCollectionViewDataSource> {

    typealias PeopleSection = PeopleCollectionViewDataSource.SectionType
    typealias PersonItem = PeopleCollectionViewDataSource.ItemType

    private(set) var reservations: [Reservation] = []
    
    let button = ThemeButton()
    private var showButton: Bool = true
    
    private let bottomGradientView = GradientPassThroughView(with: [ThemeColor.B0.color.cgColor, ThemeColor.B0.color.withAlphaComponent(0.0).cgColor],
                                                  startPoint: .bottomCenter,
                                                  endPoint: .topCenter)
    
    private let loadingView = InvitationLoadingView()
    
    private(set) var allPeople: [Person] = []
    
    @Published var selectedPeople: [Person] = []
    
    let shouldShowConnections: Bool
    
    init(shouldShowConnections: Bool) {
        self.shouldShowConnections = shouldShowConnections
        let cv = CollectionView(layout: PeopleCollectionViewLayout())
        cv.keyboardDismissMode = .interactive
        cv.isScrollEnabled = true
        cv.allowsMultipleSelection = true
        super.init(with: cv)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required init(collectionView: UICollectionView) {
        fatalError("init(collectionView:) has not been implemented")
    }

    override func initializeViews() {
        super.initializeViews()
        
        self.view.set(backgroundColor: .B0)
                
        self.setupNavigationBar()

        self.view.addSubview(self.bottomGradientView)
        self.view.addSubview(self.button)
        
        KeyboardManager.shared.$cachedKeyboardEndFrame.mainSink { [unowned self]  _ in
            self.view.setNeedsLayout()
        }.store(in: &self.cancellables)
    }
    
    private func setupNavigationBar() {
        self.navigationItem.title = "Contacts"
        
        let cancel = UIAction { _ in
            self.dismiss(animated: true, completion: nil)
        }
        let rightItem = UIBarButtonItem(title: "Cancel", image: nil, primaryAction: cancel, menu: nil)
        rightItem.tintColor = ThemeColor.D1.color
        let search = UISearchController(searchResultsController: nil)
        search.searchBar.delegate = self
        search.searchBar.tintColor = ThemeColor.D1.color
        self.navigationItem.searchController = search
        
        let reset = UIAction { _ in
            // reset all selected items
            self.selectedPeople = []
        }
        let leftItem = UIBarButtonItem(title: "Reset", image: nil, primaryAction: reset, menu: nil)
        leftItem.tintColor = ThemeColor.D1.color
        
        self.navigationItem.leftBarButtonItem = leftItem
        self.navigationItem.rightBarButtonItem = rightItem
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.loadInitialData()
        
        self.dataSource.didSelectAddContacts = { [unowned self] in
            self.loadContacts()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        self.loadingView.expandToSuperviewSize()

        self.button.setSize(with: self.view.width)
        self.button.centerOnX()
        
        if self.showButton {
            if KeyboardManager.shared.isKeyboardShowing {
                let keyboardHeight = KeyboardManager.shared.cachedKeyboardEndFrame.height
                self.button.bottom = self.view.height - keyboardHeight - Theme.ContentOffset.standard.value
            } else {
                self.button.pinToSafeAreaBottom()
            }
        } else {
            self.button.top = self.view.height
        }
        
        self.bottomGradientView.expandToSuperviewWidth()
        self.bottomGradientView.height = 94
        self.bottomGradientView.pin(.bottom)
    }
    
    func updateSelectedPeopleItems() {
         let updatedItems: [PersonItem] = self.dataSource.itemIdentifiers(in: .people).compactMap { item in
            switch item {
            case .person(let person):
                var copy = person
                copy.isSelected = self.selectedPeople.contains(where: { current in
                    return current.personId == person.personId
                })

                return .person(copy)
            }
        }
        
        var snapshot = self.dataSource.snapshot()
        snapshot.setItems(updatedItems, in: .people)
        self.dataSource.apply(snapshot)
    }

    func showLoading(for person: Person) async {
        if self.loadingView.superview.isNil {
            self.view.addSubview(self.loadingView)
            self.view.layoutNow()
            await self.loadingView.initiateLoading(with: person)
        } else {
            await self.loadingView.update(person: person)
        }
    }

    @MainActor
    func finishInviting() async {
        await self.loadingView.hideAllViews()
        self.loadingView.removeFromSuperview()
    }

    func updateButton() {
        self.button.set(style: .custom(color: .white, textColor: .B0, text: self.getButtonTitle()))
        UIView.animate(withDuration: Theme.animationDurationFast) {
            self.showButton = self.selectedItems.count > 0
            self.view.layoutNow()
        }
    }

    func getHeaderTitle() -> Localized {
        return "Add People"
    }

    func getHeaderDescription() -> Localized {
        return "Tap anyone below to add/invite them to the conversation."
    }

    func getButtonTitle() -> Localized {
        let text = self.selectedPeople.count == 1 ? "person" : "people"
        return "Add \(self.selectedPeople.count) \(text)"
    }

    // MARK: Data Loading

    /// The phone numbers of the loaded users objects (not contacts).
    private var userPhoneNumbers: Set<FuzzyPhoneNumber> = []

    override func retrieveDataForSnapshot() async -> [PeopleSection : [PersonItem]] {
        var data: [PeopleSection: [PersonItem]] = [:]

        guard self.shouldShowConnections else { return data }
        let connections = (try? await GetAllConnections().makeRequest(andUpdate: [], viewsToIgnore: [])) ?? []

        // Get all of the connected Jibber users.
        var connectedPeople: [Person] = []
        connections.forEach { connection in
            guard let userId = connection.nonMeUser?.personId else { return }

            if let upToDateUser = PeopleStore.shared.usersDictionary[userId] {
                let person = Person(user: upToDateUser, connection: connection)
                connectedPeople.append(person)
            }
        }
        self.allPeople.append(contentsOf: connectedPeople)

        // Get all of the Jibber users that aren't connected, but exist in our contacts.
        let users = PeopleStore.shared.usersArray
        let unconnectedUsers = users.filter { user in
            guard !user.isCurrentUser else { return false }

            // Filter out users who are already connected
            let isConnected = connectedPeople.contains(where: { connectedPerson in
                return user.personId == connectedPerson.personId
            })
            return !isConnected
        }
        let unconnectedPeople = unconnectedUsers.map { unconnectedUser in
            return Person(user: unconnectedUser, connection: nil)
        }
        self.allPeople.append(contentsOf: unconnectedPeople)

        // Remember the phone numbers of the user objects so we don't show their corresponding contact.
        self.allPeople.forEach { person in
            guard let phoneNumber = person.phoneNumber else { return }
            self.userPhoneNumbers.insert(FuzzyPhoneNumber(phoneNumber))
        }

        // Then list all the existing Jibber users who you aren't connected to, but are in your contacts.
        data[.people] = self.allPeople.sorted().compactMap({ person in
            return .person(person)
        })

        return data
    }

    override func getAllSections() -> [PeopleSection] {
        return PeopleSection.allCases
    }
    
    override func collectionViewDataWasLoaded() {
        super.collectionViewDataWasLoaded()
        
        if ContactsManager.shared.hasPermissions {
            self.loadContacts()
        }

        self.$selectedPeople.mainSink { [unowned self] items in
            self.updateSelectedPeopleItems()
            self.updateButton()
        }.store(in: &self.cancellables)
    }
    
    private func loadContacts() {
        Task {
            self.reservations = await Reservation.getAllUnclaimed()
            
            let contacts: [Person] = await ContactsManager.shared.fetchContacts().compactMap({ contact in
                // Make sure we're not already showing a user related to this contact.
                if let phoneNumber = contact.findBestPhoneNumberString(),
                   self.userPhoneNumbers.contains(FuzzyPhoneNumber(phoneNumber)) {
                    return nil
                }
                return Person(withContact: contact)
            })
            
            self.allPeople.append(contentsOf: contacts)

            let contactItems: [PersonItem] = contacts.map { person in
                return .person(person)
            }

            await self.dataSource.appendItems(contactItems, toSection: .people)
        }.add(to: self.autocancelTaskPool)
    }

    // MARK: - UICollectionViewDelegate

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        super.collectionView(collectionView, didSelectItemAt: indexPath)
        guard let person: Person = self.dataSource.itemIdentifier(for: indexPath).map({ item in
            switch item {
            case .person(let person):
                return person
            }
        }), !self.selectedPeople.contains(person) else { return }
        
        self.selectedPeople.append(person)
    }
    
    override func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        super.collectionView(collectionView, didDeselectItemAt: indexPath)
        guard let person: Person = self.dataSource.itemIdentifier(for: indexPath).map({ item in
            switch item {
            case .person(let person):
                return person
            }
        }), self.selectedPeople.contains(person) else { return }
        
        self.selectedPeople.remove(object: person)
    }
}
