//
//  MinimalGLBSceneLoader.swift
//  Miroir enchanté
//

import Foundation
import SceneKit
import UIKit

/// Small, local GLB 2.0 loader for static SceneKit preview assets.
///
/// SceneKit can be unreliable with GLB/FBX on iOS at runtime. This loader only
/// implements the subset we need for hair cards: one binary GLB buffer,
/// triangle meshes with POSITION/NORMAL/TEXCOORD_0 attributes, indices, and an
/// embedded base-color texture. It intentionally ignores animation and skinning.
enum MinimalGLBSceneLoader {
    static func loadScene(url: URL) throws -> SCNScene {
        let fileData = try Data(contentsOf: url)
        let glb = try parseContainer(fileData)
        let document = try JSONDecoder().decode(GLTFDocument.self, from: glb.json)

        let scene = SCNScene()

        for mesh in document.meshes {
            for primitive in mesh.primitives where primitive.mode == nil || primitive.mode == 4 {
                guard let positionAccessorIndex = primitive.attributes["POSITION"] else {
                    continue
                }

                let positions = try readVector3Accessor(positionAccessorIndex, in: document, binary: glb.binary)
                let normals = try primitive.attributes["NORMAL"].map { try readVector3Accessor($0, in: document, binary: glb.binary) }
                let texcoords = try primitive.attributes["TEXCOORD_0"].map { try readVector2Accessor($0, in: document, binary: glb.binary) }
                let indices = try primitive.indices.map { try readScalarUInt32Accessor($0, in: document, binary: glb.binary) }

                guard !positions.isEmpty else {
                    continue
                }

                let geometry = makeGeometry(
                    positions: positions,
                    normals: normals,
                    texcoords: texcoords,
                    indices: indices,
                    material: makeMaterial(for: primitive, document: document, binary: glb.binary)
                )

                let node = SCNNode(geometry: geometry)
                node.name = mesh.name ?? "GLBMesh"
                scene.rootNode.addChildNode(node)
            }
        }

        return scene
    }

    private static func parseContainer(_ data: Data) throws -> (json: Data, binary: Data) {
        guard data.count >= 20,
              data.readUInt32(at: 0) == 0x46546C67,
              data.readUInt32(at: 4) == 2 else {
            throw GLBError.unsupportedContainer
        }

        var offset = 12
        var jsonChunk: Data?
        var binaryChunk: Data?

        while offset + 8 <= data.count {
            let chunkLength = Int(data.readUInt32(at: offset))
            let chunkType = data.readUInt32(at: offset + 4)
            let chunkStart = offset + 8
            let chunkEnd = chunkStart + chunkLength

            guard chunkEnd <= data.count else {
                throw GLBError.invalidChunk
            }

            let chunk = data.subdata(in: chunkStart..<chunkEnd)
            if chunkType == 0x4E4F534A {
                jsonChunk = chunk
            } else if chunkType == 0x004E4942 {
                binaryChunk = chunk
            }

            offset = chunkEnd
        }

        guard let jsonChunk, let binaryChunk else {
            throw GLBError.missingRequiredChunk
        }

        return (jsonChunk, binaryChunk)
    }

    private static func makeGeometry(
        positions: [SCNVector3],
        normals: [SCNVector3]?,
        texcoords: [CGPoint]?,
        indices: [UInt32]?,
        material: SCNMaterial
    ) -> SCNGeometry {
        var sources = [SCNGeometrySource(vertices: positions)]

        if let normals, normals.count == positions.count {
            sources.append(SCNGeometrySource(normals: normals))
        }

        if let texcoords, texcoords.count == positions.count {
            sources.append(SCNGeometrySource(textureCoordinates: texcoords))
        }

        let element: SCNGeometryElement
        if let indices, !indices.isEmpty {
            let indexData = indices.withUnsafeBufferPointer { Data(buffer: $0) }
            element = SCNGeometryElement(
                data: indexData,
                primitiveType: .triangles,
                primitiveCount: indices.count / 3,
                bytesPerIndex: MemoryLayout<UInt32>.size
            )
        } else {
            element = SCNGeometryElement(
                data: Data(),
                primitiveType: .triangles,
                primitiveCount: positions.count / 3,
                bytesPerIndex: 0
            )
        }

        let geometry = SCNGeometry(sources: sources, elements: [element])
        geometry.firstMaterial = material
        return geometry
    }

