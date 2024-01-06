//
//  String.swift
//  MeetingBar
//
//  Created by Jens Goldhammer on 29.12.20.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//

import Foundation

extension String {
    /// Returns a version of the first occurence of `target` is replaced by `replacement`.
    /// - Parameters:
    ///   - target: The string to search for.
    ///   - replacement: The replacement string.
    /// - Returns: The string with the replacement, if any.
    func replacingFirstOccurrence(of target: String, with replacement: String) -> String {
        if let range = range(of: target) {
            return replacingCharacters(in: range, with: replacement)
        }
        return self
    }

    /// A Boolean value indicating whether the string contains HTML tags.
    var containsHTML: Bool {
        let htmlRange = range(of: #"</?[A-z][ \t\S]*>"#, options: .regularExpression)
        return htmlRange != nil
    }

    /// Returns a version of the string with all HTML tags removed, if any.
    /// - Returns: The string without HTML tags.
    func htmlTagsStripped() -> String {
        if containsHTML,
           let dataUTF16 = data(using: .utf16),
           let attributedSelf = NSAttributedString(
               html: dataUTF16,
               options: [.documentType: NSAttributedString.DocumentType.html],
               documentAttributes: nil
           ) {
            return attributedSelf.string
        }
        return self
    }

    func fileName() -> String {
        URL(fileURLWithPath: self).deletingPathExtension().lastPathComponent
    }

    func decodeUrl() -> String? {
        removingPercentEncoding
    }

    func loco() -> String {
        I18N.instance.localizedString(for: self)
    }

    func loco(_ arg: CVarArg) -> String {
        I18N.instance.localizedString(for: self, arg)
    }

    func loco(_ firstArg: CVarArg, _ secondArg: CVarArg) -> String {
        I18N.instance.localizedString(for: self, firstArg, secondArg)
    }

    func loco(_ firstArg: CVarArg, _ secondArg: CVarArg, _ thirdArg: CVarArg) -> String {
        I18N.instance.localizedString(for: self, firstArg, secondArg, thirdArg)
    }

    func splitWithNewLineString(with attributes: [NSAttributedString.Key: Any], maxWidth: CGFloat) -> String {
        let words = split(separator: " ").map { String($0) }
        var lineWidth: CGFloat = 0.0
        var thisLine = ""
        var lines: [String] = []

        func width(for string: String) -> CGFloat {
            string.boundingRect(with: NSSize.zero, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes).width
        }

        func addToAllLines(_ text: String) {
            lines.append(text)
            thisLine = ""
            lineWidth = 0.0
        }

        for (idx, word) in words.enumerated() {
            thisLine = thisLine.appending("\(word) ")

            lineWidth = width(for: thisLine)

            let isLastWord = idx + 1 >= words.count
            if isLastWord {
                addToAllLines(thisLine)
            } else {
                let nextWord = words[idx + 1]
                if lineWidth + width(for: nextWord) >= maxWidth {
                    addToAllLines(thisLine)
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    func splitWithNewLineAttributedString(with attributes: [NSAttributedString.Key: Any], maxWidth: CGFloat) -> NSAttributedString {
        let output = splitWithNewLineString(with: attributes, maxWidth: maxWidth)
        let attributedString = NSAttributedString(string: output, attributes: attributes)
        return attributedString
    }
}

extension NSAttributedString {
    func withLinksEnabled() -> NSAttributedString {
        let newAttributedString = NSMutableAttributedString(attributedString: self)
        for match in UtilsRegex.linkDetection.matches(in: string, range: NSRange(location: 0, length: string.utf16.count)) {
            guard let range = Range(match.range, in: string) else {
                continue
            }
            let urlString = String(string[range])
            guard let url = URL(string: urlString) else {
                continue
            }
            newAttributedString.addAttribute(.link, value: url, range: match.range)
        }
        return NSAttributedString(attributedString: newAttributedString)
    }
}
