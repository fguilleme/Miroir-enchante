//
//  MakeupControlPanelView.swift
//  Miroir enchanté
//

import UIKit

final class MakeupControlPanelView: UIStackView {
    let controlsSegmentedControl = UISegmentedControl(items: [
        L10n.text("tab.looks"),
        L10n.text("tab.lips"),
        L10n.text("tab.face"),
        L10n.text("tab.eyes")
    ])
    let faceSegmentedControl = UISegmentedControl(items: [
        L10n.text("face_tab.blush"),
        L10n.text("face_tab.glow"),
        L10n.text("face_tab.contour")
    ])
    let looksCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 10
        layout.minimumInteritemSpacing = 0
        layout.itemSize = CGSize(width: 76, height: 82)
        layout.sectionInset = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.clipsToBounds = false
        collectionView.register(MakeupLookCell.self, forCellWithReuseIdentifier: MakeupLookCell.reuseIdentifier)
        return collectionView
    }()
    let lipstickIntensitySlider = UISlider()
    let lipstickFinishSegmentedControl = UISegmentedControl(items: [
        L10n.text("finish.matte"),
        L10n.text("finish.satin"),
        L10n.text("finish.glossy")
    ])
    let lipstickCollectionView: UICollectionView = {
        let layout = MakeupLipstickSnapFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 12
        layout.itemSize = CGSize(width: 72, height: 116)

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.decelerationRate = .fast
        collectionView.clipsToBounds = false
        return collectionView
    }()

    let blushIntensitySlider = UISlider()
    let blushSizeSlider = UISlider()
    let blushPositionSlider = UISlider()
    let eyeshadowIntensitySlider = UISlider()
    let glowIntensitySlider = UISlider()
    let glowRadiusSlider = UISlider()
    let contourIntensitySlider = UISlider()
    let hairHueSlider = UISlider()
    let hairStrengthSlider = UISlider()
    let hairOffsetYSlider = UISlider()
    let hairOffsetZSlider = UISlider()
    let hairScaleSlider = UISlider()
    let hideHeadSwitch = UISwitch()
    let hideHairSwitch = UISwitch()

    private let hairOffsetYValueLabel = UILabel()
    private let hairOffsetZValueLabel = UILabel()
    private let hairScaleValueLabel = UILabel()
    private var looksControlRows: [UIView] = []
    private var lipstickControlRows: [UIView] = []
    private var blushControlRows: [UIView] = []
    private var eyeshadowControlRows: [UIView] = []
    private var glowControlRows: [UIView] = []
    private var contourControlRows: [UIView] = []
    private(set) var blushPresetButtons: [UIButton] = []
    private(set) var eyeshadowPresetButtons: [UIButton] = []
    private(set) var glowPresetButtons: [UIButton] = []
    private(set) var contourPresetButtons: [UIButton] = []
    private var hairControlRows: [UIView] = []
    private var debugControlRows: [UIView] = []
    private(set) var selectedMainCategory: MakeupMainCategory = .looks
    private(set) var selectedFaceSubCategory: FaceSubCategory = .blush

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureBase()
        configureControls()
        buildRows()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configureInitialValues(from state: MakeupSettingsState) {
        lipstickIntensitySlider.value = Float(clampedCGFloat(state.lipstickIntensityValue, to: 0.4...1.0))
        lipstickFinishSegmentedControl.selectedSegmentIndex = state.lipstickFinish.rawValue
        blushIntensitySlider.value = Float(state.blushSettings.intensity)
        blushSizeSlider.value = Float(state.blushSettings.size)
        blushPositionSlider.value = Float(state.blushSettings.position)
        eyeshadowIntensitySlider.value = Float(state.eyeshadowSettings.intensity)
        glowIntensitySlider.value = Float(state.glowSettings.intensity)
        glowRadiusSlider.value = Float(state.glowSettings.radius)
        contourIntensitySlider.value = Float(state.contourSettings.intensity)
        hairHueSlider.value = Float(state.hairHueValue)
        hairStrengthSlider.value = Float(state.hairStrengthValue)
        hairOffsetYSlider.value = state.hairOffsetYValue
        hairOffsetZSlider.value = state.hairOffsetZValue
        hairScaleSlider.value = state.hairScaleValue
        hideHeadSwitch.isOn = state.isHeadHidden
        hideHairSwitch.isOn = state.isHairHidden
        updateHairOffsetValueLabels()
        updateBlushPresetSelection(selectedIndex: state.selectedBlushPresetIndex, animated: false)
        updateEyeshadowPresetSelection(selectedIndex: state.selectedEyeshadowPresetIndex, animated: false)
        updateGlowPresetSelection(selectedIndex: state.selectedGlowPresetIndex, animated: false)
        updateContourPresetSelection(selectedIndex: state.selectedContourPresetIndex, animated: false)
    }

    func configureMainCategories(
        selected category: MakeupMainCategory,
        faceSubCategory: FaceSubCategory
    ) -> (MakeupMainCategory, FaceSubCategory) {
        setSelectedFaceSubCategory(faceSubCategory)
        setSelectedMainCategory(category)
        return (selectedMainCategory, selectedFaceSubCategory)
    }

    func setSelectedMainCategory(_ category: MakeupMainCategory) {
        selectedMainCategory = category
        controlsSegmentedControl.selectedSegmentIndex = category.rawValue
        updateControlTabVisibility()
    }

    func setSelectedFaceSubCategory(_ subCategory: FaceSubCategory) {
        selectedFaceSubCategory = subCategory
        faceSegmentedControl.selectedSegmentIndex = subCategory.rawValue
        updateControlTabVisibility()
    }

    func selectedMainCategoryFromSegment() -> MakeupMainCategory {
        MakeupMainCategory(rawValue: controlsSegmentedControl.selectedSegmentIndex) ?? .looks
    }

    func selectedFaceSubCategoryFromSegment() -> FaceSubCategory {
        FaceSubCategory(rawValue: faceSegmentedControl.selectedSegmentIndex) ?? .blush
    }

    func updateHairOffsetValueLabels() {
        hairOffsetYValueLabel.text = String(format: "%.2f", hairOffsetYSlider.value)
        hairOffsetZValueLabel.text = String(format: "%.2f", hairOffsetZSlider.value)
        hairScaleValueLabel.text = String(format: "%.2f", hairScaleSlider.value)
    }

    func updateBlushPresetSelection(selectedIndex: Int, animated: Bool) {
        for button in blushPresetButtons {
            updatePresetButtonSelection(button, isSelected: button.tag == selectedIndex, animated: animated)
        }
    }

    func updateEyeshadowPresetSelection(selectedIndex: Int, animated: Bool) {
        for button in eyeshadowPresetButtons {
            updatePresetButtonSelection(button, isSelected: button.tag == selectedIndex, animated: animated)
        }
    }

    func updateGlowPresetSelection(selectedIndex: Int, animated: Bool) {
        for button in glowPresetButtons {
            updatePresetButtonSelection(button, isSelected: button.tag == selectedIndex, animated: animated)
        }
    }

    func updateContourPresetSelection(selectedIndex: Int, animated: Bool) {
        for button in contourPresetButtons {
            updatePresetButtonSelection(button, isSelected: button.tag == selectedIndex, animated: animated)
        }
    }

    private func updatePresetButtonSelection(_ button: UIButton, isSelected: Bool, animated: Bool) {
        let updates = {
            button.transform = isSelected ? CGAffineTransform(scaleX: 1.12, y: 1.12) : .identity
            button.layer.borderWidth = isSelected ? 3.0 : 0.7
            button.layer.borderColor = isSelected ? UIColor.white.cgColor : UIColor.white.withAlphaComponent(0.18).cgColor
            button.layer.shadowColor = CosmeticTheme.gold.cgColor
            button.layer.shadowOpacity = isSelected ? 0.55 : 0
            button.layer.shadowRadius = isSelected ? 8 : 0
            button.layer.shadowOffset = .zero
        }

        if animated {
            UIView.animate(withDuration: 0.18, delay: 0, options: [.allowUserInteraction, .curveEaseOut], animations: updates)
        } else {
            updates()
        }
    }

    private func configureBase() {
        translatesAutoresizingMaskIntoConstraints = false
        axis = .vertical
        spacing = 6
        alignment = .fill
        backgroundColor = .clear
        layer.cornerRadius = 0
        isLayoutMarginsRelativeArrangement = true
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 24, bottom: 6, trailing: 24)

        installBackgroundGlass()
    }

    private func installBackgroundGlass() {
        let blurEffect: UIBlurEffect
        if #available(iOS 13.0, *) {
            blurEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        } else {
            blurEffect = UIBlurEffect(style: .dark)
        }

        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.alpha = 0.85
        blurView.isUserInteractionEnabled = false

        let tintView = UIView()
        tintView.translatesAutoresizingMaskIntoConstraints = false
        tintView.backgroundColor = CosmeticTheme.warmPanelTint
        tintView.isUserInteractionEnabled = false

        insertSubview(blurView, at: 0)
        insertSubview(tintView, at: 1)

        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            tintView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tintView.topAnchor.constraint(equalTo: topAnchor),
            tintView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func configureControls() {
        lipstickIntensitySlider.minimumValue = 0.4
        lipstickIntensitySlider.maximumValue = 1.0
        lipstickIntensitySlider.isContinuous = true

        lipstickFinishSegmentedControl.selectedSegmentTintColor = CosmeticTheme.gold.withAlphaComponent(0.20)
        lipstickFinishSegmentedControl.setTitleTextAttributes([.foregroundColor: CosmeticTheme.dimText], for: .normal)
        lipstickFinishSegmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)

        lipstickCollectionView.register(MakeupLipstickPresetCell.self, forCellWithReuseIdentifier: MakeupLipstickPresetCell.reuseIdentifier)

        blushIntensitySlider.minimumValue = 0.0
        blushIntensitySlider.maximumValue = 1.0
        blushIntensitySlider.isContinuous = true

        blushSizeSlider.minimumValue = 0.65
        blushSizeSlider.maximumValue = 1.45
        blushSizeSlider.isContinuous = true

        blushPositionSlider.minimumValue = 0.0
        blushPositionSlider.maximumValue = 1.0
        blushPositionSlider.isContinuous = true

        eyeshadowIntensitySlider.minimumValue = 0.0
        eyeshadowIntensitySlider.maximumValue = 1.0
        eyeshadowIntensitySlider.isContinuous = true

        glowIntensitySlider.minimumValue = 0.0
        glowIntensitySlider.maximumValue = 1.0
        glowIntensitySlider.isContinuous = true

        glowRadiusSlider.minimumValue = 0.75
        glowRadiusSlider.maximumValue = 1.25
        glowRadiusSlider.isContinuous = true

        contourIntensitySlider.minimumValue = 0.0
        contourIntensitySlider.maximumValue = 1.0
        contourIntensitySlider.isContinuous = true

        hairHueSlider.minimumValue = 0.0
        hairHueSlider.maximumValue = 1.0
        hairHueSlider.isContinuous = true

        hairStrengthSlider.minimumValue = 0.0
        hairStrengthSlider.maximumValue = 1.0
        hairStrengthSlider.isContinuous = true

        hairOffsetYSlider.minimumValue = -3.0
        hairOffsetYSlider.maximumValue = 1.0
        hairOffsetYSlider.isContinuous = true

        hairOffsetZSlider.minimumValue = -1.0
        hairOffsetZSlider.maximumValue = 5.0
        hairOffsetZSlider.isContinuous = true

        hairScaleSlider.minimumValue = 0.15
        hairScaleSlider.maximumValue = 2.0
        hairScaleSlider.isContinuous = true

        [
            lipstickIntensitySlider,
            blushIntensitySlider,
            blushSizeSlider,
            blushPositionSlider,
            eyeshadowIntensitySlider,
            glowIntensitySlider,
            glowRadiusSlider,
            contourIntensitySlider,
            hairHueSlider,
            hairStrengthSlider,
            hairOffsetYSlider,
            hairOffsetZSlider,
            hairScaleSlider
        ].forEach(styleSlider)

        controlsSegmentedControl.selectedSegmentTintColor = CosmeticTheme.gold.withAlphaComponent(0.22)
        controlsSegmentedControl.setTitleTextAttributes([.foregroundColor: CosmeticTheme.dimText], for: .normal)
        controlsSegmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)

        faceSegmentedControl.selectedSegmentTintColor = CosmeticTheme.gold.withAlphaComponent(0.14)
        faceSegmentedControl.setTitleTextAttributes([
            .foregroundColor: CosmeticTheme.dimText,
            .font: UIFont.preferredFont(forTextStyle: .caption1)
        ], for: .normal)
        faceSegmentedControl.setTitleTextAttributes([
            .foregroundColor: UIColor.white.withAlphaComponent(0.92),
            .font: UIFont.preferredFont(forTextStyle: .caption1)
        ], for: .selected)
    }

    private func buildRows() {
        let lipstickSelectorRow = makeLipstickSelectorRow()
        let lipstickIntensityRow = makeSliderRow(title: L10n.text("control.intensity"), slider: lipstickIntensitySlider)
        let lipstickFinishRow = makeFinishRow()
        let blushSelectorRow = makeBlushSelectorRow()
        let blushIntensityRow = makeSliderRow(title: L10n.text("control.intensity"), slider: blushIntensitySlider)
        let blushSizeRow = makeSliderRow(title: L10n.text("control.size"), slider: blushSizeSlider)
        let blushPositionRow = makeSliderRow(title: L10n.text("control.position"), slider: blushPositionSlider)
        let eyeshadowSelectorRow = makeEyeshadowSelectorRow()
        let eyeshadowIntensityRow = makeSliderRow(title: L10n.text("control.intensity"), slider: eyeshadowIntensitySlider)
        let glowSelectorRow = makeGlowSelectorRow()
        let glowIntensityRow = makeSliderRow(title: L10n.text("control.intensity"), slider: glowIntensitySlider)
        let glowRadiusRow = makeSliderRow(title: L10n.text("control.size"), slider: glowRadiusSlider)
        let contourSelectorRow = makeContourSelectorRow()
        let contourIntensityRow = makeSliderRow(title: L10n.text("control.intensity"), slider: contourIntensitySlider)
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

        let looksRow = makeLooksRow()
        looksControlRows = [looksRow]
        lipstickControlRows = [lipstickSelectorRow, lipstickIntensityRow, lipstickFinishRow]
        blushControlRows = [blushSelectorRow, blushIntensityRow, blushSizeRow, blushPositionRow]
        eyeshadowControlRows = [eyeshadowSelectorRow, eyeshadowIntensityRow]
        glowControlRows = [glowSelectorRow, glowIntensityRow, glowRadiusRow]
        contourControlRows = [contourSelectorRow, contourIntensityRow]
        hairControlRows = [hairRow]
        debugControlRows = [hairOffsetYRow, hairOffsetZRow, hairScaleRow, visibilityRow]

        addArrangedSubview(looksRow)
        addArrangedSubview(controlsSegmentedControl)
        addArrangedSubview(faceSegmentedControl)
        addArrangedSubview(lipstickSelectorRow)
        addArrangedSubview(lipstickIntensityRow)
        addArrangedSubview(lipstickFinishRow)
        addArrangedSubview(blushSelectorRow)
        addArrangedSubview(blushIntensityRow)
        addArrangedSubview(blushSizeRow)
        addArrangedSubview(blushPositionRow)
        addArrangedSubview(eyeshadowSelectorRow)
        addArrangedSubview(eyeshadowIntensityRow)
        addArrangedSubview(glowSelectorRow)
        addArrangedSubview(glowIntensityRow)
        addArrangedSubview(glowRadiusRow)
        addArrangedSubview(contourSelectorRow)
        addArrangedSubview(contourIntensityRow)
        addArrangedSubview(hairRow)
        addArrangedSubview(hairOffsetYRow)
        addArrangedSubview(hairOffsetZRow)
        addArrangedSubview(hairScaleRow)
        addArrangedSubview(visibilityRow)
        setSelectedMainCategory(.looks)
    }

    private func makeLooksRow() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        looksCollectionView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(looksCollectionView)
        NSLayoutConstraint.activate([
            looksCollectionView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            looksCollectionView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            looksCollectionView.topAnchor.constraint(equalTo: container.topAnchor),
            looksCollectionView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.heightAnchor.constraint(equalToConstant: 84)
        ])
        return container
    }

    private func updateControlTabVisibility() {
        let isFace = selectedMainCategory == .face
        looksControlRows.forEach { $0.isHidden = selectedMainCategory != .looks }
        lipstickControlRows.forEach { $0.isHidden = selectedMainCategory != .lips }
        faceSegmentedControl.isHidden = !isFace
        blushControlRows.forEach { $0.isHidden = !isFace || selectedFaceSubCategory != .blush }
        glowControlRows.forEach { $0.isHidden = !isFace || selectedFaceSubCategory != .glow }
        contourControlRows.forEach { $0.isHidden = !isFace || selectedFaceSubCategory != .contour }
        eyeshadowControlRows.forEach { $0.isHidden = selectedMainCategory != .eyes }
        hairControlRows.forEach { $0.isHidden = true }
        debugControlRows.forEach { $0.isHidden = true }
    }

    private func styleSlider(_ slider: UISlider) {
        slider.minimumTrackTintColor = CosmeticTheme.gold.withAlphaComponent(0.85)
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.10)
        slider.thumbTintColor = CosmeticTheme.softGold
        slider.transform = CGAffineTransform(scaleX: 1.0, y: 0.85)
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
            container.heightAnchor.constraint(equalToConstant: 120)
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
        button.layer.cornerRadius = 19
        button.layer.borderColor = CosmeticTheme.gold.withAlphaComponent(0.85).cgColor
        button.widthAnchor.constraint(equalToConstant: 38).isActive = true
        button.heightAnchor.constraint(equalToConstant: 38).isActive = true
        blushPresetButtons.append(button)

        let label = UILabel()
        label.text = L10n.text(preset.titleKey)
        label.textColor = UIColor.white.withAlphaComponent(0.66)
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

    private func makeEyeshadowSelectorRow() -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 6
        container.alignment = .fill

        let presetsRow = UIStackView()
        presetsRow.axis = .horizontal
        presetsRow.spacing = 10
        presetsRow.distribution = .fillEqually
        presetsRow.alignment = .top

        eyeshadowPresetButtons = []
        for (index, preset) in EyeshadowSettings.presets.enumerated() {
            let item = makeEyeshadowPresetItem(preset: preset, index: index)
            presetsRow.addArrangedSubview(item)
        }

        container.addArrangedSubview(presetsRow)
        return container
    }

    private func makeEyeshadowPresetItem(preset: EyeshadowPreset, index: Int) -> UIStackView {
        let button = UIButton(type: .system)
        button.tag = index
        button.backgroundColor = preset.baseColor
        button.layer.cornerRadius = 16
        button.layer.borderColor = CosmeticTheme.gold.withAlphaComponent(0.85).cgColor
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        eyeshadowPresetButtons.append(button)

        let label = UILabel()
        label.text = L10n.text(preset.titleKey)
        label.textColor = UIColor.white.withAlphaComponent(0.66)
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

    private func makeGlowSelectorRow() -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 6
        container.alignment = .fill

        let presetsRow = UIStackView()
        presetsRow.axis = .horizontal
        presetsRow.spacing = 10
        presetsRow.distribution = .fillEqually
        presetsRow.alignment = .top

        glowPresetButtons = []
        for (index, preset) in GlowSettings.presets.enumerated() {
            let item = makeGlowPresetItem(preset: preset, index: index)
            presetsRow.addArrangedSubview(item)
        }

        container.addArrangedSubview(presetsRow)
        return container
    }

    private func makeGlowPresetItem(preset: GlowPreset, index: Int) -> UIStackView {
        let button = UIButton(type: .system)
        button.tag = index
        button.backgroundColor = preset.color
        button.layer.cornerRadius = 19
        button.layer.borderColor = CosmeticTheme.gold.withAlphaComponent(0.85).cgColor
        button.widthAnchor.constraint(equalToConstant: 38).isActive = true
        button.heightAnchor.constraint(equalToConstant: 38).isActive = true
        glowPresetButtons.append(button)

        let label = UILabel()
        label.text = L10n.text(preset.titleKey)
        label.textColor = UIColor.white.withAlphaComponent(0.66)
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

    private func makeContourSelectorRow() -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 6
        container.alignment = .fill

        let presetsRow = UIStackView()
        presetsRow.axis = .horizontal
        presetsRow.spacing = 10
        presetsRow.distribution = .fillEqually
        presetsRow.alignment = .top

        contourPresetButtons = []
        for (index, preset) in ContourSettings.presets.enumerated() {
            let item = makeContourPresetItem(preset: preset, index: index)
            presetsRow.addArrangedSubview(item)
        }

        container.addArrangedSubview(presetsRow)
        return container
    }

    private func makeContourPresetItem(preset: ContourPreset, index: Int) -> UIStackView {
        let button = UIButton(type: .system)
        button.tag = index
        button.backgroundColor = preset.color
        button.layer.cornerRadius = 19
        button.layer.borderColor = CosmeticTheme.gold.withAlphaComponent(0.85).cgColor
        button.widthAnchor.constraint(equalToConstant: 38).isActive = true
        button.heightAnchor.constraint(equalToConstant: 38).isActive = true
        contourPresetButtons.append(button)

        let label = UILabel()
        label.text = L10n.text(preset.titleKey)
        label.textColor = UIColor.white.withAlphaComponent(0.66)
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
}

