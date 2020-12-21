//
//  ChannelManager.swift
//  Benji
//
//  Created by Benji Dodgson on 1/29/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import TwilioChatClient
import ReactiveSwift
import Parse
import Combine

class ChannelManager: NSObject {

    static let shared = ChannelManager()
    var client: TwilioChatClient?

    @Published var clientSyncUpdate: TCHClientSynchronizationStatus? = nil
    @Published var clientUpdate: ChatClientUpdate? = nil 
    var channelSyncUpdate = MutableProperty<ChannelSyncUpdate?>(nil)
    var channelsUpdate = MutableProperty<ChannelUpdate?>(nil)
    var messageUpdate = MutableProperty<MessageUpdate?>(nil)
    var memberUpdate = MutableProperty<ChannelMemberUpdate?>(nil)

    var isSynced: Bool {
        guard let client = self.client else { return false }
        if client.synchronizationStatus == .completed || client.synchronizationStatus == .channelsListCompleted {
            return true
        }

        return false
    }

    var isConnected: Bool {
        guard let client = self.client else { return false }
        return client.connectionState == .connected
    }
}
