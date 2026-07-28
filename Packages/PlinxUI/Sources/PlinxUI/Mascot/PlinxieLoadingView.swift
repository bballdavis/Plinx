import SwiftUI

private struct PlinxLoadingReduceMotionOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    var plinxLoadingReduceMotionOverride: Bool? {
        get { self[PlinxLoadingReduceMotionOverrideKey.self] }
        set { self[PlinxLoadingReduceMotionOverrideKey.self] = newValue }
    }
}

/// Responsive sizes for Plinx's rounded-square activity indicator.
public enum PlinxLoadingSize: Sendable, Equatable {
    case compact
    case regular
    case hero

    var dimension: CGFloat {
        #if os(tvOS)
        switch self {
        case .compact: 30
        case .regular: 84
        case .hero: 320
        }
        #else
        switch self {
        case .compact: 20
        case .regular: 56
        case .hero: 260
        }
        #endif
    }

    var cornerRadius: CGFloat {
        switch self {
        case .compact: 5
        case .regular: 11
        case .hero: 32
        }
    }

    var logoWidth: CGFloat {
        switch self {
        case .compact: 0
        case .regular: dimension * 0.64
        case .hero: dimension * 0.58
        }
    }

    var strokeWidth: CGFloat {
        switch self {
        case .compact: 2
        case .regular: 3.5
        case .hero: 3
        }
    }

    var labelSpacing: CGFloat {
        switch self {
        case .compact: 4
        case .regular: 8
        case .hero: 18
        }
    }

    var labelFont: Font {
        switch self {
        case .compact: .caption2.weight(.semibold)
        case .regular: .callout.weight(.semibold)
        case .hero:
            #if os(tvOS)
            .title.weight(.semibold)
            #else
            .title2.weight(.semibold)
            #endif
        }
    }
}

/// Background treatment for the loading indicator.
public enum PlinxLoadingSurface: Sendable, Equatable {
    /// Logo and activity path only. Best for compact inline contexts.
    case transparent
    /// A lightly frosted square for app loading states.
    case glass
    /// A high-contrast smoked square for playback buffering.
    case video
}

