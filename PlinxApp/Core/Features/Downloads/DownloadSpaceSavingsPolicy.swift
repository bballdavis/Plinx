import Foundation

/// Keeps reduced-quality downloads honest: a transcode is only worth asking the
/// server for when its estimated output is at least 20 percent smaller than the
/// source file. Otherwise the original is downloaded, which plays better and
/// costs the server nothing.
///
/// Upstream only skips the transcode when the source already fits the preset's
/// caps; this adds the size comparison Plinx shipped before the fork.
enum DownloadSpaceSavingsPolicy {
    static let audioBitrateKbps = 192
    static let containerOverheadFraction = 0.02
    static let minimumSavingsFraction = 0.20

    /// The estimated size of a transcode at `quality`, or nil for Original or an unknown duration.
    static func estimatedOutputBytes(quality: TranscodeQualityPreset, duration: TimeInterval?) -> Int64? {
        guard let videoBitrateKbps = quality.maximumVideoBitrateKbps,
              let duration, duration > 0
        else { return nil }
        let payloadBytes = Double(videoBitrateKbps + audioBitrateKbps) * 1000 * duration / 8
        return Int64((payloadBytes * (1 + containerOverheadFraction)).rounded(.up))
    }

    /// Whether to queue a transcode at `quality` rather than download the original source.
    ///
    /// Unknown source size or duration keeps the requested transcode, since the
    /// preset's caps may still matter (for example a 4K source on a phone).
    static func shouldTranscode(
        quality: TranscodeQualityPreset,
        sourceFileSize: Int64?,
        duration: TimeInterval?,
    ) -> Bool {
        guard !quality.isOriginal else { return false }
        guard let sourceFileSize, sourceFileSize > 0,
              let estimate = estimatedOutputBytes(quality: quality, duration: duration)
        else { return true }
        return hasMinimumSavings(candidateSize: estimate, sourceFileSize: sourceFileSize)
    }

    static func hasMinimumSavings(candidateSize: Int64, sourceFileSize: Int64) -> Bool {
        guard candidateSize >= 0, sourceFileSize > 0 else { return false }
        let maximumCandidateSize = Double(sourceFileSize) * (1 - minimumSavingsFraction)
        return Double(candidateSize) <= maximumCandidateSize
    }
}
