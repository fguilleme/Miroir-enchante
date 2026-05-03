//
//  DemoModelAssetLoader.swift
//  Miroir enchanté
//

import SceneKit
import UIKit

/// Centralizes bundled demo model and texture loading so renderers can focus on
/// scene assembly and material behavior.
enum DemoModelAssetLoader {
    static func loadBundledScene(filename: String, logsMissingAsset: Bool = true) -> SCNScene? {
        guard let url = bundledAssetURL(filename: filename) else {
            if logsMissingAsset {
                print("Demo model asset \(filename) was not found in the app bundle.")
            }
            return nil
        }

        let parts = splitFilename(filename)
        do {
            // SceneKit generally loads OBJ well as long as the referenced MTL
            // and texture files are bundled next to it. GLB support varies by
            // platform/toolchain; USDZ is the most reliable iOS runtime fallback.
            return try SCNScene(url: url, options: nil)
        } catch {
            print("SceneKit could not load \(filename): \(error.localizedDescription)")
            if parts.extension.lowercased() == "glb" {
                print("Convert \(filename) to \(usdzFilename(for: filename)) with Reality Converter, then add the USDZ to the app bundle.")
            } else if parts.extension.lowercased() == "fbx" {
                print("Convert \(filename) to \(usdzFilename(for: filename)) from Blender or Reality Converter, then add the USDZ to the app bundle.")
            }
            return nil
        }
    }

