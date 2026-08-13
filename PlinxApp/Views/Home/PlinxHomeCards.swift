import SwiftUI
import PlinxUI
import PlinxCore

/// Gives media cards one deterministic touch contract. A completed long press
/// wins over a tap, so opening quick actions never also starts playback or
/// navigation when the finger is released.
private struct PlinxMediaCardInteractionModifier: ViewModifier {
    let onTap: () -> Void
    let onLongPress: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(tvOS)
        content
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTap() }
        #else
        content
            .contentShape(Rectangle())
            .gesture(
                LongPressGesture(minimumDuration: 0.5, maximumDistance: 24)
                    .exclusively(before: TapGesture())
                    .onEnded { value in
                        switch value {
                        case .first:
                            onLongPress()
                        case .second:
                            onTap()
                        }
                    },
                including: .gesture
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTap() }
        #endif
    }
}

extension View {
    func plinxMediaCardInteraction(
        onTap: @escaping () -> Void,
        onLongPress: @escaping () -> Void
    ) -> some View {
        modifier(PlinxMediaCardInteractionModifier(onTap: onTap, onLongPress: onLongPress))
    }

    /// Use when an existing reusable card owns its normal Button action. The
    /// high-priority recognizer prevents that Button from winning a long press.
    @ViewBuilder
    func plinxQuickActionLongPress(_ action: @escaping () -> Void) -> some View {
        #if os(tvOS)
        highPriorityGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in action() }
        )
        #else
        highPriorityGesture(
            LongPressGesture(minimumDuration: 0.5, maximumDistance: 24)
                .onEnded { _ in action() }
        )
        #endif
    }
}

struct HomeMediaCardBody: View {
    let item: MediaDisplayItem
    let sectionKey: String
    let index: Int
    let cardWidth: CGFloat
    let ratio: CGFloat
    let isContinueWatching: Bool
    let watched: Bool
    let imageViewModel: MediaImageViewModel

    @Environment(\.isFocused) private var isFocused
    private var thumbHeight: CGFloat { cardWidth / ratio }

    private var focusHaloInset: CGFloat {
        #if os(tvOS)
        14
        #else
        0
        #endif
    }

    private var artworkCornerRadius: CGFloat {
        #if os(tvOS)
        18
        #else
        11
        #endif
    }

    private var titleFont: Font {
        #if os(tvOS)
        .subheadline.bold()
        #else
        .caption.bold()
        #endif
    }

    private var subtitleFont: Font {
        #if os(tvOS)
        .caption
        #else
        .caption2
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottom) {
                    MediaImageView(
                        viewModel: imageViewModel
                    )
                    .frame(width: cardWidth, height: thumbHeight)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: artworkCornerRadius, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if !isContinueWatching && watched {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.accentColor)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 24, height: 24)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.black.opacity(0.3), lineWidth: 1)
                            )
                            .padding(8)
                        }
                    }
                    .accessibilityIdentifier("home.thumbnail.\(sectionKey).\(index)")

                    if let pct = item.viewProgressPercentage, pct > 0 {
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.white.opacity(0.30))
                                .frame(width: cardWidth)
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(width: cardWidth * CGFloat(min(pct / 100.0, 1.0)))
                        }
                        .frame(width: cardWidth, height: 8)
                        .clipShape(RoundedRectangle(cornerRadius: artworkCornerRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: artworkCornerRadius, style: .continuous)
                                .stroke(Color.black.opacity(0.7), lineWidth: 1)
                        }
                    }
            }
            .frame(width: cardWidth, height: thumbHeight)
            .plinxTVCardFocusArtwork(
                isFocused: isFocused,
                cornerRadius: artworkCornerRadius
            )
            .frame(width: cardWidth + (focusHaloInset * 2), height: thumbHeight + (focusHaloInset * 2))

            Text(item.primaryLabel)
                .font(titleFont)
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: cardWidth, alignment: .leading)
                .padding(.leading, focusHaloInset)

            if let sub = item.secondaryLabel {
                Text(sub)
                    .font(subtitleFont)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .frame(width: cardWidth, alignment: .leading)
                    .padding(.leading, focusHaloInset)
            }
        }
        .frame(width: cardWidth + (focusHaloInset * 2), alignment: .leading)
        .accessibilityIdentifier("home.card.\(sectionKey).\(index)")
    }
}

// MARK: - JSON helpers


func decodeHomeStringArray(_ json: String) -> [String] {
    guard let data = json.data(using: .utf8),
          let arr = try? JSONDecoder().decode([String].self, from: data)
    else { return [] }
    return arr
}
