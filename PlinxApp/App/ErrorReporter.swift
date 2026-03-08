import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// ErrorReporter — Plinx Privacy Layer
// ─────────────────────────────────────────────────────────────────────────────
//
// This is a no-op adapter that replaces Strimr's ErrorReporter (which interfaces
// with Sentry). Plinx is committed to zero data collection, including crash
// diagnostics.
//
// Strimr's vendored code calls ErrorReporter.start() and ErrorReporter.capture()
// as part of its error handling. By providing this local implementation, we ensure
// that no telemetry or analytics code runs, without needing to modify vendor code.
//
// See DATA_COLLECTION_AUDIT.md for rationale and privacy compliance details.
//
// ─────────────────────────────────────────────────────────────────────────────

/// No-op error reporter for Plinx zero-collection privacy policy.
enum ErrorReporter {
    /// Initialize error reporting. In Plinx, this is a no-op.
    static func start() {
        // Plinx does not collect crash data or telemetry.
        // This is intentionally empty.
    }

    /// Capture an error for reporting. In Plinx, this is a no-op.
    /// - Parameter error: The error to report (not captured).
    static func capture(_ error: Error) {
        // Plinx does not collect crash data or telemetry.
        // Developers can add local logging here if needed for debugging:
        // print("Error (not reported): \(error)")
    }
}
