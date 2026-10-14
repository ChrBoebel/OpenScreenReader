import Foundation

/// Missing release configuration leaves development builds entirely offline.
public struct UpdateConfiguration: Sendable {
    public let feedURL: URL
    public let publicKey: String

    public init?(feed: String, publicKey: String) {
        guard let parts = URLComponents(string: feed), parts.scheme == "https",
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              !feed.contains("$("), let url = parts.url,
              let key = Data(base64Encoded: publicKey), key.count == 32,
              key.contains(where: { $0 != 0 }) else { return nil }
        feedURL = url
        self.publicKey = publicKey
    }
}

/// Holds only Sparkle's install continuation, never reading or recording data.
@MainActor
public final class UpdateRelaunchGate {
    private var continuation: (() -> Void)?
    public var isPending: Bool { continuation != nil }
    public init() {}

    public func postponeIfBusy(_ busy: Bool, install: @escaping () -> Void) -> Bool {
        guard busy else { return false }
        continuation = install
        return true
    }

    public func resumeIfIdle(_ idle: Bool) {
        guard idle, let install = continuation else { return }
        continuation = nil
        install()
    }

    public func cancel() { continuation = nil }
}
