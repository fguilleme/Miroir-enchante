//
//  GlowRenderer.swift
//  Miroir enchanté
//

import ARKit
import SceneKit
import UIKit

final class GlowRenderer {
    private struct HighlightRegion {
        let normalizedCenter: CGPoint
        let normalizedSize: CGSize
        let opacityScale: CGFloat
        let zLift: Float
    }

    private let rootNode = SCNNode()
    private var highlightMaterials: [SCNMaterial] = []
    private var highlightNodes: [SCNNode] = []
    private var settings = GlowSettings.default

    init(faceGeometry: ARFaceGeometry) {
        rootNode.name = "GlowRenderer.root"
        rootNode.renderingOrder = 32
        buildHighlights(faceGeometry: faceGeometry)
        applyGlowSettings(settings)
    }

    func attach(to faceNode: SCNNode) {
        faceNode.addChildNode(rootNode)
    }

    func applyGlowPreset(_ preset: GlowPreset, intensity: Float) {
        let clampedIntensity = CGFloat(intensity).clamped(to: 0...1)
        settings.color = preset.color
        settings.intensity = clampedIntensity
        settings.radius = CGFloat(preset.radius)
        settings.specularBoost = CGFloat(preset.specularBoost)
        settings.isEnabled = clampedIntensity > 0.01
        applyGlowSettings(settings)
    }

    func update(settings: GlowSettings) {
        self.settings = settings
        applyGlowSettings(settings)
    }

    func setGlowEnabled(_ enabled: Bool) {
        settings.isEnabled = enabled
        rootNode.isHidden = !enabled
    }

    private func buildHighlights(faceGeometry: ARFaceGeometry) {
        let bounds = Self.faceBounds(faceGeometry: faceGeometry)
        let faceWidth = max(bounds.maxX - bounds.minX, 0.001)
        let faceHeight = max(bounds.maxY - bounds.minY, 0.001)
        let centerX = (bounds.minX + bounds.maxX) * 0.5

        let regions = [
            HighlightRegion(normalizedCenter: CGPoint(x: -0.22, y: 0.54), normalizedSize: CGSize(width: 0.26, height: 0.09), opacityScale: 1.00, zLift: 0.006),
            HighlightRegion(normalizedCenter: CGPoint(x: 0.22, y: 0.54), normalizedSize: CGSize(width: 0.26, height: 0.09), opacityScale: 1.00, zLift: 0.006),
            HighlightRegion(normalizedCenter: CGPoint(x: 0.00, y: 0.56), normalizedSize: CGSize(width: 0.055, height: 0.26), opacityScale: 0.58, zLift: 0.010),
            HighlightRegion(normalizedCenter: CGPoint(x: 0.00, y: 0.31), normalizedSize: CGSize(width: 0.10, height: 0.045), opacityScale: 0.50, zLift: 0.010),
            HighlightRegion(normalizedCenter: CGPoint(x: 0.00, y: 0.79), normalizedSize: CGSize(width: 0.24, height: 0.08), opacityScale: 0.34, zLift: 0.005),
            HighlightRegion(normalizedCenter: CGPoint(x: 0.00, y: 0.20), normalizedSize: CGSize(width: 0.16, height: 0.055), opacityScale: 0.30, zLift: 0.006)
        ]

        for region in regions {
            let plane = SCNPlane(
                width: CGFloat(faceWidth) * region.normalizedSize.width,
                height: CGFloat(faceHeight) * region.normalizedSize.height
            )
            let material = makeGlowMaterial()
            plane.firstMaterial = material

            let node = SCNNode(geometry: plane)
            node.name = "GlowRenderer.highlight"
            node.renderingOrder = 32
            node.position = SCNVector3(
                centerX + Float(region.normalizedCenter.x) * faceWidth,
                bounds.minY + Float(region.normalizedCenter.y) * faceHeight,
                bounds.maxZ + region.zLift
            )
            node.opacity = region.opacityScale
            rootNode.addChildNode(node)
            highlightNodes.append(node)
            highlightMaterials.append(material)
        }
    }

    private func applyGlowSettings(_ settings: GlowSettings) {
        rootNode.isHidden = !settings.isEnabled
        let intensity = settings.intensity.clamped(to: 0...1)
        let radius = settings.radius.clamped(to: 0.75...1.25)
        let alpha = min(0.42, settings.opacity * intensity * 2.55)
        let key = MakeupTextureCache.GlowKey(
            color: MakeupTextureCache.ColorKey(settings.color),
            intensity: Int((alpha * 100).rounded()),
            radius: Int((radius * 100).rounded()),
            style: .softHighlight
        )
        let texture = MakeupTextureCache.glowGradient(key: key)

        for material in highlightMaterials {
            material.diffuse.contents = settings.color
            material.transparent.contents = texture
            material.transparency = 1.0
            material.emission.contents = settings.color.withAlphaComponent(settings.specularBoost * intensity * 0.24)
        }

        for node in highlightNodes {
            node.scale = SCNVector3(Float(radius), Float(radius), 1)
        }
    }

    private func makeGlowMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = settings.color
        material.transparent.contents = MakeupTextureCache.glowGradient(
            key: MakeupTextureCache.GlowKey(
                color: MakeupTextureCache.ColorKey(settings.color),
                intensity: 18,
                radius: 100,
                style: .softHighlight
            )
        )
        material.transparency = 1.0
        material.transparencyMode = .aOne
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        material.blendMode = .alpha
        return material
    }

    private static func faceBounds(faceGeometry: ARFaceGeometry) -> (minX: Float, maxX: Float, minY: Float, maxY: Float, maxZ: Float) {
        guard let first = faceGeometry.vertices.first else {
            return (-0.08, 0.08, -0.10, 0.10, 0)
        }

        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        var maxZ = first.z

        for vertex in faceGeometry.vertices {
            minX = min(minX, vertex.x)
            maxX = max(maxX, vertex.x)
            minY = min(minY, vertex.y)
            maxY = max(maxY, vertex.y)
            maxZ = max(maxZ, vertex.z)
        }

        return (minX, maxX, minY, maxY, maxZ)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
