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
            // The separated OBJ exports share the same Blender origin as the
            // head, so no procedural fitting is needed.
            return nil
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
    let eyeAssetFilename = "eyes.obj"

    private let modelContainerNode = SCNNode()
    private let fallbackLipRootNode = SCNNode()
    private let eyeRootNode = SCNNode()
    private let hairRootNode = SCNNode()
    private var lipNodes: [SCNNode] = []
    private var lipstickSettings = LipstickSettings.default
    private var currentHairStyle: DemoHairStyle = .none
    private var hairHueValue: CGFloat = 0.24
    private var hairStrengthValue: CGFloat = 0.84
    private var hairMaterials: [SCNMaterial] = []
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

    func updateHairColor(hue: CGFloat, strength: CGFloat) {
        hairHueValue = hue.clamped(to: 0...1)
        hairStrengthValue = strength.clamped(to: 0...1)
        applyHairColorToCachedMaterials()
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

        let usdzFilename = Self.usdzFilename(for: filename)
        let loadedHairAsset = loadBundledScene(filename: filename, logsMissingAsset: false).map { (filename, $0) }
            ?? loadBundledScene(filename: usdzFilename, logsMissingAsset: false).map { (usdzFilename, $0) }
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
        modelContainerNode.addChildNode(eyeRootNode)
        modelContainerNode.addChildNode(hairRootNode)

        let camera = SCNCamera()
        camera.fieldOfView = 38
        camera.zNear = 0.01
        camera.zFar = 100
        camera.wantsHDR = false
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = -2.15

        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 4.0)
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
        setHairStyle(.femaleHair)
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
        modelContainerNode.addChildNode(eyeRootNode)
        modelContainerNode.addChildNode(hairRootNode)

        for child in loadedScene.rootNode.childNodes {
            modelContainerNode.addChildNode(child.clone())
        }

        installCompanionLipAssets()
        // eyes.obj currently includes face geometry in the export. Loading it
        // as-is can draw those extra triangles over the skin in SceneKit, so
        // keep it disabled until the asset contains only eyes.
        // installEyeAsset()
        applySkinMaterialToModel()
    }

    private func installEyeAsset() {
        eyeRootNode.childNodes.forEach { $0.removeFromParentNode() }

        guard let eyeScene = loadBundledScene(filename: eyeAssetFilename, logsMissingAsset: false) else {
            print("Demo eye asset \(eyeAssetFilename) was not found in the app bundle.")
            return
        }

        let assetRoot = SCNNode()
        assetRoot.name = "DemoEyes"

        for child in eyeScene.rootNode.childNodes {
            let clone = child.clone()
            assetRoot.addChildNode(clone)
        }

        pruneNonEyeGeometry(in: assetRoot)
        prepareEyeMaterials(in: assetRoot)
        eyeRootNode.addChildNode(assetRoot)
        print("Loaded demo eye asset: \(eyeAssetFilename)")
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
        for node in modelContainerNode.childNodesRecursive where node.geometry != nil && !node.isDescendant(of: hairRootNode) && !node.isDescendant(of: eyeRootNode) {
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

    private func prepareHairMaterials(in rootNode: SCNNode) {
        for node in rootNode.childNodesRecursive where node.geometry != nil {
            prepareHairMaterial(on: node)
        }
    }

    private func prepareHairMaterial(on node: SCNNode) {
        let fallbackHairMaterial = MakeupMaterialFactory.makeHairMaterial()

        guard let geometry = node.geometry else { return }
        node.renderingOrder = 30

        if geometry.materials.isEmpty {
            let material = preparedHairMaterial(from: fallbackHairMaterial)
            geometry.firstMaterial = material
            registerHairMaterial(material)
            return
        }

        geometry.materials = geometry.materials.map { existingMaterial in
            let material = preparedHairMaterial(from: existingMaterial)
            registerHairMaterial(material)
            return material
        }
    }

    private func preparedHairMaterial(from existingMaterial: SCNMaterial) -> SCNMaterial {
        let fallbackHairMaterial = MakeupMaterialFactory.makeHairMaterial()
        let material = existingMaterial.copy() as? SCNMaterial ?? fallbackHairMaterial

        material.lightingModel = .physicallyBased
        material.roughness.contents = 0.72
        material.metalness.contents = 0.0
        material.specular.contents = UIColor.white.withAlphaComponent(0.06)
        material.shininess = 0.04
        material.isDoubleSided = true
        material.blendMode = .replace
        material.transparencyMode = .aOne
        material.transparency = 1.0
        material.writesToDepthBuffer = true
        material.readsFromDepthBuffer = true

        if let hairTexture = bundledImage(named: "hair_d7", fileExtension: "png", subdirectory: "textures hair") {
            material.diffuse.contents = hairTexture
            material.transparent.contents = nil
        } else {
            material.multiply.contents = nil
        }

        if let hairNormal = bundledImage(named: "hair_n", fileExtension: "png", subdirectory: "textures hair") {
            material.normal.contents = hairNormal
            material.normal.intensity = 0.35
        }

        if let hairSpecular = bundledImage(named: "flatspec.tga", fileExtension: "png", subdirectory: "textures hair") {
            material.specular.contents = hairSpecular
            material.specular.intensity = 0.18
        }

        applyHairColor(to: material)
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
            applyHairColor(to: material)
        }
    }

    private func applyHairColor(to material: SCNMaterial) {
        let tint = hairTintColor()

        if material.diffuse.contents is UIImage {
            material.diffuse.intensity = 0.48 + (1.0 - hairStrengthValue) * 0.18
            material.multiply.contents = tint
            material.multiply.intensity = 0.50 + hairStrengthValue * 0.48
        } else {
            material.diffuse.contents = tint
            material.diffuse.intensity = 0.68 + (1.0 - hairStrengthValue) * 0.18
            material.multiply.contents = nil
        }

        material.transparent.contents = nil
    }

    private func hairTintColor() -> UIColor {
        let hue = hairHueValue.clamped(to: 0...1)
        let strength = hairStrengthValue.clamped(to: 0...1)
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
        let t = fraction.clamped(to: 0...1)
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
            node.renderingOrder = 25

            if geometry.materials.isEmpty {
                geometry.firstMaterial = makeEyeMaterial(named: nil)
            } else {
                geometry.materials = geometry.materials.map { makeEyeMaterial(named: $0.name) }
            }
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

        if isCornea {
            material.diffuse.contents = UIColor.white.withAlphaComponent(0.12)
            material.transparency = 0.18
            material.transparencyMode = .aOne
            material.blendMode = .alpha
            material.writesToDepthBuffer = false
            material.readsFromDepthBuffer = true
        } else {
            material.diffuse.contents = bundledImage(named: "eyeColor", fileExtension: "jpg", subdirectory: "textures eyes")
                ?? UIColor(red: 0.42, green: 0.30, blue: 0.20, alpha: 1.0)
            material.diffuse.intensity = 0.95
            material.specular.contents = bundledImage(named: "eyeSpecular", fileExtension: "jpg", subdirectory: "textures eyes")
                ?? UIColor.white.withAlphaComponent(0.28)
            material.normal.contents = bundledImage(named: "eyeBump", fileExtension: "jpg", subdirectory: "textures eyes")
            material.normal.intensity = 0.25
        }

        return material
    }

    private func pruneNonEyeGeometry(in rootNode: SCNNode) {
        for node in rootNode.childNodesRecursive where node.geometry != nil && !isLikelyEyeGeometry(node) {
            node.isHidden = true
        }
    }

    private func isLikelyEyeGeometry(_ node: SCNNode) -> Bool {
        let nodeName = normalizeNodeName(node.name ?? "")
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

        // The separated hair OBJ can still contain eyes and head geometry.
        // Only an explicit hair material is trustworthy enough to render.
        if geometry.materials.contains(where: materialNameMatchesHair) {
            return true
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
        return nodeName.contains("hair") || nodeName.contains("bang") || nodeName.contains("xpsnewmeshhair")
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

    private func bundledImage(named name: String, fileExtension: String, subdirectory: String) -> UIImage? {
        let url = Bundle.main.url(forResource: name, withExtension: fileExtension, subdirectory: subdirectory)
            ?? Bundle.main.url(forResource: name, withExtension: fileExtension)

        guard let url else {
            return nil
        }

        return UIImage(contentsOfFile: url.path)
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

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
