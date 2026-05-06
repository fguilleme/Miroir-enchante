//
//  ARLipMeshGeometry.swift
//  Miroir enchanté
//

import ARKit
import Metal
import SceneKit

struct LipMeshCalibration {
    var widthScale: Float
    var heightScale: Float
    var verticalOffset: Float

    static let `default` = LipMeshCalibration(widthScale: 1.0, heightScale: 1.0, verticalOffset: 0.0)
}

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private struct MeshEdge: Hashable {
    let a: Int
    let b: Int

    init(_ first: Int, _ second: Int) {
        self.a = min(first, second)
        self.b = max(first, second)
    }
}

final class LipMeshGeometry {
    let geometry: SCNGeometry
    let debugPointGeometry: SCNGeometry
    let upperLipIndices: [Int]
    let lowerLipIndices: [Int]

    private let vertexBuffer: MTLBuffer
    private let normalBuffer: MTLBuffer
    private let sourceVertexIndices: [Int]
    private let localTriangleIndices: [UInt16]

    init?(device: MTLDevice, faceGeometry: ARFaceGeometry, calibration: LipMeshCalibration = .default) {
        let lipIndexSets = Self.makeLipIndexSets(from: faceGeometry, calibration: calibration)
        let triangles = Self.makeLipTriangles(
            from: faceGeometry,
            lipIndexSet: Set(lipIndexSets.upper).union(lipIndexSets.lower)
        )

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

    private static func makeLipIndexSets(
        from faceGeometry: ARFaceGeometry,
        calibration: LipMeshCalibration
    ) -> (upper: [Int], lower: [Int]) {
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
        let fallbackMouthCenterY = 0.265 + calibration.verticalOffset.clamped(to: -0.045...0.045)
        let normalizedVertices: [(x: Float, y: Float)] = vertices.map { vertex in
            (
                x: (vertex.x - centerX) / faceWidth,
                y: (vertex.y - minY) / faceHeight
            )
        }
        let mouthBoundary = mouthBoundaryIndices(
            in: faceGeometry,
            normalizedVertices: normalizedVertices,
            fallbackCenterY: fallbackMouthCenterY
        )
        let mouthCenterY = mouthBoundary.isEmpty
            ? fallbackMouthCenterY
            : mouthBoundary.reduce(Float(0)) { $0 + normalizedVertices[$1].y } / Float(mouthBoundary.count)
        let widthScale = calibration.widthScale.clamped(to: 0.70...1.25)
        let heightScale = calibration.heightScale.clamped(to: 0.60...1.30)
        let allowedLipIndices = Set(normalizedVertices.enumerated().compactMap { index, point -> Int? in
            let yDelta = point.y - mouthCenterY
            let lipRadius = yDelta >= 0 ? 0.070 * heightScale : 0.145 * heightScale
            let normalizedVertical = abs(yDelta) / lipRadius
            guard normalizedVertical <= 1 else { return nil }

            let halfWidth = (0.085 + (1 - pow(normalizedVertical, 1.35)) * 0.120) * widthScale
            let cornerTaper = max(0, (abs(point.x) - 0.130 * widthScale) / (0.060 * widthScale))
            let taperedHalfHeight = lipRadius * (1 - min(cornerTaper, 0.70) * 0.50)

            guard abs(point.x) <= halfWidth,
                  abs(yDelta) <= taperedHalfHeight else { return nil }
            return index
        })

        let seedIndices = mouthBoundary.isEmpty ? allowedLipIndices : mouthBoundary.intersection(allowedLipIndices)
        var upper = Set<Int>()
        var lower = Set<Int>()

        for index in seedIndices {
            if normalizedVertices[index].y >= mouthCenterY {
                upper.insert(index)
            } else {
                lower.insert(index)
            }
        }

        let expandedUpper = expand(indices: upper, faceGeometry: faceGeometry, steps: 3, allowedIndices: allowedLipIndices)
        let expandedLower = expand(indices: lower, faceGeometry: faceGeometry, steps: 5, allowedIndices: allowedLipIndices)

        return (
            Array(expandedUpper).sorted(),
            Array(expandedLower).sorted()
        )
    }

    private static func mouthBoundaryIndices(
        in faceGeometry: ARFaceGeometry,
        normalizedVertices: [(x: Float, y: Float)],
        fallbackCenterY: Float
    ) -> Set<Int> {
        let triangles = faceGeometry.triangleIndices.map { Int($0) }
        var edgeCounts: [MeshEdge: Int] = [:]

        for triangleStart in stride(from: 0, to: triangles.count, by: 3) {
            let i0 = triangles[triangleStart]
            let i1 = triangles[triangleStart + 1]
            let i2 = triangles[triangleStart + 2]
            edgeCounts[MeshEdge(i0, i1), default: 0] += 1
            edgeCounts[MeshEdge(i1, i2), default: 0] += 1
            edgeCounts[MeshEdge(i2, i0), default: 0] += 1
        }

        var boundary = Set<Int>()
        for (edge, count) in edgeCounts where count == 1 {
            let p0 = normalizedVertices[edge.a]
            let p1 = normalizedVertices[edge.b]
            let midX = (p0.x + p1.x) * 0.5
            let midY = (p0.y + p1.y) * 0.5

            guard abs(midX) < 0.26,
                  midY >= fallbackCenterY - 0.075,
                  midY <= fallbackCenterY + 0.075 else { continue }
            boundary.insert(edge.a)
            boundary.insert(edge.b)
        }
        return boundary
    }

    private static func expand(
        indices: Set<Int>,
        faceGeometry: ARFaceGeometry,
        steps: Int,
        allowedIndices: Set<Int>
    ) -> Set<Int> {
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
                triangle.forEach {
                    if allowedIndices.contains($0) {
                        next.insert($0)
                    }
                }
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