/// Plinx's reusable rounded-square loading indicator.
///
/// Compact indicators omit the logo for clarity inline. Regular indicators use
/// a restrained Plinx mark for video and local loading states, while hero
/// indicators use the larger canonical chevron for full-screen loading. Motion
/// stops when Reduce Motion is enabled, while the complete gradient perimeter
/// remains visible.
public struct PlinxLoadingIndicator: View {
    public let size: PlinxLoadingSize
    public let surface: PlinxLoadingSurface
    public let label: LocalizedStringKey?
    public let accessibilityLabelText: LocalizedStringKey?
    public let accessibilityIdentifier: String

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.plinxLoadingReduceMotionOverride) private var reduceMotionOverride
    @State private var isAnimating = false

    private let lime = Color(red: 0.619, green: 0.933, blue: 0.450)
    private let teal = Color(red: 0.225, green: 0.620, blue: 0.570)
    private let cyan = Color(red: 0.34, green: 0.93, blue: 0.94)

    public init(
        size: PlinxLoadingSize = .compact,
        surface: PlinxLoadingSurface = .transparent,
        label: LocalizedStringKey? = nil,
        accessibilityLabel: LocalizedStringKey? = nil,
        accessibilityIdentifier: String = "plinx.loading.indicator"
    ) {
        self.size = size
        self.surface = surface
        self.label = label
        self.accessibilityLabelText = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    public var body: some View {
        VStack(spacing: size.labelSpacing) {
            beacon

            if let label {
                Text(label)
                    .font(size.labelFont)
                    .foregroundStyle(labelColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier(accessibilityIdentifier)
        .onAppear {
            isAnimating = !reduceMotion
        }
        .onChange(of: reduceMotion) { _, newValue in
            isAnimating = !newValue
        }
    }

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }

    private var beacon: some View {
        let shape = RoundedRectangle(
            cornerRadius: size.cornerRadius,
            style: .continuous
        )

        return ZStack {
            surfaceFill(shape: shape)

            shape
                .stroke(baseStrokeColor, lineWidth: size.strokeWidth)

            if reduceMotion {
                shape
                    .stroke(
                        LinearGradient(
                            colors: [lime, teal, cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: size.strokeWidth
                    )
            } else {
                shape
                    .stroke(
                        AngularGradient(
                            colors: [
                                .clear,
                                .clear,
                                lime,
                                teal,
                                cyan,
                                .white,
                                .clear,
                                .clear,
                            ],
                            center: .center,
                            startAngle: .degrees(isAnimating ? 360 : 0),
                            endAngle: .degrees(isAnimating ? 720 : 360)
                        ),
                        style: StrokeStyle(
                            lineWidth: size.strokeWidth,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .animation(
                        .linear(duration: 1.35).repeatForever(autoreverses: false),
                        value: isAnimating
                    )
            }

            if size != .compact {
                Image("plinx_loading_logo", bundle: .module)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.logoWidth)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size.dimension, height: size.dimension)
        .shadow(
            color: surface == .video ? teal.opacity(0.42) : teal.opacity(0.18),
            radius: surface == .video ? 20 : 8
        )
    }

    @ViewBuilder
    private func surfaceFill(
        shape: RoundedRectangle
    ) -> some View {
        switch surface {
        case .transparent:
            shape.fill(Color.clear)
        case .glass:
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.fill(Color.black.opacity(0.2)))
        case .video:
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.fill(Color.black.opacity(0.42)))
        }
    }

    private var baseStrokeColor: Color {
        switch surface {
        case .transparent:
            Color.primary.opacity(0.16)
        case .glass:
            Color.white.opacity(0.28)
        case .video:
            Color.white.opacity(0.5)
        }
    }

    private var labelColor: Color {
        surface == .video ? .white : .primary
    }

    private var accessibilityText: Text {
        if let accessibilityLabelText {
            return Text(accessibilityLabelText)
        }
        if let label {
            return Text(label)
        }
        return Text("Loading")
    }
}

/// Global ProgressView style used by Plinx.
///
/// Ordinary indeterminate progress adopts the compact logo-free perimeter.
/// Explicit large controls use the regular beacon with a small mark. Determinate values
/// keep a linear progress bar and their original semantic value.
public struct PlinxProgressViewStyle: ProgressViewStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        PlinxProgressViewStyleBody(configuration: configuration)
    }
}

private struct PlinxProgressViewStyleBody: View {
    let configuration: ProgressViewStyleConfiguration

    @Environment(\.controlSize) private var controlSize

    var body: some View {
        if let fractionCompleted = configuration.fractionCompleted {
            VStack(alignment: .leading, spacing: 6) {
                configuration.label

                GeometryReader { proxy in
                    let progress = min(max(fractionCompleted, 0), 1)

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.2))

                        Capsule()
                            .fill(.tint)
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: determinateBarHeight)

                if let currentValueLabel = configuration.currentValueLabel {
                    currentValueLabel
                }
            }
        } else {
            VStack(spacing: loadingSize.labelSpacing) {
                PlinxLoadingIndicator(
                    size: loadingSize,
                    surface: .transparent,
                    accessibilityIdentifier: "plinx.loading.progress"
                )

                configuration.label
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var loadingSize: PlinxLoadingSize {
        switch controlSize {
        case .large:
            .regular
        default:
            .compact
        }
    }

    private var determinateBarHeight: CGFloat {
        switch controlSize {
        case .mini:
            2
        case .small:
            3
        case .large:
            8
        default:
            4
        }
    }
}

/// Backward-compatible wrapper for the original placeholder loading view.
@available(*, deprecated, message: "Use PlinxLoadingIndicator instead.")
public struct PlinxieLoadingView: View {
    public init() {}

    public var body: some View {
        PlinxLoadingIndicator(
            size: .regular,
            surface: .glass,
            label: "Plinx"
        )
        .padding()
    }
}
