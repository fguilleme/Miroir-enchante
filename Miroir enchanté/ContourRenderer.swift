//
//  ContourRenderer.swift
//  Miroir enchanté
//

import ARKit
import SceneKit
import UIKit

final class ContourRenderer {
    private struct ContourRegion {
        let normalizedCenter: CGPoint
        let normalizedSize: CGSize
        let opacityScale: CGFloat
        let zLift: Float
        let rotation: Float
    }

    private let rootNode = SCNNode()
    private var contourMaterials: [SCNMaterial] = []
    private var settings = ContourSettings.default

    init(faceGeometry: ARFaceGeometry) {
        rootNode.name = "ContourRenderer.root"
        rootNode.renderingOrder = 31
        buildContours(faceGeometry: faceGeometry)
        applyContourSettings(settings)
    }

    func attach(to faceNode: SCNNode) {
        faceNode.addChildNode(rootNode)
    }

    func applyContourPreset(_ preset: ContourPreset, intensity: Float) {
        let clampedIntensity = CGFloat(intensity).clamped(to: 0...1)
        settings.color = preset.color
        settings.intensity = clampedIntensity
        settings.softness = CGFloat(preset.softness)
        settings.isEnabled = clampedIntensity > 0.01
        applyContourSettings(settings)
    }

    func update(settings: ContourSettings) {
        self.settings = settings
        applyContourSettings(settings)
    }

    func setContourEnabled(_ enabled: Bool) {
        settings.isEnabled = enabled
        rootNode.isHidden = !enabled
    }

    private func buildContours(faceGeometry: ARFaceGeometry) {
        let bounds = Self.faceBounds(faceGeometry: faceGeometry)
        let faceWidth = max(bounds.maxX - bounds.minX, 0.001)
        let faceHeight = max(bounds.maxY - bounds.minY, 0.001)
        let centerX = (bounds.minX + bounds.maxX) * 0.5

        let regions = [
            ContourRegion(normalizedCenter: CGPoint(x: -0.24, y: 0.43), normalizedSize: CGSize(width: 0.22, height: 0.07), opacityScale: 1.00, zLift: 0.004, rotation: -0.18),
            ContourRegion(normalizedCenter: CGPoint(x: 0.24, y: 0.43), normalizedSize: CGSize(width: 0.22, height: 0.07), opacityScale: 1.00, zLift: 0.004, rotation: 0.18),
            ContourRegion(normalizedCenter: CGPoint(x: -0.25, y: 0.24), normalizedSize: CGSize(width: 0.18, height: 0.055), opacityScale: 0.44, zLift: 0.004, rotation: 0.20),
            ContourRegion(normalizedCenter: CGPoint(x: 0.25, y: 0.24), normalizedSize: CGSize(width: 0.18, height: 0.055), opacityScale: 0.44, zLift: 0.004, rotation: -0.20),
            ContourRegion(normalizedCenter: CGPoint(x: -0.055, y: 0.55), normalizedSize: CGSize(width: 0.035, height: 0.18), opacityScale: 0.34, zLift: 0.008, rotation: 0.03),
            ContourRegion(normalizedCenter: CGPoint(x: 0.055, y: 0.55), normalizedSize: CGSize(width: 0.035, height: 0.18), opacityScale: 0.34, zLift: 0.008, rotation: -0.03)
        ]

        for region in regions {
            let plane = SCNPlane(
                width: CGFloat(faceWidth) * region.normalizedSize.width,
                height: CGFloat(faceHeight) * region.normalizedSize.height
            )
            let material = makeContourMaterial()
            plane.firstMaterial = material

            let node = SCNNode(geometry: plane)
            node.name = "ContourRenderer.shadow"
            node.renderingOrder = 31
            node.position = SCNVector3(
                centerX + Float(region.normalizedCenter.x) * faceWidth,
                bounds.minY + Float(region.normalizedCenter.y) * faceHeight,
                bounds.maxZ + region.zLift
            )
            node.eulerAngles.z = region.rotation
            node.opacity = region.opacityScale
            rootNode.addChildNode(node)
            contourMaterials.append(material)
        }
    }

    private func applyContourSettings(_ settings: ContourSettings) {
        rootNode.isHidden = !settings.isEnabled
        let intensity = settings.intensity.clamped(to: 0...1)
        let softness = settings.softness.clamped(to: 0.65...0.95)
        let alpha = min(0.24, settings.opacity * intensity * 1.35)
        let key = MakeupTextureCache.ContourKey(
            color: MakeupTextureCache.ColorKey(settings.color),
            intensity: Int((alpha * 100).rounded()),
            softness: Int((softness * 100).rounded()),
            style: .softShadow
        )
        let texture = MakeupTextureCache.contourGradient(key: key)

        for material in contourMaterials {
            material.diffuse.contents = settings.color
            material.transparent.contents = texture
            material.transparency = 1.0
        }
    }

    private func makeContourMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = settings.color
        material.transparent.contents = MakeupTextureCache.contourGradient(
            key: MakeupTextureCache.ContourKey(
                color: MakeupTextureCache.ColorKey(settings.color),
                intensity: 16,
                softness: 82,
                style: .softShadow
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
