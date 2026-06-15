import Foundation
import os

/// Diagnostic watchdog that makes hangs *visible*. A background timer pings the
/// main queue once a second; if the ping takes too long to come back the main
/// thread is blocked — the beachball / "can't even force-quit" precursor — and
/// we log it with the current memory footprint. Without this, hangs leave no
/// trace (the app never crashes, so there's no `.ips` report to read).
///
/// Cheap enough to leave running, but gated to DEBUG or an opt-in defaults flag
/// so it never adds noise to a normal Release session.
enum MainThreadWatchdog {
    private static let log = Logger(subsystem: "app.captureaura", category: "watchdog")
    private static let queue = DispatchQueue(label: "app.captureaura.watchdog", qos: .utility)
    private static var timer: DispatchSourceTimer?

    /// Starts the watchdog if enabled (DEBUG, or `diagnosticsEnabled` in defaults).
    static func startIfEnabled(stallThreshold: TimeInterval = 0.25,
                               interval: TimeInterval = 1.0) {
        #if DEBUG
        let enabled = true
        #else
        let enabled = UserDefaults.standard.bool(forKey: "diagnosticsEnabled")
        #endif
        guard enabled, timer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler {
            let start = DispatchTime.now()
            let sem = DispatchSemaphore(value: 0)
            DispatchQueue.main.async { sem.signal() }
            // Generous upper bound so a true hang is reported rather than waited on forever.
            let result = sem.wait(timeout: .now() + 10.0)
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            if result == .timedOut {
                log.error("Main thread STALLED >10s (likely hang). footprint=\(footprintMB())MB")
            } else if elapsedMs > stallThreshold * 1000 {
                log.notice("Main thread slow: \(Int(elapsedMs))ms. footprint=\(footprintMB())MB")
            }
        }
        timer.resume()
        self.timer = timer
        log.notice("Main-thread watchdog started. footprint=\(footprintMB())MB")
    }

    /// Resident memory footprint in MB (the number jetsam watches), or -1.
    static func footprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return -1 }
        return Int(info.phys_footprint) / (1024 * 1024)
    }
}
