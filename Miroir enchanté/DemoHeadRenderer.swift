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
    let eyelidAssetFilenames = [
        "Upper Left eyelid.obj",
        "Upper Right eyelid.obj",
        "Lower Left eyelid.obj",
        "Lower Right eyelid.obj",
        "Upper Left Eyelid.obj",
        "Upper Right Eyelid.obj",
        "Lower Left Eyelid.obj",
        "Lower Right Eyelid.obj",
        "Upper eyelids.obj",
        "Lower eyelids.obj",
        "Eyelids.obj"
    ]
    let eyeAssetFilenames = ["left eyes.obj", "right eyes.obj"]

    let modelContainerNode = SCNNode()
    private let fallbackLipRootNode = SCNNode()
    private let cheekRootNode = SCNNode()
    private let eyelidRootNode = SCNNode()
    private let eyeRootNode = SCNNode()
    let hairRootNode = SCNNode()
    private var lipNodes: [SCNNode] = []
    private var cheekNodes: [SCNNode] = []
    private var eyelidNodes: [SCNNode] = []
    private var lipstickSettings = LipstickSettings.default
    private var blushSettings = BlushSettings.default
    private var eyeshadowSettings = EyeshadowSettings.default
    private var glowSettings = GlowSettings.default
    private var contourSettings = ContourSettings.default
    var currentHairStyle: DemoHairStyle = .none
    var hairHueValue: CGFloat = 0.24
    var hairStrengthValue: CGFloat = 0.84
    var hairMaterials: [SCNMaterial] = []
    var hairBaseTexture: UIImage?
    let hairMaterialNamePrefix = "DemoHairMaterial."
    private var isHeadHidden = false
    private var isHairHidden = false
    private var isMakeupEnabled = true
    private let frontFacingYaw: Float = 0
    private let demoRotationLimit: Float = 85 * .pi / 180
    // The separated hair OBJ is in the same Blender space as the head, but the
    // visible strands sit a little too far back/high in SceneKit. Keep this as
    // a single local tweak so it is easy to tune after the next device pass.
    var hairPlacementOffset = SCNVector3(0, 0.40, 0.07)
    var hairPlacementScale: Float = 1.0
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
        applyEyeshadowMaterial(settings: eyeshadowSettings)
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

    func updateEyeshadowSettings(_ settings: EyeshadowSettings) {
        eyeshadowSettings = settings
        applyEyeshadowMaterial(settings: settings)
    }

    func updateGlowSettings(_ settings: GlowSettings) {
        glowSettings = settings
    }

    func updateContourSettings(_ settings: ContourSettings) {
        contourSettings = settings
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

    func applyEyeshadowMaterial(settings: EyeshadowSettings) {
        for node in eyelidNodes {
            node.renderingOrder = 42
            applyEyeshadow(settings: settings, to: node)
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
        modelContainerNode.addChildNode(eyelidRootNode)
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
        cameraNode.position = SCNVector3(0, -0.6, 6.0)
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

    private func installModel(from loadedScene: SCNScene) {
        modelContainerNode.childNodes.forEach { $0.removeFromParentNode() }
        modelContainerNode.addChildNode(fallbackLipRootNode)
        modelContainerNode.addChildNode(cheekRootNode)
        modelContainerNode.addChildNode(eyelidRootNode)
        modelContainerNode.addChildNode(eyeRootNode)
        modelContainerNode.addChildNode(hairRootNode)

        for child in loadedScene.rootNode.childNodes {
            modelContainerNode.addChildNode(child.clone())
        }

        installCompanionLipAssets()
        installCheekAssets()
        installEyelidAssets()
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

    private func installEyelidAssets() {
        eyelidRootNode.childNodes.forEach { $0.removeFromParentNode() }
        eyelidNodes.removeAll()

        for filename in eyelidAssetFilenames {
            guard let eyelidScene = DemoModelAssetLoader.loadBundledScene(filename: filename, logsMissingAsset: false) else { continue }

            let assetRoot = SCNNode()
            assetRoot.name = DemoModelAssetLoader.splitFilename(filename).name

            for child in eyelidScene.rootNode.childNodes {
                let clone = child.clone()
                if clone.name == nil {
                    clone.name = DemoModelAssetLoader.splitFilename(filename).name
                }
                assetRoot.addChildNode(clone)
            }

            let geometryNodes = assetRoot.childNodesRecursive.filter { $0.geometry != nil }
            guard !geometryNodes.isEmpty else { continue }

            eyelidRootNode.addChildNode(assetRoot)
            eyelidNodes.append(contentsOf: geometryNodes)
            print("Loaded eyelid asset: \(filename)")
        }

        if eyelidNodes.isEmpty {
            print("No eyelid asset loaded yet. Expected one or more of \(eyelidAssetFilenames.joined(separator: ", ")) in the bundle.")
        }

        applyEyeshadowMaterial(settings: eyeshadowSettings)
    }

    private func installFallbackPrimitiveHead() {
        modelContainerNode.childNodes.forEach { $0.removeFromParentNode() }
        modelContainerNode.addChildNode(cheekRootNode)
        modelContainerNode.addChildNode(eyelidRootNode)
        modelContainerNode.addChildNode(eyeRootNode)
        modelContainerNode.addChildNode(hairRootNode)

        modelContainerNode.addChildNode(DemoFallbackFactory.makePrimitiveHead())
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
        return modelContainerNode.hierarchyBoundingBox { node in
            return !DemoGeometryClassifier.isLikelyHairGeometry(node)
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
        for node in modelContainerNode.childNodesRecursive where node.geometry != nil && !node.isDescendant(of: hairRootNode) && !node.isDescendant(of: eyeRootNode) && !node.isDescendant(of: cheekRootNode) && !node.isDescendant(of: eyelidRootNode) {
            guard let geometry = node.geometry else { continue }

            if geometry.materials.contains(where: DemoGeometryClassifier.materialMatchesHair) {
                node.renderingOrder = 30
                geometry.materials = geometry.materials.map { existingMaterial in
                    if DemoGeometryClassifier.materialMatchesHair(existingMaterial) {
                        return preparedHairMaterial(from: existingMaterial)
                    }

                    return skinMaterial.copy() as? SCNMaterial ?? skinMaterial
                }
            } else {
                apply(material: skinMaterial, to: node)
            }
        }
    }

    func applyHeadAndHairVisibility() {
        hairRootNode.isHidden = isHairHidden
        cheekRootNode.isHidden = isHeadHidden || !isMakeupEnabled
        eyelidRootNode.isHidden = isHeadHidden || !isMakeupEnabled
        for node in lipNodes {
            node.isHidden = !isMakeupEnabled
        }

        for node in modelContainerNode.childNodesRecursive where node.geometry != nil {
            guard !node.isDescendant(of: hairRootNode),
                  !node.isDescendant(of: cheekRootNode),
                  !node.isDescendant(of: eyelidRootNode),
                  !node.isDescendant(of: eyeRootNode),
                  !lipNodes.contains(where: { $0 === node }) else {
                continue
            }

            node.isHidden = isHeadHidden
        }
    }

    private func loadEyeOBJNode(filename: String) -> SCNNode? {
        guard DemoModelAssetLoader.splitFilename(filename).extension.lowercased() == "obj" else {
            return nil
        }

        let nodes = DemoModelAssetLoader.loadOBJNodes(filename: filename) { materialName in
            return DemoGeometryClassifier.materialNameLooksLikeTexturedEye(materialName)
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
        for node in rootNode.childNodesRecursive where node.geometry != nil && !DemoGeometryClassifier.isLikelyEyeGeometry(node) {
            node.removeFromParentNode()
        }
    }

    private func makeFallbackLipOverlayNodes() -> [SCNNode] {
        let lipNodes = DemoFallbackFactory.makeLipOverlayNodes(
            bounds: modelContainerNode.hierarchyBoundingBox,
            verticalRatio: fallbackLipVerticalRatio,
            widthRatio: fallbackLipWidthRatio,
            lipstickSettings: lipstickSettings
        )
        lipNodes.forEach { fallbackLipRootNode.addChildNode($0) }
        return lipNodes
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
            let material = MakeupMaterialFactory.makeLipstickMaterial(settings: settings)
            configureDemoLipstickMaterial(material, settings: settings)
            geometry.firstMaterial = material
            return
        }

        for material in geometry.materials {
            configureDemoLipstickMaterial(material, settings: settings)
        }
    }

    private func applyEyeshadow(settings: EyeshadowSettings, to node: SCNNode) {
        guard let geometry = node.geometry else { return }

        if geometry.materials.isEmpty {
            geometry.firstMaterial = MakeupMaterialFactory.makeEyeshadowMaterial(settings: settings)
            return
        }

        for material in geometry.materials {
            MakeupMaterialFactory.configureEyeshadowMaterial(material, settings: settings)
        }
    }

    private func configureDemoLipstickMaterial(_ material: SCNMaterial, settings: LipstickSettings) {
        MakeupMaterialFactory.configureLipstickMaterial(material, settings: settings)
        // Demo lips are real OBJ meshes, not flat overlays. The shared lipstick
        // factory adds a soft UV alpha mask for generic overlays; on exported
        // lip meshes that mask can land outside the UV island and hide them.
        material.transparent.contents = nil
        material.transparency = clampedCGFloat(settings.opacity, to: 0...1)
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
    }

}

extension SCNNode {
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