private func clampedCGFloat(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
    Swift.min(Swift.max(value, range.lowerBound), range.upperBound)
}

final class MakeupLipstickSnapFlowLayout: UICollectionViewFlowLayout {
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

final class MakeupLipstickPresetCell: UICollectionViewCell {
    static let reuseIdentifier = "MakeupLipstickPresetCell"

    private let iconView = MakeupLipstickIconView()
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.layer.cornerRadius = 12
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = UIColor.clear.cgColor
        contentView.backgroundColor = UIColor.white.withAlphaComponent(0.03)

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
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            iconView.heightAnchor.constraint(equalToConstant: 86),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 4),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -4)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(preset: LipstickPreset, isSelected: Bool, animated: Bool) {
        iconView.color = preset.baseColor
        titleLabel.text = L10n.text(preset.titleKey)
        let updates = {
            self.contentView.transform = isSelected ? CGAffineTransform(scaleX: 1.05, y: 1.05) : .identity
            self.contentView.layer.borderColor = isSelected ? CosmeticTheme.gold.withAlphaComponent(0.85).cgColor : UIColor.clear.cgColor
            self.contentView.backgroundColor = isSelected ? CosmeticTheme.gold.withAlphaComponent(0.06) : UIColor.white.withAlphaComponent(0.03)
            self.titleLabel.textColor = isSelected ? .white : UIColor.white.withAlphaComponent(0.74)
        }

        if animated {
            UIView.animate(
                withDuration: 0.22,
                delay: 0,
                usingSpringWithDamping: 0.78,
                initialSpringVelocity: 0.4,
                options: [.allowUserInteraction, .curveEaseOut],
                animations: updates,
                completion: nil
            )
        } else {
            updates()
        }
    }
}

