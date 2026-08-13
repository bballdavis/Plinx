import SwiftUI
import PlinxCore
import PlinxUI

struct YoutarrVideoDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: YoutarrVideoDetailViewModel

    let video: YoutarrVideo
    let configuration: YoutarrConfiguration
    let requestState: YoutarrVideoActionState
    let requestAction: () -> Void

    init(
        video: YoutarrVideo,
        configuration: YoutarrConfiguration,
        requestState: YoutarrVideoActionState,
        requestAction: @escaping () -> Void
    ) {
        self.video = video
        self.configuration = configuration
        self.requestState = requestState
        self.requestAction = requestAction
        _viewModel = StateObject(
            wrappedValue: YoutarrVideoDetailViewModel(
                video: video,
                configuration: configuration
            )
        )
    }

    var body: some View {
        ZStack {
            PlinxAmbientBackground()
                .accessibilityIdentifier("youtarr.details.screen")

            VStack(spacing: 0) {
                detailHeader

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        YoutarrThumbnailView(
                            rawURL: viewModel.detail?.thumbnailUrl ?? video.thumbnailUrl,
                            configuration: configuration,
                            aspectRatio: 16 / 9
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                        YoutarrWideRequestControl(
                            video: video,
                            state: requestState,
                            action: requestAction
                        )

                        primaryInformation

                        if viewModel.phase == .loading {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("youtarr.details.loading", tableName: "Plinx")
                            }
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                        }

                        if case .failed(let message) = viewModel.phase {
                            YoutarrExploreStateView(
                                systemImage: "wifi.exclamationmark",
                                titleKey: "youtarr.details.error",
                                message: message,
                                retry: retryDetails
                            )
                            .frame(minHeight: 180)
                        }

                        if let detail = viewModel.detail {
                            fullInformation(detail)
                                .accessibilityIdentifier("youtarr.details.loaded")
                        } else if let description = video.description,
                                  !description.isEmpty {
                            descriptionSection(description)
                        }
                    }
                    .frame(maxWidth: 820, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
        }
        .task {
            await viewModel.load()
        }
    }

    private var detailHeader: some View {
        HStack(spacing: 12) {
            Text("youtarr.details.title", tableName: "Plinx")
                .font(.title2.bold())

            Spacer()

            PlinxChromeButton(systemImage: "xmark") {
                dismiss()
            }
            .accessibilityLabel(Text("common.close", tableName: "Plinx"))
            .accessibilityIdentifier("youtarr.details.close")
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var primaryInformation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.detail?.title ?? video.title)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)

            Text(viewModel.detail?.channelTitle ?? video.channelTitle)
                .font(.headline)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 118), alignment: .leading)],
                alignment: .leading,
                spacing: 10
            ) {
                if let rating = viewModel.detail?.rating ?? video.rating {
                    detailChip(
                        rating.displayValue,
                        systemImage: "checkmark.shield"
                    )
                }
                if let duration = viewModel.detail?.duration ?? video.duration {
                    detailChip(
                        duration.displayValue,
                        systemImage: "clock"
                    )
                }
                if let published = formattedPublishedDate {
                    detailChip(
                        published,
                        systemImage: "calendar"
                    )
                }
                if let views = compactCount(viewModel.detail?.metadata?.viewCount) {
                    detailChip(
                        views + " " + YoutarrStrings.value("youtarr.details.views"),
                        systemImage: "play.rectangle"
                    )
                }
                if let likes = compactCount(viewModel.detail?.metadata?.likeCount) {
                    detailChip(
                        likes + " " + YoutarrStrings.value("youtarr.details.likes"),
                        systemImage: "hand.thumbsup"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func fullInformation(_ detail: YoutarrVideoDetail) -> some View {
        if let description = detail.metadata?.description, !description.isEmpty {
            descriptionSection(description)
        }

        let rows = technicalRows(detail)
        if !rows.isEmpty {
            detailSection(titleKey: "youtarr.details.videoInformation") {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Text(row.0)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(row.1)
                                .multilineTextAlignment(.trailing)
                        }
                        .font(.callout)
                        .padding(.vertical, 10)

                        if index < rows.count - 1 {
                            Divider()
                                .overlay(Color.white.opacity(0.08))
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
            }
        }

        if let tags = detail.metadata?.tags, !tags.isEmpty {
            detailSection(titleKey: "youtarr.details.tags") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tags.prefix(16), id: \.self) { tag in
                            Text(tag)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                }
            }
        }
    }

    private func descriptionSection(_ description: String) -> some View {
        detailSection(titleKey: "youtarr.details.description") {
            Text(description)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func detailSection<Content: View>(
        titleKey: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalizedStringKey(titleKey), tableName: "Plinx")
                .font(.title3.bold())
            content()
        }
    }

    private func detailChip(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private var formattedPublishedDate: String? {
        let raw = viewModel.detail?.publishedAt ?? video.publishedAt
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: raw) else { return nil }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func compactCount(_ value: Int?) -> String? {
        value?.formatted(.number.notation(.compactName))
    }

    private func technicalRows(
        _ detail: YoutarrVideoDetail
    ) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let categories = detail.metadata?.categories, !categories.isEmpty {
            rows.append((
                YoutarrStrings.value("youtarr.details.category"),
                categories.joined(separator: ", ")
            ))
        }
        if let availability = detail.metadata?.availability ?? detail.availability,
           !availability.isEmpty {
            rows.append((
                YoutarrStrings.value("youtarr.details.availability"),
                availability.capitalized
            ))
        }
        if let language = detail.metadata?.language, !language.isEmpty {
            rows.append((
                YoutarrStrings.value("youtarr.details.language"),
                language.uppercased()
            ))
        }
        if let resolution = resolutionDescription(detail) {
            rows.append((
                YoutarrStrings.value("youtarr.details.resolution"),
                resolution
            ))
        }
        if let fps = detail.metadata?.fps {
            rows.append((
                YoutarrStrings.value("youtarr.details.frameRate"),
                String(format: "%.0f fps", fps)
            ))
        }
        if let available = detail.metadata?.availableResolutions, !available.isEmpty {
            rows.append((
                YoutarrStrings.value("youtarr.details.availableResolutions"),
                available.sorted().map { "\($0)p" }.joined(separator: ", ")
            ))
        }
        if let followers = compactCount(detail.metadata?.channelFollowerCount) {
            rows.append((
                YoutarrStrings.value("youtarr.details.channelFollowers"),
                followers
            ))
        }
        return rows
    }

    private func resolutionDescription(_ detail: YoutarrVideoDetail) -> String? {
        if let resolution = detail.metadata?.resolution, !resolution.isEmpty {
            return resolution
        }
        if let width = detail.metadata?.width, let height = detail.metadata?.height {
            return "\(width) × \(height)"
        }
        return detail.videoResolution
    }

    private func retryDetails() {
        Task { @MainActor in
            await viewModel.retry()
        }
    }
}

