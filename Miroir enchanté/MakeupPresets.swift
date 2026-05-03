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
}

struct BlushPreset {
    let titleKey: String
    let baseColor: UIColor
    let roughness: Float
    let opacity: Float
}

enum MakeupPresets {
    static let lipstick: [LipstickPreset] = [
        LipstickPreset(titleKey: "preset.nude", baseColor: UIColor(red: 0.63, green: 0.36, blue: 0.29, alpha: 1.0), roughness: 0.38, opacity: 0.54),
        LipstickPreset(titleKey: "preset.rosewood", baseColor: UIColor(red: 0.68, green: 0.28, blue: 0.31, alpha: 1.0), roughness: 0.34, opacity: 0.58),
        LipstickPreset(titleKey: "preset.coral", baseColor: UIColor(red: 0.89, green: 0.24, blue: 0.20, alpha: 1.0), roughness: 0.30, opacity: 0.60),
        LipstickPreset(titleKey: "preset.red", baseColor: UIColor(red: 0.70, green: 0.04, blue: 0.10, alpha: 1.0), roughness: 0.24, opacity: 0.66),
        LipstickPreset(titleKey: "preset.crimson", baseColor: UIColor(red: 0.58, green: 0.00, blue: 0.07, alpha: 1.0), roughness: 0.22, opacity: 0.68),
        LipstickPreset(titleKey: "preset.pink", baseColor: UIColor(red: 0.93, green: 0.26, blue: 0.48, alpha: 1.0), roughness: 0.30, opacity: 0.60),
        LipstickPreset(titleKey: "preset.berry", baseColor: UIColor(red: 0.55, green: 0.07, blue: 0.28, alpha: 1.0), roughness: 0.26, opacity: 0.64),
        LipstickPreset(titleKey: "preset.burgundy", baseColor: UIColor(red: 0.33, green: 0.02, blue: 0.09, alpha: 1.0), roughness: 0.20, opacity: 0.64)
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
}

extension LipstickSettings {
    static var presets: [LipstickPreset] { MakeupPresets.lipstick }
}

extension BlushSettings {
    static var presets: [BlushPreset] { MakeupPresets.blush }
}
