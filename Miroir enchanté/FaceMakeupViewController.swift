//
//  FaceMakeupViewController.swift
//  Miroir enchanté
//

import ARKit
import CoreMotion
import SceneKit
import UIKit

private enum CosmeticTheme {
    static let gold = UIColor(red: 0.96, green: 0.73, blue: 0.45, alpha: 1.0)
    static let softGold = UIColor(red: 1.0, green: 0.84, blue: 0.62, alpha: 1.0)
    static let panelBackground = UIColor.black.withAlphaComponent(0.74)
    static let controlBackground = UIColor.black.withAlphaComponent(0.58)
    static let dimText = UIColor.white.withAlphaComponent(0.66)
}

/// Owns the camera view and AR session lifecycle.
/// Rendering decisions live in FaceRenderer so the UI stays small and clear.
final class FaceMakeupViewController: UIViewController {
    private enum ExperienceMode {
        case ar
        case demo
    }

    private enum ControlTab: Int {
        case lipstick = 0
        case blush = 1
        case hair = 2
        case debug = 3
    }

    private enum LipstickFinish: Int {
        case matte = 0
        case satin = 1
        case glossy = 2
    }

    private enum SettingsKey {
        static let prefix = "FaceMakeupViewController."
        static let arAutoFramingEnabled = prefix + "arAutoFramingEnabled"
        static let selectedLipstickPresetIndex = prefix + "selectedLipstickPresetIndex"
        static let lipstickIntensity = prefix + "lipstickIntensity"
        static let lipstickFinish = prefix + "lipstickFinish"
        static let selectedBlushPresetIndex = prefix + "selectedBlushPresetIndex"
        static let blushIntensity = prefix + "blushIntensity"
        static let blushSize = prefix + "blushSize"
        static let blushPosition = prefix + "blushPosition"
        static let hairHue = prefix + "hairHue"
        static let hairStrength = prefix + "hairStrength"
        static let hairOffsetY = prefix + "hairOffsetY"
        static let hairOffsetZ = prefix + "hairOffsetZ"
        static let hairScale = prefix + "hairScale"
        static let hideHead = prefix + "hideHead"
        static let hideHair = prefix + "hideHair"
    }

    private let sceneView = ARSCNView(frame: .zero)
    private let demoSceneView = SCNView(frame: .zero)
    private let faceRenderer = FaceRenderer()
    private let demoHeadRenderer = DemoHeadRenderer(assetFilename: "Female head.obj")
    private let motionManager = CMMotionManager()
    private let modeButton = UIButton(type: .system)
    private let experienceModeButton = UIButton(type: .system)
    private let hairStyleButton = UIButton(type: .system)
    private let arAutoFramingButton = UIButton(type: .system)
    private let beforeAfterButton = UIButton(type: .system)
    private let controlsSegmentedControl = UISegmentedControl(items: ["Lipstick", "Blush", "Hair", "Debug"])
    private let controlsStackView = UIStackView()
    private let lipstickIntensitySlider = UISlider()
    private let lipstickFinishSegmentedControl = UISegmentedControl(items: ["Mat", "Satiné", "Brillant"])
    private let lipstickCollectionView: UICollectionView = {
        let layout = LipstickSnapFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 12
        layout.itemSize = CGSize(width: 76, height: 130)

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.decelerationRate = .fast
        collectionView.clipsToBounds = false
        return collectionView
    }()
    private let blushIntensitySlider = UISlider()
    private let blushSizeSlider = UISlider()
    private let blushPositionSlider = UISlider()
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
    private var blushControlRows: [UIView] = []
    private var blushPresetButtons: [UIButton] = []
    private var hairControlRows: [UIView] = []
    private var debugControlRows: [UIView] = []

    private var unsupportedDeviceLabel: UILabel?
    private var experienceMode: ExperienceMode = ARFaceTrackingConfiguration.isSupported ? .ar : .demo
    private var lipstickSettings = LipstickSettings.default
    private var lipstickFinish: LipstickFinish = .satin
    private var selectedLipstickPresetIndex = 3
    private var lipstickIntensityValue: CGFloat = 0.9
    private var didCenterInitialLipstickPreset = false
    private var blushSettings = BlushSettings.default
    private var selectedBlushPresetIndex = 2
    private var hairHueValue: CGFloat = 0.24
    private var hairStrengthValue: CGFloat = 0.84
    private var hairOffsetYValue: Float = -0.08
    private var hairOffsetZValue: Float = 0.15
    private var hairScaleValue: Float = 1.0
    private var selectedControlTab: ControlTab = .lipstick
    private var visibleControlTabs: [ControlTab] = [.lipstick, .blush, .hair, .debug]
    private var smoothedInspectionTilt: CGFloat = 0
    private var isBeforePreviewActive = false
    private var isARAutoFramingEnabled = false
    private var arFaceFramingScale: CGFloat = 1
    private var arFaceFramingTranslation: CGPoint = .zero

    override func viewDidLoad() {
        super.viewDidLoad()

        loadPersistedSettings()
        configureSceneView()
        configureModeButton()
        configureExperienceModeButton()
        configureHairStyleButton()
        configureARAutoFramingButton()
        configureMakeupControls()
        configureBeforeAfterButton()
        configureUnsupportedDeviceMessageIfNeeded()
        applyLipstickSettings()
        applyBlushSettings()
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

        updateLipstickCollectionLayoutInsets()

        guard !didCenterInitialLipstickPreset, lipstickCollectionView.bounds.width > 0 else { return }
        didCenterInitialLipstickPreset = true
        centerSelectedLipstickPreset(animated: false)
        updateVisibleLipstickCells(animated: false)
    }

