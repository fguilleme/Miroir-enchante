//
//  FaceMakeupViewController.swift
//  Miroir enchanté
//

import ARKit
import SceneKit
import UIKit

/// Owns the camera view and AR session lifecycle.
/// Rendering decisions live in FaceRenderer so the UI stays small and clear.
final class FaceMakeupViewController: UIViewController {
    private enum ExperienceMode {
        case ar
        case demo
    }

    private let sceneView = ARSCNView(frame: .zero)
    private let demoSceneView = SCNView(frame: .zero)
    private let faceRenderer = FaceRenderer()
    private let demoHeadRenderer = DemoHeadRenderer(assetFilename: "female_head.obj")
    private let modeButton = UIButton(type: .system)
    private let experienceModeButton = UIButton(type: .system)
    private let hairStyleButton = UIButton(type: .system)
    private let controlsStackView = UIStackView()
    private let opacitySlider = UISlider()
    private let roughnessSlider = UISlider()
    private let colorIntensitySlider = UISlider()

    private var unsupportedDeviceLabel: UILabel?
    private var experienceMode: ExperienceMode = ARFaceTrackingConfiguration.isSupported ? .ar : .demo
    private var lipstickSettings = LipstickSettings.default

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

        let opacityRow = makeSliderRow(title: L10n.text("control.opacity"), slider: opacitySlider)
        let roughnessRow = makeSliderRow(title: L10n.text("control.gloss"), slider: roughnessSlider)
        let colorRow = makeSliderRow(title: L10n.text("control.color"), slider: colorIntensitySlider)
        let presetRow = makePresetRow()

        controlsStackView.translatesAutoresizingMaskIntoConstraints = false
        controlsStackView.axis = .vertical
        controlsStackView.spacing = 8
        controlsStackView.alignment = .fill
        controlsStackView.backgroundColor = UIColor.black.withAlphaComponent(0.52)
        controlsStackView.layer.cornerRadius = 10
        controlsStackView.isLayoutMarginsRelativeArrangement = true
        controlsStackView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)

        controlsStackView.addArrangedSubview(opacityRow)
        controlsStackView.addArrangedSubview(roughnessRow)
        controlsStackView.addArrangedSubview(colorRow)
        controlsStackView.addArrangedSubview(presetRow)

        view.addSubview(controlsStackView)
        NSLayoutConstraint.activate([
            controlsStackView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            controlsStackView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            controlsStackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
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
        hairStyleButton.isHidden = false
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
        sceneView.isHidden = false
        sceneView.session.pause()
        sceneView.scene = SCNScene()
        sceneView.delegate = faceRenderer
        sceneView.automaticallyUpdatesLighting = true
        sceneView.isPlaying = true
        modeButton.isHidden = false
        hairStyleButton.isHidden = true
        faceRenderer.attach(to: sceneView)
        faceRenderer.updateLipstickSettings(lipstickSettings)

        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true

        // Face tracking uses the TrueDepth front camera and streams one
        // ARFaceAnchor per detected face into ARSCNViewDelegate callbacks.
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
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
