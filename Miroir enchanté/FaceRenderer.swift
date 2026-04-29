//
//  FaceRenderer.swift
//  Miroir enchanté
//

import ARKit
import Metal
import SceneKit
import UIKit

/// Converts ARKit face anchors into SceneKit geometry and updates it in real time.
final class FaceRenderer: NSObject, ARSCNViewDelegate {
    enum RenderMode {
        case lipsOnly
        case fullFace
        case wireframe

        var buttonTitle: String {
            switch self {
            case .lipsOnly:
                return "Lips"
            case .fullFace:
                return "Full"
            case .wireframe:
                return "Mesh"
            }
        }
    }

    private weak var sceneView: ARSCNView?
    private weak var lipsNode: SCNNode?
    private weak var lipDebugNode: SCNNode?

    private var baseFaceGeometry: ARSCNFaceGeometry?
    private var lipMesh: LipMeshGeometry?
    private var hasDetectedFace = false
    private var lipstickSettings = LipstickSettings.default

    private(set) var renderMode: RenderMode = .lipsOnly

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

        // Lip masking currently comes from vertex-index filtering. Later this
        // can be refined with a hand-authored index list, UV-space alpha mask,
        // or custom shader for softer edges and skin-aware blending.
    }

    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        guard anchor is ARFaceAnchor else { return }

        if hasDetectedFace {
            hasDetectedFace = false
            print("Face lost")
        }
    }

    private func applyCurrentMode() {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0

        switch renderMode {
        case .lipsOnly:
            baseFaceGeometry?.firstMaterial = MakeupMaterialFactory.makeInvisibleFaceMaterial()
            lipsNode?.isHidden = false
            lipsNode?.geometry?.firstMaterial = MakeupMaterialFactory.makeARLipstickMaterial(settings: lipstickSettings)
            lipDebugNode?.isHidden = true

        case .fullFace:
            baseFaceGeometry?.firstMaterial = MakeupMaterialFactory.makeARLipstickMaterial(settings: lipstickSettings)
            lipsNode?.isHidden = true
            lipDebugNode?.isHidden = true

        case .wireframe:
            baseFaceGeometry?.firstMaterial = MakeupMaterialFactory.makeWireframeMaterial()
            lipsNode?.isHidden = false
            lipsNode?.geometry?.firstMaterial = MakeupMaterialFactory.makeLipHighlightMaterial()
            lipDebugNode?.isHidden = false
        }

        SCNTransaction.commit()
    }
}

private final class LipMeshGeometry {
    let geometry: SCNGeometry
    let debugPointGeometry: SCNGeometry
    let upperLipIndices: [Int]
    let lowerLipIndices: [Int]

    private let vertexBuffer: MTLBuffer
    private let normalBuffer: MTLBuffer
    private let sourceVertexIndices: [Int]
    private let localTriangleIndices: [UInt16]

    init?(device: MTLDevice, faceGeometry: ARFaceGeometry) {
        let lipIndexSets = Self.makeLipIndexSets(from: faceGeometry)
        let lipIndexSet = Set(lipIndexSets.upper + lipIndexSets.lower)
        let triangles = Self.makeLipTriangles(from: faceGeometry, lipIndexSet: lipIndexSet)

        guard !triangles.sourceVertexIndices.isEmpty,
              !triangles.localTriangleIndices.isEmpty else {
            return nil
        }

        self.upperLipIndices = lipIndexSets.upper
        self.lowerLipIndices = lipIndexSets.lower
        self.sourceVertexIndices = triangles.sourceVertexIndices
        self.localTriangleIndices = triangles.localTriangleIndices

        let vertexLength = sourceVertexIndices.count * MemoryLayout<SIMD3<Float>>.stride
        guard let vertexBuffer = device.makeBuffer(length: vertexLength, options: .storageModeShared),
              let normalBuffer = device.makeBuffer(length: vertexLength, options: .storageModeShared) else {
            return nil
        }

        self.vertexBuffer = vertexBuffer
        self.normalBuffer = normalBuffer

        let vertexSource = SCNGeometrySource(
            buffer: vertexBuffer,
            vertexFormat: .float3,
            semantic: .vertex,
            vertexCount: sourceVertexIndices.count,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )
        let normalSource = SCNGeometrySource(
            buffer: normalBuffer,
            vertexFormat: .float3,
            semantic: .normal,
            vertexCount: sourceVertexIndices.count,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )

        let triangleData = localTriangleIndices.withUnsafeBufferPointer { Data(buffer: $0) }
        let triangleElement = SCNGeometryElement(
            data: triangleData,
            primitiveType: .triangles,
            primitiveCount: localTriangleIndices.count / 3,
            bytesPerIndex: MemoryLayout<UInt16>.size
        )

        let pointIndices = (0..<sourceVertexIndices.count).map { UInt16($0) }
        let pointData = pointIndices.withUnsafeBufferPointer { Data(buffer: $0) }
        let pointElement = SCNGeometryElement(
            data: pointData,
            primitiveType: .point,
            primitiveCount: pointIndices.count,
            bytesPerIndex: MemoryLayout<UInt16>.size
        )

        self.geometry = SCNGeometry(sources: [vertexSource, normalSource], elements: [triangleElement])
        self.debugPointGeometry = SCNGeometry(sources: [vertexSource], elements: [pointElement])

        self.geometry.firstMaterial = MakeupMaterialFactory.makeARLipstickMaterial()
        self.debugPointGeometry.firstMaterial = MakeupMaterialFactory.makeLipVertexDebugMaterial()

        update(from: faceGeometry)
    }

