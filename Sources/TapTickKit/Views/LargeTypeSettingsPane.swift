import AppKit
import SwiftUI

struct LargeTypeSettingsPane: View {
    @Environment(UtilitiesController.self) private var utilities
    @Environment(HotkeyService.self) private var hotkeyService

    @Binding var isRecordingHotkey: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                paneHeader

                Form {
                    hotkeySection
                    appearanceSection
                    previewSection
                    usageSection
                }
                .settingsFormStyle()
                .scrollDisabled(true)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var paneHeader: some View {
        let descriptor = utilities.descriptor(for: .largeType)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Label(descriptor.title, systemImage: descriptor.systemImage)
                    .font(.title2.weight(.semibold))

                Spacer()

                Toggle(
                    isOn: Binding(
                        get: { utilities.largeType.isEnabled },
                        set: { utilities.setLargeTypeEnabled($0) }
                    )
                ) { EmptyView() }
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
            }

            Text(descriptor.summary)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hotkeySection: some View {
        Section("Hotkey") {
            LabeledContent("Show Large Type") {
                HStack(spacing: 8) {
                    HotkeyBindingControl(
                        keyCombo: utilities.largeType.hotkey,
                        isRecording: isRecordingHotkey,
                        onStartRecording: {
                            isRecordingHotkey = true
                        },
                        onRecordKey: { combo in
                            utilities.updateLargeTypeHotkey(combo)
                            isRecordingHotkey = false
                        },
                        onCancelRecording: {
                            isRecordingHotkey = false
                        },
                        checkConflict: { combo in
                            hotkeyService.hasConflict(
                                keyCombo: combo,
                                excludingUtilityID: .largeType
                            )
                        },
                        emptyTitle: "Record Hotkey"
                    )

                    Button("Default") {
                        utilities.restoreDefaultLargeTypeHotkey()
                    }
                    .controlSize(.small)
                    .disabled(utilities.largeType.hotkey == LargeTypeConfiguration.defaultHotkey)
                }
            }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            LabeledContent("Font") {
                Picker("", selection: fontFamilyBinding) {
                    Text("System Default")
                        .tag("")

                    Divider()

                    ForEach(NSFontManager.shared.availableFontFamilies, id: \.self) { family in
                        Text(family)
                            .font(.custom(family, size: 13))
                            .tag(family)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 220)
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
        }
    }

    private var previewSection: some View {
        Section("Preview") {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(utilities.largeType.backgroundColor.color)

                Text("Large Type")
                    .font(previewFont)
                    .foregroundStyle(utilities.largeType.foregroundColor.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(24)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 118)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var usageSection: some View {
        Section("How It Works") {
            VStack(alignment: .leading, spacing: 10) {
                Label("Type normally after the full-screen overlay opens.", systemImage: "keyboard")
                Label("Press Escape or the global hotkey again to close.", systemImage: "escape")
                Label("Press Option or use the QR button to switch views.", systemImage: "qrcode")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var fontFamilyBinding: Binding<String> {
        Binding(
            get: { utilities.largeType.fontFamily ?? "" },
            set: { utilities.largeType.fontFamily = $0.isEmpty ? nil : $0 }
        )
    }

    private var foregroundColorBinding: Binding<Color> {
        Binding(
            get: { utilities.largeType.foregroundColor.color },
            set: { utilities.largeType.foregroundColor = RGBAColor(NSColor($0)) }
        )
    }

    private var backgroundColorBinding: Binding<Color> {
        Binding(
            get: { utilities.largeType.backgroundColor.color },
            set: { utilities.largeType.backgroundColor = RGBAColor(NSColor($0)) }
        )
    }

    private var previewFont: Font {
        if let family = utilities.largeType.fontFamily {
            return .custom(family, size: 44)
        }

        return .system(size: 44, weight: .regular)
    }
}
