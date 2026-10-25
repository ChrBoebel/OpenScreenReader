import Foundation

/// Keeps only the SHA-256 of the terms the user accepted, on this Mac.
@MainActor
protocol ModelTermsAcceptanceStoring: AnyObject {
    var acceptedTermsSHA256: String? { get set }
}

@MainActor
final class UserDefaultsModelTermsStore: ModelTermsAcceptanceStoring {
    static let preferenceKey = "supertonicTermsAccepted.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = InterfaceSoundPlayer.defaults) { self.defaults = defaults }

    var acceptedTermsSHA256: String? {
        get { defaults.string(forKey: Self.preferenceKey) }
        set {
            if let newValue { defaults.set(newValue, forKey: Self.preferenceKey) }
            else { defaults.removeObject(forKey: Self.preferenceKey) }
        }
    }
}

/// Open RAIL-M §4(a) and §5 require the use restrictions to bind every user. Reading
/// aloud with Supertonic 3 therefore needs an explicit acceptance of exactly the terms
/// and license bundled with this build. A changed text voids the acceptance; a build
/// without the text can never be accepted. No network, nothing stored besides the hash.
@MainActor
final class ModelTermsAcceptance {
    enum State: Equatable {
        case accepted, notAccepted
        /// An acceptance exists, but for a different text than this build bundles.
        case changed
        /// The terms are missing from this build, so they cannot be accepted.
        case unavailable
    }

    /// The terms followed by the complete license, as the terms sheet shows them.
    let document: String?
    let documentSHA256: String?
    private let store: any ModelTermsAcceptanceStoring

    init(document: String?, store: any ModelTermsAcceptanceStoring) {
        self.document = document
        documentSHA256 = document.map { SHA256Digest.hex(of: Data($0.utf8)) }
        self.store = store
    }

    convenience init(bundle: Bundle = .main, store: any ModelTermsAcceptanceStoring = UserDefaultsModelTermsStore()) {
        self.init(document: ModelTerms.document(in: bundle), store: store)
    }

    var state: State {
        guard let documentSHA256 else { return .unavailable }
        switch store.acceptedTermsSHA256 {
        case documentSHA256: return .accepted
        case nil: return .notAccepted
        default: return .changed
        }
    }

    var isAccepted: Bool { state == .accepted }

    /// Accepting stores the hash of this build's text; withdrawing removes it.
    @discardableResult func setAccepted(_ accepted: Bool) -> State {
        if accepted {
            guard let documentSHA256 else { return .unavailable }
            store.acceptedTermsSHA256 = documentSHA256
        } else {
            store.acceptedTermsSHA256 = nil
        }
        return state
    }
}
