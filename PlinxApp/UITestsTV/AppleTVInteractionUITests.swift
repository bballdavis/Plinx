import XCTest

final class AppleTVInteractionUITests: XCTestCase {
    func test_rootBrowse_remoteCanReturnToHeaderAndBackToFirstContent() {
        let app = launch(screen: "appleTVBrowseFocus")
        let home = app.buttons["main.tab.home"]
        let firstCard = app.buttons["home.card.fixture.0"]
        let secondCard = app.buttons["home.card.fixture.1"]

        assertFocused(home)
        XCUIRemote.shared.press(.down)
        assertFocused(firstCard)
        capture(name: "tvOS-4K-home-focused-artwork")
        XCUIRemote.shared.press(.right)
        assertFocused(secondCard)
        XCUIRemote.shared.press(.up)
        assertFocused(home)
        XCUIRemote.shared.press(.down)
        assertFocused(firstCard)
    }

    func test_rootBrowse_reduceMotionKeepsRingWithoutScalingArtwork() {
        let app = launch(screen: "appleTVBrowseFocus", reduceMotion: true)
        let firstCard = app.buttons["home.card.fixture.0"]
        let secondCard = app.buttons["home.card.fixture.1"]

        XCUIRemote.shared.press(.down)
        assertFocused(firstCard)
        // The four-point ring sits fully outside the artwork, expanding each
        // focused dimension by eight points. Reduce Motion must add no scale.
        XCTAssertEqual(firstCard.frame.width - secondCard.frame.width, 8, accuracy: 2)
        XCTAssertEqual(firstCard.frame.height - secondCard.frame.height, 8, accuracy: 2)
        capture(name: "tvOS-4K-home-focused-artwork-reduce-motion")
    }

    func test_libraryRoot_upTargetsLibrary_andDownRestoresFirstLibrary() {
        let app = launch(screen: "appleTVBrowseFocus")
        let home = app.buttons["main.tab.home"]
        let library = app.buttons["main.tab.library"]
        let firstLibrary = app.buttons["library.tile.0"]

        assertFocused(home)
        XCUIRemote.shared.press(.right)
        assertFocused(library)
        XCUIRemote.shared.press(.select)
        XCUIRemote.shared.press(.down)
        assertFocused(firstLibrary)
        capture(name: "tvOS-4K-library-focused-tile")
        XCUIRemote.shared.press(.up)
        assertFocused(library)
        XCUIRemote.shared.press(.down)
        assertFocused(firstLibrary)
    }

    func test_switchingFromLibraryBackHome_downAlwaysRestoresHomeContent() {
        let app = launch(screen: "appleTVBrowseFocus")
        let home = app.buttons["main.tab.home"]
        let library = app.buttons["main.tab.library"]
        let firstLibrary = app.buttons["library.tile.0"]
        let firstHomeCard = app.buttons["home.card.fixture.0"]
        let shellTitle = app.staticTexts["tv.shell.context.title"]

        assertFocused(home)
        XCUIRemote.shared.press(.right)
        assertFocused(library)
        XCUIRemote.shared.press(.select)
        XCTAssertEqual(shellTitle.label, "Library")
        XCUIRemote.shared.press(.down)
        assertFocused(firstLibrary)
        XCUIRemote.shared.press(.up)
        assertFocused(library)

        XCUIRemote.shared.press(.left)
        assertFocused(home)
        XCUIRemote.shared.press(.select)
        XCTAssertFalse(shellTitle.exists, "Only Home should render the Plinx brand in the shell's leading slot")
        XCUIRemote.shared.press(.down)
        assertFocused(firstHomeCard)
    }

    func test_emptyBrowse_downStaysInHeader() {
        let app = launch(screen: "appleTVBrowseFocusEmpty")
        let home = app.buttons["main.tab.home"]

        assertFocused(home)
        XCUIRemote.shared.press(.down)
        assertFocused(home)
        XCTAssertTrue(app.staticTexts["browse.fixture.empty"].exists)
    }

    func test_libraryDetail_downVisitsFilterThenMedia_andUpReversesRoute() {
        let app = launch(screen: "appleTVLibraryDetailFocus")
        let library = app.buttons["main.tab.library"]
        let filter = app.buttons["library.detail.filter.recommended"]
        let firstCard = app.buttons["library.detail.card.0"]

        assertFocused(library)
        XCUIRemote.shared.press(.down)
        assertFocused(filter)
        XCUIRemote.shared.press(.down)
        assertFocused(firstCard)
        XCUIRemote.shared.press(.up)
        assertFocused(filter)
        XCUIRemote.shared.press(.up)
        assertFocused(library)
        XCTAssertFalse(app.buttons["library.detail.back"].exists)
    }

