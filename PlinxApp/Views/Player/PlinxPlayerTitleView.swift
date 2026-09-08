import SwiftUI

/// A title that remains inspectable when it does not fit the available chrome.
/// The full value remains available to VoiceOver even when Reduce Motion is on.
struct PlinxPlayerTitleView: View {
    let title: String
    let subtitle: String?
    let presentation: HeaderPresentation
    let isSharePlay: Bool
    let onInteractionChanged: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .headline) private var compactTitleSize: CGFloat = 17
    @ScaledMetric(relativeTo: .title3) private var wideTitleSize: CGFloat = 30
    @State private var contentWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var isInteracting = false

    private var titleFont: Font {
        .system(
            size: presentation == .compactPortrait ? compactTitleSize : wideTitleSize,
            weight: .semibold
        )
    }

    private var isOverflowing: Bool {
        contentWidth > containerWidth + 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(title)
                        .font(titleFont)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: true, vertical: false)
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: PlayerTitleWidthKey.self, value: geometry.size.width)
                        })
                        .id("player-title")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
                .background(GeometryReader { geometry in
                    Color.clear.onAppear { containerWidth = geometry.size.width }
                        .onChange(of: geometry.size.width) { _, value in containerWidth = value }
                })
                .onPreferenceChange(PlayerTitleWidthKey.self) { contentWidth = $0 }
                .playerTitleInteraction { setInteracting($0) }
                .task(id: automaticScrollID) {
                    guard isOverflowing, !reduceMotion, !isInteracting else { return }
                    let travelDuration = max(3, Double(contentWidth - containerWidth) / 22)
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(1.25))
                        guard !Task.isCancelled else { return }
                        withAnimation(.linear(duration: travelDuration)) {
                            proxy.scrollTo("player-title", anchor: .trailing)
                        }
                        try? await Task.sleep(for: .seconds(travelDuration + 1))
                        guard !Task.isCancelled else { return }
                        withAnimation(.linear(duration: travelDuration)) {
                            proxy.scrollTo("player-title", anchor: .leading)
                        }
                        try? await Task.sleep(for: .seconds(travelDuration + 1))
                    }
                }
            }

            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(presentation == .compactPortrait ? 1 : 2)
            }

            if isSharePlay {
                Text("sharePlay.badge")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule(style: .continuous).fill(Color.white.opacity(0.15)))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text([title, subtitle].compactMap { $0 }.joined(separator: ", ")))
        .onDisappear { setInteracting(false) }
    }

    private var automaticScrollID: AutomaticPlayerTitleScrollID {
        AutomaticPlayerTitleScrollID(
            title: title,
            contentWidth: contentWidth,
            containerWidth: containerWidth,
            reduceMotion: reduceMotion,
            isInteracting: isInteracting
        )
    }

    private func setInteracting(_ interacting: Bool) {
        guard isInteracting != interacting else { return }
        isInteracting = interacting
        onInteractionChanged(interacting)
    }
}

private struct AutomaticPlayerTitleScrollID: Hashable {
    let title: String
    let contentWidth: CGFloat
    let containerWidth: CGFloat
    let reduceMotion: Bool
    let isInteracting: Bool
}

private struct PlayerTitleWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    @ViewBuilder
    func playerTitleInteraction(_ onChanged: @escaping (Bool) -> Void) -> some View {
        #if os(tvOS)
        self
        #else
        simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in onChanged(true) }
                .onEnded { _ in onChanged(false) }
        )
        #endif
    }
}
