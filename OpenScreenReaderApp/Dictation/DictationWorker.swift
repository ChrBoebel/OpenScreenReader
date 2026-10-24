import Darwin
import Foundation

struct DictationWorkerMessage: Decodable, Sendable {
  let type: String
  var id: String? = nil
  var text: String? = nil
  var message: String? = nil
  var version: Int? = nil
  /// Stable worker codes map to localized text; older workers send only `message`.
  var code: String? = nil

  var localizedDetail: String? {
    switch code {
    case "load_failed": String(localized: "The model or local runtime could not be loaded.")
    case "request_too_large": String(localized: "The recording is too large to process.")
    case "processing_failed": String(localized: "The recording could not be processed. Please try again.")
    default: message
    }
  }
}

@MainActor
protocol DictationTranscribing: AnyObject {
  var onMessage: ((DictationWorkerMessage) -> Void)? { get set }
  var ready: Bool { get }
  var running: Bool { get }
  /// `modelRoot` holds an installed model's folder; `nil` uses the bundled one.
  func start(resources: URL, model: DictationModel, modelRoot: URL?)
  func transcribe(_ audio: AudioPacket, id: UUID, language: String?, vocabulary: [String])
  func stop()
}

/// One selected offline ASR process; cancellation invalidates queued messages before termination.
@MainActor
final class DictationWorker: DictationTranscribing {
  var onMessage: ((DictationWorkerMessage) -> Void)?
  private var process: Process?
  private var input: FileHandle?
  private var session = UUID()
  private let writeQueue = DispatchQueue(label: "saywing.dictation.write")
  private var watchdog: Task<Void, Never>?
  /// How the current process ended so far. The generic "ended" message waits until
  /// its output was read to the end, so a specific `fatal` it sent first always wins.
  private var exited = false, drained = false
  private(set) var ready = false
  var running: Bool { process?.isRunning ?? false }

