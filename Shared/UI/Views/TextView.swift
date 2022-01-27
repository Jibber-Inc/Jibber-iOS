//
//  TextView.swift
//  Benji
//
//  Created by Benji Dodgson on 12/25/18.
//  Copyright © 2018 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine
import Localization

class TextView: UITextView {

    // Trim white space and newline characters when end editing. Default is true
    var trimWhiteSpaceWhenEndEditing: Bool = true

    // Maximum length of text. 0 means no limit.
    var maxLength: Int = 250

    var cancellables = Set<AnyCancellable>()

    var numberOfLines: Int {
        guard let lineHeight = self.font?.lineHeight else { return 0 }
        let height = self.contentSize.height - self.textContainerInset.top - self.textContainerInset.bottom
        return Int(height / lineHeight)
    }

    override var text: String! {
        get { return super.text }
        set {
            // Always have some text in this textview so that we don't lose the text attributes.
            let string = newValue ?? ""
            self.setTextWithAttributes(string)
        }
    }

    /// Kerning to be applied to all text in this text view. If an attributed string is set manually, there is no guarantee that this variable
    /// will be accurate, but setting it will update kerning on all text in the label.
    var kerning: CGFloat {
        didSet {
            guard let text = self.text else { return }
            self.setTextWithAttributes(text)
        }
    }

    /// Line spacing for consecutive lines of text. If an attributed string is set manually, there is no guarantee that this variable
    /// will be accurate, but setting it will update line spacing on all text in the label.
    var lineSpacing: CGFloat = 0 {
        didSet {
            guard let text = self.text else { return }
            self.setTextWithAttributes(text)
        }
    }

    /// The string attributes to apply to any text given this label's assigned font and font color.
    private var attributes: [NSAttributedString.Key: Any] {
        let font = self.font ?? UIFont.systemFont(ofSize: UIFont.systemFontSize)
        let textColor = self.textColor ?? UIColor.black
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = self.textAlignment
        paragraphStyle.lineSpacing = self.lineSpacing

        return [.font: font,
                .kern: self.kerning,
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle]
    }

    private var attributedPlaceholder: NSAttributedString? {
        didSet {
            self.setNeedsDisplay()
        }
    }

    init(frame: CGRect = .zero,
         font: FontType,
         textColor: ThemeColor,
         textContainer: NSTextContainer? = nil) {

        self.kerning = font.kern

        super.init(frame: frame, textContainer: textContainer)

        self.font = font.font
        self.textColor = textColor.color.resolvedColor(with: self.traitCollection)

        self.initializeViews()
    }

    required init?(coder aDecoder: NSCoder) {
        self.kerning = FontType.regularBold.kern

        super.init(coder: aDecoder)

        self.font = FontType.regularBold.font
        self.textColor = ThemeColor.T1.color.resolvedColor(with: self.traitCollection)

        self.initializeViews()

    }

    convenience init() {
        self.init(frame: .zero, font: .smallBold, textColor: .T1, textContainer: nil)
    }

    func initializeViews() {
        // Give the text view an initial value so to get our attributes bootstrapped.
        self.text = ""

        self.contentMode = .redraw

        self.keyboardAppearance = .dark

        self.textContainer.lineBreakMode = .byWordWrapping
        self.textContainer.lineFragmentPadding = 0

        self.textAlignment = .center
        self.isUserInteractionEnabled = true
        self.dataDetectorTypes = .all

        self.set(backgroundColor: .clear)

        NotificationCenter.default.publisher(for: UITextView.textDidChangeNotification)
            .mainSink { [unowned self] (text) in
                self.textDidChange()
            }.store(in: &self.cancellables)

        NotificationCenter.default.publisher(for: UITextView.textDidBeginEditingNotification)
            .mainSink { [unowned self] (text) in
                self.textViewDidBeginEditing()
            }.store(in: &self.cancellables)

        NotificationCenter.default.publisher(for: UITextView.textDidEndEditingNotification)
            .mainSink { [unowned self] (text) in
                self.textViewDidEndEditing()
            }.store(in: &self.cancellables)
    }

    // MARK: Setters
    
    func setText(_ localizedText: Localized?) {
        guard let localizedText = localizedText else {
            self.text = nil
            return
        }
        self.text = localized(localizedText)
    }

