//
//  DemoHeadRenderer.swift
//  Miroir enchanté
//

import SceneKit
import UIKit

/// Loads a bundled OBJ/GLB/USDZ head model so makeup can be tested without ARKit.
final class DemoHeadRenderer {
    let scene = SCNScene()
    let cameraNode = SCNNode()

    let assetFilename: String
    let fallbackUSDZFilename: String

    /// Manual override hints for assets whose lip meshes are not named with
    /// obvious "lip" or "mouth" terms.
    let lipNodeNameHints = ["UpperLip", "LowerLip", "Upper Lip", "Lower Lip", "Upper_lip", "Lower_lip", "Lips", "Mouth"]
    let companionLipAssetFilenames = ["Upper Lip.obj", "Lower Lip.obj"]

    private let modelContainerNode = SCNNode()
    private let fallbackLipRootNode = SCNNode()
    private var lipNodes: [SCNNode] = []
    private var lipstickSettings = LipstickSettings.default
    private let frontFacingYaw: Float = 0
    private let demoRotationLimit: Float = 40 * .pi / 180
    private let fallbackLipVerticalRatio: Float = 0.235
    private let fallbackLipWidthRatio: Float = 0.155

    init(assetFilename: String = "female_head.obj") {
        self.assetFilename = assetFilename
        self.fallbackUSDZFilename = Self.usdzFilename(for: assetFilename)

        configureScene()
        loadHeadModel()
        applyLipstickMaterial(settings: lipstickSettings)
    }

    func updateLipstickSettings(_ settings: LipstickSettings) {
        lipstickSettings = settings
        applyLipstickMaterial(settings: settings)
    }

    func applyLipstickMaterial(settings: LipstickSettings) {
        let material = MakeupMaterialFactory.makeLipstickMaterial(settings: settings)

        for node in lipNodes {
            node.renderingOrder = 40
            apply(material: material, to: node)
        }
    }

    private func configureScene() {
        scene.background.contents = UIColor.black
        scene.rootNode.addChildNode(modelContainerNode)

        let camera = SCNCamera()
        camera.fieldOfView = 38
        camera.zNear = 0.01
        camera.zFar = 100
        camera.wantsHDR = false
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = -1.35

        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 4.0)
        scene.rootNode.addChildNode(cameraNode)

        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light?.type = .omni
        keyLight.light?.intensity = 240
        keyLight.position = SCNVector3(0.6, 1.4, 3.0)
        scene.rootNode.addChildNode(keyLight)

