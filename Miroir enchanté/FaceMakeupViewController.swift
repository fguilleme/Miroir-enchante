//
//  FaceMakeupViewController.swift
//  Miroir enchanté
//

import ARKit
import CoreMotion
import SceneKit
import UIKit

/// Owns the camera view and AR session lifecycle.
/// Rendering decisions live in FaceRenderer so the UI stays small and clear.
final class FaceMakeupViewController: UIViewController {
    private enum ExperienceMode {
        case ar
        case demo
    }

    private enum ControlTab: Int {
        case lipstick = 0
        case hair = 1
        case debug = 2
    }

    private let sceneView = ARSCNView(frame: .zero)
    private let demoSceneView = SCNView(frame: .zero)
    private let faceRenderer = FaceRenderer()
    private let demoHeadRenderer = DemoHeadRenderer(assetFilename: "Female head.obj")
    private let motionManager = CMMotionManager()
    private let modeButton = UIButton(type: .system)
    private let experienceModeButton = UIButton(type: .system)
    private let hairStyleButton = UIButton(type: .system)
    private let controlsSegmentedControl = UISegmentedControl(items: ["Lipstick", "Hair", "Debug"])
    private let controlsStackView = UIStackView()
    private let opacitySlider = UISlider()
    private let roughnessSlider = UISlider()
    private let colorIntensitySlider = UISlider()
    private let hairHueSlider = UISlider()
    private let hairStrengthSlider = UISlider()
    private let hairOffsetYSlider = UISlider()
    private let hairOffsetZSlider = UISlider()
    private let hairScaleSlider = UISlider()
    private let hairOffsetYValueLabel = UILabel()
    private let hairOffsetZValueLabel = UILabel()
    private let hairScaleValueLabel = UILabel()
    private let hideHeadSwitch = UISwitch()
    private let hideHairSwitch = UISwitch()
    private var lipstickControlRows: [UIView] = []
    private var hairControlRows: [UIView] = []
    private var debugControlRows: [UIView] = []

    private var unsupportedDeviceLabel: UILabel?
    private var experienceMode: ExperienceMode = ARFaceTrackingConfiguration.isSupported ? .ar : .demo
    private var lipstickSettings = LipstickSettings.default
    private var hairHueValue: CGFloat = 0.24
    private var hairStrengthValue: CGFloat = 0.84
    private var hairOffsetYValue: Float = -0.08
    private var hairOffsetZValue: Float = 0.15
    private var hairScaleValue: Float = 1.0
    private var selectedControlTab: ControlTab = .lipstick
    private var smoothedInspectionTilt: CGFloat = 0

    override func viewDidLoad() {
        super.viewDidLoad()

        configureSceneView()
        configureModeButton()
        configureExperienceModeButton()
        configureHairStyleButton()
        configureMakeupControls()
        configureUnsupportedDeviceMessageIfNeeded()
        applyLipstickSettings()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyExperienceMode()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Pause camera and tracking work when the app is no longer presenting
        // the mirror. ARKit will resume with a clean configuration next time.
        sceneView.session.pause()
        sceneView.delegate = nil
        sceneView.session.delegate = nil
        stopDemoTiltControl()
    }

