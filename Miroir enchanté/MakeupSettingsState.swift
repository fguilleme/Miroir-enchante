//
//  MakeupSettingsState.swift
//  Miroir enchanté
//

import Foundation
import UIKit

enum LipstickFinish: Int {
    case matte = 0
    case satin = 1
    case glossy = 2
}

struct MakeupSettingsState {
    var isARAutoFramingEnabled: Bool = false
    var selectedLipstickPresetIndex: Int = 3
    var lipstickIntensityValue: CGFloat = 0.9
    var lipstickFinish: LipstickFinish = .satin
    var lipstickSettings: LipstickSettings = .default
    var selectedBlushPresetIndex: Int = 2
    var blushSettings: BlushSettings = .default
    var selectedEyeshadowPresetIndex: Int = 1
    var eyeshadowSettings: EyeshadowSettings = .default
    var selectedGlowPresetIndex: Int = 0
    var glowSettings: GlowSettings = .default
    var selectedContourPresetIndex: Int = 0
    var contourSettings: ContourSettings = .default
    var hairHueValue: CGFloat = 0.24
    var hairStrengthValue: CGFloat = 0.84
    var hairOffsetYValue: Float = -0.08
    var hairOffsetZValue: Float = 0.15
    var hairScaleValue: Float = 1.0
    var lipMeshWidthScale: Float = 1.0
    var lipMeshHeightScale: Float = 1.0
    var lipMeshVerticalOffset: Float = 0.0
    var isHeadHidden: Bool = false
    var isHairHidden: Bool = false