    private func loadPersistedSettings() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            SettingsKey.arAutoFramingEnabled: false,
            SettingsKey.selectedLipstickPresetIndex: selectedLipstickPresetIndex,
            SettingsKey.lipstickIntensity: Double(lipstickIntensityValue),
            SettingsKey.lipstickFinish: lipstickFinish.rawValue,
            SettingsKey.selectedBlushPresetIndex: selectedBlushPresetIndex,
            SettingsKey.blushIntensity: Double(blushSettings.intensity),
            SettingsKey.blushSize: Double(blushSettings.size),
            SettingsKey.blushPosition: Double(blushSettings.position),
            SettingsKey.hairHue: Double(hairHueValue),
            SettingsKey.hairStrength: Double(hairStrengthValue),
            SettingsKey.hairOffsetY: Double(hairOffsetYValue),
            SettingsKey.hairOffsetZ: Double(hairOffsetZValue),
            SettingsKey.hairScale: Double(hairScaleValue),
            SettingsKey.hideHead: false,
            SettingsKey.hideHair: false
        ])

        isARAutoFramingEnabled = defaults.bool(forKey: SettingsKey.arAutoFramingEnabled)
        selectedLipstickPresetIndex = defaults.integer(forKey: SettingsKey.selectedLipstickPresetIndex)
        if !LipstickSettings.presets.indices.contains(selectedLipstickPresetIndex) {
            selectedLipstickPresetIndex = 3
        }

        lipstickIntensityValue = CGFloat(defaults.double(forKey: SettingsKey.lipstickIntensity)).clamped(to: 0.4...1.0)
        lipstickFinish = LipstickFinish(rawValue: defaults.integer(forKey: SettingsKey.lipstickFinish)) ?? .satin

        selectedBlushPresetIndex = defaults.integer(forKey: SettingsKey.selectedBlushPresetIndex)
        if !BlushSettings.presets.indices.contains(selectedBlushPresetIndex) {
            selectedBlushPresetIndex = 2
        }

        blushSettings.intensity = CGFloat(defaults.double(forKey: SettingsKey.blushIntensity)).clamped(to: 0...1)
        blushSettings.size = CGFloat(defaults.double(forKey: SettingsKey.blushSize)).clamped(to: 0.65...1.45)
        blushSettings.position = CGFloat(defaults.double(forKey: SettingsKey.blushPosition)).clamped(to: 0...1)
        hairHueValue = CGFloat(defaults.double(forKey: SettingsKey.hairHue)).clamped(to: 0...1)
        hairStrengthValue = CGFloat(defaults.double(forKey: SettingsKey.hairStrength)).clamped(to: 0...1)
        hairOffsetYValue = Float(CGFloat(defaults.double(forKey: SettingsKey.hairOffsetY)).clamped(to: -3...1))
        hairOffsetZValue = Float(CGFloat(defaults.double(forKey: SettingsKey.hairOffsetZ)).clamped(to: -1...5))
        hairScaleValue = Float(CGFloat(defaults.double(forKey: SettingsKey.hairScale)).clamped(to: 0.15...2.0))
    }

    private func persistSettings() {
        let defaults = UserDefaults.standard
        defaults.set(isARAutoFramingEnabled, forKey: SettingsKey.arAutoFramingEnabled)
        defaults.set(selectedLipstickPresetIndex, forKey: SettingsKey.selectedLipstickPresetIndex)
        defaults.set(Double(lipstickIntensityValue), forKey: SettingsKey.lipstickIntensity)
        defaults.set(lipstickFinish.rawValue, forKey: SettingsKey.lipstickFinish)
        defaults.set(selectedBlushPresetIndex, forKey: SettingsKey.selectedBlushPresetIndex)
        defaults.set(Double(blushSettings.intensity), forKey: SettingsKey.blushIntensity)
        defaults.set(Double(blushSettings.size), forKey: SettingsKey.blushSize)
        defaults.set(Double(blushSettings.position), forKey: SettingsKey.blushPosition)
        defaults.set(Double(hairHueValue), forKey: SettingsKey.hairHue)
        defaults.set(Double(hairStrengthValue), forKey: SettingsKey.hairStrength)
        defaults.set(Double(hairOffsetYValue), forKey: SettingsKey.hairOffsetY)
        defaults.set(Double(hairOffsetZValue), forKey: SettingsKey.hairOffsetZ)
        defaults.set(Double(hairScaleValue), forKey: SettingsKey.hairScale)
        defaults.set(hideHeadSwitch.isOn, forKey: SettingsKey.hideHead)
        defaults.set(hideHairSwitch.isOn, forKey: SettingsKey.hideHair)
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
            arAutoFramingButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            arAutoFramingButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 68),
            arAutoFramingButton.widthAnchor.constraint(equalToConstant: 44),
            arAutoFramingButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func configureBeforeAfterButton() {
        beforeAfterButton.translatesAutoresizingMaskIntoConstraints = false
        beforeAfterButton.setTitle("Avant / Après", for: .normal)
        beforeAfterButton.setImage(UIImage(systemName: "rectangle.split.2x1"), for: .normal)
        beforeAfterButton.tintColor = CosmeticTheme.softGold
        beforeAfterButton.semanticContentAttribute = .forceLeftToRight
        styleFloatingButton(beforeAfterButton)
        beforeAfterButton.addTarget(self, action: #selector(showBeforePreview), for: .touchDown)
        beforeAfterButton.addTarget(self, action: #selector(showAfterPreview), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        view.addSubview(beforeAfterButton)
        NSLayoutConstraint.activate([
            beforeAfterButton.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            beforeAfterButton.bottomAnchor.constraint(equalTo: controlsStackView.topAnchor, constant: -10),
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
        lipstickIntensitySlider.minimumValue = 0.4
        lipstickIntensitySlider.maximumValue = 1.0
        lipstickIntensitySlider.value = Float(lipstickIntensityValue.clamped(to: 0.4...1.0))
        lipstickIntensitySlider.isContinuous = true
        lipstickIntensitySlider.addTarget(self, action: #selector(lipstickIntensityChanged), for: .valueChanged)

        lipstickFinishSegmentedControl.selectedSegmentIndex = lipstickFinish.rawValue
        lipstickFinishSegmentedControl.selectedSegmentTintColor = CosmeticTheme.gold.withAlphaComponent(0.20)
        lipstickFinishSegmentedControl.setTitleTextAttributes([.foregroundColor: CosmeticTheme.dimText], for: .normal)
        lipstickFinishSegmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        lipstickFinishSegmentedControl.addTarget(self, action: #selector(lipstickFinishChanged), for: .valueChanged)

        lipstickCollectionView.dataSource = self
        lipstickCollectionView.delegate = self
        lipstickCollectionView.register(LipstickPresetCell.self, forCellWithReuseIdentifier: LipstickPresetCell.reuseIdentifier)

        blushIntensitySlider.minimumValue = 0.0
        blushIntensitySlider.maximumValue = 1.0
        blushIntensitySlider.value = Float(blushSettings.intensity)
        blushIntensitySlider.isContinuous = true
        blushIntensitySlider.addTarget(self, action: #selector(blushSliderChanged), for: .valueChanged)

        blushSizeSlider.minimumValue = 0.65
        blushSizeSlider.maximumValue = 1.45
        blushSizeSlider.value = Float(blushSettings.size)
        blushSizeSlider.isContinuous = true
        blushSizeSlider.addTarget(self, action: #selector(blushSliderChanged), for: .valueChanged)

        blushPositionSlider.minimumValue = 0.0
        blushPositionSlider.maximumValue = 1.0
        blushPositionSlider.value = Float(blushSettings.position)
        blushPositionSlider.isContinuous = true
        blushPositionSlider.addTarget(self, action: #selector(blushSliderChanged), for: .valueChanged)

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
        hideHeadSwitch.isOn = UserDefaults.standard.bool(forKey: SettingsKey.hideHead)
        hideHairSwitch.isOn = UserDefaults.standard.bool(forKey: SettingsKey.hideHair)

        [
            lipstickIntensitySlider,
            blushIntensitySlider,
            blushSizeSlider,
            blushPositionSlider,
            hairHueSlider,
            hairStrengthSlider,
            hairOffsetYSlider,
            hairOffsetZSlider,
            hairScaleSlider
        ].forEach(styleSlider)

        controlsSegmentedControl.selectedSegmentIndex = selectedControlTab.rawValue
        controlsSegmentedControl.selectedSegmentTintColor = CosmeticTheme.gold.withAlphaComponent(0.22)
        controlsSegmentedControl.setTitleTextAttributes([.foregroundColor: CosmeticTheme.dimText], for: .normal)
        controlsSegmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        controlsSegmentedControl.addTarget(self, action: #selector(controlTabChanged), for: .valueChanged)

        let lipstickSelectorRow = makeLipstickSelectorRow()
        let lipstickIntensityRow = makeSliderRow(title: L10n.text("control.intensity"), slider: lipstickIntensitySlider)
        let lipstickFinishRow = makeFinishRow()
        let blushSelectorRow = makeBlushSelectorRow()
        let blushIntensityRow = makeSliderRow(title: L10n.text("control.intensity"), slider: blushIntensitySlider)
        let blushSizeRow = makeSliderRow(title: L10n.text("control.size"), slider: blushSizeSlider)
        let blushPositionRow = makeSliderRow(title: L10n.text("control.position"), slider: blushPositionSlider)
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

        lipstickControlRows = [lipstickSelectorRow, lipstickIntensityRow, lipstickFinishRow]
        blushControlRows = [blushSelectorRow, blushIntensityRow, blushSizeRow, blushPositionRow]
        hairControlRows = [hairRow]
        debugControlRows = [hairOffsetYRow, hairOffsetZRow, hairScaleRow, visibilityRow]

        controlsStackView.translatesAutoresizingMaskIntoConstraints = false
        controlsStackView.axis = .vertical
        controlsStackView.spacing = 8
        controlsStackView.alignment = .fill
        controlsStackView.backgroundColor = CosmeticTheme.panelBackground
        controlsStackView.layer.cornerRadius = 0
        controlsStackView.isLayoutMarginsRelativeArrangement = true
        controlsStackView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 14, leading: 28, bottom: 8, trailing: 28)

        controlsStackView.addArrangedSubview(controlsSegmentedControl)
        controlsStackView.addArrangedSubview(lipstickSelectorRow)
        controlsStackView.addArrangedSubview(lipstickIntensityRow)
        controlsStackView.addArrangedSubview(lipstickFinishRow)
        controlsStackView.addArrangedSubview(blushSelectorRow)
        controlsStackView.addArrangedSubview(blushIntensityRow)
        controlsStackView.addArrangedSubview(blushSizeRow)
        controlsStackView.addArrangedSubview(blushPositionRow)
        controlsStackView.addArrangedSubview(hairRow)
        controlsStackView.addArrangedSubview(hairOffsetYRow)
        controlsStackView.addArrangedSubview(hairOffsetZRow)
        controlsStackView.addArrangedSubview(hairScaleRow)
        controlsStackView.addArrangedSubview(visibilityRow)
        updateControlTabAvailability()
        updateControlTabVisibility()

        view.addSubview(controlsStackView)
        NSLayoutConstraint.activate([
            controlsStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlsStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlsStackView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        applySelectedLipstickPreset(animated: false)
        applySelectedBlushPreset(animated: false)
    }

    private func styleSlider(_ slider: UISlider) {
        slider.minimumTrackTintColor = CosmeticTheme.gold
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.13)
        slider.thumbTintColor = UIColor(red: 1.0, green: 0.89, blue: 0.72, alpha: 1.0)
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

    private func makeLipstickSelectorRow() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        lipstickCollectionView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(lipstickCollectionView)

        NSLayoutConstraint.activate([
            lipstickCollectionView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            lipstickCollectionView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            lipstickCollectionView.topAnchor.constraint(equalTo: container.topAnchor),
            lipstickCollectionView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.heightAnchor.constraint(equalToConstant: 134)
        ])

        return container
    }

    private func makeBlushSelectorRow() -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 6
        container.alignment = .fill

        let presetsRow = UIStackView()
        presetsRow.axis = .horizontal
        presetsRow.spacing = 10
        presetsRow.distribution = .fillEqually
        presetsRow.alignment = .top

        blushPresetButtons = []
        for (index, preset) in BlushSettings.presets.enumerated() {
            let item = makeBlushPresetItem(preset: preset, index: index)
            presetsRow.addArrangedSubview(item)
        }

        container.addArrangedSubview(presetsRow)
        return container
    }

    private func makeBlushPresetItem(preset: BlushPreset, index: Int) -> UIStackView {
        let button = UIButton(type: .system)
        button.tag = index
        button.backgroundColor = preset.baseColor
        button.layer.cornerRadius = 22
        button.layer.borderWidth = index == selectedBlushPresetIndex ? 2 : 0
        button.layer.borderColor = CosmeticTheme.gold.cgColor
        button.addTarget(self, action: #selector(blushPresetTapped(_:)), for: .touchUpInside)
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        blushPresetButtons.append(button)

        let label = UILabel()
        label.text = L10n.text(preset.titleKey)
        label.textColor = UIColor.white.withAlphaComponent(index == selectedBlushPresetIndex ? 0.95 : 0.66)
        label.font = .preferredFont(forTextStyle: .caption2)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.65

        let item = UIStackView(arrangedSubviews: [button, label])
        item.axis = .vertical
        item.spacing = 5
        item.alignment = .center
        return item
    }

    private func makeFinishRow() -> UIStackView {
        let label = UILabel()
        label.text = L10n.text("control.finish")
        label.textColor = .white
        label.font = .preferredFont(forTextStyle: .caption1)
        label.widthAnchor.constraint(equalToConstant: 64).isActive = true

        let row = UIStackView(arrangedSubviews: [label, lipstickFinishSegmentedControl])
        row.axis = .horizontal
        row.spacing = 10
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

    @objc private func toggleRenderMode() {
        let mode = faceRenderer.toggleMode()
        modeButton.setTitle(mode.buttonTitle, for: .normal)
    }

    @objc private func toggleARAutoFraming() {
        isARAutoFramingEnabled.toggle()
        updateARAutoFramingButton()
        persistSettings()

        if !isARAutoFramingEnabled {
            resetARFaceFraming(animated: true)
        }
    }

    private func updateARAutoFramingButton() {
        arAutoFramingButton.isSelected = isARAutoFramingEnabled
        arAutoFramingButton.tintColor = isARAutoFramingEnabled ? CosmeticTheme.softGold : UIColor.white.withAlphaComponent(0.62)
        arAutoFramingButton.layer.borderColor = (isARAutoFramingEnabled ? CosmeticTheme.gold : UIColor.white.withAlphaComponent(0.08)).cgColor
        arAutoFramingButton.backgroundColor = isARAutoFramingEnabled
            ? CosmeticTheme.gold.withAlphaComponent(0.18)
            : CosmeticTheme.controlBackground
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

    @objc private func showBeforePreview() {
        setBeforePreviewActive(true)
    }

    @objc private func showAfterPreview() {
        setBeforePreviewActive(false)
    }

    private func setBeforePreviewActive(_ active: Bool) {
        isBeforePreviewActive = active
        faceRenderer.setMakeupEnabled(!active)
        demoHeadRenderer.setMakeupEnabled(!active)
        UIView.animate(withDuration: 0.14) {
            self.beforeAfterButton.alpha = active ? 0.64 : 1.0
        }
    }

    @objc private func lipstickIntensityChanged() {
        applySelectedLipstickPreset(animated: false, updatesSelector: false)
    }

    @objc private func lipstickFinishChanged() {
        lipstickFinish = LipstickFinish(rawValue: lipstickFinishSegmentedControl.selectedSegmentIndex) ?? .satin
        applySelectedLipstickPreset(animated: true, updatesSelector: false)
    }

    @objc private func blushPresetTapped(_ sender: UIButton) {
        guard BlushSettings.presets.indices.contains(sender.tag) else { return }
        selectedBlushPresetIndex = sender.tag
        applySelectedBlushPreset(animated: true)
    }

    @objc private func blushSliderChanged() {
        blushSettings.intensity = CGFloat(blushIntensitySlider.value)
        blushSettings.size = CGFloat(blushSizeSlider.value)
        blushSettings.position = CGFloat(blushPositionSlider.value)
        applyBlushSettings()
        persistSettings()
    }

    @objc private func hairSliderChanged() {
        hairHueValue = CGFloat(hairHueSlider.value)
        hairStrengthValue = CGFloat(hairStrengthSlider.value)
        demoHeadRenderer.updateHairColor(hue: hairHueValue, strength: hairStrengthValue)
        persistSettings()
    }

    @objc private func hairOffsetSliderChanged() {
        hairOffsetYValue = hairOffsetYSlider.value
        hairOffsetZValue = hairOffsetZSlider.value
        hairScaleValue = hairScaleSlider.value
        updateHairOffsetValueLabels()
        demoHeadRenderer.updateHairPlacement(y: hairOffsetYValue, z: hairOffsetZValue, scale: hairScaleValue)
        persistSettings()
    }

    private func updateHairOffsetValueLabels() {
        hairOffsetYValueLabel.text = String(format: "%.2f", hairOffsetYSlider.value)
        hairOffsetZValueLabel.text = String(format: "%.2f", hairOffsetZSlider.value)
        hairScaleValueLabel.text = String(format: "%.2f", hairScaleSlider.value)
    }

    @objc private func controlTabChanged() {
        let selectedIndex = controlsSegmentedControl.selectedSegmentIndex
        selectedControlTab = visibleControlTabs.indices.contains(selectedIndex) ? visibleControlTabs[selectedIndex] : .lipstick
        updateControlTabVisibility()
    }

    private func updateControlTabAvailability() {
        let demoControlsEnabled = experienceMode == .demo
        let nextTabs: [ControlTab] = demoControlsEnabled ? [.lipstick, .blush, .hair, .debug] : [.lipstick, .blush]
        controlsSegmentedControl.isHidden = false

        if !demoControlsEnabled && (selectedControlTab == .hair || selectedControlTab == .debug) {
            selectedControlTab = .lipstick
        }

        if visibleControlTabs != nextTabs {
            controlsSegmentedControl.removeAllSegments()
            for (index, tab) in nextTabs.enumerated() {
                controlsSegmentedControl.insertSegment(withTitle: controlTabTitle(tab), at: index, animated: false)
            }
            visibleControlTabs = nextTabs
        }

        controlsSegmentedControl.selectedSegmentIndex = visibleControlTabs.firstIndex(of: selectedControlTab) ?? 0
    }

    private func controlTabTitle(_ tab: ControlTab) -> String {
        switch tab {
        case .lipstick:
            return "Lipstick"
        case .blush:
            return "Blush"
        case .hair:
            return "Hair"
        case .debug:
            return "Debug"
        }
    }

    private func updateControlTabVisibility() {
        lipstickControlRows.forEach { $0.isHidden = selectedControlTab != .lipstick }

        let demoControlsEnabled = experienceMode == .demo
        blushControlRows.forEach { $0.isHidden = selectedControlTab != .blush }
        hairControlRows.forEach { $0.isHidden = selectedControlTab != .hair || !demoControlsEnabled }
        debugControlRows.forEach { $0.isHidden = selectedControlTab != .debug || !demoControlsEnabled }
    }

    @objc private func hideHeadSwitchChanged() {
        demoHeadRenderer.setHeadHidden(hideHeadSwitch.isOn)
        persistSettings()
    }

    @objc private func hideHairSwitchChanged() {
        demoHeadRenderer.setHairHidden(hideHairSwitch.isOn)
        persistSettings()
    }

    private func selectLipstickPreset(at index: Int, animated: Bool) {
        guard LipstickSettings.presets.indices.contains(index),
              selectedLipstickPresetIndex != index else {
            centerSelectedLipstickPreset(animated: animated)
            return
        }

        selectedLipstickPresetIndex = index
        applySelectedLipstickPreset(animated: animated, updatesSelector: true)
        centerSelectedLipstickPreset(animated: animated)
    }

    private func applySelectedLipstickPreset(animated: Bool, updatesSelector: Bool = true) {
        guard LipstickSettings.presets.indices.contains(selectedLipstickPresetIndex) else { return }

        let preset = LipstickSettings.presets[selectedLipstickPresetIndex]
        let intensity = CGFloat(lipstickIntensitySlider.value).clamped(to: 0.2...1.0)
        lipstickIntensityValue = intensity

        lipstickSettings.color = preset.baseColor
        lipstickSettings.opacity = CGFloat(preset.opacity) * intensity
        lipstickSettings.roughness = lipstickRoughness(for: preset)
        lipstickSettings.glossIntensity = lipstickGlossIntensity(for: preset)
        lipstickSettings.colorIntensity = 1.0

        applyLipstickSettings()
        persistSettings()

        if updatesSelector {
            updateVisibleLipstickCells(animated: animated)
        }
    }

    private func lipstickRoughness(for preset: LipstickPreset) -> CGFloat {
        switch lipstickFinish {
        case .matte:
            return max(CGFloat(preset.roughness), 0.62)
        case .satin:
            return CGFloat(preset.roughness).clamped(to: 0.24...0.44)
        case .glossy:
            return min(CGFloat(preset.roughness), 0.18)
        }
    }

    private func lipstickGlossIntensity(for preset: LipstickPreset) -> CGFloat {
        switch lipstickFinish {
        case .matte:
            return 0.10
        case .satin:
            return CGFloat(1.0 - preset.roughness).clamped(to: 0.30...0.52)
        case .glossy:
            return 0.78
        }
    }

    private func applySelectedBlushPreset(animated: Bool) {
        guard BlushSettings.presets.indices.contains(selectedBlushPresetIndex) else { return }

        let preset = BlushSettings.presets[selectedBlushPresetIndex]
        blushSettings.color = preset.baseColor
        blushSettings.opacity = CGFloat(preset.opacity)
        blushSettings.roughness = CGFloat(preset.roughness)
        blushSettings.intensity = CGFloat(blushIntensitySlider.value)
        blushSettings.size = CGFloat(blushSizeSlider.value)
        blushSettings.position = CGFloat(blushPositionSlider.value)

        applyBlushSettings()
        updateBlushPresetSelection(animated: animated)
        persistSettings()
    }

    private func updateBlushPresetSelection(animated: Bool) {
        for button in blushPresetButtons {
            let isSelected = button.tag == selectedBlushPresetIndex
            let updates = {
                button.transform = isSelected ? CGAffineTransform(scaleX: 1.12, y: 1.12) : .identity
                button.layer.borderWidth = isSelected ? 2 : 0
                button.layer.borderColor = CosmeticTheme.gold.cgColor
            }

            if animated {
                UIView.animate(withDuration: 0.18, delay: 0, options: [.allowUserInteraction, .curveEaseOut], animations: updates)
            } else {
                updates()
            }
        }
    }

    private func centerSelectedLipstickPreset(animated: Bool) {
        guard LipstickSettings.presets.indices.contains(selectedLipstickPresetIndex) else { return }
        guard lipstickCollectionNeedsScrolling else { return }
        lipstickCollectionView.layoutIfNeeded()

        let indexPath = IndexPath(item: selectedLipstickPresetIndex, section: 0)
        guard let attributes = lipstickCollectionView.layoutAttributesForItem(at: indexPath) else { return }

        let proposedX = attributes.center.x - lipstickCollectionView.bounds.width * 0.5
        lipstickCollectionView.setContentOffset(clampedLipstickContentOffset(for: proposedX), animated: animated)
    }

    private func updateLipstickCollectionLayoutInsets() {
        let shouldScroll = lipstickCollectionNeedsScrolling
        lipstickCollectionView.isScrollEnabled = shouldScroll
        lipstickCollectionView.contentInset = .zero
    }

    private var lipstickCollectionNeedsScrolling: Bool {
        guard lipstickCollectionView.bounds.width > 0,
              let layout = lipstickCollectionView.collectionViewLayout as? UICollectionViewFlowLayout else {
            return false
        }

        let itemCount = CGFloat(LipstickSettings.presets.count)
        let contentWidth = itemCount * layout.itemSize.width + max(0, itemCount - 1) * layout.minimumLineSpacing
        return contentWidth > lipstickCollectionView.bounds.width
    }

    private func clampedLipstickContentOffset(for proposedX: CGFloat) -> CGPoint {
        let maxOffsetX = max(
            0,
            lipstickCollectionView.collectionViewLayout.collectionViewContentSize.width - lipstickCollectionView.bounds.width
        )
        let offsetX = proposedX.clamped(to: 0...maxOffsetX)
        return CGPoint(x: offsetX, y: lipstickCollectionView.contentOffset.y)
    }

    private func updateSelectedLipstickPresetFromCenter(animated: Bool) {
        let visibleCenter = CGPoint(
            x: lipstickCollectionView.bounds.midX + lipstickCollectionView.contentOffset.x,
            y: lipstickCollectionView.bounds.midY
        )

        guard let indexPath = lipstickCollectionView.indexPathForItem(at: visibleCenter) ?? closestVisibleLipstickIndexPath(to: visibleCenter) else {
            return
        }

        selectLipstickPreset(at: indexPath.item, animated: animated)
    }

    private func closestVisibleLipstickIndexPath(to point: CGPoint) -> IndexPath? {
        lipstickCollectionView.indexPathsForVisibleItems.min { lhs, rhs in
            guard let lhsAttributes = lipstickCollectionView.layoutAttributesForItem(at: lhs),
                  let rhsAttributes = lipstickCollectionView.layoutAttributesForItem(at: rhs) else {
                return lhs.item < rhs.item
            }

            return abs(lhsAttributes.center.x - point.x) < abs(rhsAttributes.center.x - point.x)
        }
    }

    private func updateVisibleLipstickCells(animated: Bool) {
        for case let cell as LipstickPresetCell in lipstickCollectionView.visibleCells {
            guard let indexPath = lipstickCollectionView.indexPath(for: cell),
                  LipstickSettings.presets.indices.contains(indexPath.item) else {
                continue
            }

            cell.configure(
                preset: LipstickSettings.presets[indexPath.item],
                isSelected: indexPath.item == selectedLipstickPresetIndex,
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
        resetARFaceFraming(animated: false)
        demoSceneView.isHidden = false
        demoSceneView.isPlaying = true
        modeButton.isHidden = true
        arAutoFramingButton.isHidden = true
        hairStyleButton.isHidden = true
        updateControlTabAvailability()
        updateControlTabVisibility()
        demoHeadRenderer.updateHairColor(hue: hairHueValue, strength: hairStrengthValue)
        demoHeadRenderer.updateHairPlacement(y: hairOffsetYValue, z: hairOffsetZValue, scale: hairScaleValue)
        demoHeadRenderer.setHeadHidden(hideHeadSwitch.isOn)
        demoHeadRenderer.setHairHidden(hideHairSwitch.isOn)
        demoHeadRenderer.setMakeupEnabled(!isBeforePreviewActive)
        applyBlushSettings()
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
        resetARFaceFraming(animated: false)
        sceneView.session.pause()
        sceneView.scene = SCNScene()
        sceneView.delegate = faceRenderer
        sceneView.automaticallyUpdatesLighting = true
        sceneView.isPlaying = true
        modeButton.isHidden = false
        arAutoFramingButton.isHidden = false
        updateARAutoFramingButton()
        hairStyleButton.isHidden = true
        updateControlTabAvailability()
        updateControlTabVisibility()
        demoHeadRenderer.setHeadHidden(false)
        demoHeadRenderer.setHairHidden(false)
        faceRenderer.attach(to: sceneView)
        faceRenderer.updateLipstickSettings(lipstickSettings)
        faceRenderer.updateBlushSettings(blushSettings)
        faceRenderer.setMakeupEnabled(!isBeforePreviewActive)

        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true

        // Face tracking uses the TrueDepth front camera and streams one
        // ARFaceAnchor per detected face into ARSCNViewDelegate callbacks.
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    private func updateARFaceFraming(faceBounds: CGRect) {
        guard experienceMode == .ar,
              isARAutoFramingEnabled,
              !sceneView.isHidden,
              faceBounds.width > 1,
              faceBounds.height > 1,
              view.bounds.width > 1,
              view.bounds.height > 1 else {
            return
        }

        let targetTop = max(view.safeAreaInsets.top + 118, modeButton.frame.maxY + 12)
        let panelTop = controlsStackView.frame.minY > 0 ? controlsStackView.frame.minY : view.bounds.maxY
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

        targetScale = targetScale.clamped(to: 0.72...1.0)

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
        targetTranslation.x = targetTranslation.x.clamped(to: -180...180)
        targetTranslation.y = targetTranslation.y.clamped(to: -260...260)

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

    private func applyBlushSettings() {
        faceRenderer.updateBlushSettings(blushSettings)
        demoHeadRenderer.updateBlushSettings(blushSettings)
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

extension FaceMakeupViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        LipstickSettings.presets.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: LipstickPresetCell.reuseIdentifier,
            for: indexPath
        ) as? LipstickPresetCell else {
            return UICollectionViewCell()
        }

        let isSelected = indexPath.item == selectedLipstickPresetIndex
        cell.configure(preset: LipstickSettings.presets[indexPath.item], isSelected: isSelected, animated: false)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        selectLipstickPreset(at: indexPath.item, animated: true)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updateSelectedLipstickPresetFromCenter(animated: true)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            updateSelectedLipstickPresetFromCenter(animated: true)
        }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        updateVisibleLipstickCells(animated: true)
    }
}

private final class LipstickSnapFlowLayout: UICollectionViewFlowLayout {
    override func targetContentOffset(
        forProposedContentOffset proposedContentOffset: CGPoint,
        withScrollingVelocity velocity: CGPoint
    ) -> CGPoint {
        guard let collectionView else {
            return super.targetContentOffset(forProposedContentOffset: proposedContentOffset, withScrollingVelocity: velocity)
        }

        let visibleRect = CGRect(origin: proposedContentOffset, size: collectionView.bounds.size)
        let centerX = visibleRect.midX
        guard let attributes = layoutAttributesForElements(in: visibleRect.insetBy(dx: -itemSize.width, dy: 0)) else {
            return super.targetContentOffset(forProposedContentOffset: proposedContentOffset, withScrollingVelocity: velocity)
        }

        let closest = attributes.min { lhs, rhs in
            abs(lhs.center.x - centerX) < abs(rhs.center.x - centerX)
        }

        guard let closest else {
            return super.targetContentOffset(forProposedContentOffset: proposedContentOffset, withScrollingVelocity: velocity)
        }

        let maxOffsetX = max(0, collectionViewContentSize.width - collectionView.bounds.width)
        let centeredOffsetX = closest.center.x - collectionView.bounds.width * 0.5
        let clampedOffsetX = min(max(centeredOffsetX, 0), maxOffsetX)

        return CGPoint(x: clampedOffsetX, y: proposedContentOffset.y)
    }
}

private final class LipstickPresetCell: UICollectionViewCell {
    static let reuseIdentifier = "LipstickPresetCell"

    private let iconView = LipstickIconView()
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.layer.cornerRadius = 10
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = UIColor.clear.cgColor
        contentView.backgroundColor = UIColor.white.withAlphaComponent(0.05)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.isUserInteractionEnabled = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.88)
        titleLabel.font = .preferredFont(forTextStyle: .caption2)
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.72
        contentView.addSubview(iconView)
        contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            iconView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            iconView.heightAnchor.constraint(equalToConstant: 98),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 4),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -5)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(preset: LipstickPreset, isSelected: Bool, animated: Bool) {
        iconView.color = preset.baseColor
        titleLabel.text = L10n.text(preset.titleKey)
        let updates = {
            self.contentView.transform = isSelected ? CGAffineTransform(scaleX: 1.08, y: 1.08) : .identity
            self.contentView.layer.borderColor = isSelected ? CosmeticTheme.gold.cgColor : UIColor.clear.cgColor
            self.contentView.backgroundColor = isSelected ? CosmeticTheme.gold.withAlphaComponent(0.13) : UIColor.white.withAlphaComponent(0.05)
            self.titleLabel.textColor = isSelected ? .white : UIColor.white.withAlphaComponent(0.78)
        }

        if animated {
            UIView.animate(withDuration: 0.18, delay: 0, options: [.allowUserInteraction, .curveEaseOut], animations: updates)
        } else {
            updates()
        }
    }
}

private final class LipstickIconView: UIView {
    var color: UIColor = .systemRed {
        didSet { setNeedsDisplay() }
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        let scale = min(rect.width / 62, rect.height / 100)
        let width: CGFloat = 62 * scale
        let height: CGFloat = 100 * scale
        let origin = CGPoint(x: rect.midX - width * 0.5, y: rect.midY - height * 0.5)

        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)
        context.scaleBy(x: scale, y: scale)

        drawShadow()
        drawBase()
        drawGoldBand()
        drawBullet()
        drawSwatch()

        context.restoreGState()
    }

    private func drawShadow() {
        UIColor.black.withAlphaComponent(0.24).setFill()
        UIBezierPath(ovalIn: CGRect(x: 12, y: 90, width: 38, height: 6)).fill()
    }

    private func drawBase() {
        let baseRect = CGRect(x: 16, y: 58, width: 30, height: 32)
        UIColor.black.withAlphaComponent(0.92).setFill()
        UIBezierPath(roundedRect: baseRect, cornerRadius: 4).fill()

        UIColor.white.withAlphaComponent(0.10).setFill()
        UIBezierPath(rect: CGRect(x: 18, y: 60, width: 5, height: 27)).fill()
    }

    private func drawGoldBand() {
        let gold = UIColor(red: 0.94, green: 0.70, blue: 0.38, alpha: 1.0)
        let darkGold = UIColor(red: 0.42, green: 0.25, blue: 0.10, alpha: 1.0)

        for y in [48.0, 53.0] {
            let rect = CGRect(x: 13, y: y, width: 36, height: 7)
            gold.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 2).fill()
            darkGold.withAlphaComponent(0.45).setFill()
            UIBezierPath(rect: CGRect(x: 36, y: y, width: 4, height: 7)).fill()
            UIColor.white.withAlphaComponent(0.30).setFill()
            UIBezierPath(rect: CGRect(x: 18, y: y + 1, width: 4, height: 5)).fill()
        }
    }

    private func drawBullet() {
        let bodyRect = CGRect(x: 20, y: 16, width: 22, height: 38)
        color.setFill()
        UIBezierPath(roundedRect: bodyRect, cornerRadius: 9).fill()

        UIColor.white.withAlphaComponent(0.24).setFill()
        UIBezierPath(roundedRect: CGRect(x: 23, y: 19, width: 5, height: 31), cornerRadius: 3).fill()

        let tipPath = UIBezierPath()
        tipPath.move(to: CGPoint(x: 20, y: 22))
        tipPath.addCurve(to: CGPoint(x: 42, y: 16), controlPoint1: CGPoint(x: 25, y: 10), controlPoint2: CGPoint(x: 35, y: 11))
        tipPath.addLine(to: CGPoint(x: 42, y: 29))
        tipPath.addCurve(to: CGPoint(x: 20, y: 22), controlPoint1: CGPoint(x: 36, y: 27), controlPoint2: CGPoint(x: 27, y: 25))
        tipPath.close()
        color.withBrightnessMultiplier(1.18).setFill()
        tipPath.fill()

        color.withBrightnessMultiplier(0.78).withAlphaComponent(0.32).setFill()
        UIBezierPath(ovalIn: CGRect(x: 24, y: 18, width: 17, height: 8)).fill()
    }

    private func drawSwatch() {
        color.setFill()
        UIBezierPath(roundedRect: CGRect(x: 10, y: 95, width: 42, height: 4), cornerRadius: 1).fill()
    }
}

private extension UIColor {
    func withBrightnessMultiplier(_ multiplier: CGFloat) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return self
        }

        return UIColor(
            red: min(max(red * multiplier, 0), 1),
            green: min(max(green * multiplier, 0), 1),
            blue: min(max(blue * multiplier, 0), 1),
            alpha: alpha
        )
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
