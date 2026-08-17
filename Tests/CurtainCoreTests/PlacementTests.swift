import XCTest
@testable import CurtainCore

final class PlacementTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "curtain.placement.tests"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func testRoundTripsPerApp() {
        PlacementStore.save(HidePlacement(rightNeighbour: "com.b", x: 900), for: "com.a", to: defaults)
        PlacementStore.save(HidePlacement(rightNeighbour: nil, x: 1100), for: "com.c", to: defaults)

        XCTAssertEqual(PlacementStore.placement(for: "com.a", in: defaults)?.rightNeighbour, "com.b")
        XCTAssertEqual(PlacementStore.placement(for: "com.c", in: defaults)?.x, 1100)
    }

    func testUnknownAppHasNoPlacement() {
        XCTAssertNil(PlacementStore.placement(for: "com.nobody", in: defaults))
    }

    func testForgettingOneLeavesTheRest() {
        PlacementStore.save(HidePlacement(rightNeighbour: "com.b", x: 900), for: "com.a", to: defaults)
        PlacementStore.save(HidePlacement(rightNeighbour: "com.d", x: 950), for: "com.c", to: defaults)
        PlacementStore.forget("com.a", in: defaults)

        XCTAssertNil(PlacementStore.placement(for: "com.a", in: defaults))
        XCTAssertNotNil(PlacementStore.placement(for: "com.c", in: defaults))
    }

    func testPrefersTheRememberedNeighbour() {
        // The neighbour is the steady landmark: even though the icon was at 900
        // when hidden, the bar has since reflowed and that neighbour now sits at
        // 1000, which is where the icon belongs.
        let placement = HidePlacement(rightNeighbour: "com.b", x: 900)
        let target = DropTarget.x(
            for: placement,
            neighbour: ItemFrame(minX: 1000, width: 32),
            fallback: 500
        )
        XCTAssertEqual(target, 1000 - DropTarget.neighbourGap)
    }

    func testFallsBackToRememberedXWhenTheNeighbourIsGone() {
        let placement = HidePlacement(rightNeighbour: "com.b", x: 900)
        XCTAssertEqual(DropTarget.x(for: placement, neighbour: nil, fallback: 500), 900)
    }

    func testFallsBackToTheCallerWhenNothingIsRemembered() {
        XCTAssertEqual(DropTarget.x(for: nil, neighbour: nil, fallback: 500), 500)
    }

    func testIgnoresAnOffscreenRememberedX() {
        // An icon hidden while it was itself off-screen has nothing useful to
        // say about where it belongs.
        let placement = HidePlacement(rightNeighbour: nil, x: -1200)
        XCTAssertEqual(DropTarget.x(for: placement, neighbour: nil, fallback: 500), 500)
    }
}
