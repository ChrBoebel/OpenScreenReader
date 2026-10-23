import CryptoKit
import Foundation

extension DictationModel {
  /// Shared with worker.py and the packager.
  var directoryName: String {
    switch self {
    case .qwen: "Model"
    case .whisperTurbo: "WhisperTurbo"
    case .whisperLargeV3: "WhisperLargeV3"
    }
  }

  var manifestName: String {
    switch self {
    case .qwen: "model-manifest.json"
    case .whisperTurbo: "whisper-turbo-manifest.json"
    case .whisperLargeV3: "whisper-large-v3-manifest.json"
    }
  }

  /// The only model every build bundles.
  static let standard = DictationModel.whisperTurbo
}

/// Pinned file inventory bundled with the app; the only trust anchor for installs.
struct DictationModelManifest: Decodable, Sendable {
  struct File: Decodable, Sendable {
    let rfilename: String
    let size: Int64
    let verifiedSHA256: String?
    /// Upstream name when the packaged name differs (mlx-whisper expects `weights.safetensors`).
    let sourceFilename: String?
    /// Present for license texts that are not part of the model repository.
    let source: String?

    enum CodingKeys: String, CodingKey {
      case rfilename, size, source
      case verifiedSHA256 = "verified_sha256"
      case sourceFilename = "source_filename"
    }
  }

  let repo: String
  let revision: String
  let files: [File]

  /// Files without a pinned digest (such as `.gitattributes`) are never installed.
  var installableFiles: [File] { files.filter { $0.verifiedSHA256 != nil } }
}

enum DictationModelAvailability: Equatable, Sendable {
  case installed
  case notInstalled
  case installing(fraction: Double)
  case verifying
  case failed(String)

  var isInstalling: Bool {
    switch self { case .installing, .verifying: true; default: false }
  }
}

enum SHA256Digest {
  static func hex(of data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  static func hex(ofFileAt url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 8 * 1024 * 1024), !chunk.isEmpty {
      try Task.checkCancellation()
      hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }
}

protocol DictationModelFetching: Sendable {
  /// Writes the complete response body to `destination`; reports received bytes so far.
  func fetch(_ url: URL, to destination: URL, progress: @escaping @Sendable (Int64) -> Void) async throws
}

/// Knows which dictation models are bundled or installed, and installs missing ones
/// only on explicit request: pinned Hugging Face files, verified before they are used.
@MainActor
final class DictationModelStore: ObservableObject {
  @Published private(set) var availability: [DictationModel: DictationModelAvailability] = [:]
  private let resources: URL
  private let installRoot: URL
  private let fetcher: any DictationModelFetching
  private var tasks: [DictationModel: (id: UUID, task: Task<Void, Never>)] = [:]

  static var defaultInstallRoot: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Saywing/DictationModels", isDirectory: true)
  }

  init(resources: URL, installRoot: URL = DictationModelStore.defaultInstallRoot,
       fetcher: any DictationModelFetching = URLSessionModelFetcher()) {
    self.resources = resources
    self.installRoot = installRoot
    self.fetcher = fetcher
    for model in DictationModel.allCases {
      availability[model] = modelRootIfPresent(for: model) == nil ? .notInstalled : .installed
      restoreBundledLicenses(of: model)
    }
  }