        let fillLight = SCNNode()
        fillLight.light = SCNLight()
        fillLight.light?.type = .ambient
        fillLight.light?.intensity = 95
        scene.rootNode.addChildNode(fillLight)
    }

    private func loadHeadModel() {
        if let loadedScene = loadBundledScene(filename: assetFilename) {
            installModel(from: loadedScene)
        } else if let loadedScene = loadBundledScene(filename: fallbackUSDZFilename) {
            installModel(from: loadedScene)
        } else {
            print("""
            Demo head asset not loaded. Add \(assetFilename) to the app target bundle.
            OBJ is supported by SceneKit when the OBJ and its referenced MTL/textures are bundled together.
            If you later use GLB and SceneKit cannot load it directly, convert it to \(fallbackUSDZFilename):
            - Xcode Reality Converter: open GLB, export USDZ.
            - Command line on macOS when available: xcrun usdz_converter female_head.glb female_head.usdz
            Then bundle the USDZ and keep the same base filename.
            """)
            installFallbackPrimitiveHead()
        }

        centerAndScaleModel()
        startSlowRotation()
        resolveLipNodes()
    }

    private func loadBundledScene(filename: String) -> SCNScene? {
        let parts = splitFilename(filename)
        let bundledURL = Bundle.main.url(
            forResource: parts.name,
            withExtension: parts.extension,
            subdirectory: parts.subdirectory
        ) ?? Bundle.main.url(
            forResource: parts.name,
            withExtension: parts.extension
        )

        guard let url = bundledURL else {
            print("Demo model asset \(filename) was not found in the app bundle.")
            return nil
        }

        do {
            // SceneKit generally loads OBJ well as long as the referenced MTL
            // and texture files are bundled next to it. GLB support varies by
            // platform/toolchain; USDZ is the most reliable iOS runtime fallback.
            return try SCNScene(url: url, options: nil)
        } catch {
            print("SceneKit could not load \(filename): \(error.localizedDescription)")
            if parts.extension.lowercased() == "glb" {
                print("Convert \(filename) to \(fallbackUSDZFilename) with Reality Converter or xcrun usdz_converter, then add the USDZ to the app bundle.")
            }
            return nil
        }
    }

    private func installModel(from loadedScene: SCNScene) {
        modelContainerNode.childNodes.forEach { $0.removeFromParentNode() }
        modelContainerNode.addChildNode(fallbackLipRootNode)

        for child in loadedScene.rootNode.childNodes {
            modelContainerNode.addChildNode(child.clone())
        }

        installCompanionLipAssets()
        applySkinMaterialToModel()
    }

    private func installCompanionLipAssets() {
        for filename in companionLipAssetFilenames {
            guard let lipScene = loadBundledScene(filename: filename) else { continue }

            let assetRoot = SCNNode()
            assetRoot.name = splitFilename(filename).name

            for child in lipScene.rootNode.childNodes {
                let clone = child.clone()
                if clone.name == nil {
                    clone.name = splitFilename(filename).name
                }
                assetRoot.addChildNode(clone)
            }

            if !assetRoot.childNodes.isEmpty {
                modelContainerNode.addChildNode(assetRoot)
                print("Loaded companion lip asset: \(filename)")
            }
        }
    }

    private func installFallbackPrimitiveHead() {
        modelContainerNode.childNodes.forEach { $0.removeFromParentNode() }

        let skinMaterial = MakeupMaterialFactory.makeSkinMaterial()

        let head = SCNNode(geometry: SCNSphere(radius: 1.0))
        head.name = "FallbackHead"
        head.scale = SCNVector3(0.78, 1.08, 0.48)
        head.geometry?.firstMaterial = skinMaterial
        modelContainerNode.addChildNode(head)

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
    }

    private func makeFallbackLipNode(name: String, width: CGFloat, height: CGFloat) -> SCNNode {
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

    private func centerAndScaleModel() {
        let bounds = modelContainerNode.hierarchyBoundingBox
        let center = SCNVector3(
            (bounds.min.x + bounds.max.x) * 0.5,
            (bounds.min.y + bounds.max.y) * 0.5,
            (bounds.min.z + bounds.max.z) * 0.5
        )
        let size = SCNVector3(
            bounds.max.x - bounds.min.x,
            bounds.max.y - bounds.min.y,
            bounds.max.z - bounds.min.z
        )
        let largestDimension = max(size.x, max(size.y, size.z))

        guard largestDimension > 0 else { return }

        let scale = 2.0 / largestDimension
        modelContainerNode.scale = SCNVector3(scale, scale, scale)
        modelContainerNode.position = SCNVector3(-center.x * scale, -center.y * scale, -center.z * scale)
        modelContainerNode.eulerAngles.y = frontFacingYaw
    }

    private func startSlowRotation() {
        modelContainerNode.removeAllActions()

        // Demo inspection should stay face-forward, so sweep only +/- 40 degrees
        // around the OBJ's corrected front-facing yaw instead of spinning fully.
        let leftYaw = CGFloat(frontFacingYaw - demoRotationLimit)
        let rightYaw = CGFloat(frontFacingYaw + demoRotationLimit)
        modelContainerNode.eulerAngles.y = Float(leftYaw)

        let rotateRight = SCNAction.rotateTo(x: 0, y: rightYaw, z: 0, duration: 5.5, usesShortestUnitArc: true)
        let rotateLeft = SCNAction.rotateTo(x: 0, y: leftYaw, z: 0, duration: 5.5, usesShortestUnitArc: true)
        rotateRight.timingMode = .easeInEaseOut
        rotateLeft.timingMode = .easeInEaseOut

        modelContainerNode.runAction(.repeatForever(.sequence([rotateRight, rotateLeft])))
    }

    private func resolveLipNodes() {
        fallbackLipRootNode.childNodes.forEach { $0.removeFromParentNode() }

        lipNodes = modelContainerNode.childNodesRecursive.filter { node in
            guard let rawName = node.name, node.geometry != nil else { return false }
            let name = rawName.lowercased()
            let normalizedName = normalizeNodeName(rawName)
            let semanticMatches = ["lip", "lips", "mouth"].contains { name.contains($0) }
            let hintMatches = lipNodeNameHints.contains { normalizeNodeName($0) == normalizedName }
            return semanticMatches || hintMatches
        }

        if lipNodes.isEmpty {
            print("Warning: no lip mesh nodes found in \(assetFilename). Rename lip meshes with names like \(lipNodeNameHints.joined(separator: ", ")) or add exact names to lipNodeNameHints.")
            lipNodes = makeFallbackLipOverlayNodes()
        } else {
            print("Demo lip nodes: \(lipNodes.compactMap { $0.name }.joined(separator: ", "))")
        }
    }

    private func normalizeNodeName(_ name: String) -> String {
        name
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    private func applySkinMaterialToModel() {
        let skinMaterial = MakeupMaterialFactory.makeSkinMaterial()
        for node in modelContainerNode.childNodesRecursive where node.geometry != nil {
            apply(material: skinMaterial, to: node)
        }
    }

    private func makeFallbackLipOverlayNodes() -> [SCNNode] {
        let bounds = modelContainerNode.hierarchyBoundingBox
        let size = SCNVector3(
            bounds.max.x - bounds.min.x,
            bounds.max.y - bounds.min.y,
            bounds.max.z - bounds.min.z
        )

        // This small procedural lip overlay gives us a controllable test target
        // even when the exported OBJ is a single unnamed mesh. It assumes the
        // model's neutral/front-facing orientation is the SceneKit default.
        let frontZ = bounds.max.z + size.z * 0.004
        let centerX = (bounds.min.x + bounds.max.x) * 0.5
        let mouthY = bounds.min.y + size.y * fallbackLipVerticalRatio
        let lipWidth = CGFloat(max(size.x * fallbackLipWidthRatio, 0.08))
        let upperHeight = CGFloat(max(size.y * 0.014, 0.018))
        let lowerHeight = CGFloat(max(size.y * 0.018, 0.024))

        let upperLip = makeOverlayLipNode(name: "UpperLip", width: lipWidth, height: upperHeight, isUpperLip: true)
        upperLip.position = SCNVector3(centerX, mouthY + Float(upperHeight * 0.35), frontZ)

        let lowerLip = makeOverlayLipNode(name: "LowerLip", width: lipWidth * 0.92, height: lowerHeight, isUpperLip: false)
        lowerLip.position = SCNVector3(centerX, mouthY - Float(lowerHeight * 0.35), frontZ)

        fallbackLipRootNode.addChildNode(upperLip)
        fallbackLipRootNode.addChildNode(lowerLip)
        return [upperLip, lowerLip]
    }

    private func makeOverlayLipNode(name: String, width: CGFloat, height: CGFloat, isUpperLip: Bool) -> SCNNode {
        let path = makeLipPath(width: width, height: height, isUpperLip: isUpperLip)
        let geometry = SCNShape(path: path, extrusionDepth: 0.003)
        geometry.chamferRadius = 0.0015
        geometry.firstMaterial = MakeupMaterialFactory.makeLipstickMaterial(settings: lipstickSettings)

        let node = SCNNode(geometry: geometry)
        node.name = name
        node.renderingOrder = 20
        return node
    }

    private func makeLipPath(width: CGFloat, height: CGFloat, isUpperLip: Bool) -> UIBezierPath {
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

    private func apply(material: SCNMaterial, to node: SCNNode) {
        guard let geometry = node.geometry else { return }

        if geometry.materials.isEmpty {
            geometry.firstMaterial = material.copy() as? SCNMaterial
        } else {
            geometry.materials = geometry.materials.map { _ in material.copy() as? SCNMaterial ?? material }
        }
    }

    private static func usdzFilename(for filename: String) -> String {
        let parts = splitFilename(filename)
        if let subdirectory = parts.subdirectory {
            return "\(subdirectory)/\(parts.name).usdz"
        }

        return "\(parts.name).usdz"
    }

    private static func splitFilename(_ filename: String) -> (name: String, extension: String, subdirectory: String?) {
        let url = URL(fileURLWithPath: filename)
        let fileExtension = url.pathExtension.isEmpty ? "glb" : url.pathExtension
        let name = url.deletingPathExtension().lastPathComponent
        let subdirectory = url.deletingLastPathComponent().relativePath
        return (name, fileExtension, subdirectory == "." ? nil : subdirectory)
    }

    private func splitFilename(_ filename: String) -> (name: String, extension: String, subdirectory: String?) {
        Self.splitFilename(filename)
    }
}

private extension SCNNode {
    var childNodesRecursive: [SCNNode] {
        childNodes + childNodes.flatMap { $0.childNodesRecursive }
    }

    var hierarchyBoundingBox: (min: SCNVector3, max: SCNVector3) {
        var hasBounds = false
        var minVector = SCNVector3Zero
        var maxVector = SCNVector3Zero

        enumerateChildNodes { node, _ in
            guard node.geometry != nil else { return }

            let bounds = node.boundingBox
            let corners = [
                SCNVector3(bounds.min.x, bounds.min.y, bounds.min.z),
                SCNVector3(bounds.min.x, bounds.min.y, bounds.max.z),
                SCNVector3(bounds.min.x, bounds.max.y, bounds.min.z),
                SCNVector3(bounds.min.x, bounds.max.y, bounds.max.z),
                SCNVector3(bounds.max.x, bounds.min.y, bounds.min.z),
                SCNVector3(bounds.max.x, bounds.min.y, bounds.max.z),
                SCNVector3(bounds.max.x, bounds.max.y, bounds.min.z),
                SCNVector3(bounds.max.x, bounds.max.y, bounds.max.z)
            ]

            for corner in corners {
                let point = node.convertPosition(corner, to: self)

                if !hasBounds {
                    minVector = point
                    maxVector = point
                    hasBounds = true
                } else {
                    minVector = SCNVector3(
                        min(minVector.x, point.x),
                        min(minVector.y, point.y),
                        min(minVector.z, point.z)
                    )
                    maxVector = SCNVector3(
                        max(maxVector.x, point.x),
                        max(maxVector.y, point.y),
                        max(maxVector.z, point.z)
                    )
                }
            }
        }

        return hasBounds ? (minVector, maxVector) : (SCNVector3Zero, SCNVector3(1, 1, 1))
    }
}
