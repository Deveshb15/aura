import Foundation
import IOKit

/// A stable, per-physical-Mac identity used to bind a license activation to this
/// machine. We send `activationName` to Dodo as the activation instance `name`,
/// so the 3-device limit is enforced per actual Mac.
///
/// We anchor on the hardware `IOPlatformUUID` rather than a UUID we mint and store
/// ourselves: the platform UUID survives a clean macOS reinstall or a new user
/// account, so a user who reinstalls the OS doesn't burn a second of their three
/// activation slots. It is read-only, never leaves the device except as this
/// activation `name`, and is not an advertising identifier.
enum DeviceIdentity {
    /// The hardware UUID (`IOPlatformUUID`). Falls back to a host-derived string
    /// only if IOKit is somehow unavailable.
    static let hardwareUUID: String = {
        let fallback = "unknown-\(Host.current().localizedName ?? "mac")"
        let entry = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard entry != 0 else { return fallback }
        defer { IOObjectRelease(entry) }
        guard let property = IORegistryEntryCreateCFProperty(
                  entry, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0),
              let uuid = property.takeRetainedValue() as? String
        else { return fallback }
        return uuid
    }()

    /// The machine model identifier for the Dodo dashboard, e.g. "Mac15,7".
    static let model: String = {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var bytes = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &bytes, &size, nil, 0)
        return String(cString: bytes)
    }()

    /// Human-readable host name, e.g. "Devesh's MacBook Pro".
    static let hostName: String = Host.current().localizedName ?? "Mac"

    /// What we POST to Dodo as the activation `name`: human-readable in the
    /// dashboard, with a short UUID fragment to disambiguate same-named Macs.
    static var activationName: String {
        "\(hostName) · \(model) · \(hardwareUUID.prefix(8))"
    }
}
