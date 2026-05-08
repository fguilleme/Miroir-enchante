//
//  MakeupMaterialFactory.swift
//  Miroir enchanté
//

import SceneKit
import UIKit

/// Creates reusable SceneKit materials for virtual makeup.
enum MakeupMaterialFactory {
    static func makeSkinMaterial() -> SCNMaterial {
        let material = SCNMaterial()

        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(red: 0.48, green: 0.32, blue: 0.25, alpha: 1.0)
        material.diffuse.intensity = 0.66
        material.roughness.contents = 0.88
        material.metalness.contents = 0.0
        material.specular.contents = UIColor.white.withAlphaComponent(0.035)
        material.shininess = 0.02
        material.isDoubleSided = true

        return material
    }

    static func makeHairMaterial() -> SCNMaterial {
        let material = SCNMaterial()

        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(red: 0.09, green: 0.065, blue: 0.05, alpha: 1.0)
        material.roughness.contents = 0.72
        material.metalness.contents = 0.0
        material.specular.contents = UIColor.white.withAlphaComponent(0.18)
        material.shininess = 0.18
        material.isDoubleSided = true

        return material
    }

    static func makeInvisibleFaceMaterial() -> SCNMaterial {
        let material = SCNMaterial()

        material.lightingModel = .constant
        material.diffuse.contents = UIColor.clear
        material.transparency = 0.0
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        material.colorBufferWriteMask = []

        return material
    }

    static func makeLipstickMaterial(settings: LipstickSettings = .default) -> SCNMaterial {
        let material = SCNMaterial()
        configureLipstickMaterial(material, settings: settings)

        // Replace diffuse.contents with a texture later for brand shades or
        // fine-grained lip masks. A mask can isolate upper/lower lips while
        // this factory keeps finish controls such as gloss and matte roughness.
        return material
    }

    static func configureLipstickMaterial(_ material: SCNMaterial, settings: LipstickSettings = .default) {
        applyLipstickMaterialParams(
            material,
            color: settings.color.withIntensity(settings.colorIntensity),
            baseOpacity: settings.opacity,
            roughness: settings.roughness,
            specularStrength: settings.glossIntensity,
            colorVariation: settings.colorVariation,
            overlayMode: false
        )
    }

    static func updateLipstickMaterial(
        _ material: SCNMaterial,
        preset: LipstickPreset,
        intensity: Float,
        finish: LipFinish,
        overlayMode: Bool = false
    ) {
        let clampedIntensity = CGFloat(intensity).clamped(to: 0.2...1.0)
        let baseColor = preset.baseColor.avoidingPureRed()
        let presetRoughness = CGFloat(preset.roughness)
        let presetSpecular = CGFloat(preset.specularIntensity)
        let baseOpacity = CGFloat(preset.opacity) * clampedIntensity

        applyLipstickMaterialParams(
            material,
            color: baseColor,
            baseOpacity: baseOpacity,
            roughness: roughness(for: finish, presetRoughness: presetRoughness),
            specularStrength: specularStrength(for: finish, presetSpecular: presetSpecular),
            colorVariation: CGFloat(preset.colorVariation),
            overlayMode: overlayMode
        )
    }

    private static func applyLipstickMaterialParams(
        _ material: SCNMaterial,
        color: UIColor,
        baseOpacity: CGFloat,
        roughness: CGFloat,
        specularStrength: CGFloat,
        colorVariation: CGFloat,
        overlayMode: Bool
    ) {
        let finalOpacity = Swift.min(0.92, baseOpacity).clamped(to: 0...1)
        _ = colorVariation

        material.metalness.contents = 0.0
        material.transparent.contents = nil
        material.multiply.contents = nil
        material.transparency = finalOpacity
        material.transparencyMode = .aOne
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.blendMode = .alpha
        material.fillMode = .fill

        if overlayMode {
            // AR overlay path. ARLipMeshGeometry has no texCoord/UV channel.
            // Use blinn lighting so finish (matte/satin/glossy) drives a real
            // specular highlight without the emission/PBR alpha-blend conflict.
            // Specular strength is a fixed function of finish only — the
            // intensity slider must remain a pure diffuse-coverage control.
            material.lightingModel = .blinn
            material.diffuse.contents = color
            material.diffuse.intensity = 1.0
            material.roughness.contents = roughness
            material.specular.contents = UIColor.white.withAlphaComponent(specularStrength)
            material.shininess = specularStrength
            material.emission.contents = UIColor.clear
            material.readsFromDepthBuffer = false
        } else {
            // Demo OBJ lip mesh has UV coordinates and lives in a controlled
            // scene with stable lighting. PBR plus a procedural roughness
            // texture gives subtle vertical gloss striations that read as
            // real lip detail.
            material.lightingModel = .physicallyBased
            material.diffuse.contents = color
            material.diffuse.intensity = 1.0
            material.roughness.contents = MakeupTextureCache.lipVerticalNoise()
            material.roughness.intensity = roughness
            material.specular.contents = UIColor.white.withAlphaComponent(specularStrength * finalOpacity)
            material.shininess = specularStrength
            material.emission.contents = UIColor.clear
            material.readsFromDepthBuffer = true
        }
    }