    func setFont(_ fontType: FontType) {
        self.font = fontType.font
        self.kerning = fontType.kern
    }

    func setTextColor(_ textColor: ThemeColor) {
        self.textColor = textColor.color.resolvedColor(with: self.traitCollection)
    }

    func set(placeholder: Localized, color: ThemeColor = .T1withAlpha) {
        var styleAttributes = StringStyle(font: .regular, color: color).attributes
        let centeredParagraphStyle = NSMutableParagraphStyle()
        centeredParagraphStyle.alignment = .center
        styleAttributes[.paragraphStyle] = centeredParagraphStyle
        let string = NSAttributedString(string: localized(placeholder), attributes: styleAttributes)
        self.attributedPlaceholder = string
    }

    private func setTextWithAttributes(_ newText: String) {
        let attributedString = NSMutableAttributedString(string: newText)
        attributedString.addAttributes(self.attributes,
                                       range: NSRange(location: 0, length: attributedString.length))
        self.attributedText = attributedString

        self.typingAttributes = self.attributes
    }

    /// Adds the provided attributes to all the text in the view while preserving the existing attributes.
    func addTextAttributes(_ attributes: [NSAttributedString.Key : Any]) {
        guard let current = self.attributedText else { return }

        let newString = NSMutableAttributedString(current)
        let range = NSMakeRange(0, newString.string.count)
        newString.addAttributes(attributes, range: range)
        self.attributedText = newString
    }

    func reset() {
        self.text = ""
        self.textDidChange()
    }

    // Trim white space and new line characters when end editing.
    func textViewDidEndEditing() {
        if self.trimWhiteSpaceWhenEndEditing {
            self.text = self.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.setNeedsDisplay()
        }
        self.scrollToCorrectPosition()
    }

    // Limit the length of text
    func textDidChange() {
        if self.maxLength > 0 && self.text.count > self.maxLength {
            let endIndex = self.text.index(self.text.startIndex, offsetBy: self.maxLength)
            self.text = String(self.text[..<endIndex])
            self.undoManager?.removeAllActions()
        }
        self.setNeedsDisplay()
    }

    func textViewDidBeginEditing() {}

    func scrollToCorrectPosition() {
        if self.isFirstResponder {
            self.scrollRangeToVisible(NSMakeRange(-1, 0)) // Scroll to bottom
        } else {
            self.scrollRangeToVisible(NSMakeRange(0, 0)) // Scroll to top
        }
    }

    // Show placeholder if needed
    override func draw(_ rect: CGRect) {
        super.draw(rect)

        if self.text.isEmpty {
            let xValue = self.textContainerInset.left + self.textContainer.lineFragmentPadding
            let yValue = self.textContainerInset.top
            let width = rect.size.width - xValue - self.textContainerInset.right
            let height = rect.size.height - yValue - self.textContainerInset.bottom
            let placeholderRect = CGRect(x: xValue, y: yValue, width: width, height: height)

            if let attributedPlaceholder = self.attributedPlaceholder {
                // Prefer to use attributedPlaceholder
                attributedPlaceholder.draw(in: placeholderRect)
            }
        }
    }

    func setSize(withMaxWidth maxWidth: CGFloat, maxHeight: CGFloat = CGFloat.infinity) {
        self.size = self.getSize(withMaxWidth: maxWidth, maxHeight: maxHeight)
    }

    func getSize(withMaxWidth maxWidth: CGFloat, maxHeight: CGFloat = CGFloat.infinity) -> CGSize {
        guard let text = self.text, !text.isEmpty, let attText = self.attributedText else {
            return CGSize.zero
        }

        let horizontalPadding = self.contentInset.horizontal + self.textContainerInset.horizontal
        let verticalPadding = self.contentInset.vertical + self.textContainerInset.vertical

        // Get the max size available for the text, taking the textview's insets into account.
        let maxTextSize = CGSize(width: maxWidth - horizontalPadding, height: maxHeight - verticalPadding)

        var size: CGSize = attText.boundingRect(with: maxTextSize,
                                                options: .usesLineFragmentOrigin,
                                                context: nil).size

        // Add back the spacing for the text container insets, but ensure we don't exceed the maximum.
        size.width += horizontalPadding
        size.width = clamp(size.width, max: maxWidth)

        size.height += verticalPadding
        size.height = clamp(size.height, max: maxHeight)

        return size
    }
}
