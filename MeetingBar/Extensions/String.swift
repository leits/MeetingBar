//
//  String.swift
//  MeetingBar
//
//  Created by Jens Goldhammer on 29.12.20.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//

import Foundation

extension String {
    enum TruncationPosition {
        case head
        case middle
        case tail
    }

    /// Returns a truncated version of the string, limited to the specified length
    /// in characters, indicating the truncating with an optional truncation mark.
    /// - Parameters:
    ///   - limit: Desired maximum length of the string.
    ///   - position: The position where the truncation should be applied.
    ///   - truncationMark: A string that will be placed at the truncation position.
    /// - Returns: The truncated string, if applicable.
    func truncated(to limit: Int, at position: TruncationPosition = .tail, truncationMark: String = "…") -> String {
        guard self.count > limit else {
            return self
        }

        switch position {
        case .head:
            return truncationMark + self.suffix(limit)

        case .middle:
            let headCharactersCount = Int(ceil(Float(limit - truncationMark.count) / 2.0))
            let tailCharactersCount = Int(floor(Float(limit - truncationMark.count) / 2.0))
            return "\(self.prefix(headCharactersCount))\(truncationMark)\(self.suffix(tailCharactersCount))"

        case .tail:
            return self.prefix(limit) + truncationMark
        }
    }


    /// Returns a version of the first occurence of `target` is replaced by `replacement`.
    /// - Parameters:
    ///   - target: The string to search for.
    ///   - replacement: The replacement string.
    /// - Returns: The string with the replacement, if any.
    func replacingFirstOccurrence(of target: String, with replacement: String) -> String {
        if let range = self.range(of: target) {
            return self.replacingCharacters(in: range, with: replacement)
        }
        return self
    }

    /// A Boolean value indicating whether the string contains HTML tags.
    var containsHTML: Bool {
        let htmlRange = self.range(of: #"</?[A-z][ \t\S]*>"#, options: .regularExpression)
        return htmlRange != nil
    }

    /// Returns a version of the string with all HTML tags removed, if any.
    /// - Returns: The string without HTML tags.
    func htmlTagsStripped() -> String {
        if self.containsHTML,
           let data = self.data(using: .utf8),
           let attributedSelf = NSAttributedString(
            html: data,
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

    func fileExtension() -> String {
        URL(fileURLWithPath: self).pathExtension
    }
}
