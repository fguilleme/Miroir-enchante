//
//  MakeupMaterialFactory.swift
//  Miroir enchanté
//

import SceneKit
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

    static let presets: [(titleKey: String, color: UIColor)] = [
        ("preset.nude", UIColor(red: 0.63, green: 0.36, blue: 0.29, alpha: 1.0)),
        ("preset.red", UIColor(red: 0.70, green: 0.04, blue: 0.10, alpha: 1.0)),
        ("preset.burgundy", UIColor(red: 0.33, green: 0.02, blue: 0.09, alpha: 1.0)),
        ("preset.pink", UIColor(red: 0.93, green: 0.26, blue: 0.48, alpha: 1.0))
    ]
}

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
        let opacity = settings.opacity.clamped(to: 0...1)
        let color = settings.color.withIntensity(settings.colorIntensity)

        material.lightingModel = .physicallyBased
        material.diffuse.contents = color.withAlphaComponent(opacity)
        material.transparency = opacity
        material.transparencyMode = .aOne
        material.roughness.contents = settings.roughness
        material.metalness.contents = 0.0
        material.specular.contents = UIColor.white.withAlphaComponent(settings.glossIntensity * opacity)
        material.shininess = settings.glossIntensity
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        material.blendMode = .alpha
        material.fillMode = .fill

        // Replace diffuse.contents with a texture later for brand shades or
        // fine-grained lip masks. A mask can isolate upper/lower lips while
        // this factory keeps finish controls such as gloss and matte roughness.
        return material
    }

    static func makeARLipstickMaterial(settings: LipstickSettings = .default) -> SCNMaterial {
        let material = SCNMaterial()
        let opacity = settings.opacity.clamped(to: 0...1)
        let color = settings.color.withIntensity(settings.colorIntensity)

        // AR face geometry can receive unstable or very dark lighting around
        // the mouth, especially with facial hair and an open mouth. A constant
        // material keeps the overlay cosmetic instead of letting PBR shading
        // turn the selected mouth band black.
        material.lightingModel = .constant
        material.diffuse.contents = color.withAlphaComponent(opacity)
        material.emission.contents = color.withAlphaComponent(0.35 * opacity)
        material.transparency = opacity
        material.transparencyMode = .aOne
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        material.blendMode = .alpha
        material.fillMode = .fill

        return material
    }

    static func makeLipHighlightMaterial() -> SCNMaterial {
        let material = SCNMaterial()

        material.lightingModel = .constant
        material.diffuse.contents = UIColor.systemYellow
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
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
