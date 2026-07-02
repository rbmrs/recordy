import SwiftUI

struct RecorderView: View {
    @ObservedObject var viewModel: RecorderViewModel
    @State private var openDropdown: SettingsDropdown?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.04))

            Rectangle()
                .stroke(viewModel.state.isRecording ? Color.red : Color.accentColor, lineWidth: 3)

            VStack(spacing: 0) {
                toolbar
                    .frame(height: CaptureLayout.toolbarHeight)

                Rectangle()
                    .fill(Color.clear)
                    .overlay {
                        if !viewModel.state.isRecording {
                            Rectangle()
                                .strokeBorder(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
                                .padding(10)
                        }
                    }
            }
        }
        .frame(minWidth: CaptureLayout.minimumWindowSize.width, minHeight: CaptureLayout.minimumWindowSize.height)
        .onChange(of: openDropdown) { _, newValue in
            viewModel.settingsDropdownOpen = newValue != nil
        }
        .onDisappear {
            viewModel.settingsDropdownOpen = false
        }
    }

    private var toolbar: some View {
        ZStack {
            WindowDragArea()

            HStack(spacing: 6) {
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.white)
                .background(Circle().fill(Color.red.opacity(0.9)))
                .frame(width: 38, height: CaptureLayout.toolbarControlSlotHeight)
                .help("Close")

                Divider()
                    .frame(height: 24)

                ToolbarDropdown(
                    title: viewModel.settings.fps.label,
                    isEnabled: !viewModel.state.isRecording,
                    width: 92,
                    toggle: { toggleDropdown(.fps) }
                )

                ToolbarDropdown(
                    title: viewModel.settings.quality.label,
                    isEnabled: !viewModel.state.isRecording,
                    width: 112,
                    toggle: { toggleDropdown(.quality) }
                )

                ToolbarDropdown(
                    title: viewModel.settings.aspectRatio.label,
                    isEnabled: !viewModel.state.isRecording,
                    width: 72,
                    toggle: { toggleDropdown(.aspectRatio) }
                )

                ToolbarDropdown(
                    title: viewModel.settings.systemAudio.label,
                    isEnabled: !viewModel.state.isRecording,
                    width: 96,
                    toggle: { toggleDropdown(.audio) }
                )

                ToolbarDropdown(
                    title: viewModel.settings.microphone.label,
                    isEnabled: !viewModel.state.isRecording,
                    width: 96,
                    toggle: {
                        viewModel.refreshMicrophones()
                        toggleDropdown(.microphone)
                    }
                )

                ToolbarDropdown(
                    title: viewModel.settings.camera.label,
                    isEnabled: !viewModel.state.isRecording,
                    width: 96,
                    toggle: {
                        viewModel.refreshCameras()
                        toggleDropdown(.camera)
                    }
                )

                Button {
                    viewModel.toggleCameraShape()
                } label: {
                    Image(systemName: viewModel.cameraShape == .circle ? "circle" : "square")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: CaptureLayout.toolbarControlHeight, height: CaptureLayout.toolbarControlHeight)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color.white.opacity(viewModel.settings.camera.isEnabled ? 0.16 : 0.08))
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(viewModel.settings.camera.isEnabled ? .white : .white.opacity(0.45))
                .disabled(!viewModel.settings.camera.isEnabled || viewModel.state.isRecording)
                .frame(width: 34, height: CaptureLayout.toolbarControlSlotHeight)
                .help("Toggle webcam shape")

                Button {
                    toggleDropdown(.settings)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: CaptureLayout.toolbarControlHeight, height: CaptureLayout.toolbarControlHeight)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(openDropdown == .settings ? Color.accentColor.opacity(0.92) : Color.white.opacity(0.16))
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(viewModel.state.isRecording ? .white.opacity(0.45) : .white)
                .disabled(viewModel.state.isRecording)
                .frame(width: 34, height: CaptureLayout.toolbarControlSlotHeight)
                .help("Settings")

                Spacer(minLength: 8)

                Text(viewModel.state.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 80, alignment: .trailing)

                Button {
                    openDropdown = nil
                    viewModel.toggleRecording()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: viewModel.state.isRecording ? "stop.fill" : "record.circle.fill")
                        Text(viewModel.state.isRecording ? "Stop" : "Record")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 96, height: 32)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(viewModel.state.isRecording ? Color.red : Color.green)
                )
                .disabled(viewModel.state == .preparing || viewModel.state == .stopping)
                .frame(height: CaptureLayout.toolbarControlSlotHeight)
                .help(viewModel.state.isRecording ? "Stop recording" : "Start recording")
            }
            .padding(.horizontal, 10)
            .frame(height: CaptureLayout.toolbarControlSlotHeight, alignment: .center)
        }
        .frame(height: CaptureLayout.toolbarHeight)
        .background(.black.opacity(0.72))
        .overlay(alignment: .topLeading) {
            dropdownOverlay
        }
    }

    @ViewBuilder
    private var dropdownOverlay: some View {
        switch openDropdown {
        case .fps:
            DropdownPopup(
                options: RecordingFPS.allCases,
                selection: $viewModel.settings.fps,
                optionWidth: 82,
                label: { $0.label },
                close: { openDropdown = nil }
            )
            .offset(x: CaptureLayout.fpsDropdownX, y: CaptureLayout.dropdownPopupY)
        case .quality:
            DropdownPopup(
                options: QualityProfile.allCases,
                selection: $viewModel.settings.quality,
                optionWidth: 96,
                label: { $0.label },
                close: { openDropdown = nil }
            )
            .offset(x: CaptureLayout.qualityDropdownX, y: CaptureLayout.dropdownPopupY)
        case .aspectRatio:
            DropdownPopup(
                options: CaptureAspectRatio.allCases,
                selection: $viewModel.settings.aspectRatio,
                optionWidth: 66,
                label: { $0.label },
                close: { openDropdown = nil }
            )
            .offset(x: CaptureLayout.aspectRatioDropdownX, y: CaptureLayout.dropdownPopupY)
        case .audio:
            DropdownPopup(
                options: SystemAudioSource.allCases,
                selection: $viewModel.settings.systemAudio,
                optionWidth: 104,
                label: { $0.label },
                close: { openDropdown = nil }
            )
            .offset(x: CaptureLayout.audioDropdownX, y: CaptureLayout.dropdownPopupY)
        case .microphone:
            DropdownPopup(
                options: viewModel.microphoneOptions,
                selection: $viewModel.settings.microphone,
                optionWidth: 160,
                label: { $0.label },
                close: { openDropdown = nil }
            )
            .offset(x: CaptureLayout.microphoneDropdownX, y: CaptureLayout.dropdownPopupY)
        case .camera:
            DropdownPopup(
                options: viewModel.cameraOptions,
                selection: $viewModel.settings.camera,
                optionWidth: 160,
                label: { $0.label },
                close: { openDropdown = nil }
            )
            .offset(x: CaptureLayout.cameraDropdownX, y: CaptureLayout.dropdownPopupY)
        case .settings:
            RecorderSettingsPopup(audioTrackMode: $viewModel.settings.audioTrackMode, updater: HomebrewUpdater.shared)
                .offset(x: CaptureLayout.settingsPopupX, y: CaptureLayout.dropdownPopupY)
        case nil:
            EmptyView()
        }
    }

    private func toggleDropdown(_ dropdown: SettingsDropdown) {
        guard !viewModel.state.isRecording else {
            return
        }
        openDropdown = openDropdown == dropdown ? nil : dropdown
    }
}

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView {
        DragView()
    }

    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