    static func loadBundledGLBScene(filename: String) -> SCNScene? {
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

    static func bundledAssetExists(filename: String) -> Bool {
        bundledAssetURL(filename: filename) != nil
    }

    static func bundledAssetURL(filename: String) -> URL? {
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

    static func loadOBJNodes(
        filename: String,
        materialFilter: (String) -> Bool,
        materialProvider: (String) -> SCNMaterial
    ) -> [SCNNode] {
        guard let url = bundledAssetURL(filename: filename),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        struct OBJFaceVertex {
            let vertexIndex: Int
            let textureIndex: Int?
            let normalIndex: Int?
        }

        final class OBJBuildGroup {
            let objectName: String
            let materialName: String
            var vertices: [SCNVector3] = []
            var textureCoordinates: [CGPoint] = []
            var normals: [SCNVector3] = []
            var indices: [Int32] = []

            init(objectName: String, materialName: String) {
                self.objectName = objectName
                self.materialName = materialName
            }
        }

        var positions: [SCNVector3] = []
        var textureCoordinates: [CGPoint] = []
        var normals: [SCNVector3] = []
        var groups: [String: OBJBuildGroup] = [:]
        var materialNames: Set<String> = []
        var currentObjectName = splitFilename(filename).name
        var currentMaterialName = ""

        func resolvedIndex(_ rawIndex: Int, count: Int) -> Int? {
            let index = rawIndex >= 0 ? rawIndex - 1 : count + rawIndex
            guard index >= 0, index < count else { return nil }
            return index
        }

        func parseFaceVertex(_ token: String) -> OBJFaceVertex? {
            let parts = token.split(separator: "/", omittingEmptySubsequences: false)
            guard let firstPart = parts.first,
                  let rawVertexIndex = Int(firstPart) else {
                return nil
            }

            let rawTextureIndex = parts.indices.contains(1) && !parts[1].isEmpty ? Int(parts[1]) : nil
            let rawNormalIndex = parts.indices.contains(2) && !parts[2].isEmpty ? Int(parts[2]) : nil
            guard let vertexIndex = resolvedIndex(rawVertexIndex, count: positions.count) else {
                return nil
            }

            return OBJFaceVertex(
                vertexIndex: vertexIndex,
                textureIndex: rawTextureIndex.flatMap { resolvedIndex($0, count: textureCoordinates.count) },
                normalIndex: rawNormalIndex.flatMap { resolvedIndex($0, count: normals.count) }
            )
        }

        func groupForCurrentMaterial() -> OBJBuildGroup? {
            guard materialFilter(currentMaterialName) else {
                return nil
            }

            let key = "\(currentObjectName)|\(currentMaterialName)"
            if let group = groups[key] {
                return group
            }

            let group = OBJBuildGroup(objectName: currentObjectName, materialName: currentMaterialName)
            groups[key] = group
            return group
        }

        func append(_ faceVertex: OBJFaceVertex, to group: OBJBuildGroup) {
            group.vertices.append(positions[faceVertex.vertexIndex])

            if let textureIndex = faceVertex.textureIndex {
                group.textureCoordinates.append(textureCoordinates[textureIndex])
            } else {
                group.textureCoordinates.append(.zero)
            }

            if let normalIndex = faceVertex.normalIndex {
                group.normals.append(normals[normalIndex])
            } else {
                group.normals.append(SCNVector3(0, 0, 1))
            }

            group.indices.append(Int32(group.indices.count))
        }

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let trimmedLine = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("#") else { continue }

            let parts = trimmedLine.split(separator: " ", omittingEmptySubsequences: true)
            guard let directive = parts.first else { continue }

            switch directive {
            case "o", "g":
                currentObjectName = parts.dropFirst().joined(separator: " ")
                currentMaterialName = ""
            case "usemtl":
                currentMaterialName = parts.dropFirst().joined(separator: " ")
                materialNames.insert(currentMaterialName)
            case "v":
                guard parts.count >= 4,
                      let x = Float(parts[1]),
                      let y = Float(parts[2]),
                      let z = Float(parts[3]) else { continue }
                positions.append(SCNVector3(x, y, z))
            case "vt":
                guard parts.count >= 3,
                      let rawU = Double(parts[1]),
                      let rawV = Double(parts[2]) else { continue }
                let u = CGFloat(rawU)
                let v = CGFloat(rawV)
                // Blender OBJ exports use texture coordinates as authored. Do
                // not flip V here; flipping sends the eye mesh to the wrong
                // area of eyeColor.jpg and makes the iris disappear.
                textureCoordinates.append(CGPoint(x: u, y: v))
            case "vn":
                guard parts.count >= 4,
                      let x = Float(parts[1]),
                      let y = Float(parts[2]),
                      let z = Float(parts[3]) else { continue }
                normals.append(SCNVector3(x, y, z))
            case "f":
                guard let group = groupForCurrentMaterial() else { continue }
                let faceVertices = parts.dropFirst().compactMap { parseFaceVertex(String($0)) }
                guard faceVertices.count >= 3 else { continue }

                for index in 1..<(faceVertices.count - 1) {
                    append(faceVertices[0], to: group)
                    append(faceVertices[index], to: group)
                    append(faceVertices[index + 1], to: group)
                }
            default:
                continue
            }
        }

        let nodes = groups.values
            .filter { !$0.vertices.isEmpty }
            .sorted { $0.objectName < $1.objectName }
            .map { group -> SCNNode in
                var sources = [
                    SCNGeometrySource(vertices: group.vertices),
                    SCNGeometrySource(normals: group.normals),
                    SCNGeometrySource(textureCoordinates: group.textureCoordinates)
                ]
                sources = sources.filter { $0.vectorCount > 0 }
                let element = SCNGeometryElement(indices: group.indices, primitiveType: .triangles)
                let geometry = SCNGeometry(sources: sources, elements: [element])
                geometry.firstMaterial = materialProvider(group.materialName)

                let uvXs = group.textureCoordinates.map { Float($0.x) }
                let uvYs = group.textureCoordinates.map { Float($0.y) }
                let uvMinX = uvXs.min() ?? 0
                let uvMaxX = uvXs.max() ?? 0
                let uvMinY = uvYs.min() ?? 0
                let uvMaxY = uvYs.max() ?? 0
                print("OBJ \(filename): group \(group.objectName)|\(group.materialName) tris=\(group.indices.count/3) uvX=[\(uvMinX)..\(uvMaxX)] uvY=[\(uvMinY)..\(uvMaxY)]")

                let node = SCNNode(geometry: geometry)
                node.name = "\(group.objectName)_\(group.materialName)"
                node.renderingOrder = 30
                return node
            }

        if nodes.isEmpty {
            print("OBJ loader skipped \(filename). Materials found: \(materialNames.sorted().joined(separator: ", "))")
        }

        return nodes
    }

    static func bundledImage(named name: String, fileExtension: String, subdirectory: String) -> UIImage? {
        let url = Bundle.main.url(forResource: name, withExtension: fileExtension, subdirectory: subdirectory)
            ?? Bundle.main.url(forResource: name, withExtension: fileExtension)

        guard let url else {
            return nil
        }

        return UIImage(contentsOfFile: url.path)
    }

    static func bundledImage(named names: [String], fileExtension: String, subdirectory: String) -> UIImage? {
        for name in names {
            if let image = bundledImage(named: name, fileExtension: fileExtension, subdirectory: subdirectory) {
                return image
            }
        }

        return nil
    }

    static func usdzFilename(for filename: String) -> String {
        let parts = splitFilename(filename)
        if let subdirectory = parts.subdirectory {
            return "\(subdirectory)/\(parts.name).usdz"
        }

        return "\(parts.name).usdz"
    }

    static func splitFilename(_ filename: String) -> (name: String, extension: String, subdirectory: String?) {
        let url = URL(fileURLWithPath: filename)
        let fileExtension = url.pathExtension.isEmpty ? "glb" : url.pathExtension
        let name = url.deletingPathExtension().lastPathComponent
        let subdirectory = url.deletingLastPathComponent().relativePath
        return (name, fileExtension, subdirectory == "." ? nil : subdirectory)
    }
}
