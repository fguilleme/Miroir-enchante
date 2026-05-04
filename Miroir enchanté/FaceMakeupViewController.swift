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

    private let sceneView = ARSCNView(frame: .zero)
    private let demoSceneView = SCNView(frame: .zero)
    private let faceRenderer = FaceRenderer()
    private lazy var demoHeadRenderer = DemoHeadRenderer(assetFilename: "Female head.obj")
    private let motionManager = CMMotionManager()
    private let modeButton = UIButton(type: .system)
    private let experienceModeButton = UIButton(type: .system)
    private let hairStyleButton = UIButton(type: .system)
    private let arAutoFramingButton = UIButton(type: .system)
    private let beforeAfterButton = UIButton(type: .system)
    private let controlPanel = MakeupControlPanelView()

    private var unsupportedDeviceLabel: UILabel?
    private var experienceMode: ExperienceMode = FaceMakeupViewController.initialExperienceMode()
    private var settingsState = MakeupSettingsState.load()
    private var didCenterInitialLipstickPreset = false
    private var selectedMainCategory: MakeupMainCategory = .looks
    private var selectedFaceSubCategory: FaceSubCategory = .blush
    private var selectedLookID: String?
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let lookFeedback = UIImpactFeedbackGenerator(style: .light)
    private var smoothedInspectionTilt: CGFloat = 0
    private var isBeforePreviewActive = false
    private var arFaceFramingScale: CGFloat = 1
    private var arFaceFramingTranslation: CGPoint = .zero
    private var makeupRenderers: [MakeupRendering] {
        Self.isDemoFeatureEnabled ? [faceRenderer, demoHeadRenderer] : [faceRenderer]
    }

    private static var isDemoFeatureEnabled: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private static func initialExperienceMode() -> ExperienceMode {
        if isDemoFeatureEnabled && !ARFaceTrackingConfiguration.isSupported {
            return .demo
        }

        return .ar
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureSceneView()
        configureModeButton()
        configureExperienceModeButton()
        configureHairStyleButton()
        configureMakeupControls()
        configureBeforeAfterButton()
        configureARAutoFramingButton()
        configureUnsupportedDeviceMessageIfNeeded()
        applyLipstickSettings()
        applyBlushSettings()
        applyEyeshadowSettings()
        applyGlowSettings()
        applyContourSettings()

        selectionFeedback.prepare()
        lookFeedback.prepare()
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        faceRenderer.updateViewportSize(sceneView.bounds.size)
        updateLipstickCollectionLayoutInsets()

        guard !didCenterInitialLipstickPreset, controlPanel.lipstickCollectionView.bounds.width > 0 else { return }
        didCenterInitialLipstickPreset = true
        centerSelectedLipstickPreset(animated: false)
        updateVisibleLipstickCells(animated: false)
    }

    private func persistSettings() {
        settingsState.isHeadHidden = controlPanel.hideHeadSwitch.isOn
        settingsState.isHairHidden = controlPanel.hideHairSwitch.isOn
        settingsState.persist()
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

        demoSceneView.backgroundColor = .black
        demoSceneView.autoenablesDefaultLighting = false
        demoSceneView.isPlaying = false
        demoSceneView.isHidden = true

        if Self.isDemoFeatureEnabled {
            demoSceneView.scene = demoHeadRenderer.scene
            demoSceneView.pointOfView = demoHeadRenderer.cameraNode
        }

        faceRenderer.faceBoundsDidUpdate = { [weak self] faceBounds in
            self?.updateARFaceFraming(faceBounds: faceBounds)
        }
        faceRenderer.faceDetectionStateDidChange = { [weak self] isDetected in
            if !isDetected {
                self?.resetARFaceFraming(animated: true)
            }
        }
    }

    private func configureModeButton() {
        modeButton.translatesAutoresizingMaskIntoConstraints = false
        modeButton.setTitle(faceRenderer.renderMode.buttonTitle, for: .normal)
        styleFloatingButton(modeButton)
        modeButton.addTarget(self, action: #selector(toggleRenderMode), for: .touchUpInside)
        modeButton.isHidden = !Self.isDemoFeatureEnabled

        view.addSubview(modeButton)
        NSLayoutConstraint.activate([
            modeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            modeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 68),
            modeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 84),
            modeButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func configureExperienceModeButton() {
        experienceModeButton.translatesAutoresizingMaskIntoConstraints = false
        experienceModeButton.setTitle(experienceButtonTitle, for: .normal)
        styleFloatingButton(experienceModeButton)
        experienceModeButton.addTarget(self, action: #selector(toggleExperienceMode), for: .touchUpInside)
        experienceModeButton.isHidden = !Self.isDemoFeatureEnabled

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
        styleFloatingButton(hairStyleButton)
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

    private func configureARAutoFramingButton() {
        arAutoFramingButton.translatesAutoresizingMaskIntoConstraints = false
        arAutoFramingButton.setImage(UIImage(systemName: "viewfinder"), for: .normal)
        arAutoFramingButton.setImage(UIImage(systemName: "viewfinder.circle.fill"), for: .selected)
        arAutoFramingButton.imageView?.contentMode = .scaleAspectFit
        arAutoFramingButton.addTarget(self, action: #selector(toggleARAutoFraming), for: .touchUpInside)
        arAutoFramingButton.accessibilityLabel = "Auto framing"
        styleIconFloatingButton(arAutoFramingButton)
        updateARAutoFramingButton()
        arAutoFramingButton.isHidden = experienceMode != .ar

        view.addSubview(arAutoFramingButton)
        NSLayoutConstraint.activate([
            arAutoFramingButton.trailingAnchor.constraint(equalTo: beforeAfterButton.leadingAnchor, constant: -10),
            arAutoFramingButton.centerYAnchor.constraint(equalTo: beforeAfterButton.centerYAnchor),
            arAutoFramingButton.widthAnchor.constraint(equalToConstant: 42),
            arAutoFramingButton.heightAnchor.constraint(equalToConstant: 42)
        ])
    }

    private func configureBeforeAfterButton() {
        beforeAfterButton.translatesAutoresizingMaskIntoConstraints = false
        beforeAfterButton.setTitle("Avant / Après", for: .normal)
        beforeAfterButton.setImage(UIImage(systemName: "rectangle.split.2x1"), for: .normal)
        beforeAfterButton.tintColor = CosmeticTheme.softGold
        beforeAfterButton.semanticContentAttribute = .forceLeftToRight
        styleFloatingButton(beforeAfterButton)
        beforeAfterButton.alpha = 0.78
        beforeAfterButton.layer.borderColor = UIColor.white.withAlphaComponent(0.05).cgColor
        beforeAfterButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        beforeAfterButton.setTitleColor(UIColor.white.withAlphaComponent(0.88), for: .normal)
        beforeAfterButton.addTarget(self, action: #selector(showBeforePreview), for: .touchDown)
        beforeAfterButton.addTarget(self, action: #selector(showAfterPreview), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        view.addSubview(beforeAfterButton)
        NSLayoutConstraint.activate([
            beforeAfterButton.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            beforeAfterButton.bottomAnchor.constraint(equalTo: controlPanel.topAnchor, constant: -10),
            beforeAfterButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 166),
            beforeAfterButton.heightAnchor.constraint(equalToConstant: 42)
        ])
    }

    private func styleFloatingButton(_ button: UIButton) {
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.backgroundColor = CosmeticTheme.controlBackground
        button.layer.cornerRadius = 12
        button.layer.borderWidth = 0.8
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor
    }

    private func styleIconFloatingButton(_ button: UIButton) {
        button.backgroundColor = CosmeticTheme.controlBackground
        button.layer.cornerRadius = 12
        button.layer.borderWidth = 0.8
        button.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold),
            forImageIn: .normal
        )
    }

    private func configureMakeupControls() {
        controlPanel.configureInitialValues(from: settingsState)
        controlPanel.lipstickCollectionView.dataSource = self
        controlPanel.lipstickCollectionView.delegate = self
        controlPanel.looksCollectionView.dataSource = self
        controlPanel.looksCollectionView.delegate = self
        controlPanel.controlsSegmentedControl.addTarget(self, action: #selector(mainCategoryChanged), for: .valueChanged)
        controlPanel.faceSegmentedControl.addTarget(self, action: #selector(faceSubCategoryChanged), for: .valueChanged)
        controlPanel.lipstickIntensitySlider.addTarget(self, action: #selector(lipstickIntensityChanged), for: .valueChanged)
        controlPanel.lipstickFinishSegmentedControl.addTarget(self, action: #selector(lipstickFinishChanged), for: .valueChanged)
        controlPanel.blushIntensitySlider.addTarget(self, action: #selector(blushSliderChanged), for: .valueChanged)
        controlPanel.blushSizeSlider.addTarget(self, action: #selector(blushSliderChanged), for: .valueChanged)
        controlPanel.blushPositionSlider.addTarget(self, action: #selector(blushSliderChanged), for: .valueChanged)
        controlPanel.eyeshadowIntensitySlider.addTarget(self, action: #selector(eyeshadowSliderChanged), for: .valueChanged)
        controlPanel.glowIntensitySlider.addTarget(self, action: #selector(glowSliderChanged), for: .valueChanged)
        controlPanel.glowRadiusSlider.addTarget(self, action: #selector(glowSliderChanged), for: .valueChanged)
        controlPanel.contourIntensitySlider.addTarget(self, action: #selector(contourSliderChanged), for: .valueChanged)
        controlPanel.hairHueSlider.addTarget(self, action: #selector(hairSliderChanged), for: .valueChanged)
        controlPanel.hairStrengthSlider.addTarget(self, action: #selector(hairSliderChanged), for: .valueChanged)
        controlPanel.hairOffsetYSlider.addTarget(self, action: #selector(hairOffsetSliderChanged), for: .valueChanged)
        controlPanel.hairOffsetZSlider.addTarget(self, action: #selector(hairOffsetSliderChanged), for: .valueChanged)
        controlPanel.hairScaleSlider.addTarget(self, action: #selector(hairOffsetSliderChanged), for: .valueChanged)
        controlPanel.hideHeadSwitch.addTarget(self, action: #selector(hideHeadSwitchChanged), for: .valueChanged)
        controlPanel.hideHairSwitch.addTarget(self, action: #selector(hideHairSwitchChanged), for: .valueChanged)
        controlPanel.blushPresetButtons.forEach {
            $0.addTarget(self, action: #selector(blushPresetTapped(_:)), for: .touchUpInside)
        }
        controlPanel.eyeshadowPresetButtons.forEach {
            $0.addTarget(self, action: #selector(eyeshadowPresetTapped(_:)), for: .touchUpInside)
        }
        controlPanel.glowPresetButtons.forEach {
            $0.addTarget(self, action: #selector(glowPresetTapped(_:)), for: .touchUpInside)
        }
        controlPanel.contourPresetButtons.forEach {
            $0.addTarget(self, action: #selector(contourPresetTapped(_:)), for: .touchUpInside)
        }
        (selectedMainCategory, selectedFaceSubCategory) = controlPanel.configureMainCategories(
            selected: selectedMainCategory,
            faceSubCategory: selectedFaceSubCategory
        )

        view.addSubview(controlPanel)
        NSLayoutConstraint.activate([
            controlPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        applySelectedLipstickPreset(animated: false)
        applySelectedBlushPreset(animated: false)
        applySelectedEyeshadowPreset(animated: false)
        applySelectedGlowPreset(animated: false)
        applySelectedContourPreset(animated: false)
    }

    @objc private func toggleRenderMode() {
        let mode = faceRenderer.toggleMode()
        modeButton.setTitle(mode.buttonTitle, for: .normal)
    }

    @objc private func toggleARAutoFraming() {
        settingsState.isARAutoFramingEnabled.toggle()
        updateARAutoFramingButton()
        persistSettings()

        if !settingsState.isARAutoFramingEnabled {
            resetARFaceFraming(animated: true)
        }
    }

    private func updateARAutoFramingButton() {
        arAutoFramingButton.isSelected = settingsState.isARAutoFramingEnabled
        arAutoFramingButton.tintColor = settingsState.isARAutoFramingEnabled ? CosmeticTheme.softGold : UIColor.white.withAlphaComponent(0.62)
        arAutoFramingButton.layer.borderColor = (settingsState.isARAutoFramingEnabled ? CosmeticTheme.gold : UIColor.white.withAlphaComponent(0.08)).cgColor
        arAutoFramingButton.backgroundColor = settingsState.isARAutoFramingEnabled
            ? CosmeticTheme.gold.withAlphaComponent(0.18)
            : CosmeticTheme.controlBackground
    }

    @objc private func toggleExperienceMode() {
        guard Self.isDemoFeatureEnabled else { return }

        switch experienceMode {
        case .ar:
            experienceMode = .demo
        case .demo:
            experienceMode = .ar
        }

        applyExperienceMode()
    }

    @objc private func cycleDemoHairStyle() {
        guard Self.isDemoFeatureEnabled else { return }

        let style = demoHeadRenderer.cycleHairStyle()
        hairStyleButton.setTitle(L10n.text(style.titleKey), for: .normal)
    }

    @objc private func showBeforePreview() {
        setBeforePreviewActive(true)
    }

    @objc private func showAfterPreview() {
        setBeforePreviewActive(false)
    }

    private func setBeforePreviewActive(_ active: Bool) {
        isBeforePreviewActive = active
        setMakeupEnabledForAllRenderers(!active)
        UIView.animate(withDuration: 0.18, delay: 0, options: [.allowUserInteraction, .curveEaseOut], animations: {
            self.beforeAfterButton.alpha = active ? 0.55 : 0.78
        })
    }

    @objc private func lipstickIntensityChanged() {
        clearLookSelection()
        applySelectedLipstickPreset(animated: false, updatesSelector: false)
    }

    @objc private func lipstickFinishChanged() {
        selectionFeedback.selectionChanged()
        clearLookSelection()
        settingsState.lipstickFinish = LipstickFinish(rawValue: controlPanel.lipstickFinishSegmentedControl.selectedSegmentIndex) ?? .satin
        applySelectedLipstickPreset(animated: true, updatesSelector: false)
    }

    @objc private func blushPresetTapped(_ sender: UIButton) {
        guard BlushSettings.presets.indices.contains(sender.tag) else { return }
        if settingsState.selectedBlushPresetIndex != sender.tag {
            selectionFeedback.selectionChanged()
        }
        clearLookSelection()
        settingsState.selectedBlushPresetIndex = sender.tag
        applySelectedBlushPreset(animated: true)
    }

    @objc private func blushSliderChanged() {
        clearLookSelection()
        settingsState.blushSettings.intensity = CGFloat(controlPanel.blushIntensitySlider.value)
        settingsState.blushSettings.size = CGFloat(controlPanel.blushSizeSlider.value)
        settingsState.blushSettings.position = CGFloat(controlPanel.blushPositionSlider.value)
        applyBlushSettings()
        persistSettings()
    }

    @objc private func eyeshadowPresetTapped(_ sender: UIButton) {
        guard EyeshadowSettings.presets.indices.contains(sender.tag) else { return }
        if settingsState.selectedEyeshadowPresetIndex != sender.tag {
            selectionFeedback.selectionChanged()
        }
        clearLookSelection()
        settingsState.selectedEyeshadowPresetIndex = sender.tag
        applySelectedEyeshadowPreset(animated: true)
    }

    @objc private func eyeshadowSliderChanged() {
        clearLookSelection()
        settingsState.eyeshadowSettings.intensity = CGFloat(controlPanel.eyeshadowIntensitySlider.value)
        applyEyeshadowSettings()
        persistSettings()
    }

    @objc private func glowPresetTapped(_ sender: UIButton) {
        guard GlowSettings.presets.indices.contains(sender.tag) else { return }
        if settingsState.selectedGlowPresetIndex != sender.tag {
            selectionFeedback.selectionChanged()
        }
        clearLookSelection()
        settingsState.selectedGlowPresetIndex = sender.tag
        applySelectedGlowPreset(animated: true)
    }

    @objc private func glowSliderChanged() {
        clearLookSelection()
        settingsState.glowSettings.intensity = CGFloat(controlPanel.glowIntensitySlider.value)
        settingsState.glowSettings.radius = CGFloat(controlPanel.glowRadiusSlider.value)
        settingsState.rebuildGlowSettings()
        applyGlowSettings()
        persistSettings()
    }

    @objc private func contourPresetTapped(_ sender: UIButton) {
        guard ContourSettings.presets.indices.contains(sender.tag) else { return }
        if settingsState.selectedContourPresetIndex != sender.tag {
            selectionFeedback.selectionChanged()
        }
        clearLookSelection()
        settingsState.selectedContourPresetIndex = sender.tag
        applySelectedContourPreset(animated: true)
    }

    @objc private func contourSliderChanged() {
        clearLookSelection()
        settingsState.contourSettings.intensity = CGFloat(controlPanel.contourIntensitySlider.value)
        settingsState.rebuildContourSettings()
        applyContourSettings()
        persistSettings()
    }

    @objc private func hairSliderChanged() {
        settingsState.hairHueValue = CGFloat(controlPanel.hairHueSlider.value)
        settingsState.hairStrengthValue = CGFloat(controlPanel.hairStrengthSlider.value)
        if Self.isDemoFeatureEnabled {
            demoHeadRenderer.updateHairColor(hue: settingsState.hairHueValue, strength: settingsState.hairStrengthValue)
        }
        persistSettings()
    }

    @objc private func hairOffsetSliderChanged() {
        settingsState.hairOffsetYValue = controlPanel.hairOffsetYSlider.value
        settingsState.hairOffsetZValue = controlPanel.hairOffsetZSlider.value
        settingsState.hairScaleValue = controlPanel.hairScaleSlider.value
        controlPanel.updateHairOffsetValueLabels()
        if Self.isDemoFeatureEnabled {
            demoHeadRenderer.updateHairPlacement(y: settingsState.hairOffsetYValue, z: settingsState.hairOffsetZValue, scale: settingsState.hairScaleValue)
        }
        persistSettings()
    }

    @objc private func mainCategoryChanged() {
        selectedMainCategory = controlPanel.selectedMainCategoryFromSegment()
        controlPanel.setSelectedMainCategory(selectedMainCategory)
    }

    @objc private func faceSubCategoryChanged() {
        selectedFaceSubCategory = controlPanel.selectedFaceSubCategoryFromSegment()
        controlPanel.setSelectedFaceSubCategory(selectedFaceSubCategory)
    }

    private func updateControlPanelForExperienceMode() {
        (selectedMainCategory, selectedFaceSubCategory) = controlPanel.configureMainCategories(
            selected: selectedMainCategory,
            faceSubCategory: selectedFaceSubCategory
        )
    }

    @objc private func hideHeadSwitchChanged() {
        if Self.isDemoFeatureEnabled {
            demoHeadRenderer.setHeadHidden(controlPanel.hideHeadSwitch.isOn)
        }
        persistSettings()
    }

    @objc private func hideHairSwitchChanged() {
        if Self.isDemoFeatureEnabled {
            demoHeadRenderer.setHairHidden(controlPanel.hideHairSwitch.isOn)
        }
        persistSettings()
    }

    private func selectLipstickPreset(at index: Int, animated: Bool) {
        guard LipstickSettings.presets.indices.contains(index),
              settingsState.selectedLipstickPresetIndex != index else {
            centerSelectedLipstickPreset(animated: animated)
            return
        }

        selectionFeedback.selectionChanged()
        clearLookSelection()
        settingsState.selectedLipstickPresetIndex = index
        applySelectedLipstickPreset(animated: animated, updatesSelector: true)
        centerSelectedLipstickPreset(animated: animated)
    }

    private func applySelectedLipstickPreset(animated: Bool, updatesSelector: Bool = true) {
        let intensity = clampedCGFloat(CGFloat(controlPanel.lipstickIntensitySlider.value), to: 0.2...1.0)
        settingsState.lipstickIntensityValue = intensity
        settingsState.rebuildLipstickSettings()

        applyLipstickSettings()
        persistSettings()

        if updatesSelector {
            updateVisibleLipstickCells(animated: animated)
        }
    }

    private func applySelectedBlushPreset(animated: Bool) {
        guard BlushSettings.presets.indices.contains(settingsState.selectedBlushPresetIndex) else { return }

        settingsState.blushSettings.intensity = CGFloat(controlPanel.blushIntensitySlider.value)
        settingsState.blushSettings.size = CGFloat(controlPanel.blushSizeSlider.value)
        settingsState.blushSettings.position = CGFloat(controlPanel.blushPositionSlider.value)
        settingsState.rebuildBlushSettings()

        applyBlushSettings()
        updateBlushPresetSelection(animated: animated)
        persistSettings()
    }

    private func applySelectedEyeshadowPreset(animated: Bool) {
        guard EyeshadowSettings.presets.indices.contains(settingsState.selectedEyeshadowPresetIndex) else { return }

        settingsState.eyeshadowSettings.intensity = CGFloat(controlPanel.eyeshadowIntensitySlider.value)
        settingsState.rebuildEyeshadowSettings()

        applyEyeshadowSettings()
        updateEyeshadowPresetSelection(animated: animated)
        persistSettings()
    }

    private func applySelectedGlowPreset(animated: Bool) {
        guard GlowSettings.presets.indices.contains(settingsState.selectedGlowPresetIndex) else { return }

        settingsState.glowSettings.intensity = CGFloat(controlPanel.glowIntensitySlider.value)
        settingsState.glowSettings.radius = CGFloat(controlPanel.glowRadiusSlider.value)
        settingsState.rebuildGlowSettings()

        applyGlowSettings()
        updateGlowPresetSelection(animated: animated)
        persistSettings()
    }

    private func applySelectedContourPreset(animated: Bool) {
        guard ContourSettings.presets.indices.contains(settingsState.selectedContourPresetIndex) else { return }

        settingsState.contourSettings.intensity = CGFloat(controlPanel.contourIntensitySlider.value)
        settingsState.rebuildContourSettings()

        applyContourSettings()
        updateContourPresetSelection(animated: animated)
        persistSettings()
    }

    private func updateBlushPresetSelection(animated: Bool) {
        controlPanel.updateBlushPresetSelection(selectedIndex: settingsState.selectedBlushPresetIndex, animated: animated)
    }

    private func updateEyeshadowPresetSelection(animated: Bool) {
        controlPanel.updateEyeshadowPresetSelection(selectedIndex: settingsState.selectedEyeshadowPresetIndex, animated: animated)
    }

    private func updateGlowPresetSelection(animated: Bool) {
        controlPanel.updateGlowPresetSelection(selectedIndex: settingsState.selectedGlowPresetIndex, animated: animated)
    }

    private func updateContourPresetSelection(animated: Bool) {
        controlPanel.updateContourPresetSelection(selectedIndex: settingsState.selectedContourPresetIndex, animated: animated)
    }

    private func centerSelectedLipstickPreset(animated: Bool) {
        guard LipstickSettings.presets.indices.contains(settingsState.selectedLipstickPresetIndex) else { return }
        guard lipstickCollectionNeedsScrolling else { return }
        controlPanel.lipstickCollectionView.layoutIfNeeded()

        let indexPath = IndexPath(item: settingsState.selectedLipstickPresetIndex, section: 0)
        guard let attributes = controlPanel.lipstickCollectionView.layoutAttributesForItem(at: indexPath) else { return }

        let proposedX = attributes.center.x - controlPanel.lipstickCollectionView.bounds.width * 0.5
        controlPanel.lipstickCollectionView.setContentOffset(clampedLipstickContentOffset(for: proposedX), animated: animated)
    }

    private func updateLipstickCollectionLayoutInsets() {
        let shouldScroll = lipstickCollectionNeedsScrolling
        controlPanel.lipstickCollectionView.isScrollEnabled = shouldScroll
        controlPanel.lipstickCollectionView.contentInset = .zero
    }

    private var lipstickCollectionNeedsScrolling: Bool {
        guard controlPanel.lipstickCollectionView.bounds.width > 0,
              let layout = controlPanel.lipstickCollectionView.collectionViewLayout as? UICollectionViewFlowLayout else {
            return false
        }

        let itemCount = CGFloat(LipstickSettings.presets.count)
        let contentWidth = itemCount * layout.itemSize.width + max(0, itemCount - 1) * layout.minimumLineSpacing
        return contentWidth > controlPanel.lipstickCollectionView.bounds.width
    }

    private func clampedLipstickContentOffset(for proposedX: CGFloat) -> CGPoint {
        let maxOffsetX = max(
            0,
            controlPanel.lipstickCollectionView.collectionViewLayout.collectionViewContentSize.width - controlPanel.lipstickCollectionView.bounds.width
        )
        let offsetX = clampedCGFloat(proposedX, to: 0...maxOffsetX)
        return CGPoint(x: offsetX, y: controlPanel.lipstickCollectionView.contentOffset.y)
    }

    private func updateSelectedLipstickPresetFromCenter(animated: Bool) {
        let visibleCenter = CGPoint(
            x: controlPanel.lipstickCollectionView.bounds.midX + controlPanel.lipstickCollectionView.contentOffset.x,
            y: controlPanel.lipstickCollectionView.bounds.midY
        )

        guard let indexPath = controlPanel.lipstickCollectionView.indexPathForItem(at: visibleCenter) ?? closestVisibleLipstickIndexPath(to: visibleCenter) else {
            return
        }

        selectLipstickPreset(at: indexPath.item, animated: animated)
    }

    private func closestVisibleLipstickIndexPath(to point: CGPoint) -> IndexPath? {
        controlPanel.lipstickCollectionView.indexPathsForVisibleItems.min { lhs, rhs in
            guard let lhsAttributes = controlPanel.lipstickCollectionView.layoutAttributesForItem(at: lhs),
                  let rhsAttributes = controlPanel.lipstickCollectionView.layoutAttributesForItem(at: rhs) else {
                return lhs.item < rhs.item
            }

            return abs(lhsAttributes.center.x - point.x) < abs(rhsAttributes.center.x - point.x)
        }
    }

    private func updateVisibleLipstickCells(animated: Bool) {
        for case let cell as MakeupLipstickPresetCell in controlPanel.lipstickCollectionView.visibleCells {
            guard let indexPath = controlPanel.lipstickCollectionView.indexPath(for: cell),
                  LipstickSettings.presets.indices.contains(indexPath.item) else {
                continue
            }

            cell.configure(
                preset: LipstickSettings.presets[indexPath.item],
                isSelected: indexPath.item == settingsState.selectedLipstickPresetIndex,
                animated: animated
            )
        }
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
        setBeforePreviewActive(false)
        if !Self.isDemoFeatureEnabled {
            experienceMode = .ar
        }

        experienceModeButton.setTitle(experienceButtonTitle, for: .normal)
        unsupportedDeviceLabel?.isHidden = (Self.isDemoFeatureEnabled && experienceMode == .demo) || ARFaceTrackingConfiguration.isSupported

        switch experienceMode {
        case .ar:
            startFaceTrackingSessionIfSupported()
        case .demo:
            startDemoFaceMode()
        }
    }

    private func startDemoFaceMode() {
        guard Self.isDemoFeatureEnabled else {
            startFaceTrackingSessionIfSupported()
            return
        }

        sceneView.session.pause()
        sceneView.delegate = nil
        sceneView.session.delegate = nil
        sceneView.isPlaying = false
        sceneView.isHidden = true
        resetARFaceFraming(animated: false)
        demoSceneView.isHidden = false
        demoSceneView.isPlaying = true
        modeButton.isHidden = true
        arAutoFramingButton.isHidden = true
        hairStyleButton.isHidden = true
        updateControlPanelForExperienceMode()
        demoHeadRenderer.updateHairColor(hue: settingsState.hairHueValue, strength: settingsState.hairStrengthValue)
        demoHeadRenderer.updateHairPlacement(y: settingsState.hairOffsetYValue, z: settingsState.hairOffsetZValue, scale: settingsState.hairScaleValue)
        demoHeadRenderer.setHeadHidden(controlPanel.hideHeadSwitch.isOn)
        demoHeadRenderer.setHairHidden(controlPanel.hideHairSwitch.isOn)
        demoHeadRenderer.setMakeupEnabled(!isBeforePreviewActive)
        applyBlushSettings()
        applyEyeshadowSettings()
        applyGlowSettings()
        startDemoTiltControl()
    }

    private func startFaceTrackingSessionIfSupported() {
        guard ARFaceTrackingConfiguration.isSupported else {
            print("AR face tracking is not supported on this device.")
            if Self.isDemoFeatureEnabled {
                experienceMode = .demo
                startDemoFaceMode()
                experienceModeButton.setTitle(experienceButtonTitle, for: .normal)
            } else {
                sceneView.session.pause()
                sceneView.delegate = nil
                sceneView.session.delegate = nil
                sceneView.isPlaying = false
                sceneView.isHidden = true
                demoSceneView.isHidden = true
                modeButton.isHidden = true
                arAutoFramingButton.isHidden = true
                hairStyleButton.isHidden = true
                updateControlPanelForExperienceMode()
            }
            return
        }

        demoSceneView.isHidden = true
        demoSceneView.isPlaying = false
        stopDemoTiltControl()
        sceneView.isHidden = false
        resetARFaceFraming(animated: false)
        sceneView.session.pause()
        sceneView.scene = SCNScene()
        sceneView.delegate = faceRenderer
        sceneView.automaticallyUpdatesLighting = true
        sceneView.isPlaying = true
        modeButton.isHidden = !Self.isDemoFeatureEnabled
        arAutoFramingButton.isHidden = false
        updateARAutoFramingButton()
        hairStyleButton.isHidden = true
        updateControlPanelForExperienceMode()
        faceRenderer.attach(to: sceneView)
        applyCurrentMakeupSettings(to: faceRenderer)
        faceRenderer.setMakeupEnabled(!isBeforePreviewActive)
        if Self.isDemoFeatureEnabled {
            demoHeadRenderer.setHeadHidden(false)
            demoHeadRenderer.setHairHidden(false)
        }

        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true

        // Face tracking uses the TrueDepth front camera and streams one
        // ARFaceAnchor per detected face into ARSCNViewDelegate callbacks.
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    private func updateARFaceFraming(faceBounds: CGRect) {
        guard experienceMode == .ar,
              settingsState.isARAutoFramingEnabled,
              !sceneView.isHidden,
              faceBounds.width > 1,
              faceBounds.height > 1,
              view.bounds.width > 1,
              view.bounds.height > 1 else {
            return
        }

        let targetTop = max(view.safeAreaInsets.top + 118, modeButton.frame.maxY + 12)
        let panelTop = controlPanel.frame.minY > 0 ? controlPanel.frame.minY : view.bounds.maxY
        let targetHeight = max(180, panelTop - targetTop - 18)
        let targetRect = CGRect(
            x: 18,
            y: targetTop,
            width: max(1, view.bounds.width - 36),
            height: targetHeight
        )

        let scaleToFitWidth = targetRect.width / faceBounds.width
        let scaleToFitHeight = targetRect.height / faceBounds.height
        var targetScale = min(1, scaleToFitWidth, scaleToFitHeight)

        if targetScale >= 1, !targetRect.contains(faceBounds) {
            // Leave a little virtual margin when the face fits but is drifting
            // toward the panel or top controls. The AR camera image and makeup
            // overlay are transformed together, so alignment stays intact.
            targetScale = 0.94
        }

        targetScale = clampedCGFloat(targetScale, to: 0.72...1.0)

        let viewCenter = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        let faceCenter = CGPoint(x: faceBounds.midX, y: faceBounds.midY)
        let scaledFaceCenter = CGPoint(
            x: viewCenter.x + targetScale * (faceCenter.x - viewCenter.x),
            y: viewCenter.y + targetScale * (faceCenter.y - viewCenter.y)
        )

        var targetTranslation = CGPoint(
            x: targetRect.midX - scaledFaceCenter.x,
            y: targetRect.midY - scaledFaceCenter.y
        )
        targetTranslation.x = clampedCGFloat(targetTranslation.x, to: -180...180)
        targetTranslation.y = clampedCGFloat(targetTranslation.y, to: -260...260)

        arFaceFramingScale = arFaceFramingScale * 0.86 + targetScale * 0.14
        arFaceFramingTranslation = CGPoint(
            x: arFaceFramingTranslation.x * 0.86 + targetTranslation.x * 0.14,
            y: arFaceFramingTranslation.y * 0.86 + targetTranslation.y * 0.14
        )

        sceneView.transform = CGAffineTransform(
            a: arFaceFramingScale,
            b: 0,
            c: 0,
            d: arFaceFramingScale,
            tx: arFaceFramingTranslation.x,
            ty: arFaceFramingTranslation.y
        )
    }

    private func resetARFaceFraming(animated: Bool) {
        arFaceFramingScale = 1
        arFaceFramingTranslation = .zero

        let updates = {
            self.sceneView.transform = .identity
        }

        if animated {
            UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: updates)
        } else {
            UIView.performWithoutAnimation(updates)
        }
    }

    private func startDemoTiltControl() {
        guard Self.isDemoFeatureEnabled else { return }

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
        if Self.isDemoFeatureEnabled {
            demoHeadRenderer.updateInspectionTilt(horizontal: 0)
        }
    }

    private func applyLipstickSettings() {
        makeupRenderers.forEach { $0.updateLipstickSettings(settingsState.lipstickSettings) }
    }

    private func applyBlushSettings() {
        makeupRenderers.forEach { $0.updateBlushSettings(settingsState.blushSettings) }
    }

    private func applyEyeshadowSettings() {
        makeupRenderers.forEach { $0.updateEyeshadowSettings(settingsState.eyeshadowSettings) }
    }

    private func applyGlowSettings() {
        makeupRenderers.forEach { $0.updateGlowSettings(settingsState.glowSettings) }
    }

    private func applyContourSettings() {
        makeupRenderers.forEach { $0.updateContourSettings(settingsState.contourSettings) }
    }

    private func setMakeupEnabledForAllRenderers(_ enabled: Bool) {
        makeupRenderers.forEach { $0.setMakeupEnabled(enabled) }
    }

    private func applyCurrentMakeupSettings(to renderer: MakeupRendering) {
        renderer.updateLipstickSettings(settingsState.lipstickSettings)
        renderer.updateBlushSettings(settingsState.blushSettings)
        renderer.updateEyeshadowSettings(settingsState.eyeshadowSettings)
        renderer.updateGlowSettings(settingsState.glowSettings)
        renderer.updateContourSettings(settingsState.contourSettings)
    }

    func applyLook(_ look: MakeupLook, animated: Bool) {
        guard let lipIndex = look.lipstickIndex(),
              let blushIndex = look.blushIndex(),
              let eyesIndex = look.eyesIndex() else { return }

        if animated {
            lookFeedback.impactOccurred(intensity: 0.65)
        }

        settingsState.selectedLipstickPresetIndex = lipIndex
        settingsState.selectedBlushPresetIndex = blushIndex
        settingsState.selectedEyeshadowPresetIndex = eyesIndex
        if let glowIndex = look.glowIndex() {
            settingsState.selectedGlowPresetIndex = glowIndex
        }
        if let contourIndex = look.contourIndex() {
            settingsState.selectedContourPresetIndex = contourIndex
        }
        settingsState.lipstickFinish = look.lipstickFinish
        settingsState.lipstickIntensityValue = look.lipstickIntensity
        settingsState.blushSettings.intensity = look.blushIntensity
        settingsState.blushSettings.size = look.blushSize
        settingsState.blushSettings.position = look.blushPosition
        settingsState.eyeshadowSettings.intensity = look.eyesIntensity
        settingsState.glowSettings.intensity = look.glowIntensity
        settingsState.glowSettings.radius = look.glow.map { CGFloat($0.radius) } ?? GlowSettings.default.radius
        settingsState.contourSettings.intensity = look.contourIntensity
        settingsState.rebuildLipstickSettings()
        settingsState.rebuildBlushSettings()
        settingsState.rebuildEyeshadowSettings()
        if let glow = look.glow {
            settingsState.applyGlowPreset(glow, intensity: look.glowIntensity)
        } else {
            settingsState.rebuildGlowSettings()
        }
        if let contour = look.contour {
            settingsState.applyContourPreset(contour, intensity: look.contourIntensity)
        } else {
            settingsState.rebuildContourSettings()
        }

        syncControlPanelToState()

        selectedLookID = look.id
        refreshLooksSelection(animated: animated)

        let duration = animated ? 0.25 : 0.0
        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration
        applyLipstickSettings()
        applyBlushSettings()
        applyEyeshadowSettings()
        applyGlowSettings()
        applyContourSettings()
        SCNTransaction.commit()

        persistSettings()
    }

    private func syncControlPanelToState() {
        controlPanel.lipstickIntensitySlider.setValue(Float(settingsState.lipstickIntensityValue), animated: true)
        controlPanel.lipstickFinishSegmentedControl.selectedSegmentIndex = settingsState.lipstickFinish.rawValue
        controlPanel.blushIntensitySlider.setValue(Float(settingsState.blushSettings.intensity), animated: true)
        controlPanel.blushSizeSlider.setValue(Float(settingsState.blushSettings.size), animated: true)
        controlPanel.blushPositionSlider.setValue(Float(settingsState.blushSettings.position), animated: true)
        controlPanel.eyeshadowIntensitySlider.setValue(Float(settingsState.eyeshadowSettings.intensity), animated: true)
        controlPanel.glowIntensitySlider.setValue(Float(settingsState.glowSettings.intensity), animated: true)
        controlPanel.glowRadiusSlider.setValue(Float(settingsState.glowSettings.radius), animated: true)
        controlPanel.contourIntensitySlider.setValue(Float(settingsState.contourSettings.intensity), animated: true)
        controlPanel.updateBlushPresetSelection(selectedIndex: settingsState.selectedBlushPresetIndex, animated: true)
        controlPanel.updateEyeshadowPresetSelection(selectedIndex: settingsState.selectedEyeshadowPresetIndex, animated: true)
        controlPanel.updateGlowPresetSelection(selectedIndex: settingsState.selectedGlowPresetIndex, animated: true)
        controlPanel.updateContourPresetSelection(selectedIndex: settingsState.selectedContourPresetIndex, animated: true)
        updateVisibleLipstickCells(animated: true)
        centerSelectedLipstickPreset(animated: true)
    }

    private func refreshLooksSelection(animated: Bool) {
        let collectionView = controlPanel.looksCollectionView
        for case let cell as MakeupLookCell in collectionView.visibleCells {
            guard let indexPath = collectionView.indexPath(for: cell) else { continue }
            let look = MakeupLooks.all[indexPath.item]
            cell.configure(look: look, isSelected: look.id == selectedLookID, animated: animated)
        }
    }

    private func clearLookSelection() {
        guard selectedLookID != nil else { return }
        selectedLookID = nil
        refreshLooksSelection(animated: true)
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

private func clampedCGFloat(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
    Swift.min(Swift.max(value, range.lowerBound), range.upperBound)
}

extension FaceMakeupViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView === controlPanel.looksCollectionView {
            return MakeupLooks.all.count
        }
        return LipstickSettings.presets.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if collectionView === controlPanel.looksCollectionView {
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: MakeupLookCell.reuseIdentifier,
                for: indexPath
            ) as? MakeupLookCell else {
                return UICollectionViewCell()
            }
            let look = MakeupLooks.all[indexPath.item]
            cell.configure(look: look, isSelected: look.id == selectedLookID, animated: false)
            return cell
        }

        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: MakeupLipstickPresetCell.reuseIdentifier,
            for: indexPath
        ) as? MakeupLipstickPresetCell else {
            return UICollectionViewCell()
        }

        let isSelected = indexPath.item == settingsState.selectedLipstickPresetIndex
        cell.configure(preset: LipstickSettings.presets[indexPath.item], isSelected: isSelected, animated: false)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if collectionView === controlPanel.looksCollectionView {
            applyLook(MakeupLooks.all[indexPath.item], animated: true)
            return
        }
        selectLipstickPreset(at: indexPath.item, animated: true)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === controlPanel.lipstickCollectionView else { return }
        updateSelectedLipstickPresetFromCenter(animated: true)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === controlPanel.lipstickCollectionView else { return }
        if !decelerate {
            updateSelectedLipstickPresetFromCenter(animated: true)
        }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        guard scrollView === controlPanel.lipstickCollectionView else { return }
        updateVisibleLipstickCells(animated: true)
    }
}