enum CaptureLayout {
    static let minimumWindowSize = NSSize(width: 900, height: 320)
    static let toolbarHeight: CGFloat = 54
    static let borderWidth: CGFloat = 3
    static let resizeHitWidth: CGFloat = 12
    static let toolbarControlHeight: CGFloat = 30
    static let toolbarControlSlotHeight: CGFloat = 38
    static let dropdownPopupY: CGFloat = 44
    static let fpsDropdownX: CGFloat = 62
    static let qualityDropdownX: CGFloat = 163
    static let aspectRatioDropdownX: CGFloat = 274
    static let audioDropdownX: CGFloat = 347
    static let microphoneDropdownX: CGFloat = 421
    static let cameraDropdownX: CGFloat = 523
    static let settingsPopupX: CGFloat = 596
}

enum SettingsDropdown {
    case fps
    case quality
    case aspectRatio
    case audio
    case microphone
    case camera
    case settings
}

struct ToolbarDropdown: View {
    let title: String
    let isEnabled: Bool
    let width: CGFloat
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .frame(width: width, height: CaptureLayout.toolbarControlHeight)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isEnabled ? Color.white.opacity(0.16) : Color.white.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? .white : .white.opacity(0.45))
        .disabled(!isEnabled)
        .frame(width: width, height: CaptureLayout.toolbarControlSlotHeight, alignment: .center)
    }
}

struct DropdownPopup<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let optionWidth: CGFloat
    let label: (Option) -> String
    let close: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button {
                    selection = option
                    close()
                } label: {
                    Text(label(option))
                        .font(.system(size: 12, weight: selection == option ? .semibold : .regular))
                        .lineLimit(1)
                        .frame(width: optionWidth, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(selection == option ? Color.accentColor.opacity(0.92) : Color.white.opacity(0.14))
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.black.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
        .shadow(radius: 8, y: 4)
        .zIndex(50)
    }
}

struct RecorderSettingsPopup: View {
    @Binding var audioTrackMode: AudioTrackMode
    @ObservedObject var updater: HomebrewUpdater

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings")
                .font(.system(size: 13, weight: .semibold))

            Divider()

            Text("Audio tracks")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))

            HStack(spacing: 0) {
                ForEach(AudioTrackMode.allCases) { mode in
                    Button {
                        audioTrackMode = mode
                    } label: {
                        Text(mode.label)
                            .font(.system(size: 12, weight: audioTrackMode == mode ? .semibold : .regular))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(audioTrackMode == mode ? Color.accentColor.opacity(0.92) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                }
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.12))
            )

            Divider()

            updatesSection
        }
        .padding(10)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.black.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
        .foregroundStyle(.white)
        .shadow(radius: 8, y: 4)
        .zIndex(50)
    }

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Updates")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))

            HStack {
                Text("Version")
                    .font(.system(size: 12))
                Spacer()
                Text(updater.currentVersion)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Toggle(isOn: $updater.automaticUpdates) {
                Text("Automatic updates")
                    .font(.system(size: 12))
            }
            .toggleStyle(.switch)
            .tint(.accentColor)
            .controlSize(.mini)

            Text("When on, Recordy installs the latest version with Homebrew when you quit.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)

            if let message = updater.statusMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            } else if let checked = updater.lastChecked {
                Text("Last checked \(Self.dateFormatter.string(from: checked))")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }

            Button {
                updater.checkForUpdates()
            } label: {
                Text(updater.status == .checking ? "Checking…" : "Check for Updates…")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.14))
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .disabled(updater.status == .checking)
        }
    }
}
