import AppKit
import SwiftUI

/// The meeting transcript window: consent first, then the live conversation,
/// then copy, save or discard. One primary action per state.
struct MeetingView: View {
  @ObservedObject var controller: MeetingController

  var body: some View {
    Group {
      switch controller.phase {
      case .idle:
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      case .consent:
        MeetingConsentView(controller: controller)
      case let .unavailable(message):
        MeetingUnavailableView(message: message) { controller.discard() }
      case .starting, .live, .stopping, .finished:
        MeetingTranscriptView(controller: controller)
      }
    }
    .frame(minWidth: 380, minHeight: 360)
  }
}

private struct MeetingConsentView: View {
  @ObservedObject var controller: MeetingController

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Transcribe a Meeting").font(.title2.weight(.semibold))
        .accessibilityAddTraits(.isHeader)
      VStack(alignment: .leading, spacing: 10) {
        Label("Me: your microphone.", systemImage: "mic")
        Label("Others: the sound of every other app, such as Zoom, Teams or a browser call.", systemImage: "speaker.wave.2")
        Label("Recognized on this Mac. No audio is saved; the text stays here until you copy, save or discard it.", systemImage: "lock")
      }
      .fixedSize(horizontal: false, vertical: true)
      VStack(alignment: .leading, spacing: 8) {
        Text("Let everyone know before you start. Recording other people usually requires their consent.")
          .font(.callout.weight(.medium))
          .fixedSize(horizontal: false, vertical: true)
        HStack(alignment: .top, spacing: 10) {
          Text(MeetingController.consentNotice)
            .font(.callout)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
          Button("Copy for Chat") { controller.copyConsentNotice() }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
      }
      if let notice = controller.notice {
        Label(notice, systemImage: "exclamationmark.triangle")
          .font(.callout)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
      HStack {
        Spacer()
        Button("Cancel", role: .cancel) { controller.discard() }
          .keyboardShortcut(.cancelAction)
        Button("Everyone Is Informed – Start") { controller.confirmConsent() }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
  }
}

private struct MeetingUnavailableView: View {
  let message: String
  let close: () -> Void

  var body: some View {
    VStack(spacing: 14) {
      Image(systemName: "waveform.slash").font(.largeTitle).foregroundStyle(.secondary)
        .accessibilityHidden(true)
      Text("Meeting transcripts are not available").font(.title3.weight(.semibold))
      Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Button("Close", action: close).keyboardShortcut(.defaultAction)
    }
    .padding(32)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct MeetingTranscriptView: View {
  @ObservedObject var controller: MeetingController

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      if controller.systemAudioMissing { systemAudioHint }
      transcript
      Divider()
      footer
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      switch controller.phase {
      case .live:
        // The recording state is a shape and a word, not colour alone.
        Image(systemName: "record.circle").foregroundStyle(.red).accessibilityHidden(true)
        Text("Recording").font(.headline)
        Text(MeetingClock.elapsed(controller.elapsed)).font(.headline.monospacedDigit()).foregroundStyle(.secondary)
      case .starting:
        ProgressView().controlSize(.small)
        Text("Starting…").font(.headline)
      case .stopping:
        ProgressView().controlSize(.small)
        Text("Finishing the last words…").font(.headline)
      default:
        Text("Transcript").font(.headline)
        if controller.elapsed > 0 {
          Text(MeetingClock.elapsed(controller.elapsed)).font(.headline.monospacedDigit()).foregroundStyle(.secondary)
        }
      }
      Spacer()
      if controller.phase == .live {
        MeetingLevel(label: MeetingSpeaker.me.label, level: controller.levels[.me] ?? 0)
        MeetingLevel(label: MeetingSpeaker.others.label, level: controller.levels[.others] ?? 0)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .accessibilityElement(children: .combine)
  }

  private var systemAudioHint: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "speaker.slash").accessibilityHidden(true)
      Text("Nothing is coming from other apps. If the meeting is playing, allow Saywing under Screen & System Audio Recording.")
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
      Button("Open Settings…") { SaywingPermission.screenRecording.openSettings() }
    }
    .padding(12)
    .background(.yellow.opacity(0.12))
  }

  private var transcript: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 14) {
          if controller.transcript.isEmpty {
            Text(controller.phase == .finished ? "Nothing was recognized." : "Text appears here as people speak.")
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .center)
              .padding(.top, 40)
          }
          ForEach(controller.transcript.entries) { entry in
            MeetingTurn(entry: entry).id(entry.id)
          }
          Color.clear.frame(height: 1).id("end")
        }
        .padding(16)
      }
      .onChange(of: controller.transcript) {
        guard controller.phase == .live || controller.phase == .stopping else { return }
        proxy.scrollTo("end", anchor: .bottom)
      }
    }
  }

  private var footer: some View {
    HStack {
      if let notice = controller.notice {
        Text(notice).font(.callout).foregroundStyle(.secondary).lineLimit(2)
      }
      Spacer()
      switch controller.phase {
      case .starting, .live:
        Button("Stop") { controller.stop() }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
      case .stopping:
        EmptyView()
      default:
        Button("Discard", role: .destructive) { controller.discard() }
        Button("New Transcript") { Task { await controller.startNew() } }
        Button("Copy") { controller.copy() }
          .disabled(controller.transcript.isEmpty)
        Button("Save…") { controller.save() }
          .buttonStyle(.borderedProminent)
          .disabled(controller.transcript.isEmpty)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }
}

private struct MeetingTurn: View {
  let entry: MeetingTranscriptEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 6) {
        Text(entry.speaker.label).font(.subheadline.weight(.semibold))
        Text(MeetingClock.timestamp(entry.start)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
      }
      (Text(entry.text) + Text(entry.text.isEmpty || entry.pending.isEmpty ? "" : " ")
        + Text(entry.pending).foregroundStyle(.secondary))
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}

/// A small level bar per track, so a silent source is noticed at a glance.
private struct MeetingLevel: View {
  let label: String
  let level: Double

  var body: some View {
    let fill = min(1, sqrt(max(0, level)) * 3)
    HStack(spacing: 5) {
      Text(label).font(.caption).foregroundStyle(.secondary)
      Capsule().fill(.quaternary)
        .frame(width: 36, height: 5)
        .overlay(alignment: .leading) {
          Capsule().fill(.secondary).frame(width: 36 * fill, height: 5)
        }
        .accessibilityHidden(true)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
    .accessibilityValue(level > 0.002 ? Text("Sound") : Text("Silent"))
  }
}