final class MakeupLipstickIconView: UIView {
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

final class MakeupLookCell: UICollectionViewCell {
    static let reuseIdentifier = "MakeupLookCell"

    private let titleLabel = UILabel()
    private let sketchView = MakeupZoneFaceIconView()
    private let swatchStack = UIStackView()
    private let swatchViews: [UIView] = (0..<5).map { _ in UIView() }

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.layer.cornerRadius = 12
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = UIColor.clear.cgColor
        contentView.backgroundColor = UIColor.white.withAlphaComponent(0.05)

        sketchView.translatesAutoresizingMaskIntoConstraints = false
        sketchView.isUserInteractionEnabled = false

        swatchStack.axis = .horizontal
        swatchStack.spacing = 3
        swatchStack.alignment = .center
        swatchStack.distribution = .fillEqually
        swatchStack.translatesAutoresizingMaskIntoConstraints = false

        for view in swatchViews {
            view.layer.cornerRadius = 3
            view.layer.borderWidth = 0.5
            view.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
            view.widthAnchor.constraint(equalToConstant: 7).isActive = true
            view.heightAnchor.constraint(equalToConstant: 7).isActive = true
            swatchStack.addArrangedSubview(view)
        }

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .preferredFont(forTextStyle: .caption2)
        titleLabel.textAlignment = .center
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.82)
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.7