    private func configureSceneView() {
        view.backgroundColor = .black

        sceneView.translatesAutoresizingMaskIntoConstraints = false
        demoSceneView.translatesAutoresizingMaskIntoConstraints = false
        sceneView.backgroundColor = .black

        faceRenderer.attach(to: sceneView)

        view.addSubview(sceneView)
        view.addSubview(demoSceneView)
        NSLayoutConstraint.activate([
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sceneView.topAnchor.constraint(equalTo: view.topAnchor),
            sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            demoSceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            demoSceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            demoSceneView.topAnchor.constraint(equalTo: view.topAnchor),
            demoSceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        demoSceneView.scene = demoHeadRenderer.scene
        demoSceneView.pointOfView = demoHeadRenderer.cameraNode
        demoSceneView.backgroundColor = .black
        demoSceneView.autoenablesDefaultLighting = false
        demoSceneView.isPlaying = false
        demoSceneView.isHidden = true
    }

    private func configureModeButton() {
        modeButton.translatesAutoresizingMaskIntoConstraints = false
        modeButton.setTitle(faceRenderer.renderMode.buttonTitle, for: .normal)
        modeButton.setTitleColor(.white, for: .normal)
        modeButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        modeButton.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        modeButton.layer.cornerRadius = 8
        modeButton.addTarget(self, action: #selector(toggleRenderMode), for: .touchUpInside)

        view.addSubview(modeButton)
        NSLayoutConstraint.activate([
            modeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            modeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            modeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 84),
            modeButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func configureExperienceModeButton() {
        experienceModeButton.translatesAutoresizingMaskIntoConstraints = false
        experienceModeButton.setTitle(experienceButtonTitle, for: .normal)
        experienceModeButton.setTitleColor(.white, for: .normal)
        experienceModeButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        experienceModeButton.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        experienceModeButton.layer.cornerRadius = 8
        experienceModeButton.addTarget(self, action: #selector(toggleExperienceMode), for: .touchUpInside)

        view.addSubview(experienceModeButton)
        NSLayoutConstraint.activate([
            experienceModeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            experienceModeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            experienceModeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 112),
            experienceModeButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func configureHairStyleButton() {
        hairStyleButton.translatesAutoresizingMaskIntoConstraints = false
        hairStyleButton.setTitle(L10n.text(DemoHairStyle.none.titleKey), for: .normal)
        hairStyleButton.setTitleColor(.white, for: .normal)
        hairStyleButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        hairStyleButton.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        hairStyleButton.layer.cornerRadius = 8
        hairStyleButton.addTarget(self, action: #selector(cycleDemoHairStyle), for: .touchUpInside)
        hairStyleButton.isHidden = true

        view.addSubview(hairStyleButton)
        NSLayoutConstraint.activate([
            hairStyleButton.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            hairStyleButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            hairStyleButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 104),
            hairStyleButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func configureMakeupControls() {
        opacitySlider.minimumValue = 0.0
        opacitySlider.maximumValue = 1.0
        opacitySlider.value = Float(lipstickSettings.opacity)
        opacitySlider.addTarget(self, action: #selector(makeupSliderChanged), for: .valueChanged)

        roughnessSlider.minimumValue = 0.05
        roughnessSlider.maximumValue = 0.75
        roughnessSlider.value = Float(lipstickSettings.roughness)
        roughnessSlider.addTarget(self, action: #selector(makeupSliderChanged), for: .valueChanged)

        colorIntensitySlider.minimumValue = 0.4
        colorIntensitySlider.maximumValue = 1.45
        colorIntensitySlider.value = Float(lipstickSettings.colorIntensity)
        colorIntensitySlider.addTarget(self, action: #selector(makeupSliderChanged), for: .valueChanged)

        hairHueSlider.minimumValue = 0.0
        hairHueSlider.maximumValue = 1.0
        hairHueSlider.value = Float(hairHueValue)
        hairHueSlider.isContinuous = true
        hairHueSlider.addTarget(self, action: #selector(hairSliderChanged), for: .valueChanged)

        hairStrengthSlider.minimumValue = 0.0
        hairStrengthSlider.maximumValue = 1.0
        hairStrengthSlider.value = Float(hairStrengthValue)
        hairStrengthSlider.isContinuous = true
        hairStrengthSlider.addTarget(self, action: #selector(hairSliderChanged), for: .valueChanged)

        configureHairOffsetControls()

        hideHeadSwitch.addTarget(self, action: #selector(hideHeadSwitchChanged), for: .valueChanged)
        hideHairSwitch.addTarget(self, action: #selector(hideHairSwitchChanged), for: .valueChanged)

        controlsSegmentedControl.selectedSegmentIndex = selectedControlTab.rawValue
        controlsSegmentedControl.selectedSegmentTintColor = UIColor.white.withAlphaComponent(0.22)
        controlsSegmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        controlsSegmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        controlsSegmentedControl.addTarget(self, action: #selector(controlTabChanged), for: .valueChanged)

        let opacityRow = makeSliderRow(title: L10n.text("control.opacity"), slider: opacitySlider)
        let roughnessRow = makeSliderRow(title: L10n.text("control.gloss"), slider: roughnessSlider)
        let colorRow = makeSliderRow(title: L10n.text("control.color"), slider: colorIntensitySlider)
        let presetRow = makePresetRow()
        let visibilityRow = makeDoubleSwitchRow(
            leftTitle: L10n.text("control.hide_head"),
            leftToggle: hideHeadSwitch,
            rightTitle: L10n.text("control.hide_hair"),
            rightToggle: hideHairSwitch
        )
        let hairRow = makeDoubleSliderRow(
            leftTitle: L10n.text("control.hair_hue"),
            leftSlider: hairHueSlider,
            rightTitle: L10n.text("control.hair_strength"),
            rightSlider: hairStrengthSlider
        )
        let hairOffsetYRow = makeHairOffsetRow(title: "Y", slider: hairOffsetYSlider, valueLabel: hairOffsetYValueLabel)
        let hairOffsetZRow = makeHairOffsetRow(title: "Z", slider: hairOffsetZSlider, valueLabel: hairOffsetZValueLabel)
        let hairScaleRow = makeHairOffsetRow(title: "S", slider: hairScaleSlider, valueLabel: hairScaleValueLabel)
        updateHairOffsetValueLabels()

        lipstickControlRows = [opacityRow, roughnessRow, colorRow, presetRow]
        hairControlRows = [hairRow]
        debugControlRows = [hairOffsetYRow, hairOffsetZRow, hairScaleRow, visibilityRow]

        controlsStackView.translatesAutoresizingMaskIntoConstraints = false
        controlsStackView.axis = .vertical
        controlsStackView.spacing = 8
        controlsStackView.alignment = .fill
        controlsStackView.backgroundColor = UIColor.black.withAlphaComponent(0.52)
        controlsStackView.layer.cornerRadius = 10
        controlsStackView.isLayoutMarginsRelativeArrangement = true
        controlsStackView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)

        controlsStackView.addArrangedSubview(controlsSegmentedControl)
        controlsStackView.addArrangedSubview(opacityRow)
        controlsStackView.addArrangedSubview(roughnessRow)
        controlsStackView.addArrangedSubview(colorRow)
        controlsStackView.addArrangedSubview(presetRow)
        controlsStackView.addArrangedSubview(hairRow)
        controlsStackView.addArrangedSubview(hairOffsetYRow)
        controlsStackView.addArrangedSubview(hairOffsetZRow)
        controlsStackView.addArrangedSubview(hairScaleRow)
        controlsStackView.addArrangedSubview(visibilityRow)
        updateControlTabAvailability()
        updateControlTabVisibility()

        view.addSubview(controlsStackView)
        NSLayoutConstraint.activate([
            controlsStackView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            controlsStackView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            controlsStackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    private func configureHairOffsetControls() {
        hairOffsetYSlider.minimumValue = -3.0
        hairOffsetYSlider.maximumValue = 1.0
        hairOffsetYSlider.value = hairOffsetYValue
        hairOffsetYSlider.isContinuous = true
        hairOffsetYSlider.addTarget(self, action: #selector(hairOffsetSliderChanged), for: .valueChanged)

        hairOffsetZSlider.minimumValue = -1.0
        hairOffsetZSlider.maximumValue = 5.0
        hairOffsetZSlider.value = hairOffsetZValue
        hairOffsetZSlider.isContinuous = true
        hairOffsetZSlider.addTarget(self, action: #selector(hairOffsetSliderChanged), for: .valueChanged)

        hairScaleSlider.minimumValue = 0.15
        hairScaleSlider.maximumValue = 2.0
        hairScaleSlider.value = hairScaleValue
        hairScaleSlider.isContinuous = true
        hairScaleSlider.addTarget(self, action: #selector(hairOffsetSliderChanged), for: .valueChanged)
    }

    private func makeHairOffsetRow(title: String, slider: UISlider, valueLabel: UILabel) -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = .white
        titleLabel.font = .preferredFont(forTextStyle: .caption2)
        titleLabel.widthAnchor.constraint(equalToConstant: 16).isActive = true

        valueLabel.textColor = UIColor.white.withAlphaComponent(0.82)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valueLabel.textAlignment = .right
        valueLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true

        let row = UIStackView(arrangedSubviews: [titleLabel, slider, valueLabel])
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        return row
    }

    private func makeSliderRow(title: String, slider: UISlider) -> UIStackView {
        let label = UILabel()
        label.text = title
        label.textColor = .white
        label.font = .preferredFont(forTextStyle: .caption1)
        label.widthAnchor.constraint(equalToConstant: 64).isActive = true

        let row = UIStackView(arrangedSubviews: [label, slider])
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        return row
    }

    private func makeDoubleSliderRow(
        leftTitle: String,
        leftSlider: UISlider,
        rightTitle: String,
        rightSlider: UISlider
    ) -> UIStackView {
        let leftRow = makeCompactSliderRow(title: leftTitle, slider: leftSlider)
        let rightRow = makeCompactSliderRow(title: rightTitle, slider: rightSlider)

        let row = UIStackView(arrangedSubviews: [leftRow, rightRow])
        row.axis = .horizontal
        row.spacing = 10
        row.distribution = .fillEqually
        row.alignment = .center
        return row
    }

    private func makeCompactSliderRow(title: String, slider: UISlider) -> UIStackView {
        let label = UILabel()
        label.text = title
        label.textColor = .white
        label.font = .preferredFont(forTextStyle: .caption2)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.75
        label.widthAnchor.constraint(equalToConstant: 44).isActive = true

        let row = UIStackView(arrangedSubviews: [label, slider])
        row.axis = .horizontal
        row.spacing = 6
        row.alignment = .center
        return row
    }

    private func makeSwitchRow(title: String, toggle: UISwitch) -> UIStackView {
        let label = UILabel()
        label.text = title
        label.textColor = .white
        label.font = .preferredFont(forTextStyle: .caption1)

        let row = UIStackView(arrangedSubviews: [label, toggle])
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        row.distribution = .equalSpacing
        return row
    }

    private func makeDoubleSwitchRow(
        leftTitle: String,
        leftToggle: UISwitch,
        rightTitle: String,
        rightToggle: UISwitch
    ) -> UIStackView {
        let leftRow = makeSwitchRow(title: leftTitle, toggle: leftToggle)
        let rightRow = makeSwitchRow(title: rightTitle, toggle: rightToggle)

        let row = UIStackView(arrangedSubviews: [leftRow, rightRow])
        row.axis = .horizontal
        row.spacing = 10
        row.distribution = .fillEqually
        row.alignment = .center
        return row
    }

    private func makePresetRow() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.distribution = .fillEqually

        for (index, preset) in LipstickSettings.presets.enumerated() {
            let button = UIButton(type: .system)
            button.tag = index
            button.setTitle(L10n.text(preset.titleKey), for: .normal)
            button.setTitleColor(.white, for: .normal)
            button.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
            button.backgroundColor = preset.color
            button.layer.cornerRadius = 7
            button.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
            button.layer.borderWidth = 1
            button.addTarget(self, action: #selector(selectLipstickPreset(_:)), for: .touchUpInside)
            row.addArrangedSubview(button)
        }

        return row
    }

    @objc private func toggleRenderMode() {
        let mode = faceRenderer.toggleMode()
        modeButton.setTitle(mode.buttonTitle, for: .normal)
    }

    @objc private func toggleExperienceMode() {
        switch experienceMode {
        case .ar:
            experienceMode = .demo
        case .demo:
            experienceMode = .ar
        }

        applyExperienceMode()
    }

    @objc private func cycleDemoHairStyle() {
        let style = demoHeadRenderer.cycleHairStyle()
        hairStyleButton.setTitle(L10n.text(style.titleKey), for: .normal)
    }

    @objc private func makeupSliderChanged() {
        lipstickSettings.opacity = CGFloat(opacitySlider.value)
        lipstickSettings.roughness = CGFloat(roughnessSlider.value)
        lipstickSettings.glossIntensity = CGFloat(1.0 - roughnessSlider.value)
        lipstickSettings.colorIntensity = CGFloat(colorIntensitySlider.value)
        applyLipstickSettings()
    }

    @objc private func hairSliderChanged() {
        hairHueValue = CGFloat(hairHueSlider.value)
        hairStrengthValue = CGFloat(hairStrengthSlider.value)
        demoHeadRenderer.updateHairColor(hue: hairHueValue, strength: hairStrengthValue)
    }

    @objc private func hairOffsetSliderChanged() {
        hairOffsetYValue = hairOffsetYSlider.value
        hairOffsetZValue = hairOffsetZSlider.value
        hairScaleValue = hairScaleSlider.value
        updateHairOffsetValueLabels()
        demoHeadRenderer.updateHairPlacement(y: hairOffsetYValue, z: hairOffsetZValue, scale: hairScaleValue)
    }

    private func updateHairOffsetValueLabels() {
        hairOffsetYValueLabel.text = String(format: "%.2f", hairOffsetYSlider.value)
        hairOffsetZValueLabel.text = String(format: "%.2f", hairOffsetZSlider.value)
        hairScaleValueLabel.text = String(format: "%.2f", hairScaleSlider.value)
    }

    @objc private func controlTabChanged() {
        selectedControlTab = ControlTab(rawValue: controlsSegmentedControl.selectedSegmentIndex) ?? .lipstick
        updateControlTabVisibility()
    }

    private func updateControlTabAvailability() {
        let demoControlsEnabled = experienceMode == .demo
        controlsSegmentedControl.setEnabled(true, forSegmentAt: ControlTab.lipstick.rawValue)
        controlsSegmentedControl.setEnabled(demoControlsEnabled, forSegmentAt: ControlTab.hair.rawValue)
        controlsSegmentedControl.setEnabled(demoControlsEnabled, forSegmentAt: ControlTab.debug.rawValue)

        if !demoControlsEnabled && selectedControlTab != .lipstick {
            selectedControlTab = .lipstick
            controlsSegmentedControl.selectedSegmentIndex = selectedControlTab.rawValue
        }
    }

    private func updateControlTabVisibility() {
        lipstickControlRows.forEach { $0.isHidden = selectedControlTab != .lipstick }

        let demoControlsEnabled = experienceMode == .demo
        hairControlRows.forEach { $0.isHidden = selectedControlTab != .hair || !demoControlsEnabled }
        debugControlRows.forEach { $0.isHidden = selectedControlTab != .debug || !demoControlsEnabled }
    }

    @objc private func hideHeadSwitchChanged() {
        demoHeadRenderer.setHeadHidden(hideHeadSwitch.isOn)
    }

    @objc private func hideHairSwitchChanged() {
        demoHeadRenderer.setHairHidden(hideHairSwitch.isOn)
    }

    @objc private func selectLipstickPreset(_ sender: UIButton) {
        guard LipstickSettings.presets.indices.contains(sender.tag) else { return }

        lipstickSettings.color = LipstickSettings.presets[sender.tag].color
        applyLipstickSettings()
    }

    private var experienceButtonTitle: String {
        switch experienceMode {
        case .ar:
            return L10n.text("mode.demo")
        case .demo:
            return L10n.text("mode.ar")
        }
    }

    private func applyExperienceMode() {
        experienceModeButton.setTitle(experienceButtonTitle, for: .normal)
        unsupportedDeviceLabel?.isHidden = experienceMode == .demo || ARFaceTrackingConfiguration.isSupported

        switch experienceMode {
        case .ar:
            startFaceTrackingSessionIfSupported()
        case .demo:
            startDemoFaceMode()
        }
    }

    private func startDemoFaceMode() {
        sceneView.session.pause()
        sceneView.delegate = nil
        sceneView.session.delegate = nil
        sceneView.isPlaying = false
        sceneView.isHidden = true
        demoSceneView.isHidden = false
        demoSceneView.isPlaying = true
        modeButton.isHidden = true
        hairStyleButton.isHidden = true
        updateControlTabAvailability()
        updateControlTabVisibility()
        demoHeadRenderer.updateHairPlacement(y: hairOffsetYValue, z: hairOffsetZValue, scale: hairScaleValue)
        demoHeadRenderer.setHeadHidden(hideHeadSwitch.isOn)
        demoHeadRenderer.setHairHidden(hideHairSwitch.isOn)
        startDemoTiltControl()
    }

    private func startFaceTrackingSessionIfSupported() {
        guard ARFaceTrackingConfiguration.isSupported else {
            print("AR face tracking is not supported on this device.")
            experienceMode = .demo
            startDemoFaceMode()
            experienceModeButton.setTitle(experienceButtonTitle, for: .normal)
            return
        }

        demoSceneView.isHidden = true
        demoSceneView.isPlaying = false
        stopDemoTiltControl()
        sceneView.isHidden = false
        sceneView.session.pause()
        sceneView.scene = SCNScene()
        sceneView.delegate = faceRenderer
        sceneView.automaticallyUpdatesLighting = true
        sceneView.isPlaying = true
        modeButton.isHidden = false
        hairStyleButton.isHidden = true
        updateControlTabAvailability()
        updateControlTabVisibility()
        demoHeadRenderer.setHeadHidden(false)
        demoHeadRenderer.setHairHidden(false)
        faceRenderer.attach(to: sceneView)
        faceRenderer.updateLipstickSettings(lipstickSettings)

        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true

        // Face tracking uses the TrueDepth front camera and streams one
        // ARFaceAnchor per detected face into ARSCNViewDelegate callbacks.
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    private func startDemoTiltControl() {
        guard motionManager.isDeviceMotionAvailable else {
            demoHeadRenderer.updateInspectionTilt(horizontal: 0)
            return
        }

        if motionManager.isDeviceMotionActive {
            return
        }

        smoothedInspectionTilt = 0
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, self.experienceMode == .demo, let motion else { return }

            // In portrait, gravity.x behaves like a simple inclinometer. The
            // multiplier makes the model reach a near-back view without
            // requiring an exaggerated physical tilt of the phone.
            let amplifiedTilt = CGFloat(motion.gravity.x) * 1.75
            let rawTilt = min(1, max(-1, amplifiedTilt))
            self.smoothedInspectionTilt = self.smoothedInspectionTilt * 0.82 + rawTilt * 0.18
            self.demoHeadRenderer.updateInspectionTilt(horizontal: self.smoothedInspectionTilt)
        }
    }

    private func stopDemoTiltControl() {
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }

        smoothedInspectionTilt = 0
        demoHeadRenderer.updateInspectionTilt(horizontal: 0)
    }

    private func applyLipstickSettings() {
        faceRenderer.updateLipstickSettings(lipstickSettings)
        demoHeadRenderer.updateLipstickSettings(lipstickSettings)
    }

    private func configureUnsupportedDeviceMessageIfNeeded() {
        guard !ARFaceTrackingConfiguration.isSupported else { return }

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = L10n.text("error.truedepth_required")
        label.textAlignment = .center
        label.textColor = .white
        label.font = .preferredFont(forTextStyle: .body)
        label.numberOfLines = 0

        view.addSubview(label)
        unsupportedDeviceLabel = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}
