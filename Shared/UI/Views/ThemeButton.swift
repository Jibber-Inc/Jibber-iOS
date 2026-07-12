//
//  Button.swift
//  Benji
//
//  Created by Benji Dodgson on 2/4/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Lottie
import Combine
import Localization
import UIKit

enum ButtonStyle {
    case image(symbol: ImageSymbol,
               palletteColors: [ThemeColor],
               pointSize: CGFloat,
               backgroundColor: ThemeColor)
    
    case normal(color: ThemeColor, text: Localized)
    case custom(color: ThemeColor, textColor: ThemeColor, text: Localized)
}

class ThemeButton: UIButton, Statusable {

    let alphaOutAnimator = UIViewPropertyAnimator(duration: Theme.animationDurationStandard,
                                                  curve: .linear,
                                                  animations: nil)

    let alphaInAnimator = UIViewPropertyAnimator(duration: Theme.animationDurationStandard,
                                                 curve: .linear,
                                                 animations: nil)

    /// Used to store the initial color of the button to return to from error state
    var defaultColor: ThemeColor?

    let animationView = LottieAnimationView.with(animation: .loading)

    var style: ButtonStyle?
    lazy var errorLabel = ThemeLabel(font: .regular)

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.initializeSubviews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        self.initializeSubviews()
    }

    func initializeSubviews() {
        self.addSubview(self.animationView)
        self.animationView.contentMode = .scaleAspectFit
        self.animationView.loopMode = .loop

        self.addSubview(self.errorLabel)
        self.errorLabel.alpha = 0.0
    }

    //Sets text font, color and background color
    func set(style: ButtonStyle, casingType: StringCasing = .unchanged) {
        self.style = style

        switch style {
        case .image(let symbol, let symbolColors, let pointSize, let backgroundColor):
            
            var config = UIImage.SymbolConfiguration(pointSize: pointSize)
            var highlightConfig = UIImage.SymbolConfiguration(pointSize: pointSize * 0.9)
            
            let colors = symbolColors.map { color in
                return color.color
            }
            config = config.applying(UIImage.SymbolConfiguration.init(paletteColors: colors))
            highlightConfig = highlightConfig.applying(UIImage.SymbolConfiguration.init(paletteColors: colors))
            
            self.setImage(symbol.image, for: .normal)
            
            self.setImage(symbol.highlightSymbol?.image, for: .highlighted)
            self.setImage(symbol.selectedSymbol?.image, for: .selected)
            
            self.setPreferredSymbolConfiguration(config, forImageIn: .normal)
            
            self.setPreferredSymbolConfiguration(highlightConfig, forImageIn: .highlighted)
            
            if backgroundColor != .clear {
                self.setBackground(color: backgroundColor.color.resolvedColor(with: self.traitCollection), forUIControlState: .normal)
                self.setBackground(color: backgroundColor.color.resolvedColor(with: self.traitCollection), forUIControlState: .highlighted)
                self.setBackground(color: backgroundColor.color.resolvedColor(with: self.traitCollection), forUIControlState: .disabled)
            }
            
        case .custom(let color, let textColor, let text):
            self.setImage(nil, for: .normal)
            self.defaultColor = color

            var localizedString = localized(text)

            localizedString = casingType.format(string: localizedString)

            let normalString = NSMutableAttributedString(string: localizedString)
            normalString.addAttribute(.font, value: FontType.regular.font)

            let highlightedString = NSMutableAttributedString(string: localizedString)
            highlightedString.addAttribute(.font, value: FontType.regular.font)

            normalString.addAttribute(.foregroundColor, value: textColor.color.resolvedColor(with: self.traitCollection))
            highlightedString.addAttribute(.foregroundColor, value: textColor.color.resolvedColor(with: self.traitCollection))
    
            if color != .clear {
                self.setBackground(color: color.color.resolvedColor(with: self.traitCollection), forUIControlState: .normal)
            }

            self.setBackground(color: color.color.withAlphaComponent(0.9).resolvedColor(with: self.traitCollection), forUIControlState: .highlighted)
            self.setBackground(color: color.color.withAlphaComponent(0.9).resolvedColor(with: self.traitCollection), forUIControlState: .disabled)

            self.setAttributedTitle(normalString, for: .normal)
            self.setAttributedTitle(highlightedString, for: .highlighted)
            
        case .normal(let color, let text):
            self.setImage(nil, for: .normal)
            self.defaultColor = color

            var localizedString = localized(text)

            localizedString = casingType.format(string: localizedString)

            let normalString = NSMutableAttributedString(string: localizedString)
            normalString.addAttribute(.font, value: FontType.regular.font)

            let highlightedString = NSMutableAttributedString(string: localizedString)
            highlightedString.addAttribute(.font, value: FontType.regular.font)

            normalString.addAttribute(.foregroundColor, value: ThemeColor.white.color.resolvedColor(with: self.traitCollection))
            highlightedString.addAttribute(.foregroundColor, value: ThemeColor.white.color.resolvedColor(with: self.traitCollection))
            
            if color != .clear {
                self.setBackground(color: color.color.resolvedColor(with: self.traitCollection), forUIControlState: .normal)
            }

            self.setBackground(color: color.color.withAlphaComponent(0.9).resolvedColor(with: self.traitCollection), forUIControlState: .highlighted)
            self.setBackground(color: color.color.withAlphaComponent(0.9).resolvedColor(with: self.traitCollection), forUIControlState: .disabled)

            self.setAttributedTitle(normalString, for: .normal)
            self.setAttributedTitle(highlightedString, for: .highlighted)
        }

        self.layer.cornerRadius = Theme.cornerRadius
        self.layer.masksToBounds = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        if self.animationView.isAnimationPlaying {
            self.animationView.size = CGSize(width: 18, height: 18)
        } else {
            self.animationView.size = .zero
        }
        self.animationView.centerOnXAndY()

        self.errorLabel.setSize(withWidth: self.width - 40)
        self.errorLabel.textAlignment = .center
        self.errorLabel.centerOnXAndY()
    }

    func setBackground(color: UIColor, forUIControlState state: UIControl.State) {
        Task.onMainActor {
            self.setBackgroundImage(UIImage.imageWithColor(color: color), for: state)
        }
    }

    func setSize(with width: CGFloat) {
        self.size = CGSize(width: Theme.getPaddedWidth(with: width), height: Theme.buttonHeight)
    }

    func handleEvent(status: EventStatus) async {
        switch status {
        case .loading, .initial:
            await self.handleLoadingState()
        case .complete, .saved, .invalid, .custom(_), .valid, .cancelled:
            await self.handleNormalState()
        case .error(let message):
            await self.handleError(message)
        }
    }
}
