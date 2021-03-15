//
//  PostViewController.swift
//  Ours
//
//  Created by Benji Dodgson on 2/14/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation

class PostViewController: ViewController {

    let post: Postable

    var type: PostType {
        return self.post.type
    }

    var attributes: [String: Any]? {
        return self.post.attributes
    }

    var didFinish: CompletionOptional = nil
    var didPause: CompletionOptional = nil
    var didSelectPost: CompletionOptional = nil 

    let container = View()
    let bottomContainer = View()

    // Common items
    let textView = PostTextView()
    let avatarView = AvatarView()
    let button = Button()

    init(with post: Postable) {
        self.post = post
        super.init()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func initializeViews() {
        super.initializeViews()

        self.view.addSubview(self.container)
        self.container.didSelect { [unowned self] in
            self.didFinish?()
        }

        self.container.addSubview(self.getCenterContent())
        self.container.addSubview(self.bottomContainer)
        self.bottomContainer.addSubview(self.getBottomContent())
        self.container.addSubview(self.avatarView)

        self.button.didSelect { [unowned self] in
            self.didTapButton()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.configurePost()
    }

    func configurePost() {}
    func didTapButton() {}

    func getCenterContent() -> UIView {
        return self.textView
    }

    func getBottomContent() -> UIView {
        return self.button
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        self.container.size = CGSize(width: self.view.width, height: self.view.safeAreaRect.height)
        self.container.pinToSafeArea(.top, padding: 0)
        self.container.centerOnX()

        if let first = self.container.subviews.first {
            first.frame = self.container.bounds
        }

        self.avatarView.setSize(for: 60)
        self.avatarView.pin(.left, padding: Theme.contentOffset)
        self.avatarView.pin(.top, padding: Theme.contentOffset.doubled)
        self.avatarView.isHidden = self.avatarView.avatar.isNil

        self.bottomContainer.size = CGSize(width: self.container.width, height: Theme.buttonHeight)
        self.bottomContainer.pin(.bottom, padding: Theme.contentOffset)

        self.textView.setSize(withWidth: self.container.width * 0.9)
        self.textView.centerOnXAndY()

        self.button.setSize(with: self.bottomContainer.width)
        self.button.centerOnXAndY()
    }
}
