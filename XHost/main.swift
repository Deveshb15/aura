import Foundation
import Darwin

// Aura X-bookmark native-messaging host.
//
// Chrome (and Chromium-family browsers) launch this tiny helper once per
// `chrome.runtime.sendNativeMessage`, speaking the native-messaging stdio
// protocol: a 4-byte native-endian length prefix followed by UTF-8 JSON, on
// stdin and stdout. We read the one message, forward it to the running Aura
// app over a loopback socket (port + shared token published by the app in
// `x-bridge.json`), and write the app's reply back to the browser.
//
// If Aura isn't running (the bridge file is missing or the connection is
// refused), we answer `{"ok":false,"offline":true}` so the extension stays
// quiet instead of nagging the user.

// MARK: - Native-messaging framing (stdin/stdout)

func readExact(_ fd: Int32, _ count: Int) -> Data? {
    guard count > 0 else { return Data() }
    var out = Data(capacity: count)
    var remaining = count
    var buf = [UInt8](repeating: 0, count: 8192)
    while remaining > 0 {
        let want = min(remaining, buf.count)
        let n = buf.withUnsafeMutableBytes { read(fd, $0.baseAddress, want) }
        if n <= 0 { return nil }
        out.append(buf, count: n)
        remaining -= n
    }
    return out
}

func readMessage() -> Data? {
    guard let header = readExact(STDIN_FILENO, 4), header.count == 4 else { return nil }
    let len = header.withUnsafeBytes { $0.load(as: UInt32.self) } // native (little-endian on macOS)
    if len == 0 || len > 64 * 1024 * 1024 { return nil }
    return readExact(STDIN_FILENO, Int(len))
}

func writeMessage(_ data: Data) {
    var len = UInt32(truncatingIfNeeded: data.count) // native byte order
    var framed = Data(bytes: &len, count: 4)
    framed.append(data)
    FileHandle.standardOutput.write(framed)
}

let offlineReply = Data(#"{"ok":false,"offline":true}"#.utf8)

// MARK: - Bridge file (written by the running Aura app)

/// Always the non-DEBUG "Aura" support dir so a single, stable path works no
/// matter which build of the app is running. This is just an IPC rendezvous
/// file (port + token), never vault data.
func bridgeInfo() -> (port: UInt16, token: String)? {
    let fm = FileManager.default
    guard let support = try? fm.url(for: .applicationSupportDirectory,
                                    in: .userDomainMask, appropriateFor: nil, create: false) else { return nil }
    let url = support.appendingPathComponent("Aura/x-bridge.json")
    guard let data = try? Data(contentsOf: url),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let port = obj["port"] as? Int, port > 0, port <= 65535,
          let token = obj["token"] as? String else { return nil }
    return (UInt16(port), token)
}

// MARK: - Loopback forward

func forwardToApp(_ message: Any) -> Data? {
    guard let info = bridgeInfo() else { return nil }

    let fd = socket(AF_INET, SOCK_STREAM, 0)
    if fd < 0 { return nil }
    defer { close(fd) }

    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = info.port.bigEndian
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")

    let connected = withUnsafePointer(to: &addr) { ptr -> Bool in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
        }
    }
    if !connected { return nil }

    // One newline-delimited JSON request: { token, message }.
    let request: [String: Any] = ["token": info.token, "message": message]
    guard var line = try? JSONSerialization.data(withJSONObject: request) else { return nil }
    line.append(0x0A)

    let sent = line.withUnsafeBytes { raw -> Bool in
        guard let base = raw.baseAddress else { return false }
        var off = 0
        while off < raw.count {
            let w = write(fd, base + off, raw.count - off)
            if w <= 0 { return false }
            off += w
        }
        return true
    }
    if !sent { return nil }

    // Read one newline-terminated reply line.
    var reply = Data()
    var buf = [UInt8](repeating: 0, count: 8192)
    while true {
        let n = read(fd, &buf, buf.count)
        if n <= 0 { break }
        reply.append(buf, count: n)
        if reply.contains(0x0A) { break }
    }
    guard let nl = reply.firstIndex(of: 0x0A) else { return reply.isEmpty ? nil : reply }
    return reply.subdata(in: reply.startIndex..<nl)
}

// MARK: - Main

guard let raw = readMessage() else { exit(0) }
let message = (try? JSONSerialization.jsonObject(with: raw)) ?? [:]
let reply = forwardToApp(message) ?? offlineReply
writeMessage(reply)
exit(0)
