//
//  DemoHeadRenderer.swift
//  Miroir enchanté
//

import SceneKit
import UIKit

enum DemoHairStyle: CaseIterable {
    case none
    case femaleHair

    var titleKey: String {
        switch self {
        case .none:
            return "hair.none"
        case .femaleHair:
            return "hair.style_1"
        }
    }

    var assetFilename: String? {
        switch self {
        case .none:
            return nil
        case .femaleHair:
            return "ModelAssets/hairs/Female Hair.glb"
        }
    }

    var fitCalibration: HairFitCalibration? {
        switch self {
        case .none:
            return nil
        case .femaleHair:
            // Blender reference for Hair.02 placed with female_head:
            // location (0, 0, -24.231), rotation ~0, scale 15.473.
            // The GLB importer reads mesh vertices directly, then this
            // normalized calibration fits that asset onto the demo head.
            return HairFitCalibration(
                width: 1.45,
                height: 0.88,
                depth: 1.35,
                verticalCenter: 0.54,
                depthCenter: 0.28,
                fixedScale: 15.473
            )
        }
    }
}

struct HairFitCalibration {
    let width: Float
    let height: Float
    let depth: Float
    let verticalCenter: Float
    let depthCenter: Float
    let fixedScale: Float?
}

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
    private let hairRootNode = SCNNode()
    private var lipNodes: [SCNNode] = []
    private var lipstickSettings = LipstickSettings.default
    private var currentHairStyle: DemoHairStyle = .none
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

    @discardableResult
    func cycleHairStyle() -> DemoHairStyle {
        let styles = DemoHairStyle.allCases
        let currentIndex = styles.firstIndex(of: currentHairStyle) ?? 0
        let nextStyle = styles[(currentIndex + 1) % styles.count]
        setHairStyle(nextStyle)
        return nextStyle
    }

    func setHairStyle(_ style: DemoHairStyle) {
        currentHairStyle = style
        hairRootNode.childNodes.forEach { $0.removeFromParentNode() }

        guard let filename = style.assetFilename else {
            return
        }

        let usdzFilename = Self.usdzFilename(for: filename)
        let loadedHairAsset = loadBundledScene(filename: usdzFilename, logsMissingAsset: false).map { (usdzFilename, $0) }
            ?? loadBundledGLBScene(filename: filename).map { (filename, $0) }

        guard let (loadedFilename, loadedScene) = loadedHairAsset else {
            logUnsupportedHairAsset(sourceFilename: filename, usdzFilename: usdzFilename)
            hairRootNode.addChildNode(makeProceduralHairNode(style: style))
            return
        }

        let assetRoot = SCNNode()
        assetRoot.name = "DemoHair"

        for child in loadedScene.rootNode.childNodes {
            assetRoot.addChildNode(child.clone())
        }

        pruneNonHairGeometry(in: assetRoot)

        guard assetRoot.containsGeometry else {
            print("Hair asset \(filename) loaded without renderable geometry; using procedural fallback.")
            hairRootNode.addChildNode(makeProceduralHairNode(style: style))
            return
        }

        prepareHairMaterials(in: assetRoot)
        fitHairNode(assetRoot, style: style)
        hairRootNode.addChildNode(assetRoot)
        print("Loaded demo hair style: \(loadedFilename)")
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
        modelContainerNode.addChildNode(hairRootNode)

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

    private func loadBundledScene(filename: String, logsMissingAsset: Bool = true) -> SCNScene? {
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
            if logsMissingAsset {
                print("Demo model asset \(filename) was not found in the app bundle.")
            }
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
                print("Convert \(filename) to \(Self.usdzFilename(for: filename)) with Reality Converter, then add the USDZ to the app bundle.")
            } else if parts.extension.lowercased() == "fbx" {
                print("Convert \(filename) to \(Self.usdzFilename(for: filename)) from Blender or Reality Converter, then add the USDZ to the app bundle.")
            }
            return nil
        }
    }

    private func loadBundledGLBScene(filename: String) -> SCNScene? {
        let parts = splitFilename(filename)
        guard parts.extension.lowercased() == "glb" else {
            return nil
        }

        guard let url = bundledAssetURL(filename: filename) else {
            return nil
        }

        do {
            let scene = try MinimalGLBSceneLoader.loadScene(url: url)
            print("Loaded GLB hair with minimal importer: \(filename)")
            return scene
        } catch {
            print("Minimal GLB importer could not load \(filename): \(error.localizedDescription)")
            return nil
        }
    }

    private func logUnsupportedHairAsset(sourceFilename: String, usdzFilename: String) {
        let sourceStatus: String
        if bundledAssetExists(filename: sourceFilename) {
            sourceStatus = "\(sourceFilename) is present in the app bundle, but SceneKit on iOS does not load FBX/GLB reliably at runtime."
        } else {
            sourceStatus = "\(sourceFilename) was not found in the app bundle."
        }

        print("""
        Hair asset not loaded.
        USDZ fallback missing: \(usdzFilename).
        \(sourceStatus)
        Export the hair from Blender as USDZ, or convert it with Reality Converter, then add \(usdzFilename) to the app bundle.
        """)
    }

    private func bundledAssetExists(filename: String) -> Bool {
        bundledAssetURL(filename: filename) != nil
    }

    private func bundledAssetURL(filename: String) -> URL? {
        let parts = splitFilename(filename)
        return Bundle.main.url(
            forResource: parts.name,
            withExtension: parts.extension,
            subdirectory: parts.subdirectory
        ) ?? Bundle.main.url(
            forResource: parts.name,
            withExtension: parts.extension
        )
    }

    private func installModel(from loadedScene: SCNScene) {
        modelContainerNode.childNodes.forEach { $0.removeFromParentNode() }
        modelContainerNode.addChildNode(fallbackLipRootNode)
        modelContainerNode.addChildNode(hairRootNode)

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
        modelContainerNode.addChildNode(hairRootNode)

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
        for node in modelContainerNode.childNodesRecursive where node.geometry != nil && !node.isDescendant(of: hairRootNode) {
            apply(material: skinMaterial, to: node)
        }
    }

    private func prepareHairMaterials(in rootNode: SCNNode) {
        let fallbackHairMaterial = MakeupMaterialFactory.makeHairMaterial()

        for node in rootNode.childNodesRecursive where node.geometry != nil {
            guard let geometry = node.geometry else { continue }
            node.renderingOrder = 30

            if geometry.materials.isEmpty {
                geometry.firstMaterial = fallbackHairMaterial.copy() as? SCNMaterial
                continue
            }

            geometry.materials = geometry.materials.map { existingMaterial in
                let material = existingMaterial.copy() as? SCNMaterial ?? fallbackHairMaterial
                let hasDiffuseTexture = material.diffuse.contents != nil && !(material.diffuse.contents is UIColor)

                material.lightingModel = .physicallyBased
                material.roughness.contents = 0.72
                material.metalness.contents = 0.0
                material.specular.contents = UIColor.white.withAlphaComponent(0.06)
                material.shininess = 0.04
                material.isDoubleSided = true
                material.blendMode = .alpha
                material.transparencyMode = .aOne
                material.transparency = 1.0
                material.writesToDepthBuffer = false
                material.readsFromDepthBuffer = true

                // Hair cards rely on PNG alpha in their diffuse/base-color
                // texture. Preserve that texture and only fall back to a flat
                // dark material when the converted asset did not carry one.
                if !hasDiffuseTexture {
                    material.diffuse.contents = UIColor(red: 0.09, green: 0.065, blue: 0.05, alpha: 1.0)
                } else {
                    material.diffuse.intensity = 0.58
                    material.multiply.contents = UIColor(red: 0.50, green: 0.41, blue: 0.28, alpha: 1.0)
                    material.multiply.intensity = 0.85
                }

                return material
            }
        }
    }

    private func pruneNonHairGeometry(in rootNode: SCNNode) {
        let geometryNodes = rootNode.childNodesRecursive.filter { $0.geometry != nil }
        let hairNodes = geometryNodes.filter { isLikelyHairGeometry($0) }

        guard !hairNodes.isEmpty else {
            return
        }

        for node in geometryNodes where !hairNodes.contains(where: { $0 === node }) {
            node.isHidden = true
        }
    }

    private func isLikelyHairGeometry(_ node: SCNNode) -> Bool {
        guard let geometry = node.geometry else {
            return false
        }

        // Converted hair assets often keep a rig/armature above the renderable
        // mesh. Prefer the mesh material name first so a "Hair" material is not
        // discarded just because a parent node is called RootJoint.
        if geometry.materials.contains(where: materialNameMatchesHair) {
            return true
        }

        let nodeName = normalizeNodeName(node.name ?? "")
        let rigTerms = ["armature", "skeleton", "joint", "bone", "rootjoint", "controller", "control", "ik", "fk"]
        if rigTerms.contains(where: { nodeName.contains($0) }) {
            return false
        }

        let nodeNames = node.lineageNames.map(normalizeNodeName)
        return nodeNames.contains(where: { $0.contains("hair") || $0.contains("bang") || $0.contains("xpsnewmeshhair") })
    }

    private func materialNameMatchesHair(_ material: SCNMaterial) -> Bool {
        if let materialName = material.name {
            let name = normalizeNodeName(materialName)
            if name.contains("hair") || name.contains("bang") {
                return true
            }
        }

        return false
    }

    private func fitHairNode(_ hairNode: SCNNode, style: DemoHairStyle) {
        let headBounds = modelContainerNode.hierarchyBoundingBox(excluding: hairRootNode)
        let hairBounds = hairNode.hierarchyBoundingBox(visibleOnly: true)
        let headSize = size(of: headBounds)
        let hairSize = size(of: hairBounds)
        let headCenter = center(of: headBounds)
        let hairCenter = center(of: hairBounds)

        guard headSize.x > 0, headSize.y > 0, headSize.z > 0,
              hairSize.x > 0, hairSize.y > 0, hairSize.z > 0 else {
            return
        }

        guard let calibration = style.fitCalibration else { return }

        let targetWidth = headSize.x * calibration.width
        let targetHeight = headSize.y * calibration.height
        let targetDepth = headSize.z * calibration.depth
        let fittedScale = min(targetWidth / hairSize.x, min(targetHeight / hairSize.y, targetDepth / hairSize.z))
        let scale = calibration.fixedScale ?? fittedScale

        let targetCenter = SCNVector3(
            headCenter.x,
            headBounds.min.y + headSize.y * calibration.verticalCenter,
            headCenter.z + headSize.z * calibration.depthCenter
        )

        hairNode.scale = SCNVector3(scale, scale, scale)
        hairNode.position = SCNVector3(
            targetCenter.x - hairCenter.x * scale,
            targetCenter.y - hairCenter.y * scale,
            targetCenter.z - hairCenter.z * scale
        )
    }

    private func makeProceduralHairNode(style: DemoHairStyle) -> SCNNode {
        let headBounds = modelContainerNode.hierarchyBoundingBox(excluding: hairRootNode)
        let headSize = size(of: headBounds)
        let headCenter = center(of: headBounds)

        let capNode = SCNNode()
        capNode.name = "ProceduralHair"
        capNode.geometry = makeHairCapGeometry(
            center: SCNVector3(
                headCenter.x,
                headBounds.min.y + headSize.y * (style == .femaleHair ? 0.72 : 0.77),
                headCenter.z - headSize.z * 0.02
            ),
            radius: SCNVector3(
                headSize.x * (style == .femaleHair ? 0.53 : 0.50),
                headSize.y * (style == .femaleHair ? 0.24 : 0.18),
                headSize.z * (style == .femaleHair ? 0.51 : 0.47)
            ),
            lowerAngle: style == .femaleHair ? 1.08 : 0.88
        )
        capNode.geometry?.firstMaterial = MakeupMaterialFactory.makeHairMaterial()

        if style == .femaleHair {
            addProceduralBangs(to: capNode, headBounds: headBounds)
        }

        return capNode
    }

    private func makeHairCapGeometry(center: SCNVector3, radius: SCNVector3, lowerAngle: Float) -> SCNGeometry {
        let latitudeSegments = 12
        let longitudeSegments = 40
        var vertices: [SCNVector3] = []
        var indices: [Int32] = []

        for latitude in 0...latitudeSegments {
            let theta = lowerAngle * Float(latitude) / Float(latitudeSegments)
            let sinTheta = sin(theta)
            let cosTheta = cos(theta)

            for longitude in 0...longitudeSegments {
                let phi = 2 * Float.pi * Float(longitude) / Float(longitudeSegments)
                vertices.append(SCNVector3(
                    center.x + radius.x * sinTheta * cos(phi),
                    center.y + radius.y * cosTheta,
                    center.z + radius.z * sinTheta * sin(phi)
                ))
            }
        }

        for latitude in 0..<latitudeSegments {
            for longitude in 0..<longitudeSegments {
                let row = longitudeSegments + 1
                let a = Int32(latitude * row + longitude)
                let b = Int32((latitude + 1) * row + longitude)
                let c = Int32(latitude * row + longitude + 1)
                let d = Int32((latitude + 1) * row + longitude + 1)
                indices.append(contentsOf: [a, b, c, c, b, d])
            }
        }

        let source = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        return SCNGeometry(sources: [source], elements: [element])
    }

    private func addProceduralBangs(to capNode: SCNNode, headBounds: (min: SCNVector3, max: SCNVector3)) {
        let headSize = size(of: headBounds)
        let frontZ = headBounds.max.z + headSize.z * 0.012
        let browY = headBounds.min.y + headSize.y * 0.72
        let topY = headBounds.min.y + headSize.y * 0.78
        let centerX = (headBounds.min.x + headBounds.max.x) * 0.5

        for index in 0..<3 {
            let xOffset = (Float(index) - 1.0) * headSize.x * 0.055
            let width = CGFloat(headSize.x * 0.085)
            let height = CGFloat(headSize.y * 0.04)
            let path = UIBezierPath()
            path.move(to: CGPoint(x: -width * 0.5, y: CGFloat(topY)))
            path.addQuadCurve(
                to: CGPoint(x: width * 0.5, y: CGFloat(topY)),
                controlPoint: CGPoint(x: 0, y: CGFloat(browY) - height * 0.22)
            )
            path.close()

            let geometry = SCNShape(path: path, extrusionDepth: CGFloat(headSize.z * 0.014))
            geometry.firstMaterial = MakeupMaterialFactory.makeHairMaterial()
            let bang = SCNNode(geometry: geometry)
            bang.name = "ProceduralBang"
            bang.position = SCNVector3(centerX + xOffset, 0, frontZ)
            capNode.addChildNode(bang)
        }
    }

    private func addProceduralSideSweptHair(to capNode: SCNNode, headBounds: (min: SCNVector3, max: SCNVector3)) {
        let headSize = size(of: headBounds)
        let frontZ = headBounds.max.z + headSize.z * 0.014
        let material = MakeupMaterialFactory.makeHairMaterial()
        let topY = headBounds.min.y + headSize.y * 0.79
        let browY = headBounds.min.y + headSize.y * 0.67
        let leftX = headBounds.min.x + headSize.x * 0.16
        let rightX = headBounds.max.x - headSize.x * 0.17

        let sweepPath = UIBezierPath()
        sweepPath.move(to: CGPoint(x: CGFloat(leftX), y: CGFloat(topY)))
        sweepPath.addCurve(
            to: CGPoint(x: CGFloat(rightX), y: CGFloat(browY + headSize.y * 0.055)),
            controlPoint1: CGPoint(x: CGFloat(leftX + headSize.x * 0.18), y: CGFloat(topY - headSize.y * 0.02)),
            controlPoint2: CGPoint(x: CGFloat(rightX - headSize.x * 0.16), y: CGFloat(browY + headSize.y * 0.03))
        )
        sweepPath.addCurve(
            to: CGPoint(x: CGFloat(leftX + headSize.x * 0.08), y: CGFloat(browY + headSize.y * 0.04)),
            controlPoint1: CGPoint(x: CGFloat(rightX - headSize.x * 0.16), y: CGFloat(browY - headSize.y * 0.015)),
            controlPoint2: CGPoint(x: CGFloat(leftX + headSize.x * 0.22), y: CGFloat(browY - headSize.y * 0.005))
        )
        sweepPath.close()

        let sweepGeometry = SCNShape(path: sweepPath, extrusionDepth: CGFloat(headSize.z * 0.018))
        sweepGeometry.firstMaterial = material.copy() as? SCNMaterial
        let sweepNode = SCNNode(geometry: sweepGeometry)
        sweepNode.name = "ProceduralSideSweep"
        sweepNode.position = SCNVector3(0, 0, frontZ)
        capNode.addChildNode(sweepNode)

        let sideburnWidth = CGFloat(headSize.x * 0.10)
        let sideburnHeight = CGFloat(headSize.y * 0.11)
        for side: Float in [-1, 1] {
            let sideX = side < 0 ? headBounds.min.x + headSize.x * 0.08 : headBounds.max.x - headSize.x * 0.08
            let sideburnPath = UIBezierPath()
            sideburnPath.move(to: CGPoint(x: CGFloat(sideX), y: CGFloat(browY + headSize.y * 0.12)))
            sideburnPath.addLine(to: CGPoint(x: CGFloat(sideX + side * Float(sideburnWidth)), y: CGFloat(browY + headSize.y * 0.07)))
            sideburnPath.addLine(to: CGPoint(x: CGFloat(sideX + side * Float(sideburnWidth) * 0.35), y: CGFloat(browY - Float(sideburnHeight))))
            sideburnPath.close()

            let geometry = SCNShape(path: sideburnPath, extrusionDepth: CGFloat(headSize.z * 0.012))
            geometry.firstMaterial = material.copy() as? SCNMaterial
            let node = SCNNode(geometry: geometry)
            node.name = "ProceduralSideburn"
            node.position = SCNVector3(0, 0, frontZ - headSize.z * 0.025)
            capNode.addChildNode(node)
        }
    }

    private func center(of bounds: (min: SCNVector3, max: SCNVector3)) -> SCNVector3 {
        SCNVector3(
            (bounds.min.x + bounds.max.x) * 0.5,
            (bounds.min.y + bounds.max.y) * 0.5,
            (bounds.min.z + bounds.max.z) * 0.5
        )
    }

    private func size(of bounds: (min: SCNVector3, max: SCNVector3)) -> SCNVector3 {
        SCNVector3(
            bounds.max.x - bounds.min.x,
            bounds.max.y - bounds.min.y,
            bounds.max.z - bounds.min.z
        )
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
    var containsGeometry: Bool {
        (!isHidden && geometry != nil) || childNodes.contains { $0.containsGeometry }
    }

    var childNodesRecursive: [SCNNode] {
        childNodes + childNodes.flatMap { $0.childNodesRecursive }
    }

    var lineageNames: [String] {
        var names: [String] = []
        var current: SCNNode? = self

        while let node = current {
            if let name = node.name {
                names.append(name)
            }
            current = node.parent
        }

        return names
    }

    func isDescendant(of ancestor: SCNNode) -> Bool {
        var current = parent

        while let node = current {
            if node === ancestor {
                return true
            }
            current = node.parent
        }

        return false
    }

    var hierarchyBoundingBox: (min: SCNVector3, max: SCNVector3) {
        hierarchyBoundingBox(excluding: nil, visibleOnly: false)
    }

    func hierarchyBoundingBox(excluding excludedNode: SCNNode? = nil, visibleOnly: Bool = false) -> (min: SCNVector3, max: SCNVector3) {
        var hasBounds = false
        var minVector = SCNVector3Zero
        var maxVector = SCNVector3Zero

        enumerateChildNodes { node, _ in
            if let excludedNode, node === excludedNode || node.isDescendant(of: excludedNode) {
                return
            }

            if visibleOnly && node.isHidden {
                return
            }

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
