//
//  ARCheekMeshGeometry.swift
//  Miroir enchanté
//

import ARKit
import Metal
import SceneKit
import UIKit

final class CheekMeshGeometry {
    let geometry: SCNGeometry

    private let vertexBuffer: MTLBuffer
    private let normalBuffer: MTLBuffer
    private let colorBuffer: MTLBuffer
    private let sourceVertexIndices: [Int]
    private let localTriangleIndices: [UInt16]
    private let normalizedCoordinates: [CGPoint]

    init?(device: MTLDevice, faceGeometry: ARFaceGeometry) {
        let mask = Self.makeCheekMask(from: faceGeometry)
        let triangles = Self.makeCheekTriangles(from: faceGeometry, alphaByIndex: mask.alphaByIndex)

        guard !triangles.sourceVertexIndices.isEmpty,
              !triangles.localTriangleIndices.isEmpty else {
            return nil
        }

        self.sourceVertexIndices = triangles.sourceVertexIndices
        self.localTriangleIndices = triangles.localTriangleIndices
        self.normalizedCoordinates = triangles.sourceVertexIndices.map {
            mask.normalizedCoordinateByIndex[$0] ?? .zero
        }

        let vertexLength = sourceVertexIndices.count * MemoryLayout<SIMD3<Float>>.stride
        let colorLength = sourceVertexIndices.count * MemoryLayout<SIMD4<Float>>.stride
        guard let vertexBuffer = device.makeBuffer(length: vertexLength, options: .storageModeShared),
              let normalBuffer = device.makeBuffer(length: vertexLength, options: .storageModeShared),
              let colorBuffer = device.makeBuffer(length: colorLength, options: .storageModeShared) else {
            return nil
        }

        self.vertexBuffer = vertexBuffer
        self.normalBuffer = normalBuffer
        self.colorBuffer = colorBuffer

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
        let colorSource = SCNGeometrySource(
            buffer: colorBuffer,
            vertexFormat: .float4,
            semantic: .color,
            vertexCount: sourceVertexIndices.count,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD4<Float>>.stride
        )

        let triangleData = localTriangleIndices.withUnsafeBufferPointer { Data(buffer: $0) }
        let triangleElement = SCNGeometryElement(
            data: triangleData,
            primitiveType: .triangles,
            primitiveCount: localTriangleIndices.count / 3,
            bytesPerIndex: MemoryLayout<UInt16>.size
        )

        self.geometry = SCNGeometry(sources: [vertexSource, normalSource, colorSource], elements: [triangleElement])
        self.geometry.firstMaterial = MakeupMaterialFactory.makeARBlushMaterial()

        update(from: faceGeometry)
        updateMask(settings: .default)
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

    func updateMask(settings: BlushSettings) {
        let colorPointer = colorBuffer.contents().bindMemory(
            to: SIMD4<Float>.self,
            capacity: sourceVertexIndices.count
        )
        let opacity = Float((settings.opacity * settings.intensity).clamped(to: 0...0.6))
        let size = Float(settings.size.clamped(to: 0.65...1.45))
        let position = Float(settings.position.clamped(to: 0...1))
        let rgba = Self.rgbaComponents(from: settings.color, intensity: 0.82 + settings.intensity * 0.28)
        let centerY = Float(0.48 + (CGFloat(position) - 0.5) * 0.12)

        for (index, point) in normalizedCoordinates.enumerated() {
            let x = Float(point.x)
            let y = Float(point.y)
            let isMouthBand = abs(x) < 0.20 && y < 0.45
            guard !isMouthBand, abs(x) > 0.12, y >= 0.34 else {
                colorPointer[index] = SIMD4<Float>(rgba.x, rgba.y, rgba.z, 0)
                continue
            }

            let sideCenterX: Float = point.x < 0 ? -0.28 : 0.28
            let dx = (x - sideCenterX) / (0.19 * size)
            let dy = (y - centerY) / (0.13 * size)
            let distance = sqrt(dx * dx + dy * dy)
            let feather = 1.0 - Self.smoothstep(edge0: 0.50, edge1: 1.0, x: distance)
            let alpha = max(0, min(1, feather)) * opacity
            colorPointer[index] = SIMD4<Float>(rgba.x, rgba.y, rgba.z, alpha)
        }
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

    private static func makeCheekMask(
        from faceGeometry: ARFaceGeometry
    ) -> (alphaByIndex: [Int: Float], normalizedCoordinateByIndex: [Int: CGPoint]) {
        let vertices = faceGeometry.vertices
        guard let first = vertices.first else { return ([:], [:]) }

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
        var alphaByIndex: [Int: Float] = [:]
        var normalizedCoordinateByIndex: [Int: CGPoint] = [:]

        for (index, vertex) in vertices.enumerated() {
            let x = (vertex.x - centerX) / faceWidth
            let y = (vertex.y - minY) / faceHeight
            let sideCenterX: Float = x < 0 ? -0.28 : 0.28
            let dx = (x - sideCenterX) / 0.34
            let dy = (y - 0.48) / 0.26
            let distance = sqrt(dx * dx + dy * dy)

            let isMouthBand = abs(x) < 0.20 && y < 0.45
            guard distance <= 1.15,
                  abs(x) > 0.12,
                  !isMouthBand,
                  y >= 0.34,
                  y <= 0.68 else { continue }

            alphaByIndex[index] = 1.0 - smoothstep(edge0: 0.72, edge1: 1.15, x: distance)
            normalizedCoordinateByIndex[index] = CGPoint(x: CGFloat(x), y: CGFloat(y))
        }

        return (alphaByIndex, normalizedCoordinateByIndex)
    }

    private static func makeCheekTriangles(
        from faceGeometry: ARFaceGeometry,
        alphaByIndex: [Int: Float]
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

            guard alphaByIndex[i0] != nil,
                  alphaByIndex[i1] != nil,
                  alphaByIndex[i2] != nil else {
                continue
            }

            localTriangleIndices.append(localIndex(for: i0))
            localTriangleIndices.append(localIndex(for: i1))
            localTriangleIndices.append(localIndex(for: i2))
        }

        return (sourceVertexIndices, localTriangleIndices)
    }

    private static func smoothstep(edge0: Float, edge1: Float, x: Float) -> Float {
        let t = max(0, min(1, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    private static func rgbaComponents(from color: UIColor, intensity: CGFloat) -> SIMD3<Float> {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return SIMD3<Float>(1, 0.45, 0.5)
        }

        return SIMD3<Float>(
            Float((red * intensity).clamped(to: 0...1)),
            Float((green * intensity).clamped(to: 0...1)),
            Float((blue * intensity).clamped(to: 0...1))
        )
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
