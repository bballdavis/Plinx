import SwiftUI
import PlinxCore
import PlinxUI

struct YoutarrChannelCard: View {
    let channel: YoutarrChannel
    let configuration: YoutarrConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            YoutarrThumbnailView(
                rawURL: channel.thumbnailUrl,
                configuration: configuration,
                aspectRatio: 1
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(channel.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(channelSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(channel.title), \(channel.videoCount) "
                + YoutarrStrings.value("youtarr.explore.videos")
        )
    }

    private var channelSummary: String {
        var components = [
            "\(channel.videoCount) \(YoutarrStrings.value("youtarr.explore.videos"))"
        ]
        if channel.downloadedCount > 0 {
            components.append(
                "\(channel.downloadedCount) "
                    + YoutarrStrings.value("youtarr.explore.downloaded")
            )
        }
        if let subfolder = channel.subfolder,
           !subfolder.isEmpty,
           subfolder != "##USE_GLOBAL_DEFAULT##" {
            components.append(subfolder)
        }
        return components.joined(separator: " • ")
    }
}

struct YoutarrVideoCard: View {
    enum Layout {
        case featured
        case grid
    }

    let video: YoutarrVideo
    let configuration: YoutarrConfiguration
    let layout: Layout
    let requestState: YoutarrVideoActionState
    let selectionAction: () -> Void
    let longPressAction: () -> Void
    let requestAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .bottomTrailing) {
                YoutarrThumbnailView(
                    rawURL: video.thumbnailUrl,
                    configuration: configuration,
                    aspectRatio: 16 / 9
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if let duration = video.duration?.displayValue, !duration.isEmpty {
                    Text(duration)
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.8), in: Capsule())
                        .padding(7)
                }
            }

            Text(video.title)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(height: titleHeight, alignment: .top)

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(video.channelTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let rating = video.rating {
                        YoutarrMetadataBadge(
                            text: rating.displayValue,
                            systemImage: "checkmark.shield"
                        )
                    } else {
                        Color.clear
                            .frame(height: 14)
                            .accessibilityHidden(true)
                    }
                }

                Spacer(minLength: 4)

                YoutarrCompactRequestControl(
                    video: video,
                    state: requestState,
                    action: requestAction
                )
            }
            .frame(height: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .plinxMediaCardInteraction(
            onTap: selectionAction,
            onLongPress: longPressAction
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityElement(children: .contain)
        .accessibilityAction {
            selectionAction()
        }
        .accessibilityIdentifier("youtarr.explore.video.\(video.youtubeId)")
    }

    private var titleHeight: CGFloat {
        switch layout {
        case .featured: 46
        case .grid: 44
        }
    }
}

private struct YoutarrCompactRequestControl: View {
    let video: YoutarrVideo
    let state: YoutarrVideoActionState
    let action: () -> Void

    var body: some View {
        switch state {
        case .eligible:
            actionButton(
                systemImage: "arrow.down.to.line.compact",
                label: YoutarrStrings.value("youtarr.request.action")
            )

        case .submitting:
            compactSurface {
                ProgressView()
                    .controlSize(.small)
            }
            .accessibilityLabel(Text("youtarr.request.submitting", tableName: "Plinx"))
            .accessibilityIdentifier("youtarr.request.submitting.\(video.youtubeId)")

        case .requested(let status):
            compactSurface {
                Image(
                    systemName: status.map {
                        YoutarrRequestPresentation.systemImage(for: $0)
                    } ?? "clock.fill"
                )
            }
            .accessibilityLabel(
                status.map { Text(YoutarrRequestPresentation.label(for: $0)) }
                    ?? Text("youtarr.explore.requested", tableName: "Plinx")
            )
            .accessibilityIdentifier("youtarr.request.status.\(video.youtubeId)")

        case .downloaded:
            compactSurface {
                Image(systemName: "checkmark.circle.fill")
            }
            .accessibilityLabel(Text("youtarr.explore.downloaded", tableName: "Plinx"))

        case .failed:
            actionButton(
                systemImage: "arrow.clockwise",
                label: YoutarrStrings.value("youtarr.request.retry")
            )

        case .unavailable:
            compactSurface {
                Image(systemName: "lock.fill")
            }
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text("youtarr.explore.unavailable", tableName: "Plinx"))
        }
    }

    private func actionButton(systemImage: String, label: String) -> some View {
        Button(action: action) {
            compactSurface {
                Image(systemName: systemImage)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier("youtarr.request.video.\(video.youtubeId)")
    }

    private func compactSurface<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 44, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
            }
    }
}