    static func load(defaults: UserDefaults = .standard) -> MakeupSettingsState {
        defaults.register(defaults: [
            SettingsKey.arAutoFramingEnabled: false,
            SettingsKey.selectedLipstickPresetIndex: 3,
            SettingsKey.lipstickIntensity: 0.9,
            SettingsKey.lipstickFinish: LipstickFinish.satin.rawValue,
            SettingsKey.selectedBlushPresetIndex: 2,
            SettingsKey.blushIntensity: Double(BlushSettings.default.intensity),
            SettingsKey.blushSize: Double(BlushSettings.default.size),
            SettingsKey.blushPosition: Double(BlushSettings.default.position),
            SettingsKey.selectedEyeshadowPresetIndex: 1,
            SettingsKey.eyeshadowIntensity: Double(EyeshadowSettings.default.intensity),
            SettingsKey.selectedGlowPresetIndex: 0,
            SettingsKey.glowIntensity: Double(GlowSettings.default.intensity),
            SettingsKey.glowRadius: Double(GlowSettings.default.radius),
            SettingsKey.selectedContourPresetIndex: 0,
            SettingsKey.contourIntensity: Double(ContourSettings.default.intensity),
            SettingsKey.hairHue: 0.24,
            SettingsKey.hairStrength: 0.84,
            SettingsKey.hairOffsetY: -0.08,
            SettingsKey.hairOffsetZ: 0.15,
            SettingsKey.hairScale: 1.0,
            SettingsKey.lipMeshWidthScale: 1.0,
            SettingsKey.lipMeshHeightScale: 1.0,
            SettingsKey.lipMeshVerticalOffset: 0.0,
            SettingsKey.hideHead: false,
            SettingsKey.hideHair: false
        ])

        var state = MakeupSettingsState()
        state.isARAutoFramingEnabled = defaults.bool(forKey: SettingsKey.arAutoFramingEnabled)
        state.selectedLipstickPresetIndex = defaults.integer(forKey: SettingsKey.selectedLipstickPresetIndex)
        state.lipstickIntensityValue = clampedCGFloat(CGFloat(defaults.double(forKey: SettingsKey.lipstickIntensity)), to: 0.1...1.0)
        state.lipstickFinish = LipstickFinish(rawValue: defaults.integer(forKey: SettingsKey.lipstickFinish)) ?? .satin
        state.selectedBlushPresetIndex = defaults.integer(forKey: SettingsKey.selectedBlushPresetIndex)
        state.blushSettings.intensity = clampedCGFloat(CGFloat(defaults.double(forKey: SettingsKey.blushIntensity)), to: 0...1)
        state.blushSettings.size = clampedCGFloat(CGFloat(defaults.double(forKey: SettingsKey.blushSize)), to: 0.65...1.20)
        state.blushSettings.position = clampedCGFloat(CGFloat(defaults.double(forKey: SettingsKey.blushPosition)), to: 0...1)
        state.selectedEyeshadowPresetIndex = defaults.integer(forKey: SettingsKey.selectedEyeshadowPresetIndex)
        state.eyeshadowSettings.intensity = clampedCGFloat(CGFloat(defaults.double(forKey: SettingsKey.eyeshadowIntensity)), to: 0...1)
        state.selectedGlowPresetIndex = defaults.integer(forKey: SettingsKey.selectedGlowPresetIndex)
        state.glowSettings.intensity = clampedCGFloat(CGFloat(defaults.double(forKey: SettingsKey.glowIntensity)), to: 0...1)
        state.glowSettings.radius = clampedCGFloat(CGFloat(defaults.double(forKey: SettingsKey.glowRadius)), to: 0.75...1.25)
        state.selectedContourPresetIndex = defaults.integer(forKey: SettingsKey.selectedContourPresetIndex)
        state.contourSettings.intensity = clampedCGFloat(CGFloat(defaults.double(forKey: SettingsKey.contourIntensity)), to: 0...1)
        state.hairHueValue = clampedCGFloat(CGFloat(defaults.double(forKey: SettingsKey.hairHue)), to: 0...1)
        state.hairStrengthValue = clampedCGFloat(CGFloat(defaults.double(forKey: SettingsKey.hairStrength)), to: 0...1)
        state.hairOffsetYValue = Float(clampedCGFloat(CGFloat(defaults.double(forKey: SettingsKey.hairOffsetY)), to: -3...1))
        state.hairOffsetZValue = Float(clampedCGFloat(CGFloat(defaults.double(forKey: SettingsKey.hairOffsetZ)), to: -1...5))
        state.hairScaleValue = Float(clampedCGFloat(CGFloat(defaults.double(forKey: SettingsKey.hairScale)), to: 0.15...2.0))
        state.lipMeshWidthScale = Float(clampedCGFloat(CGFloat(defaults.double(forKey: SettingsKey.lipMeshWidthScale)), to: 0.70...1.25))
        state.lipMeshHeightScale = Float(clampedCGFloat(CGFloat(defaults.double(forKey: SettingsKey.lipMeshHeightScale)), to: 0.60...1.30))
        state.lipMeshVerticalOffset = Float(clampedCGFloat(CGFloat(defaults.double(forKey: SettingsKey.lipMeshVerticalOffset)), to: -0.045...0.045))
        state.isHeadHidden = defaults.bool(forKey: SettingsKey.hideHead)
        state.isHairHidden = defaults.bool(forKey: SettingsKey.hideHair)
        state.sanitizePresetIndices()
        state.rebuildLipstickSettings()
        state.rebuildBlushSettings()
        state.rebuildEyeshadowSettings()
        state.rebuildGlowSettings()
        state.rebuildContourSettings()
        return state
    }

    func persist(defaults: UserDefaults = .standard) {
        defaults.set(isARAutoFramingEnabled, forKey: SettingsKey.arAutoFramingEnabled)
        defaults.set(selectedLipstickPresetIndex, forKey: SettingsKey.selectedLipstickPresetIndex)
        defaults.set(Double(lipstickIntensityValue), forKey: SettingsKey.lipstickIntensity)
        defaults.set(lipstickFinish.rawValue, forKey: SettingsKey.lipstickFinish)
        defaults.set(selectedBlushPresetIndex, forKey: SettingsKey.selectedBlushPresetIndex)
        defaults.set(Double(blushSettings.intensity), forKey: SettingsKey.blushIntensity)
        defaults.set(Double(blushSettings.size), forKey: SettingsKey.blushSize)
        defaults.set(Double(blushSettings.position), forKey: SettingsKey.blushPosition)
        defaults.set(selectedEyeshadowPresetIndex, forKey: SettingsKey.selectedEyeshadowPresetIndex)
        defaults.set(Double(eyeshadowSettings.intensity), forKey: SettingsKey.eyeshadowIntensity)
        defaults.set(selectedGlowPresetIndex, forKey: SettingsKey.selectedGlowPresetIndex)
        defaults.set(Double(glowSettings.intensity), forKey: SettingsKey.glowIntensity)
        defaults.set(Double(glowSettings.radius), forKey: SettingsKey.glowRadius)
        defaults.set(selectedContourPresetIndex, forKey: SettingsKey.selectedContourPresetIndex)
        defaults.set(Double(contourSettings.intensity), forKey: SettingsKey.contourIntensity)
        defaults.set(Double(hairHueValue), forKey: SettingsKey.hairHue)
        defaults.set(Double(hairStrengthValue), forKey: SettingsKey.hairStrength)
        defaults.set(Double(hairOffsetYValue), forKey: SettingsKey.hairOffsetY)
        defaults.set(Double(hairOffsetZValue), forKey: SettingsKey.hairOffsetZ)
        defaults.set(Double(hairScaleValue), forKey: SettingsKey.hairScale)
        defaults.set(Double(lipMeshWidthScale), forKey: SettingsKey.lipMeshWidthScale)
        defaults.set(Double(lipMeshHeightScale), forKey: SettingsKey.lipMeshHeightScale)
        defaults.set(Double(lipMeshVerticalOffset), forKey: SettingsKey.lipMeshVerticalOffset)
        defaults.set(isHeadHidden, forKey: SettingsKey.hideHead)
        defaults.set(isHairHidden, forKey: SettingsKey.hideHair)
    }

