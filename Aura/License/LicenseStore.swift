import Foundation

/// The persisted license state. Stored as a single JSON file rather than the
/// macOS Keychain, so the app never triggers keychain-access password prompts.
///
/// `deviceUUID` is the hardware `IOPlatformUUID` captured at activation. On load
/// we require it to match THIS Mac (see `LicenseManager.init`): a record copied
/// to another Mac is rejected, forcing that machine to activate fresh (consuming
/// one of the 3 device slots). That carries the anti-share guarantee the Keychain
/// used to — and then some, since the Keychain never device-checked on read.
struct LicenseRecord: Codable {
    var licenseKey: String
    var instanceId: String?
    var deviceUUID: String
    var lastValidatedAt: Date?
    var status: String   // "licensed" | "revoked"
}

/// File-backed store for the license record. Lives alongside the vault in
/// Application Support (`Aura/` in Release, `Aura-Debug/` in Debug via
/// `AppDatabase.supportDirectory()`), so it survives an app reinstall but stays
/// isolated from dev runs.
enum LicenseStore {
    private static var fileURL: URL? {
        try? AppDatabase.supportDirectory().appendingPathComponent("license.json")
    }

    static func load() -> LicenseRecord? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LicenseRecord.self, from: data)
    }

    static func save(_ record: LicenseRecord) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(record) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
