//
//  MakeupPresets.swift
//  Miroir enchanté
//

import UIKit

struct LipstickPreset {
    let titleKey: String
    let baseColor: UIColor
    let roughness: Float
    let opacity: Float
    let specularIntensity: Float
    let colorVariation: Float

    init(
        titleKey: String,
        baseColor: UIColor,
        roughness: Float,
        opacity: Float,
        specularIntensity: Float = 0.55,
        colorVariation: Float = 0.35
    ) {
        self.titleKey = titleKey
        self.baseColor = baseColor
        self.roughness = roughness
        self.opacity = opacity
        self.specularIntensity = specularIntensity
        self.colorVariation = colorVariation
    }
}

struct BlushPreset {
    let titleKey: String
    let baseColor: UIColor
    let roughness: Float
    let opacity: Float
}

struct EyeshadowPreset {
    let titleKey: String
    let baseColor: UIColor
    let roughness: Float
    let opacity: Float
    let shimmer: Float
}

enum MakeupCategory {
    case looks
    case lips
    case blush
    case eyes
    case glow
}

struct GlowPreset {
    let name: String
    let color: UIColor
    let intensity: Float
    let radius: Float
    let specularBoost: Float
}

enum MakeupPresets {
    static let lipstick: [LipstickPreset] = [
        LipstickPreset(titleKey: "preset.nude", baseColor: UIColor(red: 0.63, green: 0.36, blue: 0.29, alpha: 1.0), roughness: 0.38, opacity: 0.54, specularIntensity: 0.42, colorVariation: 0.30),
        LipstickPreset(titleKey: "preset.rosewood", baseColor: UIColor(red: 0.68, green: 0.28, blue: 0.31, alpha: 1.0), roughness: 0.34, opacity: 0.58, specularIntensity: 0.55, colorVariation: 0.34),
        LipstickPreset(titleKey: "preset.coral", baseColor: UIColor(red: 0.89, green: 0.24, blue: 0.20, alpha: 1.0), roughness: 0.30, opacity: 0.60, specularIntensity: 0.62, colorVariation: 0.36),
        LipstickPreset(titleKey: "preset.red", baseColor: UIColor(red: 0.70, green: 0.04, blue: 0.10, alpha: 1.0), roughness: 0.24, opacity: 0.66, specularIntensity: 0.70, colorVariation: 0.40),
        LipstickPreset(titleKey: "preset.crimson", baseColor: UIColor(red: 0.58, green: 0.00, blue: 0.07, alpha: 1.0), roughness: 0.22, opacity: 0.68, specularIntensity: 0.74, colorVariation: 0.42),
        LipstickPreset(titleKey: "preset.pink", baseColor: UIColor(red: 0.93, green: 0.26, blue: 0.48, alpha: 1.0), roughness: 0.30, opacity: 0.60, specularIntensity: 0.65, colorVariation: 0.38),
        LipstickPreset(titleKey: "preset.berry", baseColor: UIColor(red: 0.55, green: 0.07, blue: 0.28, alpha: 1.0), roughness: 0.26, opacity: 0.64, specularIntensity: 0.72, colorVariation: 0.42),
        LipstickPreset(titleKey: "preset.burgundy", baseColor: UIColor(red: 0.33, green: 0.02, blue: 0.09, alpha: 1.0), roughness: 0.20, opacity: 0.64, specularIntensity: 0.78, colorVariation: 0.45)
    ]

    static let blush: [BlushPreset] = [
        BlushPreset(titleKey: "blush.nude", baseColor: UIColor(red: 0.78, green: 0.42, blue: 0.35, alpha: 1.0), roughness: 0.76, opacity: 0.24),
        BlushPreset(titleKey: "blush.peach", baseColor: UIColor(red: 0.98, green: 0.48, blue: 0.36, alpha: 1.0), roughness: 0.70, opacity: 0.30),
        BlushPreset(titleKey: "blush.soft_rose", baseColor: UIColor(red: 0.96, green: 0.38, blue: 0.54, alpha: 1.0), roughness: 0.68, opacity: 0.34),
        BlushPreset(titleKey: "blush.coral", baseColor: UIColor(red: 1.00, green: 0.30, blue: 0.31, alpha: 1.0), roughness: 0.66, opacity: 0.32),
        BlushPreset(titleKey: "blush.vintage_rose", baseColor: UIColor(red: 0.68, green: 0.18, blue: 0.28, alpha: 1.0), roughness: 0.72, opacity: 0.28),
        BlushPreset(titleKey: "blush.raspberry", baseColor: UIColor(red: 0.74, green: 0.08, blue: 0.32, alpha: 1.0), roughness: 0.66, opacity: 0.30),
        BlushPreset(titleKey: "blush.rosewood", baseColor: UIColor(red: 0.62, green: 0.24, blue: 0.32, alpha: 1.0), roughness: 0.72, opacity: 0.28)
    ]

    static let eyeshadow: [EyeshadowPreset] = [
        EyeshadowPreset(titleKey: "eyeshadow.taupe", baseColor: UIColor(red: 0.50, green: 0.38, blue: 0.34, alpha: 1.0), roughness: 0.64, opacity: 0.34, shimmer: 0.08),
        EyeshadowPreset(titleKey: "eyeshadow.rose", baseColor: UIColor(red: 0.74, green: 0.40, blue: 0.54, alpha: 1.0), roughness: 0.58, opacity: 0.38, shimmer: 0.16),
        EyeshadowPreset(titleKey: "eyeshadow.plum", baseColor: UIColor(red: 0.34, green: 0.16, blue: 0.32, alpha: 1.0), roughness: 0.52, opacity: 0.44, shimmer: 0.22),
        EyeshadowPreset(titleKey: "eyeshadow.copper", baseColor: UIColor(red: 0.78, green: 0.42, blue: 0.20, alpha: 1.0), roughness: 0.46, opacity: 0.42, shimmer: 0.34),
        EyeshadowPreset(titleKey: "eyeshadow.smoke", baseColor: UIColor(red: 0.18, green: 0.17, blue: 0.20, alpha: 1.0), roughness: 0.50, opacity: 0.48, shimmer: 0.12)
    ]

    static let glow: [GlowPreset] = [
        GlowPreset(name: "Natural Glow", color: UIColor(red: 1.0, green: 0.86, blue: 0.68, alpha: 1.0), intensity: 0.34, radius: 1.00, specularBoost: 0.07),
        GlowPreset(name: "Warm Gold", color: UIColor(red: 1.0, green: 0.76, blue: 0.42, alpha: 1.0), intensity: 0.38, radius: 1.04, specularBoost: 0.09),
        GlowPreset(name: "Pearl", color: UIColor(red: 0.92, green: 0.90, blue: 1.0, alpha: 1.0), intensity: 0.30, radius: 0.96, specularBoost: 0.10),
        GlowPreset(name: "Rosy Light", color: UIColor(red: 1.0, green: 0.72, blue: 0.78, alpha: 1.0), intensity: 0.32, radius: 1.02, specularBoost: 0.08)
    ]
}

extension LipstickSettings {
    static var presets: [LipstickPreset] { MakeupPresets.lipstick }
}

extension BlushSettings {
    static var presets: [BlushPreset] { MakeupPresets.blush }
}

extension EyeshadowSettings {
    static var presets: [EyeshadowPreset] { MakeupPresets.eyeshadow }
}

extension GlowSettings {
    static var presets: [GlowPreset] { MakeupPresets.glow }
}
