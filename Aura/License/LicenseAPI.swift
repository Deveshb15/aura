import Foundation

/// Errors surfaced from a Dodo license call, mapped to user-facing copy upstream.
enum ActivationError: Error, Equatable {
    case network                 // couldn't reach Dodo (offline, timeout)
    case badKey                  // key not found / malformed
    case activationLimitReached  // all device slots are in use
    case server(Int)             // other non-2xx
    case decode                  // unexpected response shape
}

/// Thin client for Dodo Payments' public License Key endpoints. These three
/// endpoints require NO API key, so it's safe to call them directly from the app.
/// Mirrors the repo convention of using `URLSession.shared` directly (no wrapper),
/// as in `LinkMetadataService`. Non-isolated so callers `await` off the main actor.
enum LicenseAPI {
    /// Dodo uses separate hosts for test vs live mode. Debug builds hit test so
    /// QA never touches real keys or burns real activation slots.
    #if DEBUG
    static let baseURL = URL(string: "https://test.dodopayments.com")!
    #else
    static let baseURL = URL(string: "https://live.dodopayments.com")!
    #endif

    /// Marketing site where a license is purchased (the in-app "Buy a license"
    /// button opens this; the site runs the Dodo checkout).
    static let checkoutURL = URL(string: "https://usecarpet.app")!
    /// Support contact for license help / transfers (no self-serve portal yet).
    static let manageURL = URL(string: "mailto:hey@usecarpet.app?subject=Carpet%20license%20help")!

    // MARK: - Endpoints

    /// Registers this device as an activation instance. Returns the
    /// `license_key_instance_id` to persist (needed later to deactivate).
    static func activate(key: String, name: String) async throws -> String {
        let json = try await post("/licenses/activate", body: ["license_key": key, "name": name])
        guard let id = json["id"] as? String else { throw ActivationError.decode }
        return id
    }

    /// Checks whether the key is currently valid (active, not revoked/refunded).
    static func validate(key: String, instanceId: String?) async throws -> Bool {
        var body = ["license_key": key]
        if let instanceId { body["license_key_instance_id"] = instanceId }
        let json = try await post("/licenses/validate", body: body)
        guard let valid = json["valid"] as? Bool else { throw ActivationError.decode }
        return valid
    }

    /// Frees this device's activation slot.
    static func deactivate(key: String, instanceId: String) async throws {
        _ = try await post("/licenses/deactivate",
                           body: ["license_key": key, "license_key_instance_id": instanceId])
    }

    // MARK: - Transport

    private static func post(_ path: String, body: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ActivationError.network
        }

        guard let http = response as? HTTPURLResponse else { throw ActivationError.decode }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        switch http.statusCode {
        case 200...299:
            return json
        case 403, 409, 429:
            // Slot/limit related codes — confirm via the body, else generic.
            if mentionsLimit(json) { throw ActivationError.activationLimitReached }
            throw ActivationError.server(http.statusCode)
        case 400, 404, 422:
            if mentionsLimit(json) { throw ActivationError.activationLimitReached }
            throw ActivationError.badKey
        default:
            throw ActivationError.server(http.statusCode)
        }
    }

    /// Best-effort detection of an "activation limit reached" error from Dodo's
    /// JSON error body. The exact shape should be confirmed against live
    /// responses; this matches common phrasings defensively.
    private static func mentionsLimit(_ json: [String: Any]) -> Bool {
        let haystack = [json["message"], json["code"], json["detail"], json["error"]]
            .compactMap { $0 as? String }
            .joined(separator: " ")
            .lowercased()
        return haystack.contains("limit") || haystack.contains("maximum")
    }
}