    mutating func rebuildLipstickSettings() {
        guard LipstickSettings.presets.indices.contains(selectedLipstickPresetIndex) else { return }

        let preset = LipstickSettings.presets[selectedLipstickPresetIndex]
        let rawIntensity = clampedCGFloat(lipstickIntensityValue, to: 0.1...1.0)
        let intensity = MakeupIntensityCurve.response(rawIntensity, in: 0.1...1.0)
        lipstickIntensityValue = rawIntensity
        lipstickSettings.color = preset.baseColor
        lipstickSettings.opacity = CGFloat(preset.opacity) * (0.30 + intensity * 0.70)
        lipstickSettings.roughness = lipstickRoughness(for: preset)
        lipstickSettings.glossIntensity = lipstickGlossIntensity(for: preset)
        lipstickSettings.colorIntensity = 1.0
        lipstickSettings.specularIntensity = CGFloat(preset.specularIntensity)
        lipstickSettings.colorVariation = CGFloat(preset.colorVariation)
    }

    mutating func rebuildBlushSettings() {
        guard BlushSettings.presets.indices.contains(selectedBlushPresetIndex) else { return }

        let preset = BlushSettings.presets[selectedBlushPresetIndex]
        blushSettings.color = preset.baseColor
        blushSettings.opacity = CGFloat(preset.opacity)
        blushSettings.roughness = CGFloat(preset.roughness)
    }

    mutating func rebuildEyeshadowSettings() {
        guard EyeshadowSettings.presets.indices.contains(selectedEyeshadowPresetIndex) else { return }

        let preset = EyeshadowSettings.presets[selectedEyeshadowPresetIndex]
        eyeshadowSettings.color = preset.baseColor
        eyeshadowSettings.opacity = CGFloat(preset.opacity)
        eyeshadowSettings.roughness = CGFloat(preset.roughness)
        eyeshadowSettings.shimmerIntensity = CGFloat(preset.shimmer)
    }

    mutating func rebuildGlowSettings() {
        guard GlowSettings.presets.indices.contains(selectedGlowPresetIndex) else { return }

        let preset = GlowSettings.presets[selectedGlowPresetIndex]
        let intensity = clampedCGFloat(glowSettings.intensity, to: 0...1)
        let radius = clampedCGFloat(glowSettings.radius, to: 0.75...1.25)
        glowSettings.color = preset.color
        glowSettings.opacity = 0.18
        glowSettings.intensity = intensity
        glowSettings.radius = radius
        glowSettings.specularBoost = CGFloat(preset.specularBoost)
        glowSettings.isEnabled = intensity > 0.01
    }

    mutating func applyGlowPreset(_ preset: GlowPreset, intensity: CGFloat) {
        glowSettings.color = preset.color
        glowSettings.opacity = 0.18
        glowSettings.intensity = clampedCGFloat(intensity, to: 0...1)
        glowSettings.radius = clampedCGFloat(CGFloat(preset.radius), to: 0.75...1.25)
        glowSettings.specularBoost = CGFloat(preset.specularBoost)
        glowSettings.isEnabled = glowSettings.intensity > 0.01
    }

