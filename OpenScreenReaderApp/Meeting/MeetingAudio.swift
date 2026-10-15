import AVFoundation
import CoreAudio
import Foundation

/// A short piece of mono audio from one source, stamped with the host time of its
/// first sample. Chunks are handed on immediately and never stored.
struct MeetingAudioChunk: Sendable {
  let samples: [Float]
  let sampleRate: Double
  let hostTime: UInt64
}

struct MeetingError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
  init(_ message: String) { self.message = message }
}

/// One live input of a meeting transcript. Start delivers chunks on an audio
/// thread until stop; stop is immediate and may be called repeatedly.
@MainActor
protocol MeetingAudioSource: AnyObject {
  func start(deliver: @escaping @Sendable (MeetingAudioChunk) -> Void) throws
  func stop()
}

enum MeetingHostClock {
  private static let timebase: mach_timebase_info_data_t = {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return info
  }()

  static func seconds(_ ticks: UInt64) -> TimeInterval {
    Double(ticks) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
  }

  static func hostTicks(forSeconds seconds: TimeInterval) -> UInt64 {
    UInt64(seconds * 1_000_000_000 * Double(timebase.denom) / Double(timebase.numer))
  }

  static var now: UInt64 { mach_absolute_time() }
}

enum MeetingAudioMixdown {
  /// Averages all channels of 32-bit float PCM, interleaved or not. Other sample
  /// formats return nil so they are never misread as noise.
  static func mono(
    _ list: UnsafePointer<AudioBufferList>, frames: AVAudioFrameCount, format: AudioStreamBasicDescription
  ) -> [Float]? {
    guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
      format.mBitsPerChannel == 32, format.mChannelsPerFrame > 0
    else { return nil }
    let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
    let count = Int(frames)
    var mono = [Float](repeating: 0, count: count)
    if format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 {
      let channels = buffers.compactMap { $0.mData?.assumingMemoryBound(to: Float.self) }
      guard !channels.isEmpty else { return nil }
      for channel in channels {
        for frame in 0..<count { mono[frame] += channel[frame] }
      }
      let scale = 1 / Float(channels.count)
      for frame in 0..<count { mono[frame] *= scale }
    } else {
      guard let data = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return nil }
      let stride = Int(format.mChannelsPerFrame)
      for frame in 0..<count {
        var sum: Float = 0
        for channel in 0..<stride { sum += data[frame * stride + channel] }
        mono[frame] = sum / Float(stride)
      }
    }
    return mono
  }
}

/// Resamples mono float chunks with one long-lived converter per track, so its
/// filter state carries across chunks and no clicks appear at chunk borders.
enum MeetingResampler {
  /// The converter's input block runs synchronously inside `convert`; the box only
  /// satisfies its `@Sendable` signature and hands the chunk over exactly once.
  private final class Feed: @unchecked Sendable {
    var buffer: AVAudioPCMBuffer?
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
  }

  static func convert(_ samples: [Float], with converter: AVAudioConverter) -> AVAudioPCMBuffer? {
    let input = converter.inputFormat
    let output = converter.outputFormat
    guard !samples.isEmpty,
      let buffer = AVAudioPCMBuffer(pcmFormat: input, frameCapacity: AVAudioFrameCount(samples.count)),
      let channel = buffer.floatChannelData?[0]
    else { return nil }
    buffer.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
    let capacity = AVAudioFrameCount(Double(samples.count) * output.sampleRate / input.sampleRate) + 64
    guard let result = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return nil }
    let feed = Feed(buffer)
    var error: NSError?
    converter.convert(to: result, error: &error) { _, status in
      guard let next = feed.buffer else {
        status.pointee = .noDataNow
        return nil
      }
      feed.buffer = nil
      status.pointee = .haveData
      return next
    }
    return error == nil && result.frameLength > 0 ? result : nil
  }
}

/// "Me": the default microphone through its own engine, independent of dictation.
@MainActor
final class MeetingMicrophoneSource: MeetingAudioSource {
  private let engine = AVAudioEngine()
  private var installed = false

  func start(deliver: @escaping @Sendable (MeetingAudioChunk) -> Void) throws {
    let node = engine.inputNode
    let format = node.outputFormat(forBus: 0)
    guard format.sampleRate >= 8_000, format.channelCount > 0, format.commonFormat == .pcmFormatFloat32 else {
      throw MeetingError(String(localized: "This microphone format is not supported yet."))
    }
    node.installTap(
      onBus: 0, bufferSize: 4_096, format: format,
      block: Self.makeTap(format: format.streamDescription.pointee, deliver: deliver))
    installed = true
    do {
      engine.prepare()
      try engine.start()
    } catch {
      stop()
      throw error
    }
  }

  // AVAudioEngine calls this on its audio queue. Copy the PCM synchronously:
  // the engine owns the buffer.
  nonisolated private static func makeTap(
    format: AudioStreamBasicDescription, deliver: @escaping @Sendable (MeetingAudioChunk) -> Void
  ) -> AVAudioNodeTapBlock {
    { buffer, time in
      guard let samples = MeetingAudioMixdown.mono(buffer.audioBufferList, frames: buffer.frameLength, format: format)
      else { return }
      let host = time.isHostTimeValid ? time.hostTime : MeetingHostClock.now
      deliver(MeetingAudioChunk(samples: samples, sampleRate: format.mSampleRate, hostTime: host))
    }
  }

