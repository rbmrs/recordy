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
        .frame(minWidth: 520, minHeight: 320)
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

            HStack(spacing: 10) {
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
                .help("Close")

                Divider()
                    .frame(height: 24)

                ToolbarDropdown(
                    title: viewModel.settings.fps.label,
                    options: RecordingFPS.allCases,
                    selection: $viewModel.settings.fps,
                    isOpen: openDropdown == .fps,
                    isEnabled: !viewModel.state.isRecording,
                    width: 116,
                    optionWidth: 82,
                    label: { $0.label },
                    toggle: { toggleDropdown(.fps) },
                    close: { openDropdown = nil }
                )

                ToolbarDropdown(
                    title: viewModel.settings.quality.label,
                    options: QualityProfile.allCases,
                    selection: $viewModel.settings.quality,
                    isOpen: openDropdown == .quality,
                    isEnabled: !viewModel.state.isRecording,
                    width: 128,
                    optionWidth: 96,
                    label: { $0.label },
                    toggle: { toggleDropdown(.quality) },
                    close: { openDropdown = nil }
                )

                ToolbarDropdown(
                    title: viewModel.settings.audioEnabled ? "Audio On" : "Audio Off",
                    options: [false, true],
                    selection: $viewModel.settings.audioEnabled,
                    isOpen: openDropdown == .audio,
                    isEnabled: !viewModel.state.isRecording,
                    width: 118,
                    optionWidth: 92,
                    label: { $0 ? "Audio On" : "Audio Off" },
                    toggle: { toggleDropdown(.audio) },
                    close: { openDropdown = nil }
                )

                Spacer(minLength: 8)

                Text(viewModel.state.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(1)
                    .truncationMode(.middle)

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
                .help(viewModel.state.isRecording ? "Stop recording" : "Start recording")
            }
            .padding(.horizontal, 12)
        }
        .background(.black.opacity(0.72))
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
    static let toolbarHeight: CGFloat = 54
    static let borderWidth: CGFloat = 3
    static let resizeHitWidth: CGFloat = 12
}

enum SettingsDropdown {
    case fps
    case quality
    case audio
}

struct ToolbarDropdown<Option: Hashable>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Option
    let isOpen: Bool
    let isEnabled: Bool
    let width: CGFloat
    let optionWidth: CGFloat
    let label: (Option) -> String
    let toggle: () -> Void
    let close: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
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
                .frame(width: width, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isEnabled ? Color.white.opacity(0.16) : Color.white.opacity(0.08))
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(isEnabled ? .white : .white.opacity(0.45))
            .disabled(!isEnabled)

            if isOpen {
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
                .offset(y: 34)
                .zIndex(10)
            }
        }
        .frame(width: width, height: 38, alignment: .topLeading)
        .zIndex(isOpen ? 20 : 0)
    }
}