    mutating func rebuildContourSettings() {
        guard ContourSettings.presets.indices.contains(selectedContourPresetIndex) else { return }

        let preset = ContourSettings.presets[selectedContourPresetIndex]
        contourSettings.color = preset.color
        contourSettings.opacity = 0.32
        contourSettings.intensity = clampedCGFloat(contourSettings.intensity, to: 0...1)
        contourSettings.softness = CGFloat(preset.softness)
        contourSettings.isEnabled = contourSettings.intensity > 0.01
    }

    mutating func applyContourPreset(_ preset: ContourPreset, intensity: CGFloat) {
        contourSettings.color = preset.color
        contourSettings.opacity = 0.32
        contourSettings.intensity = clampedCGFloat(intensity, to: 0...1)
        contourSettings.softness = CGFloat(preset.softness)
        contourSettings.isEnabled = contourSettings.intensity > 0.01
    }

    private mutating func sanitizePresetIndices() {
        if !LipstickSettings.presets.indices.contains(selectedLipstickPresetIndex) {
            selectedLipstickPresetIndex = 3
        }

        if !BlushSettings.presets.indices.contains(selectedBlushPresetIndex) {
            selectedBlushPresetIndex = 2
        }

        if !EyeshadowSettings.presets.indices.contains(selectedEyeshadowPresetIndex) {
            selectedEyeshadowPresetIndex = 1
        }

        if !GlowSettings.presets.indices.contains(selectedGlowPresetIndex) {
            selectedGlowPresetIndex = 0
        }

        if !ContourSettings.presets.indices.contains(selectedContourPresetIndex) {
            selectedContourPresetIndex = 0
        }
    }

    private func lipstickRoughness(for preset: LipstickPreset) -> CGFloat {
        switch lipstickFinish {
        case .matte:
            return max(CGFloat(preset.roughness), 0.62)
        case .satin:
            return clampedCGFloat(CGFloat(preset.roughness), to: 0.24...0.44)
        case .glossy:
            return min(CGFloat(preset.roughness), 0.18)
        }
    }

    private func lipstickGlossIntensity(for preset: LipstickPreset) -> CGFloat {
        switch lipstickFinish {
        case .matte:
            return 0.10
        case .satin:
            return clampedCGFloat(CGFloat(1.0 - preset.roughness), to: 0.30...0.52)
        case .glossy:
            return 0.78
        }
    }

    private enum SettingsKey {
        static let prefix = "FaceMakeupViewController."
        static let arAutoFramingEnabled = prefix + "arAutoFramingEnabled"
        static let selectedLipstickPresetIndex = prefix + "selectedLipstickPresetIndex"
        static let lipstickIntensity = prefix + "lipstickIntensity"
        static let lipstickFinish = prefix + "lipstickFinish"
        static let selectedBlushPresetIndex = prefix + "selectedBlushPresetIndex"
        static let blushIntensity = prefix + "blushIntensity"
        static let blushSize = prefix + "blushSize"
        static let blushPosition = prefix + "blushPosition"
        static let selectedEyeshadowPresetIndex = prefix + "selectedEyeshadowPresetIndex"
        static let eyeshadowIntensity = prefix + "eyeshadowIntensity"
        static let selectedGlowPresetIndex = prefix + "selectedGlowPresetIndex"
        static let glowIntensity = prefix + "glowIntensity"
        static let glowRadius = prefix + "glowRadius"
        static let selectedContourPresetIndex = prefix + "selectedContourPresetIndex"
        static let contourIntensity = prefix + "contourIntensity"
        static let hairHue = prefix + "hairHue"
        static let hairStrength = prefix + "hairStrength"
        static let hairOffsetY = prefix + "hairOffsetY"
        static let hairOffsetZ = prefix + "hairOffsetZ"
        static let hairScale = prefix + "hairScale"
        static let lipMeshWidthScale = prefix + "lipMeshWidthScale"
        static let lipMeshHeightScale = prefix + "lipMeshHeightScale"
        static let lipMeshVerticalOffset = prefix + "lipMeshVerticalOffset"
        static let hideHead = prefix + "hideHead"
        static let hideHair = prefix + "hideHair"
    }
}

private func clampedCGFloat(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
    Swift.min(Swift.max(value, range.lowerBound), range.upperBound)
}
