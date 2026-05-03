//
//  DemoGeometryClassifier.swift
//  Miroir enchanté
//

import SceneKit

enum DemoGeometryClassifier {
    nonisolated static func normalize(_ name: String) -> String {
        name
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    nonisolated static func nodeLooksLikeHair(_ node: SCNNode) -> Bool {
        let nodeName = normalize(node.name ?? "")
        return nodeName.contains("hair") || nodeName.contains("bang") || nodeName.contains("xpsnewmeshhair")
    }

    nonisolated static func nodeLooksLikeEye(_ node: SCNNode) -> Bool {
        let nodeName = normalize(node.name ?? "")
        return nodeName.contains("eye") || nodeName.contains("iris") || nodeName.contains("cornea")
    }

    nonisolated static func materialMatchesHair(_ material: SCNMaterial) -> Bool {
        guard let materialName = material.name else { return false }
        return materialNameLooksLikeHair(materialName)
    }

    nonisolated static func materialNameLooksLikeHair(_ materialName: String) -> Bool {
        let name = normalize(materialName)
        return name.contains("hair") || name.contains("bang")
    }

    nonisolated static func materialNameLooksLikeTexturedEye(_ materialName: String) -> Bool {
        let name = normalize(materialName)
        // Diagnostic confirmed the iris UVs live on Eyes / Eyes.001. The
        // aiStandard3* meshes are the cornea sphere and would overlay a
        // washed-out copy of the iris if they were textured too.
        return name == "eyes" || name == "eyes001" || (name.contains("eye") && !name.contains("aistandard"))
    }

    nonisolated static func materialMatchesEye(_ material: SCNMaterial) -> Bool {
        guard let materialName = material.name else { return false }

        let name = normalize(materialName)
        return name.contains("eye") || name.contains("iris") || name.contains("cornea") || name.contains("aistandard3")
    }

    nonisolated static func isLikelyEyeGeometry(_ node: SCNNode) -> Bool {
        let nodeName = normalize(node.name ?? "")
        if nodeName.contains("head") || nodeName.contains("face") || nodeName.contains("defaultmat") {
            return false
        }

        if nodeName.contains("eye") {
            return true
        }

        guard let geometry = node.geometry else { return false }
        return geometry.materials.contains { material in
            let materialName = normalize(material.name ?? "")
            return materialName.contains("eye") || materialName.contains("aistandard3")
        }
    }

    nonisolated static func isLikelyHairGeometry(_ node: SCNNode) -> Bool {
        guard let geometry = node.geometry else {
            return false
        }

        if nodeLooksLikeEye(node) {
            return false
        }

        if geometry.materials.contains(where: materialMatchesHair) {
            return true
        }

        if geometry.materials.contains(where: materialMatchesEye) {
            return false
        }

        let nodeName = normalize(node.name ?? "")
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
        return nodeLooksLikeHair(node)
    }
}
