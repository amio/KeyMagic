import AppKit
import SwiftUI

struct UtilitiesView: View {
    @Environment(UtilitiesController.self) private var utilities

    @State private var selectedFeatureID: UtilityID? = .keystrokeOverlay
    @State private var isRecordingKeystrokeOverlayHotkey = false
    @State private var isRecordingScreenshotCaptureHotkey = false
    @State private var isRecordingScreenshotMarkHotkey = false

    var body: some View {
        HStack(spacing: 0) {
            featureDirectory
                .frame(width: 280)

            Divider()

            featureDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Utilities")
    }

    private var selectedFeature: UtilityDescriptor {
        let resolvedFeatureID = selectedFeatureID ?? .keystrokeOverlay
        return utilities.descriptor(for: resolvedFeatureID)
    }

    private var featureDirectory: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(utilities.catalog.enumerated()), id: \.element.id) { index, feature in
                    UtilityRow(
                        feature: feature,
                        isOdd: !index.isMultiple(of: 2),
                        isSelected: selectedFeatureID == feature.id
                    )
                    .onTapGesture { selectedFeatureID = feature.id }
                }
            }
        }
    }

    @ViewBuilder
    private var featureDetail: some View {
        switch selectedFeature.id {
        case .keystrokeOverlay:
            KeystrokeOverlaySettingsPane(
                isRecordingHotkey: $isRecordingKeystrokeOverlayHotkey
            )
        case .screenshotTools:
            ScreenshotToolsSettingsPane(
                isRecordingCaptureHotkey: $isRecordingScreenshotCaptureHotkey,
                isRecordingMarkHotkey: $isRecordingScreenshotMarkHotkey
            )
        case .windowManager, .largeType:
            PlannedUtilityPane(feature: selectedFeature)
        }
    }
}

private struct UtilityRow: View {
    @Environment(UtilitiesController.self) private var utilities

    let feature: UtilityDescriptor
    var isOdd: Bool = false
    var isSelected: Bool = false

    private let iconColumnWidth: CGFloat = 22

    var body: some View {
        ListRowContainer(isOdd: isOdd, accentBackground: isSelected ? Color.accentColor.opacity(0.10) : .clear, verticalPadding: 8) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow(alignment: .center) {
                    utilityIcon
                    titleRow
                }

                GridRow {
                    Color.clear
                        .frame(width: iconColumnWidth, height: 1)
                    summaryRow
                }
            }
        }
    }

    private var utilityIcon: some View {
        Image(systemName: feature.systemImage)
            .font(.system(size: feature.directoryIconPointSize, weight: .regular))
            .foregroundStyle(feature.availability == .available ? Color.accentColor : Color.secondary)
            .frame(width: iconColumnWidth)
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text(feature.title)
                .font(.headline)

            featureStatusPill
        }
    }

    @ViewBuilder
    private var featureStatusPill: some View {
        switch feature.availability {
        case .planned:
            StatusPill(title: "Planned", color: .secondary)
        case .available:
            StatusPill(
                title: isFeatureActive ? "Active" : "Off",
                color: isFeatureActive ? .green : .secondary
            )
        }
    }

    private var isFeatureActive: Bool {
        switch feature.id {
        case .keystrokeOverlay:
            utilities.keystrokeOverlay.isEnabled
        case .screenshotTools:
            utilities.screenshotTools.isEnabled
        case .windowManager, .largeType:
            false
        }
    }

    private var summaryRow: some View {
        Text(feature.summary)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }
}

private struct KeystrokeOverlaySettingsPane: View {
    @Environment(UtilitiesController.self) private var utilities
    @Environment(HotkeyService.self) private var hotkeyService

