//
//  ChannelCollectionViewManager+Menu.swift
//  Benji
//
//  Created by Benji Dodgson on 11/16/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import TMROLocalization
import TwilioChatClient

extension ChannelCollectionViewManager {

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        return false
    }

    func collectionView(_ collectionView: UICollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        return nil
//        guard let messageType = self.item(at: indexPath),
//            let cell = collectionView.cellForItem(at: indexPath) as? MessageCell else { return nil }
//
//        return UIContextMenuConfiguration(identifier: nil, previewProvider: {
//            return MessagePreviewViewController(with: messageType,
//                                                cellWidth: cell.contentView.width)
//        }, actionProvider: { suggestedActions in
//
//            return self.makeContextMenu(for: messageType, at: indexPath)
//        })
    }

    private func makeContextMenu(for message: Messageable, at indexPath: IndexPath) -> UIMenu {

        // Create a UIAction for sharing
        let share = UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { action in
            //let items = [localized(message.text)]
            //let ac = UIActivityViewController(activityItems: items, applicationActivities: nil)
            //self.present(ac, animated: true)
        }

        let editMessage = UIAction(title: "Edit", image: UIImage(systemName: "square.and.pencil")) { action in
            // Show rename UI
        }

        let neverMind = UIAction(title: "Never Mind", image: UIImage(systemName: "nosign")) { action in

        }

        let confirm = UIAction(title: "Confirm", image: UIImage(systemName: "trash"), attributes: .destructive) { action in
            self.delete(item: message, in: indexPath.section)
        }

        let deleteMenu = UIMenu(title: "Delete", image: UIImage(systemName: "trash"), options: .destructive, children: [confirm, neverMind])

        let readOk = UIAction(title: "Ok", image: UIImage(systemName: "hand.thumbsup")) { action in
            self.setToRead(message: message)
        }

        let readCancel = UIAction(title: "Never mind", image: UIImage(systemName: "nosign")) { action in
        }

        let readMenu = UIMenu(title: "Set messages to read", image: UIImage(systemName: "eyeglasses"), children: [readCancel, readOk])

        if message.isFromCurrentUser {
            return UIMenu(title: "Options", children: [deleteMenu, share, editMessage])
        }

        // Create and return a UIMenu with the share action
        return UIMenu(title: "Options", children: [share, readMenu])
    }

    private func setToRead(message: Messageable) {
        guard let current = User.current() else { return }
        message.udpateConsumers(with: current)
    }
}
