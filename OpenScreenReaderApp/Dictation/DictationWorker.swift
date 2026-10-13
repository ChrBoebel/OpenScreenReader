import Darwin
import Foundation

struct DictationWorkerMessage: Decodable, Sendable {
  let type: String
  var id: String? = nil
  var text: String? = nil
  var message: String? = nil
  var version: Int? = nil
}

@MainActor
protocol DictationTranscribing: AnyObject {
  var onMessage: ((DictationWorkerMessage) -> Void)? { get set }
  var ready: Bool { get }
  var running: Bool { get }
  func start(resources: URL, model: DictationModel)
  func transcribe(_ audio: AudioPacket, id: UUID, language: String?)
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
  private(set) var ready = false
  var running: Bool { process?.isRunning ?? false }

  func start(resources: URL, model: DictationModel) {
    stop()
    let token = UUID()
    session = token
    signal(SIGPIPE, SIG_IGN)
    let child = Process()
    let stdin = Pipe()
    let stdout = Pipe()
    child.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
    child.arguments = [
      "-f", resources.appendingPathComponent("worker.sb").path,
      resources.appendingPathComponent("Python/bin/python3").path, "-I", "-B", "-u",
      resources.appendingPathComponent("worker.py").path,
      "--model", model.rawValue,
    ]
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
    child.terminationHandler = { [weak self] _ in
      Task { @MainActor in
        guard let self, self.session == token else { return }
        self.stop()
        self.onMessage?(
          .init(type: "fatal", message: "Der Diktierprozess wurde beendet. Bitte erneut starten."))
      }
    }
    do { try child.run() } catch {
      onMessage?(
        .init(
          type: "fatal",
          message: "Die lokale Diktierlaufzeit fehlt oder konnte nicht gestartet werden."))
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
          type: "fatal", message: "Zeitlimit beim Laden des Diktiermodells. Bitte erneut versuchen."
        ))
    }
    let reader = stdout.fileHandleForReading
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      defer { try? reader.close() }
      var buffer = Data()
      do {
        while true {
          let data = reader.availableData
          if data.isEmpty { break }
          buffer.append(data)
          guard buffer.count < 256 * 1024 else { throw DictationError("protocol_limit") }
          while let end = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<end])
            buffer.removeSubrange(...end)
            let packet = try JSONDecoder().decode(DictationWorkerMessage.self, from: line)
            guard ["ready", "result", "error", "fatal"].contains(packet.type),
              packet.type != "ready" || packet.version == 1
            else { throw DictationError("protocol_version") }
            Task { @MainActor in
              guard let self, self.session == token else { return }
              if packet.type == "ready" {
                self.ready = true
                self.watchdog?.cancel()
              }
              self.onMessage?(packet)
            }
          }
        }
      } catch {
        Task { @MainActor in
          guard let self, self.session == token else { return }
          self.stop()
          self.onMessage?(
            .init(type: "fatal", message: "Ungültige Antwort vom lokalen Diktiermodell."))
        }
      }
    }
  }

  func transcribe(_ audio: AudioPacket, id: UUID, language: String?) {
    guard ready, let input else {
      onMessage?(.init(type: "error", id: id.uuidString, message: "Modell ist noch nicht bereit."))
      return
    }
    let token = session
    writeQueue.async { [weak self] in
      let bytes = audio.samples.withUnsafeBufferPointer { Data(buffer: $0) }
      let request: [String: Any] = [
        "id": id.uuidString, "rate": audio.rate,
        "language": language as Any? ?? NSNull(), "pcm": bytes.base64EncodedString(),
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
              message: "Audio konnte nicht an das lokale Modell übergeben werden."))
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
