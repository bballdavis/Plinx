import Foundation
@testable import Plinx
import Testing

@MainActor
struct ErrorReporterTests {
    /// Zero collection: there is no reporter to turn on. Upstream's Sentry reporter and its breadcrumb scrubbing
    /// are not part of Plinx.
    @Test func `error reporting can never be enabled`() {
        ErrorReporter.setEnabled(true)

        #expect(!ErrorReporter.isEnabled)
    }

    @Test func `a POSIX host unreachable error is recognized`() {
        let error = NSError(domain: NSPOSIXErrorDomain, code: Int(EHOSTUNREACH))

        #expect(error.isHostUnreachable)
    }

    @Test func `other POSIX errors are not treated as host unreachable`() {
        let error = NSError(domain: NSPOSIXErrorDomain, code: Int(EADDRNOTAVAIL))

        #expect(!error.isHostUnreachable)
    }

    @Test func `the same code in another domain is not treated as host unreachable`() {
        let error = NSError(domain: NSURLErrorDomain, code: Int(EHOSTUNREACH))

        #expect(!error.isHostUnreachable)
    }
}
