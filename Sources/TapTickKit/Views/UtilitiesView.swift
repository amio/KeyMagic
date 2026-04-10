import AppKit
import SwiftUI

struct UtilitiesView: View {
    @Environment(UtilitiesController.self) private var utilities

    @State private var selectedFeatureID: UtilityID? = .keystrokeOverlay
    @State private var isRecordingKeystrokeOverlayHotkey = false

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
        case .screenshotTools, .windowManager, .largeType:
            PlannedUtilityPane(feature: selectedFeature)
        }
    }
}

private struct UtilityRow: View {
    let feature: UtilityDescriptor
    var isOdd: Bool = false
    var isSelected: Bool = false

    var body: some View {
        ListRowContainer(isOdd: isOdd, accentBackground: isSelected ? Color.accentColor.opacity(0.10) : .clear, verticalPadding: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: feature.systemImage)
                    .font(.title3)
                    .foregroundStyle(feature.availability == .available ? Color.accentColor : Color.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(feature.title)
                            .font(.headline)

                        Text(feature.availability.badgeTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(feature.availability == .available ? .green : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(feature.availability == .available ? Color.green.opacity(0.12) : Color.secondary.opacity(0.12))
                            )
                    }

                    Text(feature.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

private struct KeystrokeOverlaySettingsPane: View {
    @Environment(UtilitiesController.self) private var utilities
    @Environment(HotkeyService.self) private var hotkeyService

    @Binding var isRecordingHotkey: Bool

    var body: some View {
        Form {
            statusSection
            hotkeySection
            previewSection
            appearanceSection
            positionSection
            timingSection
        }
        .formStyle(.grouped)
    }

    private var statusSection: some View {
        Section {
            Toggle(
                "Enable Keystroke Overlay",
                isOn: Binding(
                    get: { utilities.keystrokeOverlay.isEnabled },
                    set: { utilities.setKeystrokeOverlayEnabled($0) }
                )
            )

            HStack {
                Text("Capture Status")
                Spacer(minLength: 16)
                StatusPill(
                    title: utilities.isKeystrokeOverlayCapturing ? "Active" : "Inactive",
                    color: utilities.isKeystrokeOverlayCapturing ? .green : .secondary
                )
            }

            HStack {
                Text("Input Monitoring")
                Spacer(minLength: 16)
                StatusPill(
                    title: utilities.keystrokeOverlayPermission.title,
                    color: utilities.keystrokeOverlayPermission == .granted ? .green : .orange
                )
            }

            if utilities.keystrokeOverlayPermission != .granted {
                Button("Request Input Monitoring Access") {
                    utilities.requestKeystrokeOverlayPermission()
                }
                .controlSize(.small)

                Text("TapTick uses macOS input event listening to observe global keyboard input for this overlay. If you previously denied access, re-enable TapTick in System Settings > Privacy & Security > Input Monitoring.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Status")
        }
    }

    private var hotkeySection: some View {
        Section {
            LabeledContent("Toggle Overlay") {
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

            Text("This reserved hotkey enables or disables the subtitle overlay without opening TapTick.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Hotkey")
        }
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

                Text("The live overlay appears near the lower center of the active screen and reuses these style settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            .onChange(of: utilities.keystrokeOverlay.verticalPosition) {
                utilities.showKeystrokeOverlayPreview()
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
            .onChange(of: utilities.keystrokeOverlay.holdDuration) {
                utilities.showKeystrokeOverlayPreview()
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
            .onChange(of: utilities.keystrokeOverlay.fadeOutDuration) {
                utilities.showKeystrokeOverlayPreview()
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
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
    }
}