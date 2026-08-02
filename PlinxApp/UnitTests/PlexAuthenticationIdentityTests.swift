import XCTest
@testable import Plinx

final class PlexAuthenticationIdentityTests: XCTestCase {
    func test_productIdentityPrefersHostDisplayName() {
        XCTAssertEqual(
            PlexProductIdentity.productName(
                in: [
                    "CFBundleDisplayName": "Plinx",
                    "CFBundleName": "Fallback"
                ]
            ),
            "Plinx"
        )
    }

    func test_productIdentityFallsBackToBundleNameThenStrimr() {
        XCTAssertEqual(
            PlexProductIdentity.productName(in: ["CFBundleName": "Hosted App"]),
            "Hosted App"
        )
        XCTAssertEqual(PlexProductIdentity.productName(in: [:]), "Strimr")
    }

    func test_authURLPercentEncodesProductAndUsesMatchingIdentity() throws {
        let url = PlexAuthURLBuilder.url(
            clientIdentifier: "client/id",
            code: "pin code",
            productName: "Plinx Kids"
        )

        let components = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )
        let fragment = try XCTUnwrap(components.fragment)
        let query = try XCTUnwrap(
            URLComponents(string: "https://example.test/\(fragment)")?.queryItems
        )
        let values = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value) })

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "app.plex.tv")
        XCTAssertEqual(components.path, "/auth")
        XCTAssertEqual(values["clientID"]!, "client/id")
        XCTAssertEqual(values["context[device][product]"]!, "Plinx Kids")
        XCTAssertEqual(values["code"]!, "pin code")
    }
}
