//
//  BaseCoordinator.swift
//  Jibber
//
//  Created by Benji Dodgson on 5/26/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Coordinator
import Combine

class BaseCoordinator<ResultType>: Coordinator<ResultType> {
    
    var deepLink: DeepLinkable?
    var taskPool = TaskPool()
    
    var cancellables = Set<AnyCancellable>()
    
    init(router: CoordinatorRouter, deepLink: DeepLinkable?) {
        self.deepLink = deepLink
        super.init(router: router)
    }
    
}