    private static func roughness(for finish: LipFinish, presetRoughness: CGFloat) -> CGFloat {
        switch finish {
        case .matte:
            return Swift.max(presetRoughness, 0.72)
        case .satin:
            return presetRoughness.clamped(to: 0.30...0.50)
        case .glossy:
            return Swift.min(presetRoughness, 0.16)
        }
    }

    private static func specularStrength(for finish: LipFinish, presetSpecular: CGFloat) -> CGFloat {
        switch finish {
        case .matte:
            return Swift.min(0.10, presetSpecular * 0.30)
        case .satin:
            return presetSpecular.clamped(to: 0.30...0.55)
        case .glossy:
            return Swift.max(0.78, presetSpecular * 1.10).clamped(to: 0...1.0)
        }
    }

    static func makeBlushMaterial(settings: BlushSettings = .default) -> SCNMaterial {
        let material = SCNMaterial()
        let intensity = settings.intensity.clamped(to: 0...1)
        let opacity = (settings.opacity * intensity).clamped(to: 0...0.65)
        let color = settings.color.withIntensity(0.82 + intensity * 0.34)

        material.lightingModel = .physicallyBased
        material.diffuse.contents = color.withAlphaComponent(opacity)
        material.transparency = opacity
        material.transparencyMode = .aOne
        material.roughness.contents = settings.roughness
        material.metalness.contents = 0.0
        material.specular.contents = UIColor.white.withAlphaComponent(0.04 * opacity)
        material.shininess = 0.04
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        material.blendMode = .alpha
        material.fillMode = .fill

        // Later this can become a texture-driven blush mask, or several
        // cheek/highlight/contour layers, without changing the renderer API.
        return material
    }

    static func makeEyeshadowMaterial(settings: EyeshadowSettings = .default) -> SCNMaterial {
        let material = SCNMaterial()
        configureEyeshadowMaterial(material, settings: settings)
        return material
    }

    static func configureEyeshadowMaterial(_ material: SCNMaterial, settings: EyeshadowSettings = .default) {
        let intensity = settings.intensity.clamped(to: 0...1)
        let opacity = (settings.opacity * intensity).clamped(to: 0...0.72)
        let color = settings.color.withIntensity(0.72 + intensity * 0.42)

        material.lightingModel = .constant
        material.diffuse.contents = color
        material.emission.contents = color.withAlphaComponent(0.16 * opacity)
        material.transparent.contents = nil
        material.transparency = opacity
        material.transparencyMode = .aOne
        material.roughness.contents = settings.roughness
        material.metalness.contents = 0.0
        material.specular.contents = UIColor.white.withAlphaComponent(settings.shimmerIntensity * opacity)
        material.shininess = settings.shimmerIntensity
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        material.blendMode = .alpha
        material.fillMode = .fill
    }

    static func makeAREyeshadowMaterial(settings: EyeshadowSettings = .default) -> SCNMaterial {
        let material = SCNMaterial()
        configureAREyeshadowMaterial(material, settings: settings)
        return material
    }

