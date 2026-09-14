import AppKit
import Observation
import UsageBarCore

@MainActor
@Observable
final class Updater {
  static let shared = Updater()

  private(set) var available: AppRelease?
  private(set) var isInstalling = false
  private(set) var failure: String?

  private var checkTask: Task<Void, Never>?

  private var repository: String? {
    guard let repository = Bundle.main.usageBarUpdateRepository, !repository.isEmpty else {
      return nil
    }
    return repository
  }

  var currentVersion: SemanticVersion {
    SemanticVersion(
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")
      ?? SemanticVersion("0")!
  }

  func startChecking() {
    guard repository != nil else {
      checkTask?.cancel()
      checkTask = nil
      available = nil
      failure = nil
      return
    }

    checkTask?.cancel()
    checkTask = Task { [weak self] in
      while !Task.isCancelled {
        await self?.check()
        try? await Task.sleep(for: .seconds(AppUpdate.checkInterval))
      }
    }
  }

  func check() async {
    guard let repository else {
      available = nil
      failure = nil
      return
    }

    do {
      let latest = try await AppUpdate.fetchLatest(repository: repository)
      available = latest.version > currentVersion ? latest : nil
      failure = nil
    } catch {
      failure = (error as? AppUpdate.ParseError)?.message ?? error.localizedDescription
    }
  }

  func install() {
    guard let release = available, !isInstalling else { return }
    isInstalling = true
    Task {
      do {
        try await Self.install(release, replacing: Bundle.main.bundleURL)
      } catch {
        failure = error.localizedDescription
        isInstalling = false
      }
    }
  }

  /// The bundle cannot replace itself while it is running, so the swap is handed to a
  /// detached shell that waits for this process to exit first, then reopens the app.
  private static func install(_ release: AppRelease, replacing bundle: URL) async throws {
    let work = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("usagebar-update-\(release.tag)")
    try? FileManager.default.removeItem(at: work)
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

    let archive = work.appendingPathComponent(AppUpdate.assetName)
    let (downloaded, response) = try await URLSession.shared.download(from: release.downloadURL)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else {
      throw AppUpdate.ParseError(message: "Download failed (HTTP \(status)).")
    }
    try FileManager.default.moveItem(at: downloaded, to: archive)

    let unpacked = work.appendingPathComponent("unpacked")
    try run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path])

    let staged = unpacked.appendingPathComponent(bundle.lastPathComponent)
    guard
      FileManager.default.fileExists(atPath: staged.appendingPathComponent("Contents/MacOS").path)
    else {
      throw AppUpdate.ParseError(
        message: "The downloaded archive did not contain \(bundle.lastPathComponent).")
    }
    guard FileManager.default.isWritableFile(atPath: bundle.deletingLastPathComponent().path) else {
      throw AppUpdate.ParseError(
        message: "\(bundle.deletingLastPathComponent().path) is not writable.")
    }

    let script = """
      while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
      rm -rf '\(bundle.path)'
      /usr/bin/ditto '\(staged.path)' '\(bundle.path)'
      /usr/bin/xattr -dr com.apple.quarantine '\(bundle.path)' 2>/dev/null
      rm -rf '\(work.path)'
      /usr/bin/open '\(bundle.path)'
      """
    let handoff = Process()
    handoff.executableURL = URL(fileURLWithPath: "/bin/sh")
    handoff.arguments = ["-c", script]
    try handoff.run()

    NSApplication.shared.terminate(nil)
  }

  private static func run(_ tool: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw AppUpdate.ParseError(message: "\(tool) failed with code \(process.terminationStatus).")
    }
  }
}
