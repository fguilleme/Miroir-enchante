//
//  MakeupRendering.swift
//  Miroir enchanté
//

protocol MakeupRendering: AnyObject {
    func updateLipstickSettings(_ settings: LipstickSettings)
    func updateBlushSettings(_ settings: BlushSettings)
    func setMakeupEnabled(_ enabled: Bool)
}