        contentView.addSubview(titleLabel)
        contentView.addSubview(sketchView)
        contentView.addSubview(swatchStack)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            sketchView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            sketchView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            sketchView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            sketchView.bottomAnchor.constraint(equalTo: swatchStack.topAnchor, constant: -1),
            swatchStack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            swatchStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(look: MakeupLook, isSelected: Bool, animated: Bool) {
        titleLabel.text = L10n.text(look.titleKey)
        sketchView.configure(look: look)
        for (view, color) in zip(swatchViews, look.swatchColors) {
            view.backgroundColor = color
        }

        let updates = {
            self.contentView.transform = isSelected ? CGAffineTransform(scaleX: 1.05, y: 1.05) : .identity
            self.contentView.layer.borderColor = isSelected ? CosmeticTheme.gold.withAlphaComponent(0.85).cgColor : UIColor.clear.cgColor
            self.contentView.backgroundColor = isSelected
                ? CosmeticTheme.gold.withAlphaComponent(0.08)
                : UIColor.white.withAlphaComponent(0.03)
            self.titleLabel.textColor = isSelected ? .white : UIColor.white.withAlphaComponent(0.62)
            self.contentView.alpha = isSelected ? 1.0 : 0.85
        }

        if animated {
            UIView.animate(
                withDuration: 0.22,
                delay: 0,
                usingSpringWithDamping: 0.78,
                initialSpringVelocity: 0.4,
                options: [.allowUserInteraction, .curveEaseOut],
                animations: updates,
                completion: nil
            )
        } else {
            updates()
        }
    }
}

