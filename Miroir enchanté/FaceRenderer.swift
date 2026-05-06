//
//  FaceRenderer.swift
//  Miroir enchanté
//

import ARKit
import SceneKit
import UIKit

/// Converts ARKit face anchors into SceneKit geometry and updates it in real time.
final class FaceRenderer: NSObject, ARSCNViewDelegate, MakeupRendering {
    enum RenderMode {
        case lipsOnly
        case fullFace
        case wireframe

        var buttonTitle: String {
            switch self {
            case .lipsOnly:
                return L10n.text("render.lips")
            case .fullFace:
                return L10n.text("render.full")
            case .wireframe:
                return L10n.text("render.mesh")
            }
        }
    }

    private weak var sceneView: ARSCNView?
    private weak var lipsNode: SCNNode?
    private weak var cheeksNode: SCNNode?
    private weak var eyeshadowNode: SCNNode?
    private weak var lipDebugNode: SCNNode?

    private var baseFaceGeometry: ARSCNFaceGeometry?
    private var lipMesh: LipMeshGeometry?
    private var cheekMesh: CheekMeshGeometry?
    private var eyeshadowMesh: EyeshadowMeshGeometry?
    private var glowRenderer: GlowRenderer?
    private var contourRenderer: ContourRenderer?
    private var hasDetectedFace = false
    private let makeupState = MakeupState()
    private let viewportLock = NSLock()
    private var lipMeshCalibration = LipMeshCalibration.default
    private var shouldRebuildLipMesh = false
    private var appliedMakeupRevision: UInt64 = UInt64.max
    private var frameIndex: UInt64 = 0
    private var cachedViewportSize: CGSize = .zero
    private let lipsOnlyMaterial = MakeupMaterialFactory.makeARLipstickMaterial()
    private let fullFaceMaterial = MakeupMaterialFactory.makeARLipstickMaterial()
    private let blushMaterial = MakeupMaterialFactory.makeARBlushMaterial()
    private let eyeshadowMaterial = MakeupMaterialFactory.makeAREyeshadowMaterial()
    private let invisibleFaceMaterial = MakeupMaterialFactory.makeInvisibleFaceMaterial()
    private let wireframeMaterial = MakeupMaterialFactory.makeWireframeMaterial()
    private let lipHighlightMaterial = MakeupMaterialFactory.makeLipHighlightMaterial()
    private let cheekWireframeMaterial = MakeupMaterialFactory.makeZoneWireframeMaterial(color: .systemPink)
    private let eyeshadowWireframeMaterial = MakeupMaterialFactory.makeZoneWireframeMaterial(color: .systemPurple)
    private let lipVertexDebugMaterial = MakeupMaterialFactory.makeLipVertexDebugMaterial()

    #if DEBUG
    private let fpsMonitor = DebugFPSMonitor()
    #endif

    private(set) var renderMode: RenderMode = .lipsOnly
    var faceBoundsDidUpdate: ((CGRect) -> Void)?
    var faceDetectionStateDidChange: ((Bool) -> Void)?

    /// Prototype lip index sets. They are generated once from the first
    /// ARFaceGeometry frame by selecting vertices in the face-local mouth band.
    /// ARKit's face mesh topology is stable for the session, so those vertex
    /// indices can then be reused every frame. For production, replace these
    /// generated arrays with curated constants from a labeled topology map and
    /// refine the boundary for cupid's bow, lip corners, and inner mouth.
    private var upperLipIndices: [Int] = []
    private var lowerLipIndices: [Int] = []

    func attach(to sceneView: ARSCNView) {
        self.sceneView = sceneView
    }

    func updateViewportSize(_ size: CGSize) {
        viewportLock.lock()
        cachedViewportSize = size
        viewportLock.unlock()
    }

    func updateLipstickSettings(_ settings: LipstickSettings) {
        makeupState.updateLipstick(settings)
    }

    func updateBlushSettings(_ settings: BlushSettings) {
        makeupState.updateBlush(settings)
    }

    func updateEyeshadowSettings(_ settings: EyeshadowSettings) {
        makeupState.updateEyeshadow(settings)
    }