    static func configureAREyeshadowMaterial(_ material: SCNMaterial, settings: EyeshadowSettings = .default) {
        let intensity = settings.intensity.clamped(to: 0...1)
        let visibleIntensity = pow(intensity, 0.60)
        let opacityScale = settings.color.makeupPerceptualOpacityScale()
        let opacity = (settings.opacity * (0.24 + visibleIntensity * 1.45) * opacityScale).clamped(to: 0...0.72)
        let color = settings.color.withIntensity(0.88 + visibleIntensity * 0.34)

        material.lightingModel = .constant
        material.diffuse.contents = color
        material.emission.contents = color.withAlphaComponent(0.10 * opacity)
        material.transparency = opacity
        material.transparencyMode = .aOne
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        material.blendMode = .alpha
        material.fillMode = .fill
    }

    static func makeARLipstickMaterial(settings: LipstickSettings = .default) -> SCNMaterial {
        let material = SCNMaterial()
        configureARLipstickMaterial(material, settings: settings)
        return material
    }

    static func configureARLipstickMaterial(_ material: SCNMaterial, settings: LipstickSettings = .default) {
        applyLipstickMaterialParams(
            material,
            color: settings.color.withIntensity(settings.colorIntensity),
            baseOpacity: settings.opacity,
            roughness: settings.roughness,
            specularStrength: settings.glossIntensity,
            colorVariation: settings.colorVariation,
            overlayMode: true
        )
    }

    static func makeARBlushMaterial(settings: BlushSettings = .default) -> SCNMaterial {
        let material = SCNMaterial()
        configureARBlushMaterial(material, settings: settings)
        return material
    }

    static func configureARBlushMaterial(_ material: SCNMaterial, settings: BlushSettings = .default) {
        let intensity = min(settings.intensity * 2.0, 1.0).clamped(to: 0...1)
        let visibleIntensity = pow(intensity, 0.75)
        let opacityScale = settings.color.makeupPerceptualOpacityScale()
        let opacity = (settings.opacity * visibleIntensity * 1.70 * opacityScale).clamped(to: 0...0.68)
        let color = settings.color.withIntensity(0.84 + visibleIntensity * 0.34)

        // Keep the AR overlay explicitly colored and alpha-blended. Some
        // devices/SceneKit paths do not reliably apply alpha from vertex color
        // buffers on ARSCNFaceGeometry-derived meshes; using the material alpha
        // here avoids the white opaque cheek patches seen during live testing.
        material.lightingModel = .constant
        material.diffuse.contents = color
        material.emission.contents = color.withAlphaComponent(0.08 * opacity)
        material.transparency = opacity
        material.transparencyMode = .aOne
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        material.blendMode = .alpha
        material.fillMode = .fill
    }

    static func makeLipHighlightMaterial() -> SCNMaterial {
        makeZoneWireframeMaterial(color: .systemYellow)
    }

    static func makeZoneWireframeMaterial(color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()

        material.lightingModel = .constant
        material.diffuse.contents = color
        material.transparency = 1.0
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        material.blendMode = .replace
        material.fillMode = .lines

        return material
    }

    static func makeLipVertexDebugMaterial() -> SCNMaterial {
        let material = SCNMaterial()

        material.lightingModel = .constant
        material.diffuse.contents = UIColor.white
        material.transparency = 1.0
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false

        return material
    }

    static func makeWireframeMaterial() -> SCNMaterial {
        let material = SCNMaterial()

        material.lightingModel = .constant
        material.diffuse.contents = UIColor.systemGreen
        material.transparency = 1.0
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        material.blendMode = .replace
        material.fillMode = .lines

        return material
    }
}

typealias LipFinish = LipstickFinish

private extension UIColor {
    func avoidingPureRed() -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return self }
        guard red > 0.92, green < 0.08, blue < 0.08 else { return self }
        return UIColor(red: 0.84, green: 0.10, blue: 0.14, alpha: alpha)
    }
}

private extension UIColor {
    func withIntensity(_ intensity: CGFloat) -> UIColor {
        let clampedIntensity = max(0.25, min(intensity, 1.6))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return self
        }

        return UIColor(
            red: min(red * clampedIntensity, 1.0),
            green: min(green * clampedIntensity, 1.0),
            blue: min(blue * clampedIntensity, 1.0),
            alpha: alpha
        )
    }

    func makeupPerceptualOpacityScale() -> CGFloat {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return 0.50
        }

        let perceptualStrength = saturation * (0.45 + brightness * 0.55)
        return (0.68 - perceptualStrength * 0.26).clamped(to: 0.38...0.62)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
