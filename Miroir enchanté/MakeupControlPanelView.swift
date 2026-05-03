//
//  MakeupControlPanelView.swift
//  Miroir enchanté
//

import UIKit

final class MakeupControlPanelView: UIStackView {
    let controlsSegmentedControl = UISegmentedControl(items: ["Lipstick", "Blush", "Hair", "Debug"])
    let lipstickIntensitySlider = UISlider()
    let lipstickFinishSegmentedControl = UISegmentedControl(items: ["Mat", "Satiné", "Brillant"])
    let lipstickCollectionView: UICollectionView = {
        let layout = MakeupLipstickSnapFlowLayout()
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

    let blushIntensitySlider = UISlider()
    let blushSizeSlider = UISlider()
    let blushPositionSlider = UISlider()
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
    private var lipstickControlRows: [UIView] = []
    private var blushControlRows: [UIView] = []
    private(set) var blushPresetButtons: [UIButton] = []
    private var hairControlRows: [UIView] = []
    private var debugControlRows: [UIView] = []
    private(set) var selectedControlTab: MakeupControlTab = .lipstick
    private(set) var visibleControlTabs: [MakeupControlTab] = [.lipstick, .blush, .hair, .debug]
    private var isDemoMode = true

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
        hairHueSlider.value = Float(state.hairHueValue)
        hairStrengthSlider.value = Float(state.hairStrengthValue)
        hairOffsetYSlider.value = state.hairOffsetYValue
        hairOffsetZSlider.value = state.hairOffsetZValue
        hairScaleSlider.value = state.hairScaleValue
        hideHeadSwitch.isOn = state.isHeadHidden
        hideHairSwitch.isOn = state.isHairHidden
        updateHairOffsetValueLabels()
        updateBlushPresetSelection(selectedIndex: state.selectedBlushPresetIndex, animated: false)
    }

    func configureTabs(isDemoMode: Bool, selectedTab: MakeupControlTab) -> MakeupControlTab {
        self.isDemoMode = isDemoMode
        let nextTabs: [MakeupControlTab] = isDemoMode ? [.lipstick, .blush, .hair, .debug] : [.lipstick, .blush]
        var nextSelectedTab = selectedTab
        if !isDemoMode && (nextSelectedTab == .hair || nextSelectedTab == .debug) {
            nextSelectedTab = .lipstick
        }

        if visibleControlTabs != nextTabs {
            controlsSegmentedControl.removeAllSegments()
            for (index, tab) in nextTabs.enumerated() {
                controlsSegmentedControl.insertSegment(withTitle: controlTabTitle(tab), at: index, animated: false)
            }
            visibleControlTabs = nextTabs
        }

        setSelectedTab(nextSelectedTab)
        return nextSelectedTab
    }

    func setSelectedTab(_ tab: MakeupControlTab) {
        selectedControlTab = tab
        controlsSegmentedControl.selectedSegmentIndex = visibleControlTabs.firstIndex(of: tab) ?? 0
        updateControlTabVisibility()
    }

    func selectedTabFromSegment() -> MakeupControlTab {
        let selectedIndex = controlsSegmentedControl.selectedSegmentIndex
        return visibleControlTabs.indices.contains(selectedIndex) ? visibleControlTabs[selectedIndex] : .lipstick
    }

    func updateHairOffsetValueLabels() {
        hairOffsetYValueLabel.text = String(format: "%.2f", hairOffsetYSlider.value)
        hairOffsetZValueLabel.text = String(format: "%.2f", hairOffsetZSlider.value)
        hairScaleValueLabel.text = String(format: "%.2f", hairScaleSlider.value)
    }

    func updateBlushPresetSelection(selectedIndex: Int, animated: Bool) {
        for button in blushPresetButtons {
            let isSelected = button.tag == selectedIndex
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

    private func configureBase() {
        translatesAutoresizingMaskIntoConstraints = false
        axis = .vertical
        spacing = 8
        alignment = .fill
        backgroundColor = CosmeticTheme.panelBackground
        layer.cornerRadius = 0
        isLayoutMarginsRelativeArrangement = true
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: 14, leading: 28, bottom: 8, trailing: 28)
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
            hairHueSlider,
            hairStrengthSlider,
            hairOffsetYSlider,
            hairOffsetZSlider,
            hairScaleSlider
        ].forEach(styleSlider)

        controlsSegmentedControl.selectedSegmentTintColor = CosmeticTheme.gold.withAlphaComponent(0.22)
        controlsSegmentedControl.setTitleTextAttributes([.foregroundColor: CosmeticTheme.dimText], for: .normal)
        controlsSegmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
    }

    private func buildRows() {
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

        lipstickControlRows = [lipstickSelectorRow, lipstickIntensityRow, lipstickFinishRow]
        blushControlRows = [blushSelectorRow, blushIntensityRow, blushSizeRow, blushPositionRow]
        hairControlRows = [hairRow]
        debugControlRows = [hairOffsetYRow, hairOffsetZRow, hairScaleRow, visibilityRow]

        addArrangedSubview(controlsSegmentedControl)
        addArrangedSubview(lipstickSelectorRow)
        addArrangedSubview(lipstickIntensityRow)
        addArrangedSubview(lipstickFinishRow)
        addArrangedSubview(blushSelectorRow)
        addArrangedSubview(blushIntensityRow)
        addArrangedSubview(blushSizeRow)
        addArrangedSubview(blushPositionRow)
        addArrangedSubview(hairRow)
        addArrangedSubview(hairOffsetYRow)
        addArrangedSubview(hairOffsetZRow)
        addArrangedSubview(hairScaleRow)
        addArrangedSubview(visibilityRow)
        setSelectedTab(.lipstick)
    }

    private func updateControlTabVisibility() {
        lipstickControlRows.forEach { $0.isHidden = selectedControlTab != .lipstick }
        blushControlRows.forEach { $0.isHidden = selectedControlTab != .blush }
        hairControlRows.forEach { $0.isHidden = selectedControlTab != .hair || !isDemoMode }
        debugControlRows.forEach { $0.isHidden = selectedControlTab != .debug || !isDemoMode }
    }

    private func controlTabTitle(_ tab: MakeupControlTab) -> String {
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

    private func styleSlider(_ slider: UISlider) {
        slider.minimumTrackTintColor = CosmeticTheme.gold
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.13)
        slider.thumbTintColor = UIColor(red: 1.0, green: 0.89, blue: 0.72, alpha: 1.0)
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
        button.layer.borderColor = CosmeticTheme.gold.cgColor
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
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