    private static func makeMaterial(for primitive: GLTFPrimitive, document: GLTFDocument, binary: Data) -> SCNMaterial {
        let material = SCNMaterial()
        material.name = primitive.material.flatMap { document.materials[safe: $0]?.name } ?? "GLBMaterial"
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(red: 0.10, green: 0.075, blue: 0.055, alpha: 1.0)
        material.roughness.contents = primitive.material
            .flatMap { document.materials[safe: $0]?.pbrMetallicRoughness?.roughnessFactor } ?? 0.76
        material.metalness.contents = 0.0
        material.specular.contents = UIColor.white.withAlphaComponent(0.16)
        material.isDoubleSided = true
        material.blendMode = .alpha
        material.transparencyMode = .aOne
        material.transparency = 1.0
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true

        if let materialIndex = primitive.material,
           let textureIndex = document.materials[safe: materialIndex]?.pbrMetallicRoughness?.baseColorTexture?.index,
           let sourceIndex = document.textures[safe: textureIndex]?.source,
           let image = loadImage(sourceIndex: sourceIndex, document: document, binary: binary) {
            material.diffuse.contents = image
        }

        return material
    }

    private static func loadImage(sourceIndex: Int, document: GLTFDocument, binary: Data) -> UIImage? {
        guard let imageInfo = document.images[safe: sourceIndex],
              let bufferViewIndex = imageInfo.bufferView,
              let bufferView = document.bufferViews[safe: bufferViewIndex] else {
            return nil
        }

        let start = bufferView.byteOffset ?? 0
        let end = start + bufferView.byteLength
        guard start >= 0, end <= binary.count else {
            return nil
        }

        return UIImage(data: binary.subdata(in: start..<end))
    }

    private static func readVector3Accessor(_ index: Int, in document: GLTFDocument, binary: Data) throws -> [SCNVector3] {
        let values = try readFloatAccessor(index, expectedComponents: 3, in: document, binary: binary)
        return stride(from: 0, to: values.count, by: 3).map {
            SCNVector3(values[$0], values[$0 + 1], values[$0 + 2])
        }
    }

    private static func readVector2Accessor(_ index: Int, in document: GLTFDocument, binary: Data) throws -> [CGPoint] {
        let values = try readFloatAccessor(index, expectedComponents: 2, in: document, binary: binary)
        return stride(from: 0, to: values.count, by: 2).map {
            CGPoint(x: CGFloat(values[$0]), y: CGFloat(1.0 - values[$0 + 1]))
        }
    }

    private static func readFloatAccessor(
        _ index: Int,
        expectedComponents: Int,
        in document: GLTFDocument,
        binary: Data
    ) throws -> [Float] {
        guard let accessor = document.accessors[safe: index],
              let bufferViewIndex = accessor.bufferView,
              let bufferView = document.bufferViews[safe: bufferViewIndex],
              accessor.componentType == 5126 else {
            throw GLBError.unsupportedAccessor
        }

        let componentCount = accessor.componentCount
        guard componentCount == expectedComponents else {
            throw GLBError.unsupportedAccessor
        }

        let stride = bufferView.byteStride ?? componentCount * MemoryLayout<Float>.size
        let baseOffset = (bufferView.byteOffset ?? 0) + (accessor.byteOffset ?? 0)
        var values: [Float] = []
        values.reserveCapacity(accessor.count * componentCount)

        for elementIndex in 0..<accessor.count {
            let elementOffset = baseOffset + elementIndex * stride
            for componentIndex in 0..<componentCount {
                values.append(binary.readFloat32(at: elementOffset + componentIndex * MemoryLayout<Float>.size))
            }
        }

        return values
    }

