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
    var specularIntensity: CGFloat
    var colorVariation: CGFloat

    static let `default` = LipstickSettings(
        color: UIColor(red: 0.62, green: 0.04, blue: 0.11, alpha: 1.0),
        opacity: 0.58,
        roughness: 0.24,
        glossIntensity: 0.55,
        colorIntensity: 1.0,
        specularIntensity: 0.55,
        colorVariation: 0.35
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

struct EyeshadowSettings {
    var color: UIColor
    var opacity: CGFloat
    var roughness: CGFloat
    var intensity: CGFloat
    var shimmerIntensity: CGFloat

    static let `default` = EyeshadowSettings(
        color: UIColor(red: 0.58, green: 0.34, blue: 0.47, alpha: 1.0),
        opacity: 0.38,
        roughness: 0.58,
        intensity: 0.72,
        shimmerIntensity: 0.18
    )
}

struct GlowSettings {
    var color: UIColor
    var opacity: CGFloat
    var intensity: CGFloat
    var radius: CGFloat
    var specularBoost: CGFloat
    var isEnabled: Bool

    static let `default` = GlowSettings(
        color: UIColor(red: 1.0, green: 0.86, blue: 0.68, alpha: 1.0),
        opacity: 0.18,
        intensity: 0.36,
        radius: 1.0,
        specularBoost: 0.08,
        isEnabled: true
    )
}
