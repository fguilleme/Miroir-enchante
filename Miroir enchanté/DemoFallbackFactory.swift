//
//  DemoFallbackFactory.swift
//  Miroir enchanté
//

import SceneKit
import UIKit

enum DemoFallbackFactory {
    static func makePrimitiveHead() -> SCNNode {
        let skinMaterial = MakeupMaterialFactory.makeSkinMaterial()

        let head = SCNNode(geometry: SCNSphere(radius: 1.0))
        head.name = "FallbackHead"
        head.scale = SCNVector3(0.78, 1.08, 0.48)
        head.geometry?.firstMaterial = skinMaterial

        let nose = SCNNode(geometry: SCNCone(topRadius: 0.03, bottomRadius: 0.13, height: 0.34))
        nose.name = "FallbackNose"
        nose.eulerAngles.x = .pi / 2
        nose.position = SCNVector3(0, -0.08, 0.54)
        nose.geometry?.firstMaterial = skinMaterial
        head.addChildNode(nose)

        let upperLip = makeFallbackLipNode(name: "UpperLip", width: 0.62, height: 0.10)
        upperLip.position = SCNVector3(0, -0.38, 0.62)
        head.addChildNode(upperLip)

        let lowerLip = makeFallbackLipNode(name: "LowerLip", width: 0.58, height: 0.14)
        lowerLip.position = SCNVector3(0, -0.50, 0.62)
        head.addChildNode(lowerLip)

        return head
    }

    static func makeLipOverlayNodes(
        bounds: (min: SCNVector3, max: SCNVector3),
        verticalRatio: Float,
        widthRatio: Float,
        lipstickSettings: LipstickSettings
    ) -> [SCNNode] {
        let size = SCNVector3(
            bounds.max.x - bounds.min.x,
            bounds.max.y - bounds.min.y,
            bounds.max.z - bounds.min.z
        )

        // Small procedural overlay for exported OBJs without named lip meshes.
        let frontZ = bounds.max.z + size.z * 0.004
        let centerX = (bounds.min.x + bounds.max.x) * 0.5
        let mouthY = bounds.min.y + size.y * verticalRatio
        let lipWidth = CGFloat(Swift.max(size.x * widthRatio, 0.08))
        let upperHeight = CGFloat(Swift.max(size.y * 0.014, 0.018))
        let lowerHeight = CGFloat(Swift.max(size.y * 0.018, 0.024))

        let upperLip = makeOverlayLipNode(
            name: "UpperLip",
            width: lipWidth,
            height: upperHeight,
            isUpperLip: true,
            lipstickSettings: lipstickSettings
        )
        upperLip.position = SCNVector3(centerX, mouthY + Float(upperHeight * 0.35), frontZ)

        let lowerLip = makeOverlayLipNode(
            name: "LowerLip",
            width: lipWidth * 0.92,
            height: lowerHeight,
            isUpperLip: false,
            lipstickSettings: lipstickSettings
        )
        lowerLip.position = SCNVector3(centerX, mouthY - Float(lowerHeight * 0.35), frontZ)

        return [upperLip, lowerLip]
    }

    private static func makeFallbackLipNode(name: String, width: CGFloat, height: CGFloat) -> SCNNode {
        let path = UIBezierPath(
            roundedRect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height),
            cornerRadius: height / 2
        )
        let geometry = SCNShape(path: path, extrusionDepth: 0.025)
        geometry.chamferRadius = 0.01

        let node = SCNNode(geometry: geometry)
        node.name = name
        return node
    }

    private static func makeOverlayLipNode(
        name: String,
        width: CGFloat,
        height: CGFloat,
        isUpperLip: Bool,
        lipstickSettings: LipstickSettings
    ) -> SCNNode {
        let path = makeLipPath(width: width, height: height, isUpperLip: isUpperLip)
        let geometry = SCNShape(path: path, extrusionDepth: 0.003)
        geometry.chamferRadius = 0.0015
        geometry.firstMaterial = MakeupMaterialFactory.makeLipstickMaterial(settings: lipstickSettings)

        let node = SCNNode(geometry: geometry)
        node.name = name
        node.renderingOrder = 20
        return node
    }

    private static func makeLipPath(width: CGFloat, height: CGFloat, isUpperLip: Bool) -> UIBezierPath {
        let halfWidth = width * 0.5
        let path = UIBezierPath()

        if isUpperLip {
            path.move(to: CGPoint(x: -halfWidth, y: -height * 0.18))
            path.addQuadCurve(to: CGPoint(x: 0, y: height * 0.18), controlPoint: CGPoint(x: -width * 0.22, y: height * 0.52))
            path.addQuadCurve(to: CGPoint(x: halfWidth, y: -height * 0.18), controlPoint: CGPoint(x: width * 0.22, y: height * 0.52))
            path.addQuadCurve(to: CGPoint(x: 0, y: -height * 0.34), controlPoint: CGPoint(x: width * 0.18, y: -height * 0.30))
            path.addQuadCurve(to: CGPoint(x: -halfWidth, y: -height * 0.18), controlPoint: CGPoint(x: -width * 0.18, y: -height * 0.30))
        } else {
            path.move(to: CGPoint(x: -halfWidth, y: height * 0.08))
            path.addQuadCurve(to: CGPoint(x: 0, y: -height * 0.45), controlPoint: CGPoint(x: -width * 0.26, y: -height * 0.50))
            path.addQuadCurve(to: CGPoint(x: halfWidth, y: height * 0.08), controlPoint: CGPoint(x: width * 0.26, y: -height * 0.50))
            path.addQuadCurve(to: CGPoint(x: 0, y: height * 0.26), controlPoint: CGPoint(x: width * 0.20, y: height * 0.22))
            path.addQuadCurve(to: CGPoint(x: -halfWidth, y: height * 0.08), controlPoint: CGPoint(x: -width * 0.20, y: height * 0.22))
        }

        path.close()
        return path
    }
}
