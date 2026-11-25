import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// ErrorReporter — Plinx Privacy Layer
// ─────────────────────────────────────────────────────────────────────────────
//
// Plinx is committed to zero data collection, including crash diagnostics.
// The absorbed media stack calls `ErrorReporter.capture(_:)` from its error
// paths; this implementation keeps those call sites compiling while nothing is
// ever recorded or sent. Upstream's Sentry reporter and package are not part
// of Plinx.
//
// See docs/security/privacy-and-safety.md for rationale and privacy details.
//
// ─────────────────────────────────────────────────────────────────────────────

/// No-op error reporter for Plinx zero-collection privacy policy.
enum ErrorReporter {
    /// Always `false`: Plinx has no error reporting to opt into.
    static var isEnabled: Bool {
        false
    }

    /// Ignored. Kept only so absorbed settings screens compile; Plinx must not
    /// present an error-reporting toggle (there is nothing to enable).
    static func setEnabled(_: Bool) {}

    /// Capture an error for reporting. In Plinx, this is a no-op.
    /// - Parameter error: The error to report (not captured).
    static func capture(_: Error) {
        // Plinx does not collect crash data or telemetry.
    }
}

/// Errors that describe an expected lack of connectivity.
protocol ExpectedConnectivityError: Error {}

extension Error {
    var isCancellation: Bool {
        self is CancellationError
            || (self as? URLError)?.code == .cancelled
    }

    /// Surfaces outside `URLError` when a LAN address is unreachable or local network access is denied.
    var isHostUnreachable: Bool {
        let error = self as NSError
        return error.domain == NSPOSIXErrorDomain && error.code == Int(EHOSTUNREACH)
    }
}
