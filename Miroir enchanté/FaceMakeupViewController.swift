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
    private let lipstickIntensitySlider = UISlider()
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
    private var selectedLipstickPresetIndex = 3
    private var didCenterInitialLipstickPreset = false
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        updateLipstickCollectionLayoutInsets()

        guard !didCenterInitialLipstickPreset, lipstickCollectionView.bounds.width > 0 else { return }
        didCenterInitialLipstickPreset = true
        centerSelectedLipstickPreset(animated: false)
        updateVisibleLipstickCells(animated: false)
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
        lipstickIntensitySlider.minimumValue = 0.4
        lipstickIntensitySlider.maximumValue = 1.0
        lipstickIntensitySlider.value = 0.9
        lipstickIntensitySlider.isContinuous = true
        lipstickIntensitySlider.addTarget(self, action: #selector(lipstickIntensityChanged), for: .valueChanged)

        lipstickCollectionView.dataSource = self
        lipstickCollectionView.delegate = self
        lipstickCollectionView.register(LipstickPresetCell.self, forCellWithReuseIdentifier: LipstickPresetCell.reuseIdentifier)

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

        let lipstickSelectorRow = makeLipstickSelectorRow()
        let lipstickIntensityRow = makeSliderRow(title: L10n.text("control.intensity"), slider: lipstickIntensitySlider)
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

        lipstickControlRows = [lipstickSelectorRow, lipstickIntensityRow]
        hairControlRows = [hairRow]
        debugControlRows = [hairOffsetYRow, hairOffsetZRow, hairScaleRow, visibilityRow]

        controlsStackView.translatesAutoresizingMaskIntoConstraints = false
        controlsStackView.axis = .vertical
        controlsStackView.spacing = 8
        controlsStackView.alignment = .fill
        controlsStackView.backgroundColor = UIColor.black.withAlphaComponent(0.52)
        controlsStackView.layer.cornerRadius = 0
        controlsStackView.isLayoutMarginsRelativeArrangement = true
        controlsStackView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 28, bottom: 0, trailing: 28)

        controlsStackView.addArrangedSubview(controlsSegmentedControl)
        controlsStackView.addArrangedSubview(lipstickIntensityRow)
        controlsStackView.addArrangedSubview(lipstickSelectorRow)
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

    @objc private func lipstickIntensityChanged() {
        applySelectedLipstickPreset(animated: false, updatesSelector: false)
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
        controlsSegmentedControl.isHidden = !demoControlsEnabled
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

        lipstickSettings.color = preset.baseColor
        lipstickSettings.opacity = CGFloat(preset.opacity) * intensity
        lipstickSettings.roughness = CGFloat(preset.roughness)
        lipstickSettings.glossIntensity = CGFloat(1.0 - preset.roughness).clamped(to: 0...1)
        lipstickSettings.colorIntensity = 1.0

        applyLipstickSettings()

        if updatesSelector {
            updateVisibleLipstickCells(animated: animated)
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
            self.contentView.layer.borderColor = isSelected ? UIColor.white.withAlphaComponent(0.85).cgColor : UIColor.clear.cgColor
            self.contentView.backgroundColor = isSelected ? UIColor.white.withAlphaComponent(0.13) : UIColor.white.withAlphaComponent(0.05)
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
