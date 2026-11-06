import XCTest
@testable import Plinx

final class DownloadsGridLayoutPolicyTests: XCTestCase {
    private let phoneMetrics = DownloadsGridLayoutPolicy.Metrics(
        minimumColumnWidth: 136,
        maximumColumnWidth: 220,
        columnSpacing: 12
    )

    func test_columnsFillAvailableWidthExactly() {
        // iPhone portrait (393 pt wide minus 16 pt gutters), iPad portrait and
        // iPad landscape: the grid should reach both gutters, never leave a
        // ragged right edge, and never collapse below two columns.
        for width in [361.0, 788.0, 1148.0, 1334.0] as [CGFloat] {
            let arrangement = DownloadsGridLayoutPolicy.arrange(
                Array(repeating: .portrait, count: 12),
                availableWidth: width,
                metrics: phoneMetrics
            )

            XCTAssertGreaterThanOrEqual(arrangement.columnCount, 2)
            XCTAssertGreaterThanOrEqual(arrangement.columnWidth, phoneMetrics.minimumColumnWidth)
            XCTAssertEqual(arrangement.gridWidth, width, accuracy: 0.5, "width \(width)")
            XCTAssertEqual(arrangement.leadingInset, 0)
        }
    }

    func test_everyPlacementStartsOnASharedColumnLine() {
        let artworks: [DownloadsGridLayoutPolicy.Artwork] = [
            .portrait, .landscape(aspectRatio: 16.0 / 9.0), .portrait, .portrait,
            .landscape(aspectRatio: 2.0), .portrait, .portrait, .portrait,
        ]
        let arrangement = DownloadsGridLayoutPolicy.arrange(
            artworks,
            availableWidth: 788,
            metrics: phoneMetrics
        )

        let columnLines = (0..<arrangement.columnCount).map { arrangement.minX(forColumn: $0) }
        for row in arrangement.rows {
            var x = arrangement.leadingInset
            for placement in row.placements {
                XCTAssertEqual(x, columnLines[placement.column], accuracy: 0.001)
                XCTAssertLessThanOrEqual(placement.column + placement.span, arrangement.columnCount)
                x += placement.cellWidth + arrangement.columnSpacing
            }
        }
    }

    func test_landscapeSpansTwoColumnsAndRowSharesPosterHeight() {
        let arrangement = DownloadsGridLayoutPolicy.arrange(
            [.portrait, .landscape(aspectRatio: 16.0 / 9.0)],
            availableWidth: 788,
            metrics: phoneMetrics
        )

        XCTAssertEqual(arrangement.rows.count, 1)
        let row = arrangement.rows[0]
        let portrait = row.placements[0]
        let landscape = row.placements[1]

        XCTAssertEqual(landscape.span, 2)
        XCTAssertGreaterThan(landscape.posterSize.width, landscape.posterSize.height)
        XCTAssertGreaterThan(portrait.posterSize.height, portrait.posterSize.width)
        XCTAssertEqual(
            portrait.posterSize.width / portrait.posterSize.height,
            DownloadsArtworkLayoutPolicy.portraitAspectRatio,
            accuracy: 0.001
        )
        XCTAssertEqual(row.posterAreaHeight, portrait.posterSize.height, accuracy: 0.001)
    }

    func test_landscapeWrapsInsteadOfOverflowingRow() {
        // Two columns on a narrow phone: portrait fills column 0, so the
        // two-column landscape item must start the next row.
        let arrangement = DownloadsGridLayoutPolicy.arrange(
            [.portrait, .landscape(aspectRatio: 16.0 / 9.0), .portrait],
            availableWidth: 300,
            metrics: phoneMetrics
        )

        XCTAssertEqual(arrangement.columnCount, 2)
        XCTAssertEqual(arrangement.rows.map { $0.placements.map(\.index) }, [[0], [1], [2]])
        XCTAssertEqual(arrangement.rows[1].placements[0].column, 0)
        XCTAssertEqual(
            arrangement.rows[1].placements[0].cellWidth,
            arrangement.gridWidth,
            accuracy: 0.001
        )
    }

    func test_landscapeOnlyRowUsesLandscapeHeight() {
        let arrangement = DownloadsGridLayoutPolicy.arrange(
            [.landscape(aspectRatio: 16.0 / 9.0)],
            availableWidth: 788,
            metrics: phoneMetrics
        )

        let row = arrangement.rows[0]
        XCTAssertEqual(row.posterAreaHeight, row.placements[0].posterSize.height, accuracy: 0.001)
    }

    func test_maximumColumnWidthCentersGrid() {
        let metrics = DownloadsGridLayoutPolicy.Metrics(
            minimumColumnWidth: 400,
            maximumColumnWidth: 220,
            columnSpacing: 12,
            minimumColumnCount: 2
        )
        let arrangement = DownloadsGridLayoutPolicy.arrange(
            [.portrait, .portrait],
            availableWidth: 700,
            metrics: metrics
        )

        XCTAssertEqual(arrangement.columnWidth, 220)
        XCTAssertEqual(arrangement.leadingInset, ((700 - arrangement.gridWidth) / 2).rounded(.down))
    }

    func test_emptyInputProducesNoRows() {
        let arrangement = DownloadsGridLayoutPolicy.arrange([], availableWidth: 788, metrics: phoneMetrics)
        XCTAssertTrue(arrangement.rows.isEmpty)
    }
}