    func updateGlowSettings(_ settings: GlowSettings) {
        makeupState.updateGlow(settings)
    }

    func updateContourSettings(_ settings: ContourSettings) {
        makeupState.updateContour(settings)
    }

    func setMakeupEnabled(_ enabled: Bool) {
        makeupState.updateMakeupEnabled(enabled)
    }

    func updateLipMeshCalibration(_ calibration: LipMeshCalibration) {
        lipMeshCalibration = calibration
        shouldRebuildLipMesh = true
    }

    @discardableResult
    func toggleMode() -> RenderMode {
        switch renderMode {
        case .lipsOnly:
            renderMode = .fullFace
        case .fullFace:
            renderMode = .wireframe
        case .wireframe:
            renderMode = .lipsOnly
        }

        applyCurrentMode()
        return renderMode
    }

    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard let faceAnchor = anchor as? ARFaceAnchor else { return nil }
        guard let device = sceneView?.device else { return nil }

        let baseFaceGeometry = ARSCNFaceGeometry(device: device)
        self.baseFaceGeometry = baseFaceGeometry

        let faceNode = SCNNode(geometry: baseFaceGeometry)
        faceNode.renderingOrder = 1

        if let lipMesh = LipMeshGeometry(device: device, faceGeometry: faceAnchor.geometry, calibration: lipMeshCalibration) {
            self.upperLipIndices = lipMesh.upperLipIndices
            self.lowerLipIndices = lipMesh.lowerLipIndices
            self.lipMesh = lipMesh

            let lipsNode = SCNNode(geometry: lipMesh.geometry)
            lipsNode.renderingOrder = 40
            faceNode.addChildNode(lipsNode)
            self.lipsNode = lipsNode

            if let cheekMesh = CheekMeshGeometry(device: device, faceGeometry: faceAnchor.geometry) {
                self.cheekMesh = cheekMesh

                let cheeksNode = SCNNode(geometry: cheekMesh.geometry)
                cheeksNode.renderingOrder = 35
                faceNode.addChildNode(cheeksNode)
                self.cheeksNode = cheeksNode
            }

            if let eyeshadowMesh = EyeshadowMeshGeometry(device: device, faceGeometry: faceAnchor.geometry) {
                self.eyeshadowMesh = eyeshadowMesh

                let eyeshadowNode = SCNNode(geometry: eyeshadowMesh.geometry)
                eyeshadowNode.renderingOrder = 38
                faceNode.addChildNode(eyeshadowNode)
                self.eyeshadowNode = eyeshadowNode
            }

            let lipDebugNode = SCNNode(geometry: lipMesh.debugPointGeometry)
            lipDebugNode.renderingOrder = 41
            lipDebugNode.geometry?.firstMaterial = lipVertexDebugMaterial
            faceNode.addChildNode(lipDebugNode)
            self.lipDebugNode = lipDebugNode

            let glowRenderer = GlowRenderer(faceGeometry: faceAnchor.geometry)
            glowRenderer.attach(to: faceNode)
            self.glowRenderer = glowRenderer

            let contourRenderer = ContourRenderer(faceGeometry: faceAnchor.geometry)
            contourRenderer.attach(to: faceNode)
            self.contourRenderer = contourRenderer
        }