  /// Installs made before their manifest listed a license text (Qwen3-ASR) receive the
  /// copy bundled in the app. Nothing is downloaded or overwritten; the worker still
  /// verifies every manifest file before loading.
  private func restoreBundledLicenses(of model: DictationModel) {
    guard let root = modelRootIfPresent(for: model), root != resources,
          let manifest = try? manifest(for: model) else { return }
    let directory = root.appendingPathComponent(model.directoryName, isDirectory: true)
    for file in manifest.installableFiles where file.source != nil {
      let destination = directory.appendingPathComponent(file.rfilename)
      guard destination.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path + "/"),
            !FileManager.default.fileExists(atPath: destination.path) else { continue }
      try? FileManager.default.copyItem(
        at: resources.appendingPathComponent("Licenses").appendingPathComponent(file.rfilename), to: destination)
    }
  }

  /// The signed bundle declares providers; unknown or malformed declarations fail closed.
  /// Legacy development bundles predate this file and support the original MLX models.
  func isSupported(_ model: DictationModel) -> Bool {
    let url = resources.appendingPathComponent("runtime-backends.json")
    guard FileManager.default.fileExists(atPath: url.path) else { return true }
    guard let data = try? Data(contentsOf: url),
          let backends = try? JSONDecoder().decode([String: String].self, from: data),
          let backend = backends[model.rawValue] else { return false }
    return backend == "mlx" || backend == "whisper.cpp"
  }

  func isInstalled(_ model: DictationModel) -> Bool { availability[model] == .installed }

  /// Directory containing the model's folder when it is not bundled; `nil` for bundled models.
  func modelRoot(for model: DictationModel) -> URL? {
    guard isInstalled(model) else { return nil }
    return modelRootIfPresent(for: model).flatMap { $0 == resources ? nil : $0 }
  }

  func downloadSize(of model: DictationModel) -> Int64? {
    guard let manifest = try? manifest(for: model) else { return nil }
    return manifest.installableFiles.filter { $0.source == nil }.reduce(0) { $0 + $1.size }
  }
  func isBundled(_ model: DictationModel) -> Bool { modelRootIfPresent(for: model) == resources }
  func downloadSource(of model: DictationModel) -> String? { try? manifest(for: model).repo }
  func canDownload(_ model: DictationModel) -> Bool {
    isSupported(model) && model != .whisperTurbo && downloadSize(of: model).map { $0 > 0 } == true
  }

  @discardableResult
  func install(_ model: DictationModel) -> Task<Void, Never> {
    if let running = tasks[model] { return running.task }
    guard canDownload(model), !isInstalled(model) else { return Task {} }
    let id = UUID()
    availability[model] = .installing(fraction: 0)
    let task = Task { [weak self] in
      guard let self else { return }
      let outcome: DictationModelAvailability
      do {
        try await self.performInstall(model, id: id)
        outcome = .installed
      } catch is CancellationError {
        outcome = .notInstalled
      } catch let error as URLError where error.code == .cancelled {
        outcome = .notInstalled
      } catch {
        outcome = .failed(Self.describe(error))
      }
      // A cancelled and restarted install must not be overwritten by the old task.
      guard self.tasks[model]?.id == id else { return }
      self.tasks[model] = nil
      self.availability[model] = outcome
    }
    tasks[model] = (id, task)
    return task
  }

  func cancelInstall(_ model: DictationModel) {
    tasks[model]?.task.cancel()
  }

  private func modelRootIfPresent(for model: DictationModel) -> URL? {
    guard isSupported(model) else { return nil }
    return [resources, installRoot].first { root in
      var isDirectory: ObjCBool = false
      return FileManager.default.fileExists(
        atPath: root.appendingPathComponent(model.directoryName).path, isDirectory: &isDirectory)
        && isDirectory.boolValue
    }
  }

  private func manifest(for model: DictationModel) throws -> DictationModelManifest {
    try JSONDecoder().decode(
      DictationModelManifest.self,
      from: Data(contentsOf: resources.appendingPathComponent(model.manifestName)))
  }

  private func performInstall(_ model: DictationModel, id: UUID) async throws {
    let manifest = try manifest(for: model)
    let manager = FileManager.default
    try manager.createDirectory(at: installRoot, withIntermediateDirectories: true)
    let total = max(1, downloadSize(of: model) ?? 1)
    if let free = try? installRoot.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
      .volumeAvailableCapacityForImportantUsage, free < total + total / 10 {
      throw DictationError(String(localized: "Not enough free disk space for this model."))
    }
    // Only one install per model runs at a time, so older staging folders are leftovers of a quit app.
    let prefix = ".staging-\(model.directoryName)-"
    for leftover in (try? manager.contentsOfDirectory(atPath: installRoot.path)) ?? [] where leftover.hasPrefix(prefix) {
      try? manager.removeItem(at: installRoot.appendingPathComponent(leftover))
    }
    let staging = installRoot.appendingPathComponent(prefix + UUID().uuidString, isDirectory: true)
    try manager.createDirectory(at: staging, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: staging) }
    var completed: Int64 = 0
    var checks: [(URL, Int64, String)] = []
    for file in manifest.installableFiles {
      try Task.checkCancellation()
      let destination = staging.appendingPathComponent(file.rfilename)
      guard destination.standardizedFileURL.path.hasPrefix(staging.standardizedFileURL.path + "/") else {
        throw DictationError(String(localized: "The model could not be installed."))
      }
      if file.source != nil {
        // License texts ship inside the app; they are copied, not downloaded.
        try manager.copyItem(at: resources.appendingPathComponent("Licenses").appendingPathComponent(file.rfilename),
                             to: destination)
      } else {
        let url = URL(string: "https://huggingface.co/\(manifest.repo)/resolve/\(manifest.revision)/")!
          .appendingPathComponent(file.sourceFilename ?? file.rfilename)
        let base = completed
        try await fetcher.fetch(url, to: destination) { [weak self] received in
          Task { @MainActor in
            guard let self, self.tasks[model]?.id == id,
                  case .installing = self.availability[model] else { return }
            self.availability[model] = .installing(fraction: min(1, Double(base + received) / Double(total)))
          }
        }
        completed += file.size
      }
      checks.append((destination, file.size, file.verifiedSHA256 ?? ""))
    }
    try Task.checkCancellation()
    availability[model] = .verifying
    for (file, size, hash) in checks {
      try Task.checkCancellation()
      try await Self.verify(file, size: size, sha256: hash)
    }
    try Task.checkCancellation()
    let target = installRoot.appendingPathComponent(model.directoryName, isDirectory: true)
    if manager.fileExists(atPath: target.path) { try manager.removeItem(at: target) }
    // The final directory appears only after every file has been verified.
    try manager.moveItem(at: staging, to: target)
  }

  private nonisolated static func verify(_ file: URL, size: Int64, sha256: String) async throws {
    let verification = Task.detached(priority: .utility) {
      let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
      guard (attributes[.size] as? NSNumber)?.int64Value == size,
        try SHA256Digest.hex(ofFileAt: file) == sha256
      else { throw DictationError(String(localized: "A downloaded model file did not match its pinned checksum.")) }
    }
    try await withTaskCancellationHandler {
      try await verification.value
    } onCancel: { verification.cancel() }
  }

  private static func describe(_ error: any Error) -> String {
    if let error = error as? DictationError { return error.message }
    if error is URLError { return String(localized: "The model could not be downloaded. Check the connection and try again.") }
    return String(localized: "The model could not be installed.")
  }
}

