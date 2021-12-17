//
//  newStatusView.swift
//  Jibber
//
//  Created by Benji Dodgson on 12/16/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import SwiftUI

struct newReadView: View {
    
    @State var message: Messageable?
    
    var body: some View {
        HStack {
            Spacer.length(.short)
            Text("Read")
                .fontType(.small)
                .color(.textColor)
            Spacer.length(.short)
            Image("checkmark-double")
                .color(.white)
            Spacer.length(.short)
        }.color(.white, alpha: 0.1)
            .cornerRadius(5)
    }
}

struct newReplyView: View {
    
    @State var message: Messageable?
    
    var body: some View {
        HStack {
            Spacer.length(.short)
            Text("Replies")
                .fontType(.small)
                .color(.textColor)
            Spacer.length(.short)
            Text("1")
                .fontType(.xtraSmall)
                .color(.white)
            Spacer.length(.short)
        }.color(.red, alpha: 1.0)
            .cornerRadius(5)
    }
}

struct newStatusView: View {
    
    @State var message: Messageable?
    
    var body: some View {
        HStack {
            newReadView()
            Spacer.length(.short)
            newReplyView()
        }
    }
}

struct newStatusView_Previews: PreviewProvider {
    static var previews: some View {
        newStatusView(message: nil).preferredColorScheme(.dark)
    }
}
