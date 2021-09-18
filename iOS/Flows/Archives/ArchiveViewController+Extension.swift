//
//  ArchiveViewController+Menu.swift
//  ArchiveViewController+Menu
//
//  Created by Benji Dodgson on 9/16/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import StreamChat

extension ArchiveViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let identifier = self.dataSource.itemIdentifier(for: indexPath) else { return }

        self.delegate?.archiveView(self, didSelect: identifier)
    }

    func collectionView(_ collectionView: UICollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {

        guard let conversation = self.channelListController?.channels[indexPath.row],
              let cell = collectionView.cellForItem(at: indexPath) as? ConversationCell else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: {
            return ConversationPreviewViewController(with: conversation, size: cell.size)
        }, actionProvider: { suggestedActions in
            if conversation.isFromCurrentUser {
                return self.makeCurrentUserMenu(for: conversation, at: indexPath)
            } else {
                return self.makeNonCurrentUserMenu(for: conversation, at: indexPath)
            }
        })
    }

    func makeCurrentUserMenu(for conversation: Conversation, at indexPath: IndexPath) -> UIMenu {
        let neverMind = UIAction(title: "Never Mind", image: UIImage(systemName: "nosign")) { _ in }

        let confirm = UIAction(title: "Confirm",
                               image: UIImage(systemName: "trash"),
                               attributes: .destructive) { action in

            Task {
                do {
                    try await ChatClient.shared.deleteChannel(conversation)
                } catch {
                    logDebug(error)
                }
            }
        }

        let deleteMenu = UIMenu(title: "Delete",
                                image: UIImage(systemName: "trash"),
                                options: .destructive,
                                children: [confirm, neverMind])

        let open = UIAction(title: "Open", image: UIImage(systemName: "arrowshape.turn.up.right")) { [unowned self] _ in
            guard let identifier = self.dataSource.itemIdentifier(for: indexPath) else { return }
            self.delegate?.archiveView(self, didSelect: identifier)
        }

        // Create and return a UIMenu with the share action
        return UIMenu(title: "Options", children: [open, deleteMenu])
    }

    func makeNonCurrentUserMenu(for conversation: Conversation, at indexPath: IndexPath) -> UIMenu {

        let neverMind = UIAction(title: "Never Mind", image: UIImage(systemName: "nosign")) { _ in }

        let confirm = UIAction(title: "Confirm",
                               image: UIImage(systemName: "clear"),
                               attributes: .destructive) { action in
            Task {
                do {
                    try await ChatClient.shared.deleteChannel(conversation)
                } catch {
                    logDebug(error)
                }
            }
        }

        let deleteMenu = UIMenu(title: "Leave",
                                image: UIImage(systemName: "clear"),
                                options: .destructive,
                                children: [confirm, neverMind])

        let open = UIAction(title: "Open", image: UIImage(systemName: "arrowshape.turn.up.right")) { [unowned self] _ in
            guard let item = self.dataSource.itemIdentifier(for: indexPath) else { return }
            self.delegate?.archiveView(self, didSelect: item)
        }

        // Create and return a UIMenu with the share action
        return UIMenu(title: "Options", children: [open, deleteMenu])
    }
}