  func stop() {
    if installed {
      engine.inputNode.removeTap(onBus: 0)
      installed = false
    }
    engine.stop()
  }
}

/// "Others": everything the Mac plays, except Saywing itself, through a private
/// Core Audio process tap inside a private aggregate device (macOS 14.2+). The first
/// start makes macOS ask for system audio recording; a denied request delivers
/// silence rather than an error, which the transcript window points out.
@available(macOS 14.2, *)
@MainActor
final class SystemAudioTapSource: MeetingAudioSource {
  private var tapID = AudioObjectID(kAudioObjectUnknown)
  private var aggregateID = AudioObjectID(kAudioObjectUnknown)
  private var procID: AudioDeviceIOProcID?
  private let queue = DispatchQueue(label: "Saywing.meeting.system-audio", qos: .userInitiated)

  func start(deliver: @escaping @Sendable (MeetingAudioChunk) -> Void) throws {
    stop()
    do {
      let own = try? Self.read(
        AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyTranslatePIDToProcessObject,
        qualifier: getpid(), as: AudioObjectID.self)
      let description = CATapDescription(
        monoGlobalTapButExcludeProcesses: own.map { $0 == kAudioObjectUnknown ? [] : [$0] } ?? [])
      description.uuid = UUID()
      description.name = "Saywing meeting transcript"
      description.isPrivate = true
      description.muteBehavior = .unmuted
      try Self.check(AudioHardwareCreateProcessTap(description, &tapID))

      // Only the tap, as in Apple's sample: an output device with its own inputs
      // (a headset) would otherwise add streams ahead of the tap's.
      let aggregate: [String: Any] = [
        kAudioAggregateDeviceNameKey: "Saywing Meeting",
        kAudioAggregateDeviceUIDKey: UUID().uuidString,
        kAudioAggregateDeviceIsPrivateKey: true,
        kAudioAggregateDeviceTapAutoStartKey: true,
        kAudioAggregateDeviceTapListKey: [
          [kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]
        ],
      ]
      try Self.check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID))

      let format = try Self.read(tapID, kAudioTapPropertyFormat, as: AudioStreamBasicDescription.self)
      try Self.check(
        AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue, Self.makeBlock(format: format, deliver: deliver)))
      try Self.check(AudioDeviceStart(aggregateID, procID))
    } catch {
      stop()
      throw error
    }
  }

  nonisolated private static func makeBlock(
    format: AudioStreamBasicDescription, deliver: @escaping @Sendable (MeetingAudioChunk) -> Void
  ) -> AudioDeviceIOBlock {
    { _, input, inputTime, _, _ in
      let bytesPerFrame = max(format.mBytesPerFrame, 1)
      let frames = AVAudioFrameCount(input.pointee.mBuffers.mDataByteSize / bytesPerFrame)
      guard frames > 0, let samples = MeetingAudioMixdown.mono(input, frames: frames, format: format) else { return }
      let stamp = inputTime.pointee
      let host = stamp.mFlags.contains(.hostTimeValid) ? stamp.mHostTime : MeetingHostClock.now
      deliver(MeetingAudioChunk(samples: samples, sampleRate: format.mSampleRate, hostTime: host))
    }
  }

  func stop() {
    if aggregateID != kAudioObjectUnknown {
      if let procID {
        AudioDeviceStop(aggregateID, procID)
        AudioDeviceDestroyIOProcID(aggregateID, procID)
      }
      AudioHardwareDestroyAggregateDevice(aggregateID)
    }
    if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
    procID = nil
    aggregateID = AudioObjectID(kAudioObjectUnknown)
    tapID = AudioObjectID(kAudioObjectUnknown)
  }

  private static func check(_ status: OSStatus) throws {
    guard status == noErr else {
      throw MeetingError(String(localized: "System audio could not start (error \(Int(status)))."))
    }
  }

  private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
  }

  private static func read<Value>(
    _ object: AudioObjectID, _ selector: AudioObjectPropertySelector, as type: Value.Type
  ) throws -> Value {
    var address = address(selector)
    var size = UInt32(MemoryLayout<Value>.size)
    let value = UnsafeMutableRawPointer.allocate(
      byteCount: MemoryLayout<Value>.size, alignment: MemoryLayout<Value>.alignment)
    defer { value.deallocate() }
    try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, value))
    return value.load(as: Value.self)
  }

  private static func read<Value>(
    _ object: AudioObjectID, _ selector: AudioObjectPropertySelector, qualifier: pid_t, as type: Value.Type
  ) throws -> Value {
    var address = address(selector)
    var size = UInt32(MemoryLayout<Value>.size)
    var pid = qualifier
    let value = UnsafeMutableRawPointer.allocate(
      byteCount: MemoryLayout<Value>.size, alignment: MemoryLayout<Value>.alignment)
    defer { value.deallocate() }
    try check(
      AudioObjectGetPropertyData(object, &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, value))
    return value.load(as: Value.self)
  }
}