    func update(from faceGeometry: ARFaceGeometry) {
        let vertexPointer = vertexBuffer.contents().bindMemory(
            to: SIMD3<Float>.self,
            capacity: sourceVertexIndices.count
        )

        for (localIndex, sourceIndex) in sourceVertexIndices.enumerated() {
            vertexPointer[localIndex] = faceGeometry.vertices[sourceIndex]
        }

        updateNormals(vertexPointer: vertexPointer)
    }

    private func updateNormals(vertexPointer: UnsafeMutablePointer<SIMD3<Float>>) {
        let normalPointer = normalBuffer.contents().bindMemory(
            to: SIMD3<Float>.self,
            capacity: sourceVertexIndices.count
        )

        for index in 0..<sourceVertexIndices.count {
            normalPointer[index] = SIMD3<Float>(repeating: 0)
        }

        for triangleStart in stride(from: 0, to: localTriangleIndices.count, by: 3) {
            let i0 = Int(localTriangleIndices[triangleStart])
            let i1 = Int(localTriangleIndices[triangleStart + 1])
            let i2 = Int(localTriangleIndices[triangleStart + 2])

            let p0 = vertexPointer[i0]
            let p1 = vertexPointer[i1]
            let p2 = vertexPointer[i2]
            let faceNormal = simd_cross(p1 - p0, p2 - p0)

            if simd_length_squared(faceNormal) > 0 {
                let normalized = simd_normalize(faceNormal)
                normalPointer[i0] += normalized
                normalPointer[i1] += normalized
                normalPointer[i2] += normalized
            }
        }

        for index in 0..<sourceVertexIndices.count where simd_length_squared(normalPointer[index]) > 0 {
            normalPointer[index] = simd_normalize(normalPointer[index])
        }
    }

    private static func makeLipIndexSets(from faceGeometry: ARFaceGeometry) -> (upper: [Int], lower: [Int]) {
        let vertices = faceGeometry.vertices
        guard let first = vertices.first else { return ([], []) }

        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y

        for vertex in vertices {
            minX = min(minX, vertex.x)
            maxX = max(maxX, vertex.x)
            minY = min(minY, vertex.y)
            maxY = max(maxY, vertex.y)
        }

        let faceWidth = max(maxX - minX, 0.001)
        let faceHeight = max(maxY - minY, 0.001)
        let centerX = (minX + maxX) * 0.5

        var upper = Set<Int>()
        var lower = Set<Int>()

        for (index, vertex) in vertices.enumerated() {
            let xRatio = abs(vertex.x - centerX) / faceWidth
            let yRatio = (vertex.y - minY) / faceHeight

            // These bounds describe only the central mouth band in normalized
            // face-local space. They are deliberately conservative: a beard or
            // moustache can visually hide the real lips, but the AR mesh itself
            // is stable, so keeping the selected band small avoids spilling onto
            // the nose and cheeks. Production masks should replace this with
            // curated upperLipIndices/lowerLipIndices from a mesh inspection pass.
            guard xRatio <= 0.22, yRatio >= 0.18, yRatio <= 0.35 else { continue }

            if yRatio >= 0.27 {
                upper.insert(index)
            } else {
                lower.insert(index)
            }
        }

        let expandedUpper = expand(indices: upper, faceGeometry: faceGeometry, steps: 0)
        let expandedLower = expand(indices: lower, faceGeometry: faceGeometry, steps: 0)

        return (
            Array(expandedUpper).sorted(),
            Array(expandedLower).sorted()
        )
    }

    private static func expand(indices: Set<Int>, faceGeometry: ARFaceGeometry, steps: Int) -> Set<Int> {
        guard steps > 0, !indices.isEmpty else { return indices }

        var expanded = indices
        let triangles = faceGeometry.triangleIndices.map { Int($0) }

        for _ in 0..<steps {
            var next = expanded

            for triangleStart in stride(from: 0, to: triangles.count, by: 3) {
                let triangle = [
                    triangles[triangleStart],
                    triangles[triangleStart + 1],
                    triangles[triangleStart + 2]
                ]

                guard triangle.contains(where: expanded.contains) else { continue }
                triangle.forEach { next.insert($0) }
            }

            expanded = next
        }

        return expanded
    }

    private static func makeLipTriangles(
        from faceGeometry: ARFaceGeometry,
        lipIndexSet: Set<Int>
    ) -> (sourceVertexIndices: [Int], localTriangleIndices: [UInt16]) {
        let sourceTriangles = faceGeometry.triangleIndices.map { Int($0) }
        var localIndexBySourceIndex: [Int: UInt16] = [:]
        var sourceVertexIndices: [Int] = []
        var localTriangleIndices: [UInt16] = []

        func localIndex(for sourceIndex: Int) -> UInt16 {
            if let existing = localIndexBySourceIndex[sourceIndex] {
                return existing
            }

            let newIndex = UInt16(sourceVertexIndices.count)
            sourceVertexIndices.append(sourceIndex)
            localIndexBySourceIndex[sourceIndex] = newIndex
            return newIndex
        }

        for triangleStart in stride(from: 0, to: sourceTriangles.count, by: 3) {
            let i0 = sourceTriangles[triangleStart]
            let i1 = sourceTriangles[triangleStart + 1]
            let i2 = sourceTriangles[triangleStart + 2]

            guard lipIndexSet.contains(i0),
                  lipIndexSet.contains(i1),
                  lipIndexSet.contains(i2) else {
                continue
            }

            localTriangleIndices.append(localIndex(for: i0))
            localTriangleIndices.append(localIndex(for: i1))
            localTriangleIndices.append(localIndex(for: i2))
        }

        return (sourceVertexIndices, localTriangleIndices)
    }
}
