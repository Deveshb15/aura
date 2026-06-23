import Foundation
import Observation

/// Why a license is not usable.
enum LicenseInvalidReason: Equatable {
    case revoked                 // validate returned valid:false (refund/chargeback/manual)
    case activationLimitReached  // all device slots are in use
    case badKey                  // key not found / typo
}

/// The single source of truth for whether the app may run.
enum LicenseStatus: Equatable {
    case unlicensed                       // no key stored → show the hard paywall
    case activating                       // activate() in flight
    case licensed                         // confirmed valid
    case offlineGrace                     // prior-valid key, but offline now → run anyway
    case invalid(LicenseInvalidReason)    // server said no → lock
}

/// Owns license state for the whole app: loads cached state from the Keychain at
/// init (synchronously, so the launch gate can decide before any network call),
/// talks to Dodo via `LicenseAPI`, and persists the result. Mirrors
/// `ThemeManager`'s `@Observable` + manual-persistence shape and lives in
/// `AppEnvironment`.
///
/// Anti-piracy stance (perpetual license): we only LOCK on an explicit
/// `valid:false` from a *successful* Dodo call. A failure to *reach* Dodo never
/// locks — it drops to `.offlineGrace` and keeps running, indefinitely. There is
/// no expiry, and therefore no clock-dependent logic anywhere here — please don't
/// add any (`lastValidatedAt` is bookkeeping for the UI, never a gate).
@MainActor
@Observable
final class LicenseManager {
    private(set) var status: LicenseStatus
    private(set) var licenseKey: String?
    private(set) var instanceId: String?
    private(set) var lastValidatedAt: Date?
    /// Transient detail for the activation UI (e.g. limit reached); not persisted.
    private(set) var lastError: ActivationError?

    /// Fired when the app transitions usable → locked while running (revocation
    /// detected, or the user deactivated this Mac). `AppDelegate` uses it to tear
    /// down the notch + clipboard capture and re-present the gate.
    @ObservationIgnored var onLockedOut: (() -> Void)?

    private enum Account {
        static let key = "licenseKey"
        static let instance = "instanceId"
        static let validatedAt = "lastValidatedAt"
        static let cachedStatus = "cachedStatus"
    }

    private static let isoFormatter = ISO8601DateFormatter()

    /// True when the app is allowed to run. `.offlineGrace` counts as licensed.
    var isLicensed: Bool {
        switch status {
        case .licensed, .offlineGrace: return true
        default: return false
        }
    }

    /// A masked form of the key for display, e.g. "••••–••••–7F3A".
    var maskedKey: String? {
        guard let key = licenseKey, key.count >= 4 else { return licenseKey }
        return "••••–••••–\(key.suffix(4))"
    }

    init() {
        let key = Keychain.get(Account.key)
        licenseKey = key
        instanceId = Keychain.get(Account.instance)
        lastValidatedAt = Keychain.get(Account.validatedAt).flatMap { Self.isoFormatter.date(from: $0) }

        let cached = Keychain.get(Account.cachedStatus)
        if key == nil {
            status = .unlicensed
        } else if cached == "revoked" {
            // A previously-confirmed revoke stays locked even offline; don't
            // silently re-grant on a later offline launch.
            status = .invalid(.revoked)
        } else {
            // Have a key + a prior good state: assume good (offline-optimistic) so
            // relaunch never blocks. `validateOnLaunch()` confirms or revokes it.
            status = .offlineGrace
        }
    }

    // MARK: - Activation (first run / Settings)

    /// Activates `rawKey` against Dodo, binding this Mac. On success the app is
    /// unlocked and the key is persisted; on failure `status`/`lastError` drive
    /// the activation UI's error copy.
    func activate(key rawKey: String) async {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            lastError = .badKey
            status = .invalid(.badKey)
            return
        }

        lastError = nil
        status = .activating
        do {
            let id = try await LicenseAPI.activate(key: key, name: DeviceIdentity.activationName)
            let now = Date()
            persist(key: key, instanceId: id, validatedAt: now, cached: "licensed")
            licenseKey = key
            instanceId = id
            lastValidatedAt = now
            status = .licensed
        } catch let error as ActivationError {
            lastError = error
            switch error {
            case .activationLimitReached: status = .invalid(.activationLimitReached)
            case .badKey, .decode:        status = .invalid(.badKey)
            case .network, .server:       status = .unlicensed  // can't activate offline; allow retry
            }
        } catch {
            lastError = .network
            status = .unlicensed
        }
    }

    // MARK: - Re-validation (every launch, non-blocking)

    /// Silently re-checks an already-stored key against Dodo. Called after the
    /// app is already live, so it never blocks launch — it only confirms
    /// (`.licensed`), catches revocation (`.invalid(.revoked)` → re-lock), or
    /// keeps running offline (`.offlineGrace`).
    func validateOnLaunch() async {
        guard let key = licenseKey else { return }
        if case .invalid = status { return }  // a known-revoked key stays revoked

        do {
            let valid = try await LicenseAPI.validate(key: key, instanceId: instanceId)
            if valid {
                let now = Date()
                lastValidatedAt = now
                persist(key: key, instanceId: instanceId, validatedAt: now, cached: "licensed")
                status = .licensed
            } else {
                let wasUsable = isLicensed
                persist(key: key, instanceId: instanceId, validatedAt: lastValidatedAt, cached: "revoked")
                status = .invalid(.revoked)
                if wasUsable { onLockedOut?() }
            }
        } catch {
            // Couldn't reach Dodo — keep running on the cached key, indefinitely.
            if isLicensed { status = .offlineGrace }
        }
    }

    // MARK: - Deactivation (Settings → release this Mac)

    /// Frees this Mac's activation slot and re-locks the app. Best-effort: even if
    /// the network call fails we still clear local state, so the user is never
    /// stranded "activated" on a Mac they wanted to release.
    func deactivate() async {
        if let key = licenseKey, let id = instanceId {
            try? await LicenseAPI.deactivate(key: key, instanceId: id)
        }
        clearAndLock()
    }

    // MARK: - Persistence

    private func persist(key: String, instanceId: String?, validatedAt: Date?, cached: String) {
        Keychain.set(key, for: Account.key)
        if let instanceId { Keychain.set(instanceId, for: Account.instance) }
        if let validatedAt {
            Keychain.set(Self.isoFormatter.string(from: validatedAt), for: Account.validatedAt)
        }
        Keychain.set(cached, for: Account.cachedStatus)
    }

    private func clearAndLock() {
        Keychain.deleteAll()
        licenseKey = nil
        instanceId = nil
        lastValidatedAt = nil
        lastError = nil
        let wasUsable = isLicensed
        status = .unlicensed
        if wasUsable { onLockedOut?() }
    }
}