private struct YoutarrWideRequestControl: View {
    let video: YoutarrVideo
    let state: YoutarrVideoActionState
    let action: () -> Void

    var body: some View {
        switch state {
        case .eligible:
            actionButton(
                title: YoutarrStrings.value("youtarr.request.action"),
                systemImage: "arrow.down.to.line.compact"
            )

        case .failed:
            actionButton(
                title: YoutarrStrings.value("youtarr.request.retry"),
                systemImage: "arrow.clockwise"
            )

        case .submitting:
            wideSurface {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("youtarr.request.submitting", tableName: "Plinx")
                }
            }
            .accessibilityIdentifier("youtarr.request.submitting.\(video.youtubeId)")

        case .requested(let status):
            wideSurface {
                Label(
                    status.map { YoutarrRequestPresentation.label(for: $0) }
                        ?? YoutarrStrings.value("youtarr.explore.requested"),
                    systemImage: status.map {
                        YoutarrRequestPresentation.systemImage(for: $0)
                    } ?? "clock.fill"
                )
            }

        case .downloaded:
            wideSurface {
                Label(
                    YoutarrStrings.value("youtarr.explore.downloaded"),
                    systemImage: "checkmark.circle.fill"
                )
            }

        case .unavailable:
            wideSurface {
                Label(
                    YoutarrStrings.value("youtarr.explore.unavailable"),
                    systemImage: "lock.fill"
                )
            }
            .foregroundStyle(.secondary)
        }
    }

    private func actionButton(title: String, systemImage: String) -> some View {
        Button(action: action) {
            wideSurface {
                Label(title, systemImage: systemImage)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("youtarr.details.request.\(video.youtubeId)")
    }

    private func wideSurface<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .font(.headline)
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.38), lineWidth: 1)
            }
    }
}
