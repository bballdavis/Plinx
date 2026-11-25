import XCTest
@testable import Plinx

/// Jellyfin's local server search sends a UDP broadcast. On iPhone and iPad
/// that needs the managed `com.apple.developer.networking.multicast`
/// entitlement, which the iOS target is not signed with yet
/// (docs/development/setup.md, "Entitlements"). Until it is, the sign-in form
/// offers manual address entry only and never starts a search that can only
/// fail.
///
/// When the iOS target is signed with the granted entitlement and defines
/// `PLINX_MULTICAST_ENTITLEMENT`, these expectations fail on purpose: update
/// them in that same change.
@MainActor
final class JellyfinServerDiscoveryAvailabilityTests: XCTestCase {
    func test_iOSBuildWithoutTheMulticastEntitlementDoesNotSupportDiscovery() {
        XCTAssertFalse(JellyfinServerDiscoveryService.isSupported)
    }

    func test_signInFormHidesTheServerSearch() {
        let viewModel = makeViewModel()

        XCTAssertFalse(viewModel.isDiscoveryAvailable)
    }

    func test_discoverServersDoesNothingWhenDiscoveryIsUnavailable() async throws {
        let viewModel = makeViewModel()
        let earlierServer = try JellyfinDiscoveredServer(
            serverID: "earlier",
            name: "Earlier server",
            url: XCTUnwrap(URL(string: "http://192.168.1.20:8096")),
        )
        // A search that started would clear both before broadcasting.
        viewModel.discoveredServers = [earlierServer]
        viewModel.errorMessage = "earlier message"

        await viewModel.discoverServers()

        XCTAssertFalse(viewModel.isDiscovering)
        XCTAssertEqual(viewModel.discoveredServers, [earlierServer])
        XCTAssertEqual(viewModel.errorMessage, "earlier message")
    }

    private func makeViewModel() -> JellyfinAuthenticationViewModel {
        JellyfinAuthenticationViewModel { _, _ in
            XCTFail("No sign-in is expected")
        }
    }
}