/// Plain HTTPS downloads without cookies or caches; redirects may only stay on Hugging Face.
final class URLSessionModelFetcher: NSObject, DictationModelFetching, URLSessionDownloadDelegate, @unchecked Sendable {
  private let lock = NSLock()
  private var pending: [Int: (destination: URL, progress: @Sendable (Int64) -> Void,
                              continuation: CheckedContinuation<Void, any Error>)] = [:]
  private lazy var session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.urlCache = nil
    configuration.httpAdditionalHeaders = ["User-Agent": "Saywing"]
    return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
  }()

  static func allows(_ url: URL) -> Bool {
    guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
    return host == "huggingface.co" || host.hasSuffix(".huggingface.co") || host == "hf.co"
      || host.hasSuffix(".hf.co")
  }

  func fetch(_ url: URL, to destination: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
    guard Self.allows(url) else { throw URLError(.unsupportedURL) }
    let task = session.downloadTask(with: url)
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        lock.withLock { pending[task.taskIdentifier] = (destination, progress, continuation) }
        task.resume()
      }
    } onCancel: {
      task.cancel()
    }
  }

  private func finish(_ task: URLSessionTask, _ result: Result<Void, any Error>) {
    let entry = lock.withLock { pending.removeValue(forKey: task.taskIdentifier) }
    entry?.continuation.resume(with: result)
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
    guard let url = request.url, Self.allows(url) else {
      task.cancel()
      completionHandler(nil)
      return
    }
    completionHandler(request)
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                  totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
    let progress = lock.withLock { pending[downloadTask.taskIdentifier]?.progress }
    progress?(totalBytesWritten)
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    guard let destination = lock.withLock({ pending[downloadTask.taskIdentifier]?.destination }) else { return }
    guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200 else {
      finish(downloadTask, .failure(URLError(.badServerResponse)))
      return
    }
    // The temporary file disappears when this method returns.
    do {
      try FileManager.default.moveItem(at: location, to: destination)
      finish(downloadTask, .success(()))
    } catch {
      finish(downloadTask, .failure(error))
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
    // Success was already reported after the file was moved; this only catches failures.
    finish(task, error.map { .failure($0) } ?? .failure(URLError(.badServerResponse)))
  }
}
