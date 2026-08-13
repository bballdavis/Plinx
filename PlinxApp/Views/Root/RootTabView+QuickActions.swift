import SwiftUI
import PlinxCore
import PlinxUI

extension RootTabView {
    func quickActionSheet(for item: MediaDisplayItem) -> some View {
        let options = quickActionOptions(for: item)
        let optionIDs = options.map(\.id)
        return ZStack(alignment: .bottom) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .accessibilityIdentifier("quickAction.backdrop")
                .onTapGesture {
                    selectedQuickActionMedia = nil
                }

            VStack(alignment: .leading, spacing: 12) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityIdentifier("quickAction.sheet")

                Text(item.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                ForEach(options) { option in
                    quickActionButton(option)
                }

                quickActionCancelButton
            }
            .padding(14)
            .liquidGlassBackground(style: PlinxTheme.Glass(cornerRadius: quickActionCornerRadius))
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            #if os(tvOS)
            .focusSection()
            #endif
        }
        #if os(tvOS)
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                focusedQuickActionID = optionIDs.first ?? QuickActionFocusOrder.cancelID
            }
        }
        .onDisappear {
            focusedQuickActionID = nil
        }
        .onMoveCommand { direction in
            handleQuickActionMove(direction, optionIDs: optionIDs)
        }
        .onPlayPauseCommand {
            performFocusedQuickAction(options)
        }
        .onExitCommand {
            selectedQuickActionMedia = nil
        }
        #endif
    }

    var quickActionCancelButton: some View {
        #if os(tvOS)
        let isFocused = focusedQuickActionID == QuickActionFocusOrder.cancelID
        #else
        let isFocused = false
        #endif

        return Button {
            selectedQuickActionMedia = nil
        } label: {
            Text(String(localized: "common.actions.cancel"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.95))
                .frame(maxWidth: .infinity, minHeight: quickActionCancelMinHeight)
                .background(
                    RoundedRectangle(cornerRadius: quickActionCornerRadius, style: .continuous)
                        .fill(PlinxBrand.surface.opacity(isFocused ? 1 : 0.9))
                )
                .plinxFocusSurface(
                    isSelected: false,
                    isFocused: isFocused,
                    style: PlinxFocusSurfaceStyle(cornerRadius: quickActionCornerRadius)
                )
        }
        .buttonStyle(.plain)
        #if os(tvOS)
        .focusEffectDisabled()
        .focused($focusedQuickActionID, equals: QuickActionFocusOrder.cancelID)
        #endif
        .accessibilityIdentifier("quickAction.cancel")
    }

    func quickActionButton(_ option: QuickActionOption) -> some View {
        #if os(tvOS)
        let isFocused = focusedQuickActionID == option.id
        #else
        let isFocused = false
        #endif

        return Button(role: option.role) {
            performQuickAction(option.action)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: option.systemImage)
                    .font(.system(size: quickActionIconSize, weight: .semibold))
                Text(option.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.95))
            .padding(.horizontal, quickActionHorizontalPadding)
            .frame(maxWidth: .infinity, minHeight: quickActionOptionMinHeight)
            .background(
                RoundedRectangle(cornerRadius: quickActionCornerRadius, style: .continuous)
                    .fill(PlinxBrand.surface.opacity(isFocused ? 1 : 0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: quickActionCornerRadius, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.32), lineWidth: 1)
            )
            .plinxFocusSurface(
                isSelected: false,
                isFocused: isFocused,
                style: PlinxFocusSurfaceStyle(cornerRadius: quickActionCornerRadius)
            )
        }
        .buttonStyle(PlinkButtonStyle())
        #if os(tvOS)
        .focusEffectDisabled()
        .focused($focusedQuickActionID, equals: option.id)
        #endif
        .accessibilityIdentifier("quickAction.option.\(option.id)")
    }

    #if os(tvOS)
    func handleQuickActionMove(_ direction: MoveCommandDirection, optionIDs: [String]) {
        let focusDirection: QuickActionFocusDirection
        switch direction {
        case .up:
            focusDirection = .up
        case .down:
            focusDirection = .down
        default:
            return
        }

        focusedQuickActionID = QuickActionFocusOrder.nextFocusedID(
            current: focusedQuickActionID,
            optionIDs: optionIDs,
            direction: focusDirection
        )
    }

    func performFocusedQuickAction(_ options: [QuickActionOption]) {
        guard let focusedQuickActionID else { return }
        if focusedQuickActionID == QuickActionFocusOrder.cancelID {
            selectedQuickActionMedia = nil
            return
        }

        guard let option = options.first(where: { $0.id == focusedQuickActionID }) else { return }
        performQuickAction(option.action)
    }
    #endif

    func performQuickAction(_ action: @escaping () -> Void) {
        selectedQuickActionMedia = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            action()
        }
    }

    func quickActionOptions(for item: MediaDisplayItem) -> [QuickActionOption] {
        switch item {
        case let .playable(media):
            var actions: [QuickActionOption] = [
                QuickActionOption(
                    id: "play",
                    title: String(localized: "common.actions.play"),
                    systemImage: "play.fill",
                    role: nil,
                    action: {
                        handlePrimarySelection(item)
                    }
                ),
                QuickActionOption(
                    id: "toggle-watched",
                    title: isWatched(media)
                        ? String(localized: "quickActions.markUnwatched", table: "Plinx")
                        : String(localized: "quickActions.markWatched", table: "Plinx"),
                    systemImage: isWatched(media) ? "checkmark.circle.fill" : "checkmark.circle",
                    role: nil,
                    action: {
                        Task { await toggleWatched(media) }
                    }
                )
            ]

            #if !os(tvOS)
            switch QuickActionDownloadActionPolicy.action(for: media, downloadItems: downloadManager.items) {
            case .download:
                let downloadTitle: String
                switch media.type {
                case .show:
                    downloadTitle = "Download All Episodes"
                case .season:
                    downloadTitle = "Download Season"
                default:
                    downloadTitle = "Download Video"
                }

                actions.append(
                    QuickActionOption(
                        id: "download-\(media.id)",
                        title: downloadTitle,
                        systemImage: "arrow.down.circle",
                        role: nil,
                        action: {
                            guard PlinxContentAuthorization.isAllowed(media, policy: safetyPolicy) else {
                                quickActionErrorMessage = NSLocalizedString(
                                    "downloads.blockedByContentControls",
                                    tableName: "Plinx",
                                    comment: ""
                                )
                                return
                            }
                            Task {
                                guard let ownerIdentity = sessionManager.plinxDownloadOwnerIdentity else {
                                    quickActionErrorMessage = NSLocalizedString(
                                        "downloads.ownerUnavailable",
                                        tableName: "Plinx",
                                        comment: ""
                                    )
                                    return
                                }
                                let newDownloadIDs: [String]
                                switch media.type {
                                case .show:
                                    newDownloadIDs = await downloadManager.enqueueShow(
                                        ratingKey: media.id,
                                        context: plexApiContext
                                    )
                                case .season:
                                    newDownloadIDs = await downloadManager.enqueueSeason(
                                        ratingKey: media.id,
                                        context: plexApiContext
                                    )
                                default:
                                    newDownloadIDs = await downloadManager.enqueueItem(
                                        ratingKey: media.id,
                                        context: plexApiContext
                                    )
                                }
                                downloadOwnershipStore.claim(
                                    downloadIDs: newDownloadIDs,
                                    as: ownerIdentity
                                )
                            }
                        }
                    )
                )
            case .goToDownloads:
                actions.append(
                    QuickActionOption(
                        id: "go-downloads-\(media.id)",
                        title: "Go to downloads",
                        systemImage: "arrow.down.circle.fill",
                        role: nil,
                        action: {
                            mainCoordinator.resetToRoot(for: .more)
                            mainCoordinator.tab = .more
                        }
                    )
                )
            }
            #endif

            actions.append(
                QuickActionOption(
                    id: "go-details",
                    title: String(localized: "quickActions.moreInfo", table: "Plinx"),
                    systemImage: "info.circle",
                    role: nil,
                    action: {
                        mainCoordinator.showMediaDetail(media)
                    }
                )
            )

            return actions

        case let .collection(collection):
            return [
                QuickActionOption(
                    id: "collection-details-\(collection.id)",
                    title: String(localized: "quickActions.moreInfo", table: "Plinx"),
                    systemImage: "info.circle",
                    role: nil,
                    action: {
                        mainCoordinator.showCollectionDetail(collection)
                    }
                )
            ]

        case let .playlist(playlist):
            return [
                QuickActionOption(
                    id: "playlist-play-\(playlist.id)",
                    title: String(localized: "common.actions.play"),
                    systemImage: "play.fill",
                    role: nil,
                    action: {
                        handlePrimarySelection(item)
                    }
                ),
                QuickActionOption(
                    id: "playlist-details-\(playlist.id)",
                    title: String(localized: "quickActions.moreInfo", table: "Plinx"),
                    systemImage: "info.circle",
                    role: nil,
                    action: {
                        mainCoordinator.showPlaylistDetail(playlist)
                    }
                )
            ]
        }
    }

    func toggleWatched(_ item: MediaItem) async {
        guard !ReleaseScreenshotCaptureMode.isActive() else {
            selectedQuickActionMedia = nil
            return
        }
        let wasWatched = isWatched(item)

        // Optimistic local update — instant UI feedback
        watchedOverrides[item.id] = !wasWatched
        selectedQuickActionMedia = nil

        do {
            let scrobbleRepository = try ScrobbleRepository(context: plexApiContext)
            if wasWatched {
                try await scrobbleRepository.markUnwatched(key: item.id)
            } else {
                try await scrobbleRepository.markWatched(key: item.id)
            }
            // Reload from server to refresh home data. Keep the successful
            // local override in place so independently owned library view
            // models cannot briefly revert to stale watch state.
            await homeViewModel?.reload()
        } catch {
            // Revert optimistic update on failure
            watchedOverrides.removeValue(forKey: item.id)
            quickActionErrorMessage = error.localizedDescription
        }
    }

    func isWatched(_ item: MediaItem) -> Bool {
        // Check local override first (instant feedback)
        if let override = watchedOverrides[item.id] {
            return override
        }
        guard let playableType = PlayableItemType(plexType: item.type) else { return false }

        switch playableType {
        case .movie, .episode, .clip:
            return (item.viewCount ?? 0) > 0
        case .show, .season:
            guard let leafCount = item.leafCount, let viewedLeafCount = item.viewedLeafCount else {
                return false
            }
            guard leafCount > 0 else { return false }
            return leafCount == viewedLeafCount
        }
    }

    func isWatchedDisplay(_ item: MediaDisplayItem) -> Bool {
        guard let media = item.playableItem else { return false }
        return isWatched(media)
    }
}
