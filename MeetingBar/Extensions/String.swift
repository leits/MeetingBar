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

    /*
     Truncates the string to the specified length number of characters and appends an optional trailing string if longer.
     - Parameter length: Desired maximum lengths of a string
     - Parameter trailing: A 'String' that will be appended after the truncation.
     
     - Returns: 'String' object.
     */
    func trunc(limit: Int, position: TruncationPosition = .tail, leader: String = "...") -> String {
        guard self.count > limit else {
            return self
        }

        switch position {
        case .head:
            return leader + self.suffix(limit)
        case .middle:
            let headCharactersCount = Int(ceil(Float(limit - leader.count) / 2.0))

            let tailCharactersCount = Int(floor(Float(limit - leader.count) / 2.0))

            return "\(self.prefix(headCharactersCount))\(leader)\(self.suffix(tailCharactersCount))"
        case .tail:
            return self.prefix(limit) + leader
        }
    }


    func stringByReplacingFirstOccurrenceOfString( target: String, withString replaceString: String ) -> String {
        if let range = self.range(of: target) {
            return self.replacingCharacters(in: range, with: replaceString)
        }
        return self
    }

    /// A Boolean value indicating whether the string contains HTML tags.
    var containsHTML: Bool {
        let htmlTest = NSPredicate(format: "SELF MATCHES %@", #"</?[A-z][ \t\S]*>"#)
        return htmlTest.evaluate(with: self)
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
}
