//
//  MakeupState.swift
//  Miroir enchanté
//

import Foundation

struct MakeupStateSnapshot {
    var lipstick: LipstickSettings
    var blush: BlushSettings
    var eyeshadow: EyeshadowSettings
    var glow: GlowSettings
    var isMakeupEnabled: Bool
}

final class MakeupState {
    private let lock = NSLock()
    private var value = MakeupStateSnapshot(
        lipstick: .default,
        blush: .default,
        eyeshadow: .default,
        glow: .default,
        isMakeupEnabled: true
    )
    private var revision: UInt64 = 0

    func updateLipstick(_ settings: LipstickSettings) {
        mutate {
            value.lipstick = settings
        }
    }

    func updateBlush(_ settings: BlushSettings) {
        mutate {
            value.blush = settings
        }
    }

    func updateEyeshadow(_ settings: EyeshadowSettings) {
        mutate {
            value.eyeshadow = settings
        }
    }

    func updateGlow(_ settings: GlowSettings) {
        mutate {
            value.glow = settings
        }
    }

    func updateMakeupEnabled(_ enabled: Bool) {
        mutate {
            value.isMakeupEnabled = enabled
        }
    }

    func snapshot() -> (MakeupStateSnapshot, UInt64) {
        lock.lock()
        defer { lock.unlock() }
        return (value, revision)
    }

    func snapshotIfChanged(after appliedRevision: UInt64) -> (MakeupStateSnapshot, UInt64)? {
        lock.lock()
        defer { lock.unlock() }

        guard revision != appliedRevision else { return nil }
        return (value, revision)
    }

    private func mutate(_ update: () -> Void) {
        lock.lock()
        update()
        revision &+= 1
        lock.unlock()
    }
}
