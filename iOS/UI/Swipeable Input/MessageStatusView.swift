//
//  newStatusView.swift
//  Jibber
//
//  Created by Benji Dodgson on 12/16/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import SwiftUI

/// A view that shows the read status and reply count of a message.
struct MessageStatusView: View {

    @ObservedObject var config: MessageDetailViewState

    var body: some View {
        HStack {
            MessageReadView(config: self.config)

            // Don't show the replies view if there aren't any replies.
            if self.config.replyCount > 0 {
                Spacer.length(.short)
                MessageReplyView(config: self.config)
            }
        }
    }
}

/// A subview of the message status view that specifically shows read status of message.
private struct MessageReadView: View {
    
    @ObservedObject var config: MessageDetailViewState
    
    var body: some View {
        HStack {
            Spacer.length(.standard)

            if let updateDate = self.config.updateDate {
                let dateString = updateDate.getTimeAgoString() 
                Text(dateString)
                    .fontType(.small)
                    .color(.T1)

                Spacer.length(.standard)
            }

            MessageDeliveryStatusUIViewRepresentable(message: self.$config.message,
                                                 readingState: self.$config.readingState)
                .frame(width: 25)

            Spacer.length(.standard)
        }
        .frame(minHeight: 25, idealHeight: 25, maxHeight: 25)
        .background(
            RoundedRectangle(cornerRadius: Theme.innerCornerRadius)
                .fill(color: .B1withAlpha,
                      strokeColor: .D6withAlpha,
                      lineWidth: 0.5)

        )
    }
}

/// A subview of the message status view that specifically shows how many replies a message has..
private struct MessageReplyView: View {
    
    @ObservedObject var config: MessageDetailViewState
    
    var body: some View {
        HStack {
            Spacer.length(.standard)
            Text(self.config.replyCount.description)
                .fontType(.small)
                .color(.T1)
            Spacer.length(.standard)
        }
        .frame(minWidth: 25, minHeight: 25, idealHeight: 25, maxHeight: 25)
        .background(
            RoundedRectangle(cornerRadius: Theme.innerCornerRadius)
                .fill(color: .B1withAlpha,
                      strokeColor: .D6withAlpha,
                      lineWidth: 0.5)

        )
    }
}

struct StatusView_Previews: PreviewProvider {

    static var previews: some View {
        let config = MessageDetailViewState(message: MockMessage())
        MessageStatusView(config: config).preferredColorScheme(.dark)
    }
}