    func test_movingAcrossHeader_doesNotSwitchTabsUntilSelect() {
        let app = launch(screen: "appleTVBrowseFocus")
        let home = app.buttons["main.tab.home"]
        let library = app.buttons["main.tab.library"]
        let firstHomeCard = app.buttons["home.card.fixture.0"]

        assertFocused(home)
        XCUIRemote.shared.press(.right)
        assertFocused(library)
        XCUIRemote.shared.press(.down)
        assertFocused(firstHomeCard)
    }

    func test_settings_hasDeterministicFirstFocus() {
        let app = launch(screen: "settings")
        assertFocused(app.buttons["settings.libraries"], timeout: 8)
        XCTAssertFalse(app.buttons["settings.close"].exists)
        capture(name: "tvOS-4K-settings-focused-row")
    }

    func test_settings_upAndDownMovesBetweenContentAndPersistentHeader() {
        let app = launch(screen: "settingsNavigation")
        let libraries = app.buttons["settings.libraries"]
        let settings = app.buttons["main.tab.settings"]

        assertFocused(libraries, timeout: 8)
        XCTAssertEqual(app.staticTexts["tv.shell.context.title"].label, "Settings")
        XCUIRemote.shared.press(.up)
        assertFocused(settings)
        XCUIRemote.shared.press(.down)
        assertFocused(libraries)
    }

    func test_settings_headerTabClosesAndRestoresDestinationFocus() {
        let app = launch(screen: "settingsNavigation")
        let libraries = app.buttons["settings.libraries"]
        let settings = app.buttons["main.tab.settings"]
        let home = app.buttons["main.tab.home"]

        assertFocused(libraries, timeout: 8)
        XCUIRemote.shared.press(.up)
        assertFocused(settings)
        move(.left, count: 3)
        assertFocused(home)
        XCUIRemote.shared.press(.select)

        XCTAssertTrue(app.staticTexts["settings.fixture.closed"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["settings.fixture.destination.home"].exists)
        XCTAssertFalse(app.buttons["settings.close"].exists)
        assertFocused(home)

        XCUIRemote.shared.press(.down)
        assertFocused(app.buttons["settings.fixture.restored.home"])
    }

    func test_settings_menuPopsSubpageBeforeClosingRoot() {
        let app = launch(screen: "settingsNavigation")
        let libraries = app.buttons["settings.libraries"]
        let movieRating = app.buttons["settings.rating.movie"]

        assertFocused(libraries, timeout: 8)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.libraries.screen"]
                .waitForExistence(timeout: 8)
        )
        XCTAssertTrue(app.buttons["settings.back"].exists)
        capture(name: "tvOS-4K-settings-subpage-back")

        XCUIRemote.shared.press(.menu)
        assertFocused(libraries, timeout: 8)
        XCTAssertFalse(app.staticTexts["settings.fixture.closed"].exists)

        for _ in 0..<20 where !movieRating.hasFocus {
            XCUIRemote.shared.press(.down)
        }
        assertFocused(movieRating, timeout: 8)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.rating.screen"]
                .waitForExistence(timeout: 8)
        )

