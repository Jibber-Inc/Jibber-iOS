//
//  Weather.swift
//  Jibber
//
//  Created by Benji Dodgson on 9/26/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore
import WeatherKit

enum WeatherKey: String {
    case symbolName
    case condition
    case temperature
}

final class Weather: PFObject, PFSubclassing, @unchecked Sendable {
    
    static func parseClassName() -> String {
        return String(describing: self)
    }
    
    @available(iOS 16.0, *)
    init(with currentWeather: CurrentWeather) {
        super.init(className: Weather.parseClassName())

        self.symbolName = currentWeather.symbolName
        self.condition = currentWeather.condition.description
    }
    
    var symbolName: String? {
        get { self.getObject(for: .symbolName) }
        set { self.setObject(for: .symbolName, with: newValue) }
    }
    
    var condition: String? {
        get { self.getObject(for: .condition) }
        set { self.setObject(for: .condition, with: newValue) }
    }
    
    var temperature: String? {
        get { self.getObject(for: .temperature) }
        set { self.setObject(for: .temperature, with: newValue) }
    }
}

extension Weather: Objectable {
    typealias KeyType = WeatherKey
    
    func getObject<Type>(for key: WeatherKey) -> Type? {
        return self.object(forKey: key.rawValue) as? Type
    }
    
    func setObject<Type>(for key: WeatherKey, with newValue: Type) {
        self.setObject(newValue, forKey: key.rawValue)
    }
    
    func getRelationalObject<PFRelation>(for key: WeatherKey) -> PFRelation? {
        return self.relation(forKey: key.rawValue) as? PFRelation
    }
}

extension Weather: ImageDisplayable {
    
    var image: UIImage? {
        guard let symbolName = self.symbolName else { return nil }
        return UIImage(systemName: symbolName)
    }
}
