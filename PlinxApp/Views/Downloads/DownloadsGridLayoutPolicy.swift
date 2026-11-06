import CoreGraphics

/// Deterministic column grid for the Downloads tab.
///
/// The grid divides the available width into equal columns so every card edge
/// lands on a shared column line in portrait and landscape, on iPhone and iPad.
/// Portrait posters occupy one column; landscape artwork (Other Videos, clips)
/// spans two columns so it keeps a readable size. Every card in a row shares
/// the row's poster-area height and artwork is bottom-aligned inside it, so
/// titles start on one baseline even when a row mixes portrait and landscape
/// art. Items keep their sorted order; a landscape item that does not fit the
/// remaining columns of a row starts the next row.
struct DownloadsGridLayoutPolicy {
    enum Artwork: Equatable {
        case portrait
        case landscape(aspectRatio: CGFloat)
    }

    struct Metrics: Equatable {
        var minimumColumnWidth: CGFloat
        var maximumColumnWidth: CGFloat
        var columnSpacing: CGFloat
        var minimumColumnCount: Int = 2
        var landscapeColumnSpan: Int = 2
    }

    struct Placement: Equatable {
        /// Index into the artwork array passed to `arrange`.
        let index: Int
        let column: Int
        let span: Int
        /// Width of the card slot (column width times span plus inner gaps).
        let cellWidth: CGFloat
        let posterSize: CGSize
    }

    struct Row: Equatable {
        let placements: [Placement]
        /// Tallest poster in the row; every card in the row uses this height.
        let posterAreaHeight: CGFloat
    }

    struct Arrangement: Equatable {
        let columnCount: Int
        let columnWidth: CGFloat
        let columnSpacing: CGFloat
        /// Leading inset that centers the grid when columns hit their maximum
        /// width. Zero whenever the columns fill the available width.
        let leadingInset: CGFloat
        let rows: [Row]

        var gridWidth: CGFloat {
            CGFloat(columnCount) * columnWidth + CGFloat(max(columnCount - 1, 0)) * columnSpacing
        }

        func minX(forColumn column: Int) -> CGFloat {
            leadingInset + CGFloat(column) * (columnWidth + columnSpacing)
        }
    }

    static func columnCount(availableWidth: CGFloat, metrics: Metrics) -> Int {
        let width = max(availableWidth, 1)
        let spacing = max(metrics.columnSpacing, 0)
        let minimumWidth = max(metrics.minimumColumnWidth, 1)
        let fitting = Int(((width + spacing) / (minimumWidth + spacing)).rounded(.down))
        return max(metrics.minimumColumnCount, fitting, 1)
    }

    static func columnWidth(availableWidth: CGFloat, columnCount: Int, metrics: Metrics) -> CGFloat {
        let width = max(availableWidth, 1)
        let gaps = CGFloat(max(columnCount - 1, 0)) * metrics.columnSpacing
        let fill = (width - gaps) / CGFloat(max(columnCount, 1))
        return max(min(fill, metrics.maximumColumnWidth), 1)
    }

    static func arrange(
        _ artworks: [Artwork],
        availableWidth: CGFloat,
        metrics: Metrics
    ) -> Arrangement {
        let columns = columnCount(availableWidth: availableWidth, metrics: metrics)
        let width = columnWidth(availableWidth: availableWidth, columnCount: columns, metrics: metrics)
        let spacing = metrics.columnSpacing
        let landscapeSpan = min(max(metrics.landscapeColumnSpan, 1), columns)

        func slotWidth(span: Int) -> CGFloat {
            CGFloat(span) * width + CGFloat(span - 1) * spacing
        }

        var rows: [Row] = []
        var current: [Placement] = []
        var column = 0

        func closeRow() {
            guard !current.isEmpty else { return }
            let height = current.map(\.posterSize.height).max() ?? 0
            rows.append(Row(placements: current, posterAreaHeight: height))
            current = []
            column = 0
        }

        for (index, artwork) in artworks.enumerated() {
            let span: Int
            let posterSize: CGSize
            switch artwork {
            case .portrait:
                span = 1
                let posterWidth = slotWidth(span: 1)
                posterSize = CGSize(
                    width: posterWidth,
                    height: posterWidth / DownloadsArtworkLayoutPolicy.portraitAspectRatio
                )
            case .landscape(let aspectRatio):
                span = landscapeSpan
                let posterWidth = slotWidth(span: span)
                posterSize = CGSize(width: posterWidth, height: posterWidth / max(aspectRatio, 0.1))
            }

            if column + span > columns {
                closeRow()
            }

            current.append(
                Placement(
                    index: index,
                    column: column,
                    span: span,
                    cellWidth: slotWidth(span: span),
                    posterSize: posterSize
                )
            )
            column += span
            if column >= columns {
                closeRow()
            }
        }
        closeRow()

        let gridWidth = CGFloat(columns) * width + CGFloat(columns - 1) * spacing
        let leadingInset = max((max(availableWidth, 1) - gridWidth) / 2, 0)

        return Arrangement(
            columnCount: columns,
            columnWidth: width,
            columnSpacing: spacing,
            leadingInset: leadingInset.rounded(.down),
            rows: rows
        )
    }
}
