//
//  MakeupSettings.swift
//  Miroir enchanté
//

import UIKit

struct LipstickSettings {
    var color: UIColor
    var opacity: CGFloat
    var roughness: CGFloat
    var glossIntensity: CGFloat
    var colorIntensity: CGFloat

    static let `default` = LipstickSettings(
        color: UIColor(red: 0.62, green: 0.04, blue: 0.11, alpha: 1.0),
        opacity: 0.58,
        roughness: 0.24,
        glossIntensity: 0.55,
        colorIntensity: 1.0
    )
}

struct BlushSettings {
    var color: UIColor
    var opacity: CGFloat
    var roughness: CGFloat
    var intensity: CGFloat
    var size: CGFloat
    var position: CGFloat

    static let `default` = BlushSettings(
        color: UIColor(red: 0.92, green: 0.36, blue: 0.31, alpha: 1.0),
        opacity: 0.34,
        roughness: 0.68,
        intensity: 0.42,
        size: 1.0,
        position: 0.5
    )
}
