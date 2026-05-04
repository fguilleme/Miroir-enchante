//
//  MakeupRendering.swift
//  Miroir enchanté
//

protocol MakeupRendering: AnyObject {
    func updateLipstickSettings(_ settings: LipstickSettings)
    func updateBlushSettings(_ settings: BlushSettings)
    func updateEyeshadowSettings(_ settings: EyeshadowSettings)
    func updateGlowSettings(_ settings: GlowSettings)
    func setMakeupEnabled(_ enabled: Bool)
}