    private static func readScalarUInt32Accessor(_ index: Int, in document: GLTFDocument, binary: Data) throws -> [UInt32] {
        guard let accessor = document.accessors[safe: index],
              let bufferViewIndex = accessor.bufferView,
              let bufferView = document.bufferViews[safe: bufferViewIndex],
              accessor.type == "SCALAR" else {
            throw GLBError.unsupportedAccessor
        }

        let componentSize: Int
        switch accessor.componentType {
        case 5121:
            componentSize = MemoryLayout<UInt8>.size
        case 5123:
            componentSize = MemoryLayout<UInt16>.size
        case 5125:
            componentSize = MemoryLayout<UInt32>.size
        default:
            throw GLBError.unsupportedAccessor
        }

        let stride = bufferView.byteStride ?? componentSize
        let baseOffset = (bufferView.byteOffset ?? 0) + (accessor.byteOffset ?? 0)

        return (0..<accessor.count).map { elementIndex in
            let offset = baseOffset + elementIndex * stride
            switch accessor.componentType {
            case 5121:
                return UInt32(binary[offset])
            case 5123:
                return UInt32(binary.readUInt16(at: offset))
            default:
                return binary.readUInt32(at: offset)
            }
        }
    }
}

private enum GLBError: Error {
    case invalidChunk
    case missingRequiredChunk
    case unsupportedAccessor
    case unsupportedContainer
}

private struct GLTFDocument: Decodable {
    let accessors: [GLTFAccessor]
    let bufferViews: [GLTFBufferView]
    let images: [GLTFImage]
    let materials: [GLTFMaterial]
    let meshes: [GLTFMesh]
    let textures: [GLTFTexture]

    private enum CodingKeys: String, CodingKey {
        case accessors
        case bufferViews
        case images
        case materials
        case meshes
        case textures
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessors = try container.decode([GLTFAccessor].self, forKey: .accessors)
        bufferViews = try container.decode([GLTFBufferView].self, forKey: .bufferViews)
        images = try container.decodeIfPresent([GLTFImage].self, forKey: .images) ?? []
        materials = try container.decodeIfPresent([GLTFMaterial].self, forKey: .materials) ?? []
        meshes = try container.decodeIfPresent([GLTFMesh].self, forKey: .meshes) ?? []
        textures = try container.decodeIfPresent([GLTFTexture].self, forKey: .textures) ?? []
    }
}

private struct GLTFAccessor: Decodable {
    let bufferView: Int?
    let byteOffset: Int?
    let componentType: Int
    let count: Int
    let type: String

    var componentCount: Int {
        switch type {
        case "SCALAR": return 1
        case "VEC2": return 2
        case "VEC3": return 3
        case "VEC4": return 4
        case "MAT4": return 16
        default: return 0
        }
    }
}

private struct GLTFBufferView: Decodable {
    let buffer: Int
    let byteLength: Int
    let byteOffset: Int?
    let byteStride: Int?
}

private struct GLTFImage: Decodable {
    let bufferView: Int?
    let mimeType: String?
}

private struct GLTFMaterial: Decodable {
    let name: String?
    let pbrMetallicRoughness: GLTFPBRMaterial?
}

private struct GLTFPBRMaterial: Decodable {
    let baseColorTexture: GLTFTextureReference?
    let roughnessFactor: Double?
}

private struct GLTFTextureReference: Decodable {
    let index: Int
}

private struct GLTFMesh: Decodable {
    let name: String?
    let primitives: [GLTFPrimitive]
}

private struct GLTFPrimitive: Decodable {
    let attributes: [String: Int]
    let indices: Int?
    let material: Int?
    let mode: Int?
}

private struct GLTFTexture: Decodable {
    let source: Int?
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension Data {
    func readUInt16(at offset: Int) -> UInt16 {
        subdata(in: offset..<(offset + MemoryLayout<UInt16>.size)).withUnsafeBytes {
            UInt16(littleEndian: $0.load(as: UInt16.self))
        }
    }

    func readUInt32(at offset: Int) -> UInt32 {
        subdata(in: offset..<(offset + MemoryLayout<UInt32>.size)).withUnsafeBytes {
            UInt32(littleEndian: $0.load(as: UInt32.self))
        }
    }

    func readFloat32(at offset: Int) -> Float {
        Float(bitPattern: readUInt32(at: offset))
    }
}
