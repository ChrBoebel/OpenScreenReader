import Foundation
import Testing
@testable import OpenScreenReaderCore

struct UpdatePolicyTests {
    @Test func requiresHTTPSAndARealPublicKey() {
        let key = Data(repeating: 7, count: 32).base64EncodedString()
        #expect(UpdateConfiguration(feed: "https://downloads.example.org/appcast.xml", publicKey: key) != nil)
        for feed in ["", "$(SAYWING_UPDATE_FEED_URL)", "http://example.org/feed", "https://user:secret@example.org/feed", "https://example.org/feed?token=secret", "file:///tmp/feed"] {
            #expect(UpdateConfiguration(feed: feed, publicKey: key) == nil)
        }
        #expect(UpdateConfiguration(feed: "https://example.org/feed", publicKey: "") == nil)
        #expect(UpdateConfiguration(feed: "https://example.org/feed", publicKey: Data(repeating: 0, count: 32).base64EncodedString()) == nil)
    }

    @Test @MainActor func installationWaitsForIdleAndRunsOnlyOnce() {
        let gate = UpdateRelaunchGate()
        var calls = 0
        #expect(gate.postponeIfBusy(true) { calls += 1 })
        gate.resumeIfIdle(false)
        #expect(calls == 0)
        #expect(gate.isPending)
        gate.resumeIfIdle(true)
        gate.resumeIfIdle(true)
        #expect(calls == 1)
        #expect(!gate.isPending)
    }

    @Test @MainActor func abortedUpdateCannotRelaunchLater() {
        let gate = UpdateRelaunchGate()
        var calls = 0
        #expect(gate.postponeIfBusy(true) { calls += 1 })
        gate.cancel()
        gate.resumeIfIdle(true)
        #expect(calls == 0)
        #expect(!gate.postponeIfBusy(false) { calls += 1 })
        #expect(calls == 0) // Sparkle owns the immediate installation.
    }
}
