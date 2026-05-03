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
            return "Female hair.obj"
        }
    }

    var fitCalibration: HairFitCalibration? {
        switch self {
        case .none:
            return nil
        case .femaleHair:
            // The hair OBJ is exported from Blender in the same coordinate
            // space as the head. Procedural recentering moves the strands
            // off the scalp, so we keep the authored transform.
            return nil
        }
    }
}

private func clampedCGFloat(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
    Swift.min(Swift.max(value, range.lowerBound), range.upperBound)
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
final class DemoHeadRenderer: MakeupRendering {
    let scene = SCNScene()
    let cameraNode = SCNNode()

    let assetFilename: String
    let fallbackUSDZFilename: String

    /// Manual override hints for assets whose lip meshes are not named with
    /// obvious "lip" or "mouth" terms.
    let lipNodeNameHints = ["UpperLip", "LowerLip", "Upper Lip", "Lower Lip", "Upper_lip", "Lower_lip", "Lips", "Mouth"]
    let companionLipAssetFilenames = ["Upper Lip.obj", "Lower Lip.obj"]
    let cheekAssetFilenames = ["left cheek.obj", "right cheek.obj"]
    let eyeAssetFilenames = ["left eyes.obj", "right eyes.obj"]

    private let modelContainerNode = SCNNode()
    private let fallbackLipRootNode = SCNNode()
    private let cheekRootNode = SCNNode()
    private let eyeRootNode = SCNNode()
    private let hairRootNode = SCNNode()
    private var lipNodes: [SCNNode] = []
    private var cheekNodes: [SCNNode] = []
    private var lipstickSettings = LipstickSettings.default
    private var blushSettings = BlushSettings.default
    private var currentHairStyle: DemoHairStyle = .none
    private var hairHueValue: CGFloat = 0.24
    private var hairStrengthValue: CGFloat = 0.84
    private var hairMaterials: [SCNMaterial] = []
    private var hairBaseTexture: UIImage?
    private let hairMaterialNamePrefix = "DemoHairMaterial."
    private var isHeadHidden = false
    private var isHairHidden = false
    private var isMakeupEnabled = true
    private let frontFacingYaw: Float = 0
    private let demoRotationLimit: Float = 135 * .pi / 180
    // The separated hair OBJ is in the same Blender space as the head, but the
    // visible strands sit a little too far back/high in SceneKit. Keep this as
    // a single local tweak so it is easy to tune after the next device pass.
    private var hairPlacementOffset = SCNVector3(0, 0.40, 0.07)
    private var hairPlacementScale: Float = 1.0
    private var cheekPlacementOffsetY: Float = 0
    private var cheekPlacementScale: Float = 1.0
    private let fallbackLipVerticalRatio: Float = 0.235
    private let fallbackLipWidthRatio: Float = 0.155

    init(assetFilename: String = "female_head.obj") {
        self.assetFilename = assetFilename
        self.fallbackUSDZFilename = DemoModelAssetLoader.usdzFilename(for: assetFilename)

        configureScene()
        loadHeadModel()
        applyLipstickMaterial(settings: lipstickSettings)
        applyBlushMaterial(settings: blushSettings)
    }

    func updateLipstickSettings(_ settings: LipstickSettings) {
        lipstickSettings = settings
        applyLipstickMaterial(settings: settings)
    }

    func updateBlushSettings(_ settings: BlushSettings) {
        blushSettings = settings
        updateCheekPlacement(settings: settings)
        applyBlushMaterial(settings: settings)
    }

    func updateHairColor(hue: CGFloat, strength: CGFloat) {
        hairHueValue = clampedCGFloat(hue, to: 0...1)
        hairStrengthValue = clampedCGFloat(strength, to: 0...1)
        applyHairColorToCachedMaterials()
    }

    func updateHairPlacement(y: Float, z: Float, scale: Float) {
        hairPlacementOffset = SCNVector3(0, y, z)
        hairPlacementScale = scale
        hairRootNode.position = hairPlacementOffset
        hairRootNode.scale = SCNVector3(scale, scale, scale)
    }

    func setHeadHidden(_ hidden: Bool) {
        isHeadHidden = hidden
        applyHeadAndHairVisibility()
    }

    func setHairHidden(_ hidden: Bool) {
        isHairHidden = hidden
        applyHeadAndHairVisibility()
    }

    func setMakeupEnabled(_ enabled: Bool) {
        isMakeupEnabled = enabled
        applyHeadAndHairVisibility()
    }

    func updateInspectionTilt(horizontal: CGFloat) {
        let clampedHorizontal = Float(clampedCGFloat(horizontal, to: -1...1))
        modelContainerNode.removeAllActions()
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.12
        modelContainerNode.eulerAngles.y = frontFacingYaw + clampedHorizontal * demoRotationLimit
        SCNTransaction.commit()
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
        hairMaterials.removeAll()

        guard let filename = style.assetFilename else {
            return
        }

        if let hairNode = loadHairOBJNode(filename: filename) {
            fitHairNode(hairNode, style: style)
            hairRootNode.addChildNode(hairNode)
            applyHeadAndHairVisibility()
            print("Loaded demo hair OBJ directly: \(filename)")
            return
        }

        let usdzFilename = DemoModelAssetLoader.usdzFilename(for: filename)
        let loadedHairAsset = DemoModelAssetLoader.loadBundledScene(filename: filename, logsMissingAsset: false).map { (filename, $0) }
            ?? DemoModelAssetLoader.loadBundledScene(filename: usdzFilename, logsMissingAsset: false).map { (usdzFilename, $0) }
            ?? DemoModelAssetLoader.loadBundledGLBScene(filename: filename).map { (filename, $0) }

        guard let (loadedFilename, loadedScene) = loadedHairAsset else {
            logUnsupportedHairAsset(sourceFilename: filename, usdzFilename: usdzFilename)
            return
        }

        let assetRoot = SCNNode()
        assetRoot.name = "DemoHair"

        for child in loadedScene.rootNode.childNodes {
            assetRoot.addChildNode(child.clone())
        }

        pruneNonHairGeometry(in: assetRoot)

        guard assetRoot.containsGeometry else {
            print("Hair asset \(filename) loaded without renderable hair geometry.")
            return
        }

        prepareHairMaterials(in: assetRoot)
        fitHairNode(assetRoot, style: style)
        hairRootNode.addChildNode(assetRoot)
        applyHeadAndHairVisibility()
        print("Loaded demo hair style: \(loadedFilename)")
    }

    func applyLipstickMaterial(settings: LipstickSettings) {
        for node in lipNodes {
            node.renderingOrder = 40
            applyLipstick(settings: settings, to: node)
        }
    }

    func applyBlushMaterial(settings: BlushSettings) {
        let material = MakeupMaterialFactory.makeBlushMaterial(settings: settings)
        updateCheekPlacement(settings: settings)

        for node in cheekNodes {
            node.renderingOrder = 35
            apply(material: material, to: node)
        }
    }

    private func updateCheekPlacement(settings: BlushSettings) {
        // Demo cheek meshes are exported in the same Blender coordinate space
        // as the head. Keep placement conservative here: the real adjustable
        // blush area is the AR vertex mask, while demo mode is mainly an asset
        // debug view.
        cheekPlacementScale = 1.0
        cheekPlacementOffsetY = 0
        cheekRootNode.position = SCNVector3(0, cheekPlacementOffsetY, 0)
        cheekRootNode.scale = SCNVector3(cheekPlacementScale, cheekPlacementScale, cheekPlacementScale)
    }

    private func configureScene() {
        scene.background.contents = UIColor.black
        scene.rootNode.addChildNode(modelContainerNode)
        modelContainerNode.addChildNode(cheekRootNode)
        modelContainerNode.addChildNode(eyeRootNode)
        hairRootNode.position = hairPlacementOffset
        hairRootNode.scale = SCNVector3(hairPlacementScale, hairPlacementScale, hairPlacementScale)
        modelContainerNode.addChildNode(hairRootNode)

        let camera = SCNCamera()
        camera.fieldOfView = 38
        camera.zNear = 0.01
        camera.zFar = 100
        camera.wantsHDR = false
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = -2.15

        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, -0.3, 6.0)
        scene.rootNode.addChildNode(cameraNode)

        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light?.type = .omni
        keyLight.light?.intensity = 145
        keyLight.position = SCNVector3(0.6, 1.4, 3.0)
        scene.rootNode.addChildNode(keyLight)

        let fillLight = SCNNode()
        fillLight.light = SCNLight()
        fillLight.light?.type = .ambient
        fillLight.light?.intensity = 42
        scene.rootNode.addChildNode(fillLight)
    }

    private func loadHeadModel() {
        if let loadedScene = DemoModelAssetLoader.loadBundledScene(filename: assetFilename) {
            installModel(from: loadedScene)
        } else if let loadedScene = DemoModelAssetLoader.loadBundledScene(filename: fallbackUSDZFilename) {
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
        setHairStyle(.femaleHair)
        updateInspectionTilt(horizontal: 0)
        resolveLipNodes()
    }

    private func logUnsupportedHairAsset(sourceFilename: String, usdzFilename: String) {
        let sourceStatus: String
        if DemoModelAssetLoader.bundledAssetExists(filename: sourceFilename) {
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

    private func installModel(from loadedScene: SCNScene) {
        modelContainerNode.childNodes.forEach { $0.removeFromParentNode() }
        modelContainerNode.addChildNode(fallbackLipRootNode)
        modelContainerNode.addChildNode(cheekRootNode)
        modelContainerNode.addChildNode(eyeRootNode)
        modelContainerNode.addChildNode(hairRootNode)

        for child in loadedScene.rootNode.childNodes {
            modelContainerNode.addChildNode(child.clone())
        }

        installCompanionLipAssets()
        installCheekAssets()
        // eyes.obj is exported in the same coordinate space as the head. Its
        // material file does not need texture references because the demo
        // renderer applies the bundled eye textures explicitly below.
        installEyeAsset()
        applySkinMaterialToModel()
        applyHeadAndHairVisibility()
    }

    private func installEyeAsset() {
        eyeRootNode.childNodes.forEach { $0.removeFromParentNode() }

        var loadedAny = false
        for filename in eyeAssetFilenames {
            if let eyeNode = loadEyeOBJNode(filename: filename) {
                eyeRootNode.addChildNode(eyeNode)
                print("Loaded demo eye OBJ directly: \(filename)")
                loadedAny = true
                continue
            }

            guard let eyeScene = DemoModelAssetLoader.loadBundledScene(filename: filename, logsMissingAsset: false) else {
                print("Demo eye asset \(filename) was not found in the app bundle.")
                continue
            }

            let assetRoot = SCNNode()
            assetRoot.name = "DemoEyes_\(DemoModelAssetLoader.splitFilename(filename).name)"

            for child in eyeScene.rootNode.childNodes {
                assetRoot.addChildNode(child.clone())
            }

            pruneNonEyeGeometry(in: assetRoot)
            prepareEyeMaterials(in: assetRoot)
            eyeRootNode.addChildNode(assetRoot)
            print("Loaded demo eye asset: \(filename)")
            loadedAny = true
        }

        if !loadedAny {
            print("No eye asset loaded. Expected one or more of \(eyeAssetFilenames.joined(separator: ", ")) in the bundle.")
        }
    }

    private func installCompanionLipAssets() {
        for filename in companionLipAssetFilenames {
            guard let lipScene = DemoModelAssetLoader.loadBundledScene(filename: filename) else { continue }

            let assetRoot = SCNNode()
            assetRoot.name = DemoModelAssetLoader.splitFilename(filename).name

            for child in lipScene.rootNode.childNodes {
                let clone = child.clone()
                if clone.name == nil {
                    clone.name = DemoModelAssetLoader.splitFilename(filename).name
                }
                assetRoot.addChildNode(clone)
            }

            if !assetRoot.childNodes.isEmpty {
                modelContainerNode.addChildNode(assetRoot)
                print("Loaded companion lip asset: \(filename)")
            }
        }
    }

    private func installCheekAssets() {
        cheekRootNode.childNodes.forEach { $0.removeFromParentNode() }
        cheekNodes.removeAll()

        for filename in cheekAssetFilenames {
            guard let cheekScene = DemoModelAssetLoader.loadBundledScene(filename: filename) else { continue }

            let assetRoot = SCNNode()
            assetRoot.name = DemoModelAssetLoader.splitFilename(filename).name

            for child in cheekScene.rootNode.childNodes {
                let clone = child.clone()
                if clone.name == nil {
                    clone.name = DemoModelAssetLoader.splitFilename(filename).name
                }
                assetRoot.addChildNode(clone)
            }

            let geometryNodes = assetRoot.childNodesRecursive.filter { $0.geometry != nil }
            guard !geometryNodes.isEmpty else { continue }

            cheekRootNode.addChildNode(assetRoot)
            cheekNodes.append(contentsOf: geometryNodes)
            print("Loaded cheek asset: \(filename)")
        }

        if cheekNodes.isEmpty {
            print("No cheek asset loaded. Expected \(cheekAssetFilenames.joined(separator: ", ")) in the app bundle.")
        }

        applyBlushMaterial(settings: blushSettings)
    }

    private func installFallbackPrimitiveHead() {
        modelContainerNode.childNodes.forEach { $0.removeFromParentNode() }
        modelContainerNode.addChildNode(cheekRootNode)
        modelContainerNode.addChildNode(eyeRootNode)
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
        // Frame the head/face, not the whole combined asset. Long hair and
        // ponytails can extend far outside the head and would otherwise make
        // the demo camera scale the face down or shift it off center.
        let bounds = modelFramingBounds()
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

    private func modelFramingBounds() -> (min: SCNVector3, max: SCNVector3) {
        return modelContainerNode.hierarchyBoundingBox { [weak self] node in
            guard let self else { return true }
            return !self.isLikelyHairGeometry(node)
        }
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
        for node in modelContainerNode.childNodesRecursive where node.geometry != nil && !node.isDescendant(of: hairRootNode) && !node.isDescendant(of: eyeRootNode) && !node.isDescendant(of: cheekRootNode) {
            guard let geometry = node.geometry else { continue }

            if geometry.materials.contains(where: materialNameMatchesHair) {
                node.renderingOrder = 30
                geometry.materials = geometry.materials.map { existingMaterial in
                    if materialNameMatchesHair(existingMaterial) {
                        return preparedHairMaterial(from: existingMaterial)
                    }

                    return skinMaterial.copy() as? SCNMaterial ?? skinMaterial
                }
            } else {
                apply(material: skinMaterial, to: node)
            }
        }
    }

    private func applyHeadAndHairVisibility() {
        hairRootNode.isHidden = isHairHidden
        cheekRootNode.isHidden = isHeadHidden || !isMakeupEnabled

        for node in lipNodes {
            node.isHidden = !isMakeupEnabled
        }

        for node in modelContainerNode.childNodesRecursive where node.geometry != nil {
            guard !node.isDescendant(of: hairRootNode),
                  !node.isDescendant(of: cheekRootNode),
                  !node.isDescendant(of: eyeRootNode),
                  !lipNodes.contains(where: { $0 === node }) else {
                continue
            }

            node.isHidden = isHeadHidden
        }
    }

    private func loadHairOBJNode(filename: String) -> SCNNode? {
        guard DemoModelAssetLoader.splitFilename(filename).extension.lowercased() == "obj" else {
            return nil
        }

        let nodes = DemoModelAssetLoader.loadOBJNodes(filename: filename) { [weak self] materialName in
            guard let self else { return false }
            return self.materialNameLooksLikeHair(materialName)
        } materialProvider: { [weak self] materialName in
            guard let self else { return MakeupMaterialFactory.makeHairMaterial() }
            let sourceMaterial = MakeupMaterialFactory.makeHairMaterial()
            sourceMaterial.name = materialName
            let material = self.preparedHairMaterial(from: sourceMaterial)
            self.registerHairMaterial(material)
            return material
        }

        guard !nodes.isEmpty else {
            print("Direct OBJ hair loader found no hair material in \(filename). Expected a material name containing 'hair'.")
            return nil
        }

        let rootNode = SCNNode()
        rootNode.name = "DirectDemoHair"
        nodes.forEach { node in
            // The hair OBJ is already exported in the head coordinate space.
            // Keep normal depth testing so back-side cards do not draw over the
            // face while inspecting the model with device tilt.
            node.renderingOrder = 30
            rootNode.addChildNode(node)
        }
        let triangleCount = nodes.reduce(0) { partialResult, node in
            partialResult + ((node.geometry?.elements.first?.primitiveCount) ?? 0)
        }
        let bounds = rootNode.hierarchyBoundingBox(visibleOnly: true)
        let nodeNames = nodes.compactMap(\.name).joined(separator: ", ")
        print("Direct OBJ hair geometry: \(nodes.count) node(s), \(triangleCount) triangles, nodes: \(nodeNames), bounds min \(bounds.min), max \(bounds.max)")
        return rootNode
    }

    private func loadEyeOBJNode(filename: String) -> SCNNode? {
        guard DemoModelAssetLoader.splitFilename(filename).extension.lowercased() == "obj" else {
            return nil
        }

        let nodes = DemoModelAssetLoader.loadOBJNodes(filename: filename) { [weak self] materialName in
            guard let self else { return false }
            return self.materialNameLooksLikeTexturedEye(materialName)
        } materialProvider: { [weak self] materialName in
            self?.makeTexturedEyeMaterial(named: materialName) ?? SCNMaterial()
        }

        guard !nodes.isEmpty else {
            print("Direct OBJ eye loader found no textured eye material in \(filename). Expected Eyes / Eyes.001.")
            return nil
        }

        let rootNode = SCNNode()
        rootNode.name = "DirectDemoEyes"
        nodes.forEach { node in
            node.renderingOrder = 45
            rootNode.addChildNode(node)
        }
        for node in nodes {
            let triangles = node.geometry?.elements.first?.primitiveCount ?? 0
            let sources = node.geometry?.sources ?? []
            let vertexCount = sources.first(where: { $0.semantic == .vertex })?.vectorCount ?? 0
            let uvCount = sources.first(where: { $0.semantic == .texcoord })?.vectorCount ?? 0
            let materialName = node.geometry?.firstMaterial?.name ?? "?"
            let hasDiffuseTexture = node.geometry?.firstMaterial?.diffuse.contents is UIImage
            print("Direct OBJ eye node \(node.name ?? "?"): material=\(materialName), tris=\(triangles), verts=\(vertexCount), uv=\(uvCount), diffuseImage=\(hasDiffuseTexture)")
        }
        return rootNode
    }

    private func prepareHairMaterials(in rootNode: SCNNode) {
        for node in rootNode.childNodesRecursive where node.geometry != nil {
            prepareHairMaterial(on: node)
        }
    }

    private func prepareHairMaterial(on node: SCNNode) {
        let fallbackHairMaterial = MakeupMaterialFactory.makeHairMaterial()

        guard let geometry = node.geometry else { return }
        node.renderingOrder = 30
        let nodeLooksLikeHair = nodeNameLooksLikeHair(node)
        let hasExplicitHairMaterial = geometry.materials.contains(where: materialNameMatchesHair)

        if geometry.materials.isEmpty {
            let material = preparedHairMaterial(from: fallbackHairMaterial)
            geometry.firstMaterial = material
            registerHairMaterial(material)
            return
        }

        geometry.materials = geometry.materials.map { existingMaterial in
            guard materialNameMatchesHair(existingMaterial) || (!hasExplicitHairMaterial && nodeLooksLikeHair) else {
                return makeHiddenGeometryMaterial()
            }

            let material = preparedHairMaterial(from: existingMaterial)
            registerHairMaterial(material)
            return material
        }
    }

    private func preparedHairMaterial(from existingMaterial: SCNMaterial) -> SCNMaterial {
        let fallbackHairMaterial = MakeupMaterialFactory.makeHairMaterial()
        let material = existingMaterial.copy() as? SCNMaterial ?? fallbackHairMaterial
        material.name = hairMaterialNamePrefix + (existingMaterial.name ?? "fallback")

        // Blinn keeps the texture's apparent color stable. PBR over-lit the
        // hair to near white because hair_d7.png is a light/neutral base meant
        // to be tinted, and PBR + ambient + key light pushed it past the tint.
        material.lightingModel = .blinn
        material.shininess = 0.18
        material.specular.contents = UIColor.white.withAlphaComponent(0.10)
        material.isDoubleSided = true
        material.blendMode = .alpha
        material.transparencyMode = .aOne
        material.transparency = 1.0
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        material.transparent.contents = nil
        material.multiply.contents = nil

        let hairTexture = DemoModelAssetLoader.bundledImage(named: "hair_d7", fileExtension: "png", subdirectory: "textures hair")
        let hairNormal = DemoModelAssetLoader.bundledImage(named: "hair_n", fileExtension: "png", subdirectory: "textures hair")
        let hairSpecular = DemoModelAssetLoader.bundledImage(named: "flatspec.tga", fileExtension: "png", subdirectory: "textures hair")

        if let hairTexture {
            hairBaseTexture = hairTexture
            material.diffuse.wrapS = .repeat
            material.diffuse.wrapT = .repeat
            material.diffuse.magnificationFilter = .linear
            material.diffuse.minificationFilter = .linear
            // hair_d7.png currently carries alpha/UV data that makes SceneKit
            // drop visible hair cards when used directly as diffuse or alpha.
            // Keep it cached for future processing, but render with a solid
            // tint plus normal/specular maps until a clean color/cutout export
            // is available.
            material.transparent.contents = nil
        }

        if let hairNormal {
            material.normal.contents = hairNormal
            material.normal.intensity = 0.35
            material.normal.wrapS = .repeat
            material.normal.wrapT = .repeat
        }

        if let hairSpecular {
            material.specular.contents = hairSpecular
            material.specular.intensity = 0.18
            material.specular.wrapS = .repeat
            material.specular.wrapT = .repeat
        }

        print("Demo hair material \(material.name ?? "?"): colorMap=\(hairTexture == nil ? "missing" : "cached") normal=\(hairNormal == nil ? "missing" : "loaded") spec=\(hairSpecular == nil ? "missing" : "loaded") alphaMask=disabled")

        applyHairColor(to: material)
        return material
    }

    private func makeHiddenGeometryMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.name = "DemoHiddenGeometryMaterial"
        material.lightingModel = .constant
        material.diffuse.contents = UIColor.clear
        material.transparency = 0.0
        material.transparencyMode = .aOne
        material.blendMode = .alpha
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        material.colorBufferWriteMask = []
        return material
    }

    private func registerHairMaterial(_ material: SCNMaterial) {
        guard !hairMaterials.contains(where: { $0 === material }) else {
            return
        }

        hairMaterials.append(material)
    }

    private func applyHairColorToCachedMaterials() {
        for material in hairMaterials {
            guard isManagedHairMaterial(material) else { continue }
            applyHairColor(to: material)
        }
    }

    private func applyHairColor(to material: SCNMaterial) {
        guard isManagedHairMaterial(material) else { return }

        let tint = hairTintColor()

        if material.diffuse.contents is UIImage {
            // Multiplying a very dark hair texture barely changes it. Generate
            // a tinted diffuse image instead. In normal runtime we avoid this
            // branch because hair_d7's alpha currently clips hair cards.
            material.diffuse.intensity = 1.0
            material.diffuse.contents = makeTintedHairTexture(tint: tint)
            material.multiply.contents = nil
        } else {
            material.diffuse.contents = tint
            material.diffuse.intensity = 0.82 + (1.0 - hairStrengthValue) * 0.12
            material.multiply.contents = nil
        }
    }

    private func makeTintedHairTexture(tint: UIColor) -> UIImage? {
        guard let baseTexture = hairBaseTexture else {
            return nil
        }

        let rect = CGRect(origin: .zero, size: baseTexture.size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = baseTexture.scale
        format.opaque = false

        let tintAlpha = 0.25 + clampedCGFloat(hairStrengthValue, to: 0...1) * 0.70
        return UIGraphicsImageRenderer(size: baseTexture.size, format: format).image { _ in
            baseTexture.draw(in: rect)
            tint.withAlphaComponent(tintAlpha).setFill()
            UIRectFillUsingBlendMode(rect, .sourceAtop)
            // Bring a little of the original texture back so strand variation
            // stays visible after the hue overlay.
            baseTexture.draw(in: rect, blendMode: .multiply, alpha: 0.22)
        }
    }

    private func isManagedHairMaterial(_ material: SCNMaterial) -> Bool {
        guard let materialName = material.name else {
            return false
        }

        return materialName.hasPrefix(hairMaterialNamePrefix)
    }

    private func hairTintColor() -> UIColor {
        let hue = clampedCGFloat(hairHueValue, to: 0...1)
        let strength = clampedCGFloat(hairStrengthValue, to: 0...1)
        let stops: [(position: CGFloat, color: UIColor)] = [
            (0.00, UIColor(red: 0.030, green: 0.028, blue: 0.026, alpha: 1.0)),
            (0.22, UIColor(red: 0.095, green: 0.060, blue: 0.038, alpha: 1.0)),
            (0.48, UIColor(red: 0.34, green: 0.15, blue: 0.055, alpha: 1.0)),
            (0.72, UIColor(red: 0.55, green: 0.40, blue: 0.20, alpha: 1.0)),
            (1.00, UIColor(red: 0.45, green: 0.45, blue: 0.42, alpha: 1.0))
        ]

        let tint = interpolatedColor(in: stops, value: hue)
        let neutral = UIColor(red: 0.22, green: 0.22, blue: 0.21, alpha: 1.0)

        return interpolatedColor(from: neutral, to: tint, fraction: 0.35 + strength * 0.65)
    }

    private func interpolatedColor(in stops: [(position: CGFloat, color: UIColor)], value: CGFloat) -> UIColor {
        guard let upperIndex = stops.firstIndex(where: { value <= $0.position }) else {
            return stops[stops.count - 1].color
        }

        if upperIndex == 0 {
            return stops[0].color
        }

        let lower = stops[upperIndex - 1]
        let upper = stops[upperIndex]
        let span = upper.position - lower.position
        let fraction = span > 0 ? (value - lower.position) / span : 0
        return interpolatedColor(from: lower.color, to: upper.color, fraction: fraction)
    }

    private func interpolatedColor(from startColor: UIColor, to endColor: UIColor, fraction: CGFloat) -> UIColor {
        let t = clampedCGFloat(fraction, to: 0...1)
        var startRed: CGFloat = 0
        var startGreen: CGFloat = 0
        var startBlue: CGFloat = 0
        var startAlpha: CGFloat = 0
        var endRed: CGFloat = 0
        var endGreen: CGFloat = 0
        var endBlue: CGFloat = 0
        var endAlpha: CGFloat = 0

        guard startColor.getRed(&startRed, green: &startGreen, blue: &startBlue, alpha: &startAlpha),
              endColor.getRed(&endRed, green: &endGreen, blue: &endBlue, alpha: &endAlpha) else {
            return startColor
        }

        return UIColor(
            red: startRed + (endRed - startRed) * t,
            green: startGreen + (endGreen - startGreen) * t,
            blue: startBlue + (endBlue - startBlue) * t,
            alpha: startAlpha + (endAlpha - startAlpha) * t
        )
    }

    private func prepareEyeMaterials(in rootNode: SCNNode) {
        for node in rootNode.childNodesRecursive where node.geometry != nil {
            guard let geometry = node.geometry else { continue }

            if geometry.materials.isEmpty {
                geometry.firstMaterial = makeEyeMaterial(named: nil)
            } else {
                geometry.materials = geometry.materials.map { makeEyeMaterial(named: $0.name) }
            }

            let materialNames = geometry.materials.map { normalizeNodeName($0.name ?? "") }
            node.renderingOrder = materialNames.contains(where: { $0.contains("aistandard3") }) ? 36 : 35
        }
    }

    private func makeEyeMaterial(named name: String?) -> SCNMaterial {
        let material = SCNMaterial()
        let normalizedName = normalizeNodeName(name ?? "")
        let isCornea = normalizedName.contains("aistandard3")

        material.lightingModel = .physicallyBased
        material.isDoubleSided = true
        material.metalness.contents = 0.0
        material.roughness.contents = isCornea ? 0.08 : 0.36
        material.specular.contents = UIColor.white.withAlphaComponent(isCornea ? 0.65 : 0.32)
        material.shininess = isCornea ? 0.9 : 0.35
        material.readsFromDepthBuffer = true

        if isCornea {
            material.diffuse.contents = UIColor.white.withAlphaComponent(0.12)
            material.transparency = 0.18
            material.transparencyMode = .aOne
            material.blendMode = .alpha
            material.writesToDepthBuffer = false
        } else {
            let colorTexture = DemoModelAssetLoader.bundledImage(named: "eyeColor", fileExtension: "jpg", subdirectory: "textures eyes")
            let specularTexture = DemoModelAssetLoader.bundledImage(named: "eyeSpecular", fileExtension: "jpg", subdirectory: "textures eyes")
            let bumpTexture = DemoModelAssetLoader.bundledImage(named: ["eyeBump", "eyesBump"], fileExtension: "jpg", subdirectory: "textures eyes")
            configureEyeTexture(colorTexture, specularTexture: specularTexture, bumpTexture: bumpTexture, on: material)
            material.diffuse.contents = colorTexture ?? UIColor(red: 0.42, green: 0.30, blue: 0.20, alpha: 1.0)
            material.diffuse.intensity = 0.82
            material.writesToDepthBuffer = true
        }

        return material
    }

    private func makeTexturedEyeMaterial(named name: String) -> SCNMaterial {
        let material = SCNMaterial()
        material.name = "DemoTexturedEye.\(name)"
        let colorTexture = DemoModelAssetLoader.bundledImage(named: "eyeColor", fileExtension: "jpg", subdirectory: "textures eyes")

        print("Demo eye material \(name): eyeColor.jpg \(colorTexture == nil ? "missing" : "loaded")")
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.diffuse.contents = colorTexture ?? UIColor(red: 0.42, green: 0.30, blue: 0.20, alpha: 1.0)
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        material.diffuse.magnificationFilter = .linear
        material.diffuse.minificationFilter = .linear
        material.diffuse.intensity = 1.0
        material.transparency = 1.0
        material.blendMode = .replace
        material.writesToDepthBuffer = true
        material.readsFromDepthBuffer = true
        return material
    }

    private func configureEyeTexture(
        _ colorTexture: UIImage?,
        specularTexture: UIImage?,
        bumpTexture: UIImage?,
        on material: SCNMaterial
    ) {
        material.diffuse.contents = colorTexture
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        material.diffuse.magnificationFilter = .linear
        material.diffuse.minificationFilter = .linear

        material.specular.contents = specularTexture ?? UIColor.white.withAlphaComponent(0.18)
        material.specular.intensity = 0.12
        material.specular.wrapS = .clamp
        material.specular.wrapT = .clamp

        material.normal.contents = bumpTexture
        material.normal.intensity = 0.15
        material.normal.wrapS = .clamp
        material.normal.wrapT = .clamp
    }

    private func pruneNonEyeGeometry(in rootNode: SCNNode) {
        for node in rootNode.childNodesRecursive where node.geometry != nil && !isLikelyEyeGeometry(node) {
            node.removeFromParentNode()
        }
    }

    private func isLikelyEyeGeometry(_ node: SCNNode) -> Bool {
        let nodeName = normalizeNodeName(node.name ?? "")
        if nodeName.contains("head") || nodeName.contains("face") || nodeName.contains("defaultmat") {
            return false
        }

        if nodeName.contains("eye") {
            return true
        }

        guard let geometry = node.geometry else { return false }
        return geometry.materials.contains { material in
            let materialName = normalizeNodeName(material.name ?? "")
            return materialName.contains("eye") || materialName.contains("aistandard3")
        }
    }

    private func pruneNonHairGeometry(in rootNode: SCNNode) {
        let geometryNodes = rootNode.childNodesRecursive.filter { $0.geometry != nil }
        let hairNodes = geometryNodes.filter { isLikelyHairGeometry($0) }

        guard !hairNodes.isEmpty else {
            for node in geometryNodes {
                node.removeFromParentNode()
            }
            return
        }

        for node in geometryNodes where !hairNodes.contains(where: { $0 === node }) {
            node.removeFromParentNode()
        }
    }

    private func isLikelyHairGeometry(_ node: SCNNode) -> Bool {
        guard let geometry = node.geometry else {
            return false
        }

        if nodeNameLooksLikeEye(node) {
            return false
        }

        // The separated hair OBJ can still contain eyes and head geometry.
        // Keep any geometry that has a hair material, then hide the non-hair
        // material slots in prepareHairMaterial(on:) instead of discarding the
        // whole node.
        if geometry.materials.contains(where: materialNameMatchesHair) {
            return true
        }

        if geometry.materials.contains(where: materialNameMatchesEye) {
            return false
        }

        let nodeName = normalizeNodeName(node.name ?? "")
        let rigTerms = ["armature", "skeleton", "joint", "bone", "rootjoint", "controller", "control", "ik", "fk"]
        if rigTerms.contains(where: { nodeName.contains($0) }) {
            return false
        }

        if nodeName.contains("head") || nodeName.contains("face") {
            return false
        }

        // Do not inspect parent names here: the combined demo OBJ is named
        // "Female head with hair", and using lineage names would classify the
        // whole head as hair. Only the renderable object/material should decide.
        return nodeNameLooksLikeHair(node)
    }

    private func nodeNameLooksLikeHair(_ node: SCNNode) -> Bool {
        let nodeName = normalizeNodeName(node.name ?? "")
        return nodeName.contains("hair") || nodeName.contains("bang") || nodeName.contains("xpsnewmeshhair")
    }

    private func nodeNameLooksLikeEye(_ node: SCNNode) -> Bool {
        let nodeName = normalizeNodeName(node.name ?? "")
        return nodeName.contains("eye") || nodeName.contains("iris") || nodeName.contains("cornea")
    }

    private func materialNameMatchesHair(_ material: SCNMaterial) -> Bool {
        if let materialName = material.name {
            if materialNameLooksLikeHair(materialName) {
                return true
            }
        }

        return false
    }

    private func materialNameLooksLikeHair(_ materialName: String) -> Bool {
        let name = normalizeNodeName(materialName)
        return name.contains("hair") || name.contains("bang")
    }

    private func materialNameLooksLikeTexturedEye(_ materialName: String) -> Bool {
        let name = normalizeNodeName(materialName)
        // Diagnostic confirmed the iris UVs live on Eyes / Eyes.001. The
        // aiStandard3* meshes are the cornea sphere and would overlay a
        // washed-out copy of the iris if they were textured too.
        return name == "eyes" || name == "eyes001" || (name.contains("eye") && !name.contains("aistandard"))
    }

    private func materialNameMatchesEye(_ material: SCNMaterial) -> Bool {
        guard let materialName = material.name else {
            return false
        }

        let name = normalizeNodeName(materialName)
        return name.contains("eye") || name.contains("iris") || name.contains("cornea") || name.contains("aistandard3")
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

    private func applyLipstick(settings: LipstickSettings, to node: SCNNode) {
        guard let geometry = node.geometry else { return }

        if geometry.materials.isEmpty {
            geometry.firstMaterial = MakeupMaterialFactory.makeLipstickMaterial(settings: settings)
            return
        }

        for material in geometry.materials {
            MakeupMaterialFactory.configureLipstickMaterial(material, settings: settings)
        }
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

    func hierarchyBoundingBox(
        excluding excludedNode: SCNNode? = nil,
        visibleOnly: Bool = false,
        shouldInclude: ((SCNNode) -> Bool)? = nil
    ) -> (min: SCNVector3, max: SCNVector3) {
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
            if let shouldInclude, !shouldInclude(node) {
                return
            }

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
