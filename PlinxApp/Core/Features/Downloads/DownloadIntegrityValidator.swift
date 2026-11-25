import Foundation

/// Strict check of a finished transfer before it is kept as a playable video.
///
/// URLSession hands over the body of any response as a finished file, so an
/// error page, a JSON or XML error, an empty body or a truncated transfer would
/// otherwise become a "completed" download. A resumed transfer (HTTP 206) is
/// checked against the complete size from `Content-Range`, because the session
/// delivers the reassembled file, not the resumed segment.
enum DownloadIntegrityValidator {
    static func validate(response: URLResponse?, stagedFileSize: Int64) throws {
        guard let response = response as? HTTPURLResponse else {
            throw DownloadIntegrityFailure.invalidResponse
        }

        guard (200 ..< 300).contains(response.statusCode) else {
            throw DownloadIntegrityFailure.unsuccessfulStatus
        }

        if let mimeType = response.mimeType?.lowercased(),
           mimeType.hasPrefix("text/")
           || mimeType == "application/json"
           || mimeType.contains("xml")
        {
            throw DownloadIntegrityFailure.unexpectedContentType
        }

        guard stagedFileSize > 0 else {
            throw DownloadIntegrityFailure.emptyFile
        }

        let expectedFileSize = expectedCompleteFileSize(from: response)
        guard expectedFileSize == nil || expectedFileSize == stagedFileSize else {
            throw DownloadIntegrityFailure.contentLengthMismatch
        }
    }

    /// The localized reason shown on the failed download row.
    static func failureMessage(for failure: DownloadIntegrityFailure, response: URLResponse?) -> String {
        if failure == .unsuccessfulStatus, let statusCode = (response as? HTTPURLResponse)?.statusCode {
            return String(localized: "downloads.status.serverError \(statusCode)")
        }
        return String(localized: "downloads.status.failed")
    }

    private static func expectedCompleteFileSize(from response: HTTPURLResponse) -> Int64? {
        if response.statusCode == 206 {
            guard let contentRange = response.value(forHTTPHeaderField: "Content-Range"),
                  let totalComponent = contentRange.split(separator: "/").last,
                  totalComponent != "*"
            else {
                return nil
            }
            return Int64(totalComponent.trimmingCharacters(in: .whitespaces))
        }

        let expectedContentLength = response.expectedContentLength
        return expectedContentLength > 0 ? expectedContentLength : nil
    }
}

enum DownloadIntegrityFailure: Error, Equatable {
    case invalidResponse
    case unsuccessfulStatus
    case unexpectedContentType
    case emptyFile
    case contentLengthMismatch
}
