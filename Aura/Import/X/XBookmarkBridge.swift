import Foundation
import Network

/// Receives X-bookmark saves from the browser extension. The extension talks to
/// a tiny bundled native-messaging host (`aura-x-host`), which forwards each
/// message to this loopback listener. We publish the chosen port + a random
/// per-launch token to `x-bridge.json` so the host can find and authenticate to
/// us; every message must carry the token, and we bind to 127.0.0.1 only.
///
/// Not `@MainActor`: connection callbacks run on a background queue. Saves hop
/// to the main actor (`DataStore`) explicitly.
final class XBookmarkBridge {
    private let dataStore: DataStore
    private let token = UUID().uuidString
    private var listener: NWListener?

    init(dataStore: DataStore) {
        self.dataStore = dataStore
    }

    func start() {
        guard listener == nil else { return }
        do {
            let tcp = NWProtocolTCP.Options()
            tcp.noDelay = true
            let params = NWParameters(tls: nil, tcp: tcp)
            // Bind to loopback only (no LAN exposure, no firewall prompt) with an
            // OS-assigned ephemeral port.
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            params.allowLocalEndpointReuse = true

            let listener = try NWListener(using: params)
            self.listener = listener

            let token = self.token
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let port = listener.port?.rawValue {
                        XBookmarkBridge.writeBridgeFile(port: port, token: token)
                    }
                case .failed(let error):
                    NSLog("Aura: X bridge listener failed: \(error)")
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] conn in
                self?.handle(conn)
            }
            listener.start(queue: .global(qos: .userInitiated))
        } catch {
            NSLog("Aura: X bridge failed to start: \(error)")
        }
    }

    // MARK: - Connection handling

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .userInitiated))
        var buffer = Data()

        func receiveMore() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
                if let data, !data.isEmpty { buffer.append(data) }
                if let nl = buffer.firstIndex(of: 0x0A) {
                    let line = buffer.subdata(in: buffer.startIndex..<nl)
                    self?.process(line: line, conn: conn)
                    return
                }
                if isComplete || error != nil || buffer.count > 8 * 1024 * 1024 {
                    self?.process(line: buffer, conn: conn)
                    return
                }
                receiveMore()
            }
        }
        receiveMore()
    }

    private func process(line: Data, conn: NWConnection) {
        guard !line.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              (obj["token"] as? String) == token,
              let message = obj["message"] as? [String: Any] else {
            reply(["ok": false], on: conn)
            return
        }

        switch message["type"] as? String {
        case "ping":
            reply(["ok": true], on: conn)

        case "save":
            guard let tweetObj = message["tweet"],
                  let tweetData = try? JSONSerialization.data(withJSONObject: tweetObj),
                  let tweet = try? JSONDecoder().decode(XTweet.self, from: tweetData) else {
                reply(["ok": false], on: conn)
                return
            }
            let store = dataStore
            Task { @MainActor in
                let outcome = await store.saveXTweet(tweet)
                self.reply(["ok": outcome.ok, "duplicate": outcome.duplicate], on: conn)
            }

        default:
            reply(["ok": false], on: conn)
        }
    }

    private func reply(_ object: [String: Any], on conn: NWConnection) {
        var data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{\"ok\":false}".utf8)
        data.append(0x0A)
        conn.send(content: data, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    // MARK: - Bridge rendezvous file

    /// Always the non-DEBUG "Aura" support dir so the host (which can't know the
    /// build config) reads one stable path. This is an IPC rendezvous file, not
    /// vault data.
    static func bridgeDirectory() -> URL? {
        let fm = FileManager.default
        guard let support = try? fm.url(for: .applicationSupportDirectory,
                                        in: .userDomainMask, appropriateFor: nil, create: true) else { return nil }
        return support.appendingPathComponent("Aura", isDirectory: true)
    }

    private static func writeBridgeFile(port: UInt16, token: String) {
        guard let dir = bridgeDirectory() else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("x-bridge.json")
        let payload: [String: Any] = [
            "port": Int(port),
            "token": token,
            "pid": ProcessInfo.processInfo.processIdentifier,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? data.write(to: url, options: .atomic)
        // Owner-only — it carries the shared secret.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