        let (snapshot, revision) = makeupState.snapshot()
        applyMakeup(snapshot: snapshot, revision: revision)
        applyCurrentMode(snapshot: snapshot)
        return faceNode
    }

    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard anchor is ARFaceAnchor else { return }

        if !hasDetectedFace {
            hasDetectedFace = true
            print("Face detected")
            DispatchQueue.main.async { [faceDetectionStateDidChange] in
                faceDetectionStateDidChange?(true)
            }
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let faceAnchor = anchor as? ARFaceAnchor,
              let baseFaceGeometry = node.geometry as? ARSCNFaceGeometry else {
            return
        }

        // ARKit supplies updated face vertices every frame. Updating existing
        // SceneKit geometry and Metal buffers avoids node churn and flicker.
        baseFaceGeometry.update(from: faceAnchor.geometry)
        if shouldRebuildLipMesh {
            shouldRebuildLipMesh = false
            rebuildLipMesh(from: faceAnchor.geometry)
        }

        let (snapshot, _) = makeupState.snapshot()
        switch renderMode {
        case .lipsOnly where snapshot.isMakeupEnabled,
             .fullFace where snapshot.isMakeupEnabled:
            lipMesh?.update(from: faceAnchor.geometry)
            cheekMesh?.update(from: faceAnchor.geometry)
            eyeshadowMesh?.update(from: faceAnchor.geometry)
        case .wireframe:
            lipMesh?.update(from: faceAnchor.geometry)
            cheekMesh?.update(from: faceAnchor.geometry)
            eyeshadowMesh?.update(from: faceAnchor.geometry)
        case .lipsOnly, .fullFace:
            break
        }

        applyPendingMakeupUpdates()

        frameIndex &+= 1
        if frameIndex.isMultiple(of: 6) {
            publishProjectedFaceBounds(for: faceAnchor)
        }

        #if DEBUG
        fpsMonitor.frameRendered()
        #endif

        // Lip masking currently comes from vertex-index filtering. Later this
        // can be refined with a hand-authored index list, UV-space alpha mask,
        // or custom shader for softer edges and skin-aware blending.
    }

    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        guard anchor is ARFaceAnchor else { return }

        if hasDetectedFace {
            hasDetectedFace = false
            print("Face lost")
            DispatchQueue.main.async { [faceDetectionStateDidChange] in
                faceDetectionStateDidChange?(false)
            }
        }
    }

    private func publishProjectedFaceBounds(for faceAnchor: ARFaceAnchor) {
        guard let currentFrame = sceneView?.session.currentFrame else {
            return
        }

        let viewportSize = currentViewportSize()
        guard viewportSize.width > 1, viewportSize.height > 1 else { return }

        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        for vertex in faceAnchor.geometry.vertices {
            let localPoint = SIMD4<Float>(vertex.x, vertex.y, vertex.z, 1)
            let worldPoint = faceAnchor.transform * localPoint
            let projectedPoint = currentFrame.camera.projectPoint(
                SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z),
                orientation: .portrait,
                viewportSize: viewportSize
            )

            guard projectedPoint.x.isFinite, projectedPoint.y.isFinite else { continue }
            minX = min(minX, projectedPoint.x)
            minY = min(minY, projectedPoint.y)
            maxX = max(maxX, projectedPoint.x)
            maxY = max(maxY, projectedPoint.y)
        }

        guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite, maxX > minX, maxY > minY else {
            return
        }

        let faceRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        let expandedRect = faceRect.insetBy(dx: -faceRect.width * 0.18, dy: -faceRect.height * 0.24)

        DispatchQueue.main.async { [faceBoundsDidUpdate] in
            faceBoundsDidUpdate?(expandedRect)
        }
    }

    private func currentViewportSize() -> CGSize {
        viewportLock.lock()
        defer { viewportLock.unlock() }
        return cachedViewportSize
    }

    private func applyPendingMakeupUpdates() {
        guard let (snapshot, revision) = makeupState.snapshotIfChanged(after: appliedMakeupRevision) else {
            return
        }

        applyMakeup(snapshot: snapshot, revision: revision)
        applyCurrentMode(snapshot: snapshot)
    }

    private func rebuildLipMesh(from faceGeometry: ARFaceGeometry) {
        guard let device = sceneView?.device,
              let lipsNode,
              let lipDebugNode,
              let lipMesh = LipMeshGeometry(device: device, faceGeometry: faceGeometry, calibration: lipMeshCalibration) else {
            return
        }

        self.upperLipIndices = lipMesh.upperLipIndices
        self.lowerLipIndices = lipMesh.lowerLipIndices
        self.lipMesh = lipMesh

        lipsNode.geometry = lipMesh.geometry
        lipDebugNode.geometry = lipMesh.debugPointGeometry
        lipDebugNode.geometry?.firstMaterial = lipVertexDebugMaterial
        applyCurrentMode()
    }

    private func applyMakeup(snapshot: MakeupStateSnapshot, revision: UInt64) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        MakeupMaterialFactory.configureARLipstickMaterial(lipsOnlyMaterial, settings: snapshot.lipstick)
        MakeupMaterialFactory.configureARLipstickMaterial(fullFaceMaterial, settings: snapshot.lipstick)
        MakeupMaterialFactory.configureARBlushMaterial(blushMaterial, settings: snapshot.blush)
        MakeupMaterialFactory.configureAREyeshadowMaterial(eyeshadowMaterial, settings: snapshot.eyeshadow)
        glowRenderer?.update(settings: snapshot.glow)
        contourRenderer?.update(settings: snapshot.contour)
        cheekMesh?.updateMask(settings: snapshot.blush)
        eyeshadowMesh?.updateMask(settings: snapshot.eyeshadow)
        appliedMakeupRevision = revision
        SCNTransaction.commit()
    }

    private func applyCurrentMode() {
        let (snapshot, _) = makeupState.snapshot()
        applyCurrentMode(snapshot: snapshot)
    }

    private func applyCurrentMode(snapshot: MakeupStateSnapshot) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0

        switch renderMode {
        case .lipsOnly:
            baseFaceGeometry?.firstMaterial = invisibleFaceMaterial
            cheekMesh?.updateMask(settings: snapshot.blush)
            eyeshadowMesh?.updateMask(settings: snapshot.eyeshadow)
            lipsNode?.isHidden = !snapshot.isMakeupEnabled
            setSingleMaterial(lipsOnlyMaterial, on: lipsNode?.geometry)
            cheeksNode?.isHidden = !snapshot.isMakeupEnabled
            setSingleMaterial(blushMaterial, on: cheeksNode?.geometry)
            eyeshadowNode?.isHidden = !snapshot.isMakeupEnabled
            setSingleMaterial(eyeshadowMaterial, on: eyeshadowNode?.geometry)
            glowRenderer?.setGlowEnabled(snapshot.isMakeupEnabled && snapshot.glow.isEnabled)
            contourRenderer?.setContourEnabled(snapshot.isMakeupEnabled && snapshot.contour.isEnabled)
            lipDebugNode?.isHidden = true

        case .fullFace:
            baseFaceGeometry?.firstMaterial = invisibleFaceMaterial
            cheekMesh?.updateMask(settings: snapshot.blush)
            eyeshadowMesh?.updateMask(settings: snapshot.eyeshadow)
            lipsNode?.isHidden = !snapshot.isMakeupEnabled
            setSingleMaterial(lipsOnlyMaterial, on: lipsNode?.geometry)
            cheeksNode?.isHidden = !snapshot.isMakeupEnabled
            setSingleMaterial(blushMaterial, on: cheeksNode?.geometry)
            eyeshadowNode?.isHidden = !snapshot.isMakeupEnabled
            setSingleMaterial(eyeshadowMaterial, on: eyeshadowNode?.geometry)
            glowRenderer?.setGlowEnabled(snapshot.isMakeupEnabled && snapshot.glow.isEnabled)
            contourRenderer?.setContourEnabled(snapshot.isMakeupEnabled && snapshot.contour.isEnabled)
            lipDebugNode?.isHidden = true

        case .wireframe:
            baseFaceGeometry?.firstMaterial = wireframeMaterial
            lipsNode?.isHidden = false
            setSingleMaterial(lipHighlightMaterial, on: lipsNode?.geometry)
            cheeksNode?.isHidden = false
            cheekMesh?.useOpaqueDebugColors()
            setSingleMaterial(cheekWireframeMaterial, on: cheeksNode?.geometry)
            eyeshadowNode?.isHidden = false
            eyeshadowMesh?.useOpaqueDebugColors()
            setSingleMaterial(eyeshadowWireframeMaterial, on: eyeshadowNode?.geometry)
            glowRenderer?.setGlowEnabled(false)
            contourRenderer?.setContourEnabled(false)
            lipDebugNode?.isHidden = false
        }

        SCNTransaction.commit()
    }

    private func setSingleMaterial(_ material: SCNMaterial, on geometry: SCNGeometry?) {
        guard let geometry else { return }
        geometry.materials = [material]
    }
}
