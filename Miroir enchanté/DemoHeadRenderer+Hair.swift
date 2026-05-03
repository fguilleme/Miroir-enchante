//
//  DemoHeadRenderer+Hair.swift
//  Miroir enchanté
//

import SceneKit
import UIKit

private func clampedCGFloat(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
    Swift.min(Swift.max(value, range.lowerBound), range.upperBound)
}

extension DemoHeadRenderer {
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

    private func loadHairOBJNode(filename: String) -> SCNNode? {
        guard DemoModelAssetLoader.splitFilename(filename).extension.lowercased() == "obj" else {
            return nil
        }

        let nodes = DemoModelAssetLoader.loadOBJNodes(filename: filename) { materialName in
            return DemoGeometryClassifier.materialNameLooksLikeHair(materialName)
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

    private func prepareHairMaterials(in rootNode: SCNNode) {
        for node in rootNode.childNodesRecursive where node.geometry != nil {
            prepareHairMaterial(on: node)
        }
    }

    private func prepareHairMaterial(on node: SCNNode) {
        let fallbackHairMaterial = MakeupMaterialFactory.makeHairMaterial()

        guard let geometry = node.geometry else { return }
        node.renderingOrder = 30
        let nodeLooksLikeHair = DemoGeometryClassifier.nodeLooksLikeHair(node)
        let hasExplicitHairMaterial = geometry.materials.contains(where: DemoGeometryClassifier.materialMatchesHair)

        if geometry.materials.isEmpty {
            let material = preparedHairMaterial(from: fallbackHairMaterial)
            geometry.firstMaterial = material
            registerHairMaterial(material)
            return
        }

        geometry.materials = geometry.materials.map { existingMaterial in
            guard DemoGeometryClassifier.materialMatchesHair(existingMaterial) || (!hasExplicitHairMaterial && nodeLooksLikeHair) else {
                return makeHiddenGeometryMaterial()
            }

            let material = preparedHairMaterial(from: existingMaterial)
            registerHairMaterial(material)
            return material
        }
    }

    func preparedHairMaterial(from existingMaterial: SCNMaterial) -> SCNMaterial {
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

    private func pruneNonHairGeometry(in rootNode: SCNNode) {
        let geometryNodes = rootNode.childNodesRecursive.filter { $0.geometry != nil }
        let hairNodes = geometryNodes.filter { DemoGeometryClassifier.isLikelyHairGeometry($0) }

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
}
