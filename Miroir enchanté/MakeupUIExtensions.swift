//
//  MakeupUIExtensions.swift
//  Miroir enchanté
//

import UIKit

extension UIColor {
    func withBrightnessMultiplier(_ multiplier: CGFloat) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return self
        }

        return UIColor(
            red: min(max(red * multiplier, 0), 1),
            green: min(max(green * multiplier, 0), 1),
            blue: min(max(blue * multiplier, 0), 1),
            alpha: alpha
        )
    }
}
