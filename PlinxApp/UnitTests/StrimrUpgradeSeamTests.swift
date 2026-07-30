import XCTest
@testable import Plinx

@MainActor
final class StrimrUpgradeSeamTests: XCTestCase {
    func test_flexiblePlexBooleanDecodesSupportedRepresentations() throws {
        let decoder = JSONDecoder()
        let values: [(String, Bool)] = [
            ("true", true),
            ("false", false),
            ("1", true),
            ("0", false),
            ("\"true\"", true),
            ("\"false\"", false),
            ("\"1\"", true),
            ("\"0\"", false)
        ]

        for (json, expected) in values {
            let decoded = try decoder.decode(PlexFlexibleBool.self, from: Data(json.utf8))
            XCTAssertEqual(decoded.value, expected, "Unexpected result for \(json)")
        }
    }

    func test_flexiblePlexBooleanRejectsAmbiguousValues() {
        let decoder = JSONDecoder()

        for json in ["2", "-1", "\"yes\"", "\"\"", "null", "[]", "{}"] {
            XCTAssertThrowsError(
                try decoder.decode(PlexFlexibleBool.self, from: Data(json.utf8)),
                "Expected \(json) to be rejected"
            )
        }
    }

    func test_titleLogoSelectionPrefersFirstLogoImage() {
        let poster = PlexImage(
            alt: "Poster",
            type: "coverPoster",
            url: URL(string: "https://example.test/poster.png")!
        )
        let logo = PlexImage(
            alt: "Title",
            type: "clearLogo",
            url: URL(string: "https://example.test/logo.png")!
        )

        XCTAssertEqual(
            MediaDetailViewModel.preferredTitleLogo(in: [poster, logo]),
            logo
        )
    }

    func test_titleLogoSelectionReturnsNilWithoutLogoArt() {
        let poster = PlexImage(
            alt: "Poster",
            type: "coverPoster",
            url: URL(string: "https://example.test/poster.png")!
        )

        XCTAssertNil(MediaDetailViewModel.preferredTitleLogo(in: [poster]))
    }

    func test_titleLogoSelectionIsCaseInsensitiveAndKeepsSourceOrder() {
        let firstLogo = PlexImage(
            alt: "Primary title",
            type: "CLEARLOGO",
            url: URL(string: "https://example.test/first-logo.png")!
        )
        let laterLogo = PlexImage(
            alt: "Alternate title",
            type: "logo",
            url: URL(string: "https://example.test/later-logo.png")!
        )

        XCTAssertEqual(
            MediaDetailViewModel.preferredTitleLogo(in: [firstLogo, laterLogo]),
            firstLogo
        )
    }
}
