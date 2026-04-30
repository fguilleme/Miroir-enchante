//
//  Localization.swift
//  Miroir enchanté
//

import Foundation

enum L10n {
    static func text(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}