        XCUIRemote.shared.press(.menu)
        assertFocused(movieRating, timeout: 8)
        XCTAssertFalse(app.staticTexts["settings.fixture.closed"].exists)

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(
            app.staticTexts["settings.fixture.closed"].waitForExistence(timeout: 8)
        )
    }

    func test_playerPreparation_hasFocusedBackAction() {
        let app = launch(screen: "playerLoading")
        assertFocused(app.buttons["player.back"], timeout: 8)
        XCTAssertEqual(app.activityIndicators.count, 0)
    }

    func test_parentalGate_selectEntersDigit_deleteRemovesIt_andInvalidUnlockStaysGated() {
        let app = launch(screen: "parentalGate")
        let entry = app.staticTexts["parentalGate.numberEntry"]
        let one = app.buttons["parentalGate.key.1"]

        XCTAssertTrue(one.waitForExistence(timeout: 8))
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        XCTAssertTrue(one.hasFocus, "The first digit should receive deterministic initial focus")

        XCUIRemote.shared.press(.select)
        XCTAssertEqual(entry.value as? String, "1")
        XCTAssertTrue(app.staticTexts["parentalGate.title"].exists)

        move(.down, count: 3)
        XCTAssertTrue(app.buttons["parentalGate.delete"].hasFocus)
        XCUIRemote.shared.press(.select)
        XCTAssertEqual(entry.value as? String, "Empty")

        move(.up, count: 3)
        XCUIRemote.shared.press(.select)
        move(.down, count: 3)
        move(.right, count: 2)
        XCTAssertTrue(app.buttons["parentalGate.unlock"].hasFocus)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(
            app.staticTexts["parentalGate.title"].exists,
            "An invalid answer must keep the parental gate open"
        )
    }

    func test_parentalGate_validMathAnswer_opensSettingsOnlyAfterUnlock() throws {
        let app = launch(screen: "parentalGate")
        let challengeElement = app.staticTexts["parentalGate.challenge"]
        XCTAssertTrue(challengeElement.waitForExistence(timeout: 8))
        let challenge = challengeElement.label
        let operands = challenge
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
        XCTAssertEqual(operands.count, 2)

        let answer = String(operands.reduce(1, *))
        var focusedPosition = KeyPosition(digit: 1)
        for digit in answer {
            let destination = KeyPosition(digit: try XCTUnwrap(Int(String(digit))))
            moveHorizontally(from: focusedPosition.column, to: destination.column)
            moveVertically(from: focusedPosition.row, to: destination.row)
            XCTAssertTrue(app.buttons["parentalGate.key.\(digit)"].hasFocus)
            XCUIRemote.shared.press(.select)
            focusedPosition = destination
        }

        XCTAssertTrue(app.staticTexts["parentalGate.title"].exists)
        moveHorizontally(from: focusedPosition.column, to: 2)
        moveVertically(from: focusedPosition.row, to: 3)
        XCTAssertTrue(app.buttons["parentalGate.unlock"].hasFocus)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(
            app.buttons["settings.rating.movie"].waitForExistence(timeout: 8),
            "A correct answer should reveal Settings after explicit Unlock"
        )
        XCTAssertFalse(app.staticTexts["parentalGate.title"].exists)
    }

    func test_settings_usesLargeGroupedRows_andReadableRatingChooser() {
        let app = launch(screen: "settings")
        let movieRating = app.buttons["settings.rating.movie"]

        XCTAssertTrue(movieRating.waitForExistence(timeout: 8))
        XCTAssertGreaterThanOrEqual(movieRating.frame.height, 72)

        for _ in 0..<20 where !movieRating.hasFocus {
            XCUIRemote.shared.press(.down)
        }
        XCTAssertTrue(movieRating.hasFocus)
        XCUIRemote.shared.press(.select)

        let focusedChoice = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH 'settings.rating.choice.' AND hasFocus == true"
            )
        ).firstMatch
        XCTAssertTrue(focusedChoice.waitForExistence(timeout: 8))
        XCTAssertGreaterThanOrEqual(focusedChoice.frame.height, 72)
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'green'")).firstMatch.exists
        )
    }

    private func capture(name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch(screen: String, reduceMotion: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "--disable-animations"]
        app.launchEnvironment["PLINX_UI_TEST_SCREEN"] = screen
        if reduceMotion {
            app.launchEnvironment["PLINX_UI_TEST_REDUCE_MOTION"] = "1"
        }
        app.launch()
        return app
    }

    private func move(_ direction: XCUIRemote.Button, count: Int) {
        for _ in 0..<count {
            XCUIRemote.shared.press(direction)
        }
    }

    private func assertFocused(
        _ element: XCUIElement,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), file: file, line: line)
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasFocus == true"),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: timeout),
            .completed,
            "Expected \(element.identifier) to have focus",
            file: file,
            line: line
        )
    }

    private func moveHorizontally(from source: Int, to destination: Int) {
        move(destination > source ? .right : .left, count: abs(destination - source))
    }

    private func moveVertically(from source: Int, to destination: Int) {
        move(destination > source ? .down : .up, count: abs(destination - source))
    }
}

private struct KeyPosition {
    let column: Int
    let row: Int

    init(digit: Int) {
        if digit == 0 {
            column = 1
            row = 3
        } else {
            column = (digit - 1) % 3
            row = (digit - 1) / 3
        }
    }
}