  func start(resources: URL, model: DictationModel, modelRoot: URL?) {
    stop()
    let token = UUID()
    session = token
    signal(SIGPIPE, SIG_IGN)
    let child = Process()
    let stdin = Pipe()
    let stdout = Pipe()
    guard
      let sandbox = WorkerSandbox.arguments(
        resources: resources, modelRoot: modelRoot,
        python: resources.appendingPathComponent("Python/bin/python3"))
    else {
      onMessage?(
        .init(
          type: "fatal",
          message: String(localized: "The local dictation runtime is missing or could not start.")))
      return
    }
    child.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
    child.arguments = sandbox + [
      "-I", "-B", "-u",
      resources.appendingPathComponent("worker.py").path,
      "--model", model.rawValue,
    ] + (modelRoot.map { ["--model-root", $0.path] } ?? [])
    child.currentDirectoryURL = resources
    child.environment = [
      "PATH": "/usr/bin:/bin", "HOME": resources.path,
      "TMPDIR": "/private/tmp", "PYTHONDONTWRITEBYTECODE": "1", "HF_HUB_OFFLINE": "1",
      "TRANSFORMERS_OFFLINE": "1", "HF_HUB_DISABLE_TELEMETRY": "1",
      "TOKENIZERS_PARALLELISM": "false",
    ]
    child.standardInput = stdin
    child.standardOutput = stdout
    child.standardError = FileHandle.nullDevice
    exited = false
    drained = false
    child.terminationHandler = { [weak self] _ in
      DispatchQueue.main.async {
        MainActor.assumeIsolated { self?.processEnded(token, exited: true) }
      }
    }
    do { try child.run() } catch {
      onMessage?(
        .init(
          type: "fatal",
          message: String(localized: "The local dictation runtime is missing or could not start.")))
      return
    }
    process = child
    input = stdin.fileHandleForWriting
    watchdog = Task { [weak self] in
      try? await Task.sleep(for: .seconds(120))
      guard !Task.isCancelled, let self, self.session == token, !self.ready else { return }
      self.stop()
      self.onMessage?(
        .init(
          type: "fatal", message: String(localized: "Loading the dictation model timed out. Please try again.")
        ))
    }
    let reader = stdout.fileHandleForReading
    // Packets and the end of output reach the main queue in the order they were read
    // (FIFO), which unstructured Tasks do not guarantee.
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      defer { try? reader.close() }
      var buffer = Data()
      do {
        while true {
          let data = reader.availableData
          if data.isEmpty {
            DispatchQueue.main.async {
              MainActor.assumeIsolated { self?.processEnded(token, drained: true) }
            }
            break
          }
          buffer.append(data)
          guard buffer.count < 256 * 1024 else { throw DictationError("protocol_limit") }
          while let end = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<end])
            buffer.removeSubrange(...end)
            let packet = try JSONDecoder().decode(DictationWorkerMessage.self, from: line)
            guard ["ready", "result", "error", "fatal"].contains(packet.type),
              packet.type != "ready" || packet.version == 1
            else { throw DictationError("protocol_version") }
            DispatchQueue.main.async {
              MainActor.assumeIsolated {
                guard let self, self.session == token else { return }
                if packet.type == "ready" {
                  self.ready = true
                  self.watchdog?.cancel()
                }
                // The specific reason ends this session; a later exit cannot replace it.
                if packet.type == "fatal" { self.stop() }
                self.onMessage?(packet)
              }
            }
          }
        }
      } catch {
        DispatchQueue.main.async {
          MainActor.assumeIsolated {
            guard let self, self.session == token else { return }
            self.stop()
            self.onMessage?(
              .init(type: "fatal", message: String(localized: "The local dictation model sent an invalid response.")))
          }
        }
      }
    }
  }

  /// Reports the generic end only after the exit and the end of output were both
  /// seen, or shortly after the exit if a descendant keeps the pipe open. A `fatal`
  /// read before that has already stopped this session, so it is never overwritten.
  private func processEnded(_ token: UUID, exited: Bool = false, drained: Bool = false) {
    guard session == token else { return }
    self.exited = self.exited || exited
    self.drained = self.drained || drained
    guard self.exited else { return }
    if self.drained {
      reportEnded(token)
    } else if exited {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        MainActor.assumeIsolated { self?.reportEnded(token) }
      }
    }
  }

  private func reportEnded(_ token: UUID) {
    guard session == token else { return }
    stop()
    onMessage?(.init(type: "fatal", message: String(localized: "The dictation process ended. Please start again.")))
  }

  func transcribe(_ audio: AudioPacket, id: UUID, language: String?, vocabulary: [String]) {
    guard ready, let input else {
      onMessage?(.init(type: "error", id: id.uuidString, message: String(localized: "The model is not ready yet.")))
      return
    }
    let token = session
    writeQueue.async { [weak self] in
      let bytes = audio.samples.withUnsafeBufferPointer { Data(buffer: $0) }
      let request: [String: Any] = [
        "id": id.uuidString, "rate": audio.rate,
        "language": language as Any? ?? NSNull(), "pcm": bytes.base64EncodedString(),
        "vocabulary": vocabulary,
      ]
      do {
        var encoded = try JSONSerialization.data(withJSONObject: request)
        encoded.append(10)
        try input.write(contentsOf: encoded)
      } catch {
        Task { @MainActor in
          guard let self, self.session == token else { return }
          self.onMessage?(
            .init(
              type: "error", id: id.uuidString,
              message: String(localized: "Audio could not be passed to the local model.")))
        }
      }
    }
  }

  func stop() {
    session = UUID()
    ready = false
    watchdog?.cancel()
    watchdog = nil
    let old = process
    process = nil
    // Closing a pipe can wait for a blocked writer. Kill the reader first.
    if let old, old.isRunning {
      old.terminate()
      DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
        if old.isRunning { kill(old.processIdentifier, SIGKILL) }
      }
    }
    let handle = input
    input = nil
    writeQueue.async { try? handle?.close() }
  }
}
