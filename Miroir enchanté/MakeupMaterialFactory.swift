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
        let opacity = settings.opacity.clamped(to: 0...1)
        let color = settings.color.withIntensity(settings.colorIntensity)

        material.lightingModel = .physicallyBased
        material.diffuse.contents = color
        material.transparent.contents = makeSoftOvalAlphaMask()
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
    }

    private static func makeSoftOvalAlphaMask(size: CGSize = CGSize(width: 128, height: 128)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            let cgContext = context.cgContext
            cgContext.clear(CGRect(origin: .zero, size: size))

            let colors = [
                UIColor.white.cgColor,
                UIColor.white.withAlphaComponent(0.72).cgColor,
                UIColor.clear.cgColor
            ] as CFArray
            let locations: [CGFloat] = [0.0, 0.55, 1.0]
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: locations
            ) else { return }

            cgContext.saveGState()
            let ovalRect = CGRect(x: size.width * 0.08, y: size.height * 0.16, width: size.width * 0.84, height: size.height * 0.68)
            cgContext.addEllipse(in: ovalRect)
            cgContext.clip()
            cgContext.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: size.width * 0.5, y: size.height * 0.5),
                startRadius: 0,
                endCenter: CGPoint(x: size.width * 0.5, y: size.height * 0.5),
                endRadius: size.width * 0.46,
                options: []
            )
            cgContext.restoreGState()
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
        let opacity = (settings.opacity * settings.intensity).clamped(to: 0...0.56)
        let color = settings.color.withIntensity(0.72 + settings.intensity * 0.32)

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

        return material
    }

    static func makeARLipstickMaterial(settings: LipstickSettings = .default) -> SCNMaterial {
        let material = SCNMaterial()
        configureARLipstickMaterial(material, settings: settings)
        return material
    }

    static func configureARLipstickMaterial(_ material: SCNMaterial, settings: LipstickSettings = .default) {
        let opacity = settings.opacity.clamped(to: 0...1)
        let color = settings.color.withIntensity(settings.colorIntensity)

        // AR face geometry can receive unstable or very dark lighting around
        // the mouth, especially with facial hair and an open mouth. A constant
        // material keeps the overlay cosmetic instead of letting PBR shading
        // turn the selected mouth band black.
        material.lightingModel = .constant
        material.diffuse.contents = color
        material.emission.contents = color.withAlphaComponent(0.18 * opacity)
        material.transparency = opacity
        material.transparencyMode = .aOne
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        material.blendMode = .alpha
        material.fillMode = .fill
    }

    static func makeARBlushMaterial(settings: BlushSettings = .default) -> SCNMaterial {
        let material = SCNMaterial()
        let intensity = settings.intensity.clamped(to: 0...1)
        let opacity = (settings.opacity * intensity).clamped(to: 0...0.45)
        let color = settings.color.withIntensity(0.78 + intensity * 0.24)

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
