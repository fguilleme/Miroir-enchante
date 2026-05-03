//
//  MakeupLooks.swift
//  Miroir enchanté
//

import UIKit

typealias EyesPreset = EyeshadowPreset

struct MakeupLook: Equatable {
    let id: String
    let titleKey: String
    let lipstick: LipstickPreset
    let blush: BlushPreset
    let eyes: EyesPreset
    let lipstickFinish: LipstickFinish
    let lipstickIntensity: CGFloat
    let blushIntensity: CGFloat
    let blushSize: CGFloat
    let blushPosition: CGFloat
    let eyesIntensity: CGFloat

    var swatchColors: [UIColor] {
        [lipstick.baseColor, blush.baseColor, eyes.baseColor]
    }

    static func == (lhs: MakeupLook, rhs: MakeupLook) -> Bool { lhs.id == rhs.id }
}

enum MakeupLooks {
    static let all: [MakeupLook] = [
        MakeupLook(
            id: "natural_nude",
            titleKey: "look.natural_nude",
            lipstick: lipstick("preset.nude"),
            blush: blush("blush.nude"),
            eyes: eyes("eyeshadow.taupe"),
            lipstickFinish: .satin,
            lipstickIntensity: 0.70,
            blushIntensity: 0.30,
            blushSize: 1.00,
            blushPosition: 0.55,
            eyesIntensity: 0.45
        ),
        MakeupLook(
            id: "soft_rose",
            titleKey: "look.soft_rose",
            lipstick: lipstick("preset.rosewood"),
            blush: blush("blush.soft_rose"),
            eyes: eyes("eyeshadow.rose"),
            lipstickFinish: .satin,
            lipstickIntensity: 0.85,
            blushIntensity: 0.45,
            blushSize: 1.05,
            blushPosition: 0.50,
            eyesIntensity: 0.55
        ),
        MakeupLook(
            id: "evening_glam",
            titleKey: "look.evening_glam",
            lipstick: lipstick("preset.berry"),
            blush: blush("blush.vintage_rose"),
            eyes: eyes("eyeshadow.plum"),
            lipstickFinish: .glossy,
            lipstickIntensity: 0.95,
            blushIntensity: 0.55,
            blushSize: 1.10,
            blushPosition: 0.48,
            eyesIntensity: 0.78
        ),
        MakeupLook(
            id: "bold_red",
            titleKey: "look.bold_red",
            lipstick: lipstick("preset.red"),
            blush: blush("blush.coral"),
            eyes: eyes("eyeshadow.copper"),
            lipstickFinish: .satin,
            lipstickIntensity: 1.00,
            blushIntensity: 0.50,
            blushSize: 1.00,
            blushPosition: 0.52,
            eyesIntensity: 0.62
        )
    ]

    private static func lipstick(_ key: String) -> LipstickPreset {
        guard let preset = MakeupPresets.lipstick.first(where: { $0.titleKey == key }) else {
            preconditionFailure("Missing lipstick preset \(key)")
        }
        return preset
    }

    private static func blush(_ key: String) -> BlushPreset {
        guard let preset = MakeupPresets.blush.first(where: { $0.titleKey == key }) else {
            preconditionFailure("Missing blush preset \(key)")
        }
        return preset
    }

    private static func eyes(_ key: String) -> EyeshadowPreset {
        guard let preset = MakeupPresets.eyeshadow.first(where: { $0.titleKey == key }) else {
            preconditionFailure("Missing eyeshadow preset \(key)")
        }
        return preset
    }
}

extension MakeupLook {
    func lipstickIndex() -> Int? {
        MakeupPresets.lipstick.firstIndex { $0.titleKey == lipstick.titleKey }
    }

    func blushIndex() -> Int? {
        MakeupPresets.blush.firstIndex { $0.titleKey == blush.titleKey }
    }

    func eyesIndex() -> Int? {
        MakeupPresets.eyeshadow.firstIndex { $0.titleKey == eyes.titleKey }
    }
}
