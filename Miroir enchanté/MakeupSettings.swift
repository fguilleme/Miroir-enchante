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

struct ContourSettings {
    var color: UIColor
    var opacity: CGFloat
    var intensity: CGFloat
    var softness: CGFloat
    var isEnabled: Bool

    static let `default` = ContourSettings(
        color: UIColor(red: 0.42, green: 0.25, blue: 0.19, alpha: 1.0),
        opacity: 0.16,
        intensity: 0.22,
        softness: 0.82,
        isEnabled: true
    )
}

enum MakeupIntensityCurve {
    static func response(_ value: CGFloat) -> CGFloat {
        let clampedValue = Swift.min(Swift.max(value, 0), 1)
        guard clampedValue > 0.8 else { return clampedValue }

        let normalizedTail = (clampedValue - 0.8) / 0.2
        let exponentialTail = (exp(3.0 * normalizedTail) - 1.0) / (exp(3.0) - 1.0)
        return 0.8 + exponentialTail * 0.2
    }

    static func response(_ value: CGFloat, in range: ClosedRange<CGFloat>) -> CGFloat {
        let clampedValue = Swift.min(Swift.max(value, range.lowerBound), range.upperBound)
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return clampedValue }

        let normalizedValue = (clampedValue - range.lowerBound) / span
        return range.lowerBound + response(normalizedValue) * span
    }
}