struct MakeupFaceZone: OptionSet {
    let rawValue: Int

    static let lips = MakeupFaceZone(rawValue: 1 << 0)
    static let blush = MakeupFaceZone(rawValue: 1 << 1)
    static let glow = MakeupFaceZone(rawValue: 1 << 2)
    static let contour = MakeupFaceZone(rawValue: 1 << 3)
    static let eyes = MakeupFaceZone(rawValue: 1 << 4)
    static let fullLook: MakeupFaceZone = [.lips, .blush, .glow, .contour, .eyes]
}

struct MakeupFaceIconPalette {
    var lips: UIColor
    var blush: UIColor
    var glow: UIColor
    var contour: UIColor
    var eyes: UIColor
}

final class MakeupZoneFaceIconView: UIView {
    private var zones: MakeupFaceZone = .fullLook
    private var palette = MakeupFaceIconPalette(
        lips: .systemRed,
        blush: .systemPink,
        glow: CosmeticTheme.softGold,
        contour: UIColor(red: 0.42, green: 0.28, blue: 0.22, alpha: 1.0),
        eyes: UIColor(red: 0.42, green: 0.28, blue: 0.44, alpha: 1.0)
    )

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        zones: MakeupFaceZone,
        palette: MakeupFaceIconPalette
    ) {
        self.zones = zones
        self.palette = palette
        setNeedsDisplay()
    }

    func configure(look: MakeupLook) {
        configure(
            zones: .fullLook,
            palette: MakeupFaceIconPalette(
                lips: look.lipstick.baseColor,
                blush: look.blush.baseColor,
                glow: look.glow?.color ?? CosmeticTheme.softGold,
                contour: look.contour?.color ?? UIColor(red: 0.42, green: 0.28, blue: 0.22, alpha: 1.0),
                eyes: look.eyes.baseColor
            )
        )
    }

    override func draw(_ rect: CGRect) {
        guard rect.width > 4, rect.height > 4 else { return }

        let scale = min(rect.width / 48, rect.height / 46)
        let width = 48 * scale
        let height = 46 * scale
        let origin = CGPoint(x: rect.midX - width * 0.5, y: rect.midY - height * 0.5)

        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)
        context.scaleBy(x: scale, y: scale)

        drawFaceOutline()
        if zones.contains(.contour) { drawContour() }
        if zones.contains(.glow) { drawGlow() }
        if zones.contains(.blush) { drawBlush() }
        if zones.contains(.eyes) { drawEyes() }
        if zones.contains(.lips) { drawLips() }

        context.restoreGState()
    }

    private func drawFaceOutline() {
        let facePath = UIBezierPath(ovalIn: CGRect(x: 11, y: 3, width: 26, height: 38))
        UIColor.white.withAlphaComponent(0.24).setStroke()
        facePath.lineWidth = 1.15
        facePath.stroke()

        UIColor.white.withAlphaComponent(0.16).setStroke()
        let nose = UIBezierPath()
        nose.move(to: CGPoint(x: 24, y: 17))
        nose.addQuadCurve(to: CGPoint(x: 23.3, y: 26), controlPoint: CGPoint(x: 25.6, y: 22))
        nose.lineWidth = 0.75
        nose.lineCapStyle = .round
        nose.stroke()
    }

    private func drawContour() {
        palette.contour.withAlphaComponent(0.34).setStroke()
        drawCurve(from: CGPoint(x: 14, y: 18), to: CGPoint(x: 16, y: 31), control: CGPoint(x: 12, y: 25), width: 2.0)
        drawCurve(from: CGPoint(x: 34, y: 18), to: CGPoint(x: 32, y: 31), control: CGPoint(x: 36, y: 25), width: 2.0)
        drawCurve(from: CGPoint(x: 17, y: 27), to: CGPoint(x: 23, y: 30), control: CGPoint(x: 19, y: 30), width: 1.6)
        drawCurve(from: CGPoint(x: 31, y: 27), to: CGPoint(x: 25, y: 30), control: CGPoint(x: 29, y: 30), width: 1.6)
    }

    private func drawGlow() {
        palette.glow.withAlphaComponent(0.62).setFill()
        UIBezierPath(ovalIn: CGRect(x: 17.5, y: 21, width: 3, height: 3)).fill()
        UIBezierPath(ovalIn: CGRect(x: 27.5, y: 21, width: 3, height: 3)).fill()
        UIBezierPath(ovalIn: CGRect(x: 23, y: 13.5, width: 2, height: 5)).fill()
    }

    private func drawBlush() {
        palette.blush.withAlphaComponent(0.50).setFill()
        UIBezierPath(ovalIn: CGRect(x: 15.5, y: 25, width: 6, height: 5)).fill()
        UIBezierPath(ovalIn: CGRect(x: 26.5, y: 25, width: 6, height: 5)).fill()
    }

    private func drawEyes() {
        palette.eyes.withAlphaComponent(0.62).setStroke()
        drawCurve(from: CGPoint(x: 16.5, y: 17.5), to: CGPoint(x: 22.5, y: 17.5), control: CGPoint(x: 19.5, y: 15.4), width: 1.9)
        drawCurve(from: CGPoint(x: 25.5, y: 17.5), to: CGPoint(x: 31.5, y: 17.5), control: CGPoint(x: 28.5, y: 15.4), width: 1.9)

        UIColor.white.withAlphaComponent(0.34).setFill()
        UIBezierPath(ovalIn: CGRect(x: 19.1, y: 17.1, width: 1.1, height: 1.1)).fill()
        UIBezierPath(ovalIn: CGRect(x: 28.1, y: 17.1, width: 1.1, height: 1.1)).fill()
    }

    private func drawLips() {
        palette.lips.withAlphaComponent(0.82).setFill()
        let lips = UIBezierPath()
        lips.move(to: CGPoint(x: 18.5, y: 32))
        lips.addCurve(to: CGPoint(x: 29.5, y: 32), controlPoint1: CGPoint(x: 21, y: 29.7), controlPoint2: CGPoint(x: 27, y: 29.7))
        lips.addCurve(to: CGPoint(x: 18.5, y: 32), controlPoint1: CGPoint(x: 27, y: 34.8), controlPoint2: CGPoint(x: 21, y: 34.8))
        lips.close()
        lips.fill()
    }

    private func drawCurve(from start: CGPoint, to end: CGPoint, control: CGPoint, width: CGFloat) {
        let path = UIBezierPath()
        path.move(to: start)
        path.addQuadCurve(to: end, controlPoint: control)
        path.lineWidth = width
        path.lineCapStyle = .round
        path.stroke()
    }
}
