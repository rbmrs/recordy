import Combine
import Foundation

// Updates are delegated entirely to Homebrew — no Sparkle, no custom feed.
// "Check for Updates" runs `brew upgrade --cask recordy` and reads the log;
// "Automatic updates" re-runs the same command detached at quit, when the
// closing .app can be replaced cleanly.
@MainActor
final class HomebrewUpdater: ObservableObject {
    static let shared = HomebrewUpdater()

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case updated
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastChecked: Date?
    @Published var automaticUpdates: Bool {
        didSet { AppPreferences.automaticUpdates = automaticUpdates }
    }

    let currentVersion: String

    private init() {
        currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        automaticUpdates = AppPreferences.automaticUpdates
        lastChecked = AppPreferences.lastUpdateCheck
    }

    var statusMessage: String? {
        switch status {
        case .idle: return nil
        case .checking: return "Checking…"
        case .upToDate: return "Up to date"
        case .updated: return "Updated — relaunch to apply"
        case .failed(let reason): return reason
        }
    }

    func checkForUpdates() {
        guard status != .checking else { return }
        guard let brew = Self.brewURL() else {
            status = .failed("Homebrew not found")
            return
        }
        status = .checking
        Task {
            let result = await Self.runUpgrade(brew: brew)
            status = result
            let now = Date()
            lastChecked = now
            AppPreferences.lastUpdateCheck = now
        }
    }

    // Called on quit. Fire-and-forget: output redirected and never awaited so
    // the child outlives termination and Homebrew can swap the .app in place.
    func runAutomaticUpdateOnQuit() {
        guard automaticUpdates, let brew = Self.brewURL() else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "\(brew.path) update >/dev/null 2>&1 && \(brew.path) upgrade --cask recordy >/dev/null 2>&1"]
        try? process.run()
    }

    nonisolated private static func brewURL() -> URL? {
        for path in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    nonisolated private static func runUpgrade(brew: URL) async -> Status {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-lc", "\(brew.path) update && \(brew.path) upgrade --cask recordy"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: .failed("Update failed"))
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: classify(exitCode: process.terminationStatus, output: output))
            }
        }
    }

    // brew exits 0 whether or not it upgraded, so the log is the only signal.
    // Match only "successfully upgraded" — the up-to-date log says
    // "Not upgrading recordy…", which would false-positive on "upgrading recordy".
    nonisolated static func classify(exitCode: Int32, output: String) -> Status {
        guard exitCode == 0 else { return .failed("Update failed") }
        return output.lowercased().contains("successfully upgraded") ? .updated : .upToDate
    }
}