    @Binding var isRecordingHotkey: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                paneHeader
                Form {
                    controlSection
                    appearanceSection
                    previewSection
                    positionSection
                    timingSection
                }
                .settingsFormStyle()
                .scrollDisabled(true)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: utilities.keystrokeOverlay.fontSize) {
                    refreshLivePreview()
                }
                .onChange(of: utilities.keystrokeOverlay.foregroundColor) {
                    refreshLivePreview()
                }
                .onChange(of: utilities.keystrokeOverlay.backgroundColor) {
                    refreshLivePreview()
                }
                .onChange(of: utilities.keystrokeOverlay.verticalPosition) {
                    refreshLivePreview()
                }
                .onChange(of: utilities.keystrokeOverlay.holdDuration) {
                    refreshLivePreview()
                }
                .onChange(of: utilities.keystrokeOverlay.fadeOutDuration) {
                    refreshLivePreview()
                }
            }
        }
    }

    // MARK: - Header

    private var paneHeader: some View {
        let d = utilities.descriptor(for: .keystrokeOverlay)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Label(d.title, systemImage: d.systemImage)
                    .font(.title2.weight(.semibold))
                Spacer()
                Toggle(isOn: Binding(
                    get: { utilities.keystrokeOverlay.isEnabled },
                    set: { utilities.setKeystrokeOverlayEnabled($0) }
                )) { EmptyView() }
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
            }
            Text(d.summary)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controlSection: some View {
        Section {
            if utilities.keystrokeOverlayPermission != .granted {
                permissionAccessRow
            }

            LabeledContent("Toggle Hotkey") {
                HStack(spacing: 8) {
                    HotkeyBindingControl(
                        keyCombo: utilities.keystrokeOverlay.hotkey,
                        isRecording: isRecordingHotkey,
                        onStartRecording: {
                            isRecordingHotkey = true
                        },
                        onRecordKey: { combo in
                            utilities.updateKeystrokeOverlayHotkey(combo)
                            isRecordingHotkey = false
                        },
                        onCancelRecording: {
                            isRecordingHotkey = false
                        },
                        checkConflict: { combo in
                            hotkeyService.hasConflict(
                                keyCombo: combo,
                                excludingUtilityID: .keystrokeOverlay
                            )
                        },
                        emptyTitle: "Record Hotkey"
                    )

                    Button("Default") {
                        utilities.restoreDefaultKeystrokeOverlayHotkey()
                    }
                    .controlSize(.small)
                    .disabled(
                        utilities.keystrokeOverlay.hotkey == KeystrokeOverlayConfiguration.defaultHotkey
                    )
                }
            }
        }
    }

    private var permissionAccessRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                grantInputMonitoringButton
                permissionRecoveryText
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                grantInputMonitoringButton
                permissionRecoveryText
            }
        }
    }

    private var grantInputMonitoringButton: some View {
        Button("Grant Input Monitoring Access") {
            utilities.requestKeystrokeOverlayPermission()
        }
        .controlSize(.small)
        .fixedSize()
    }

    private var permissionRecoveryText: some View {
        Text("If previously denied, re-enable in System Settings › Privacy & Security › Input Monitoring.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var previewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                Text("Preview")
                    .font(.subheadline.weight(.semibold))

                HStack {
                    Spacer(minLength: 0)

                    Text(utilities.keystrokeOverlay.hotkey.displayString)
                        .font(.system(
                            size: utilities.keystrokeOverlay.fontSize,
                            weight: .semibold,
                            design: .rounded
                        ))
                        .tracking(max(0.8, utilities.keystrokeOverlay.fontSize * 0.025))
                        .foregroundStyle(utilities.keystrokeOverlay.foregroundColor.color)
                        .lineLimit(1)
                        .padding(.horizontal, max(18, utilities.keystrokeOverlay.fontSize * 0.48))
                        .padding(.vertical, max(12, utilities.keystrokeOverlay.fontSize * 0.28))
                        .background {
                            RoundedRectangle(
                                cornerRadius: max(18, utilities.keystrokeOverlay.fontSize * 0.42),
                                style: .continuous
                            )
                            .fill(utilities.keystrokeOverlay.backgroundColor.color)
                        }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.black.opacity(0.06))
                )
            }
        }
    }

    private var appearanceSection: some View {
        Section {
            LabeledContent("Font Size") {
                HStack(spacing: 12) {
                    Slider(value: fontSizeBinding.stepped(by: 1), in: 18 ... 72)
                        .frame(width: 200)
                    Text("\(Int(utilities.keystrokeOverlay.fontSize)) pt")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
            }

            LabeledContent("Foreground Color") {
                ColorPicker("", selection: foregroundColorBinding, supportsOpacity: true)
                    .labelsHidden()
                    .frame(height: 16)
            }

            LabeledContent("Background Color") {
                ColorPicker("", selection: backgroundColorBinding, supportsOpacity: true)
                    .labelsHidden()
                    .frame(height: 16)
            }
        } header: {
            Text("Appearance")
        }
    }

    private var positionSection: some View {
        Section {
            LabeledContent("Vertical Position") {
                HStack(spacing: 12) {
                    Slider(value: verticalPositionBinding.stepped(by: 0.01), in: 0 ... 1)
                        .frame(width: 200)
                    Text("\(Int(utilities.keystrokeOverlay.verticalPosition * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
            }
        } header: {
            Text("Position")
        }
    }

    private var timingSection: some View {
        Section {
            LabeledContent("Visible Time") {
                HStack(spacing: 12) {
                    Slider(value: holdDurationBinding.stepped(by: 0.1), in: 0.4 ... 4)
                        .frame(width: 200)
                    Text("\(utilities.keystrokeOverlay.holdDuration.formatted(.number.precision(.fractionLength(2)))) s")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
            }

            LabeledContent("Fade Out") {
                HStack(spacing: 12) {
                    Slider(value: fadeOutDurationBinding.stepped(by: 0.05), in: 0.1 ... 1.4)
                        .frame(width: 200)
                    Text("\(utilities.keystrokeOverlay.fadeOutDuration.formatted(.number.precision(.fractionLength(2)))) s")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
            }
        } header: {
            Text("Timing")
        }
    }

    private var verticalPositionBinding: Binding<Double> {
        Binding(
            get: { utilities.keystrokeOverlay.verticalPosition },
            set: { utilities.keystrokeOverlay.verticalPosition = $0 }
        )
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { utilities.keystrokeOverlay.fontSize },
            set: { utilities.keystrokeOverlay.fontSize = $0 }
        )
    }

    private var holdDurationBinding: Binding<Double> {
        Binding(
            get: { utilities.keystrokeOverlay.holdDuration },
            set: { utilities.keystrokeOverlay.holdDuration = $0 }
        )
    }

    private var fadeOutDurationBinding: Binding<Double> {
        Binding(
            get: { utilities.keystrokeOverlay.fadeOutDuration },
            set: { utilities.keystrokeOverlay.fadeOutDuration = $0 }
        )
    }

    private var foregroundColorBinding: Binding<Color> {
        Binding(
            get: { utilities.keystrokeOverlay.foregroundColor.color },
            set: { utilities.keystrokeOverlay.foregroundColor = RGBAColor(NSColor($0)) }
        )
    }

    private var backgroundColorBinding: Binding<Color> {
        Binding(
            get: { utilities.keystrokeOverlay.backgroundColor.color },
            set: { utilities.keystrokeOverlay.backgroundColor = RGBAColor(NSColor($0)) }
        )
    }

    private func refreshLivePreview() {
        utilities.showKeystrokeOverlayPreview()
    }
}

// MARK: - Helpers

private extension Binding where Value == Double {
    /** Returns a derived binding that snaps to the nearest multiple of `step`, avoiding
     tick marks that SwiftUI adds to `NSSlider` when the `step:` parameter is used. */
    func stepped(by step: Double) -> Binding<Double> {
        Binding(
            get: { wrappedValue },
            set: { wrappedValue = (($0 / step).rounded() * step * 1e10).rounded() / 1e10 }
        )
    }
}

// MARK: - Screenshot Tools Settings

private struct ScreenshotToolsSettingsPane: View {
    @Environment(UtilitiesController.self) private var utilities
    @Environment(HotkeyService.self) private var hotkeyService

    @Binding var isRecordingCaptureHotkey: Bool
    @Binding var isRecordingMarkHotkey: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                paneHeader
                Form {
                    hotkeysSection
                    usageSection
                }
                .settingsFormStyle()
                .scrollDisabled(true)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Header

    private var paneHeader: some View {
        let d = utilities.descriptor(for: .screenshotTools)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Label(d.title, systemImage: d.systemImage)
                    .font(.title2.weight(.semibold))
                Spacer()
                Toggle(isOn: Binding(
                    get: { utilities.screenshotTools.isEnabled },
                    set: { utilities.setScreenshotToolsEnabled($0) }
                )) { EmptyView() }
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
            }
            Text(d.summary)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Hotkeys

    private var hotkeysSection: some View {
        Section("Hotkeys") {
            LabeledContent("Capture to Clipboard") {
                HStack(spacing: 8) {
                    HotkeyBindingControl(
                        keyCombo: utilities.screenshotTools.captureToClipboardHotkey,
                        isRecording: isRecordingCaptureHotkey,
                        onStartRecording: {
                            isRecordingMarkHotkey = false
                            isRecordingCaptureHotkey = true
                        },
                        onRecordKey: { combo in
                            utilities.updateScreenshotCaptureToClipboardHotkey(combo)
                            isRecordingCaptureHotkey = false
                        },
                        onCancelRecording: {
                            isRecordingCaptureHotkey = false
                        },
                        checkConflict: { combo in
                            hotkeyService.hasConflict(
                                keyCombo: combo,
                                excludingUtilityID: .screenshotTools
                            )
                        },
                        emptyTitle: "Record Hotkey"
                    )

                    Button("Default") {
                        utilities.updateScreenshotCaptureToClipboardHotkey(
                            ScreenshotToolsConfiguration.defaultCaptureToClipboardHotkey
                        )
                    }
                    .controlSize(.small)
                    .disabled(
                        utilities.screenshotTools.captureToClipboardHotkey
                            == ScreenshotToolsConfiguration.defaultCaptureToClipboardHotkey
                    )
                }
            }

            LabeledContent("Capture & Mark") {
                HStack(spacing: 8) {
                    HotkeyBindingControl(
                        keyCombo: utilities.screenshotTools.captureAndMarkHotkey,
                        isRecording: isRecordingMarkHotkey,
                        onStartRecording: {
                            isRecordingCaptureHotkey = false
                            isRecordingMarkHotkey = true
                        },
                        onRecordKey: { combo in
                            utilities.updateScreenshotCaptureAndMarkHotkey(combo)
                            isRecordingMarkHotkey = false
                        },
                        onCancelRecording: {
                            isRecordingMarkHotkey = false
                        },
                        checkConflict: { combo in
                            hotkeyService.hasConflict(
                                keyCombo: combo,
                                excludingUtilityID: .screenshotTools
                            )
                        },
                        emptyTitle: "Record Hotkey"
                    )

                    Button("Default") {
                        utilities.updateScreenshotCaptureAndMarkHotkey(
                            ScreenshotToolsConfiguration.defaultCaptureAndMarkHotkey
                        )
                    }
                    .controlSize(.small)
                    .disabled(
                        utilities.screenshotTools.captureAndMarkHotkey
                            == ScreenshotToolsConfiguration.defaultCaptureAndMarkHotkey
                    )
                }
            }
        }
    }

    // MARK: - Usage Guide

    private var usageSection: some View {
        Section("Usage") {
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Capture to Clipboard")
                            .font(.body.weight(.medium))
                        Text("Select a region — copied straight to clipboard, no preview.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "doc.on.clipboard")
                        .foregroundStyle(.secondary)
                }

                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Capture & Mark")
                            .font(.body.weight(.medium))
                        Text("Select a region — opens annotation window. Draw, then press ↩ to copy.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "pencil.and.outline")
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Annotation Shortcuts")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 5) {
                        GridRow {
                            keycap("⌥")
                            Text("Tap to switch freehand / rect, hold to swap temporarily")
                        }
                        GridRow {
                            keycap("TAB")
                            Text("Cycle annotation color")
                        }
                        GridRow {
                            keycap("⌘ Z")
                            Text("Undo")
                        }
                        GridRow {
                            keycap("↩")
                            Text("Copy & close")
                        }
                        GridRow {
                            keycap("ESC")
                            Text("Cancel")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func keycap(_ label: String) -> some View {
        Text(label)
            .font(.system(.caption, design: .rounded, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(.quaternary)
            )
    }
}

// MARK: - Planned Utility

private struct PlannedUtilityPane: View {
    let feature: UtilityDescriptor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Label(feature.title, systemImage: feature.systemImage)
                        .font(.title2.weight(.semibold))

                    Text(feature.summary)
                        .font(.body)
                        .foregroundStyle(.secondary)

                    StatusPill(title: "Planned", color: .secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Planned Surface")
                        .font(.headline)

                    ForEach(feature.highlights, id: \.self) { highlight in
                        Label(highlight, systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }

                Text("This slot already has a dedicated place in the settings IA, so future implementation can add native controls here without changing the top-level structure.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(maxWidth: 680, alignment: .leading)
        }
    }
}

private struct StatusPill: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
            .fixedSize(horizontal: true, vertical: true)
    }
}
