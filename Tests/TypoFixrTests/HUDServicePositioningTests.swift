import XCTest
@testable import TypoFixr

final class HUDServicePositioningTests: XCTestCase {
    func testBottomCenterPlacementOnStandardFrame() {
        let origin = HUDService.hudOrigin(
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            windowSize: CGSize(width: 280, height: 72),
            bottomMargin: 28,
            horizontalSafetyMargin: 12
        )

        XCTAssertEqual(origin.x, 580)
        XCTAssertEqual(origin.y, 28)
    }

    func testBottomCenterPlacementRespectsNegativeMinX() {
        let origin = HUDService.hudOrigin(
            visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
            windowSize: CGSize(width: 300, height: 60),
            bottomMargin: 28,
            horizontalSafetyMargin: 12
        )

        XCTAssertEqual(origin.x, -1110)
        XCTAssertEqual(origin.y, 28)
    }

    func testHorizontalClampWhenWindowNearOrWiderThanVisibleFrame() {
        let visibleFrame = CGRect(x: 100, y: 50, width: 320, height: 500)

        let nearWidthOrigin = HUDService.hudOrigin(
            visibleFrame: visibleFrame,
            windowSize: CGSize(width: 300, height: 60),
            bottomMargin: 28,
            horizontalSafetyMargin: 12
        )
        XCTAssertEqual(nearWidthOrigin.x, 110)

        let widerOrigin = HUDService.hudOrigin(
            visibleFrame: visibleFrame,
            windowSize: CGSize(width: 360, height: 60),
            bottomMargin: 28,
            horizontalSafetyMargin: 12
        )
        XCTAssertEqual(widerOrigin.x, 100)
    }

    func testBottomMarginAppliedCorrectly() {
        let origin = HUDService.hudOrigin(
            visibleFrame: CGRect(x: 0, y: 40, width: 1280, height: 760),
            windowSize: CGSize(width: 260, height: 68),
            bottomMargin: 28,
            horizontalSafetyMargin: 12
        )

        XCTAssertEqual(origin.y, 68)
    }
}
