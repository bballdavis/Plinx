import XCTest
@testable import Plinx

@MainActor
final class SafeLibraryViewModelTests: XCTestCase {
    func test_allLibrariesAreVisibleByDefaultAndParentCanHideOne() {
        let context = PlexAPIContext()
        let store = LibraryStore(context: context)
        store.libraries = [
            Library(id: "movies", title: "Movies", type: .movie, sectionId: 1),
            Library(id: "shows", title: "Shows", type: .show, sectionId: 2)
        ]
        let inner = LibraryViewModel(context: context, libraryStore: store)
        let model = SafeLibraryViewModel(inner: inner, context: context)

        XCTAssertEqual(model.libraries.map(\.id), ["movies", "shows"])

        model.updateHiddenLibraryIDs(["shows"])

        XCTAssertEqual(model.libraries.map(\.id), ["movies"])
    }
}
