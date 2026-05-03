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
    private var hasDetectedFace = false
    private var lipstickSettings = LipstickSettings.default
    private var blushSettings = BlushSettings.default
    private var eyeshadowSettings = EyeshadowSettings.default
    private var isMakeupEnabled = true
    private let lipsOnlyMaterial = MakeupMaterialFactory.makeARLipstickMaterial()
    private let fullFaceMaterial = MakeupMaterialFactory.makeARLipstickMaterial()

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

    func updateLipstickSettings(_ settings: LipstickSettings) {
        lipstickSettings = settings
        applyCurrentMode()
    }

    func updateBlushSettings(_ settings: BlushSettings) {
        blushSettings = settings
        cheekMesh?.updateMask(settings: settings)
        applyCurrentMode()
    }

    func updateEyeshadowSettings(_ settings: EyeshadowSettings) {
        eyeshadowSettings = settings
        eyeshadowMesh?.updateMask(settings: settings)
        applyCurrentMode()
    }

    func setMakeupEnabled(_ enabled: Bool) {
        isMakeupEnabled = enabled
        applyCurrentMode()
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

        if let lipMesh = LipMeshGeometry(device: device, faceGeometry: faceAnchor.geometry) {
            self.upperLipIndices = lipMesh.upperLipIndices
            self.lowerLipIndices = lipMesh.lowerLipIndices
            self.lipMesh = lipMesh

            let lipsNode = SCNNode(geometry: lipMesh.geometry)
            lipsNode.renderingOrder = 40
            faceNode.addChildNode(lipsNode)
            self.lipsNode = lipsNode

            if let cheekMesh = CheekMeshGeometry(device: device, faceGeometry: faceAnchor.geometry) {
                self.cheekMesh = cheekMesh
                cheekMesh.updateMask(settings: blushSettings)

                let cheeksNode = SCNNode(geometry: cheekMesh.geometry)
                cheeksNode.renderingOrder = 35
                faceNode.addChildNode(cheeksNode)
                self.cheeksNode = cheeksNode
            }

            if let eyeshadowMesh = EyeshadowMeshGeometry(device: device, faceGeometry: faceAnchor.geometry) {
                self.eyeshadowMesh = eyeshadowMesh
                eyeshadowMesh.updateMask(settings: eyeshadowSettings)

                let eyeshadowNode = SCNNode(geometry: eyeshadowMesh.geometry)
                eyeshadowNode.renderingOrder = 38
                faceNode.addChildNode(eyeshadowNode)
                self.eyeshadowNode = eyeshadowNode
            }

            let lipDebugNode = SCNNode(geometry: lipMesh.debugPointGeometry)
            lipDebugNode.renderingOrder = 41
            faceNode.addChildNode(lipDebugNode)
            self.lipDebugNode = lipDebugNode
        }

        applyCurrentMode()
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
        lipMesh?.update(from: faceAnchor.geometry)
        cheekMesh?.update(from: faceAnchor.geometry)
        eyeshadowMesh?.update(from: faceAnchor.geometry)
        publishProjectedFaceBounds(for: faceAnchor)

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
        guard let sceneView,
              let currentFrame = sceneView.session.currentFrame else {
            return
        }

        let viewportSize = sceneView.bounds.size
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

    private func applyCurrentMode() {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        MakeupMaterialFactory.configureARLipstickMaterial(lipsOnlyMaterial, settings: lipstickSettings)
        MakeupMaterialFactory.configureARLipstickMaterial(fullFaceMaterial, settings: lipstickSettings)

        switch renderMode {
        case .lipsOnly:
            baseFaceGeometry?.firstMaterial = MakeupMaterialFactory.makeInvisibleFaceMaterial()
            lipsNode?.isHidden = !isMakeupEnabled
            setSingleMaterial(lipsOnlyMaterial, on: lipsNode?.geometry)
            cheeksNode?.isHidden = !isMakeupEnabled
            setSingleMaterial(MakeupMaterialFactory.makeARBlushMaterial(settings: blushSettings), on: cheeksNode?.geometry)
            eyeshadowNode?.isHidden = !isMakeupEnabled
            setSingleMaterial(MakeupMaterialFactory.makeAREyeshadowMaterial(settings: eyeshadowSettings), on: eyeshadowNode?.geometry)
            lipDebugNode?.isHidden = true

        case .fullFace:
            baseFaceGeometry?.firstMaterial = fullFaceMaterial
            lipsNode?.isHidden = true
            cheeksNode?.isHidden = true
            eyeshadowNode?.isHidden = true
            lipDebugNode?.isHidden = true

        case .wireframe:
            baseFaceGeometry?.firstMaterial = MakeupMaterialFactory.makeWireframeMaterial()
            lipsNode?.isHidden = false
            lipsNode?.geometry?.firstMaterial = MakeupMaterialFactory.makeLipHighlightMaterial()
            cheeksNode?.isHidden = true
            eyeshadowNode?.isHidden = true
            lipDebugNode?.isHidden = false
        }

        SCNTransaction.commit()
    }

    private func setSingleMaterial(_ material: SCNMaterial, on geometry: SCNGeometry?) {
        guard let geometry else { return }
        geometry.materials = [material]
    }
}
