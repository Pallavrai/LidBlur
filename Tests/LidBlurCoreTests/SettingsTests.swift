import XCTest
@testable import LidBlurCore

final class SettingsTests: XCTestCase {
    private let suite = "LidBlurTests.\(UUID().uuidString)"
    private var settings: Settings!

    override func setUp() { settings = Settings(defaults: UserDefaults(suiteName: suite)!) }
    override func tearDown() { UserDefaults().removePersistentDomain(forName: suite) }

    func testDefaults() {
        XCTAssertTrue(settings.enabled)
        XCTAssertEqual(settings.fullAngle, 20)
    }

    func testCalibrationMedianKeepsLastFiveAndRejectsOutliers() {
        for a in [2.0, 70, 18, 19, 20, 21, 22, 23] { settings.recordDarkAngle(a) }
        XCTAssertEqual(settings.calibratedDarkAngles, [19, 20, 21, 22, 23])
        XCTAssertEqual(settings.fullAngle, 26)   // median 21 + 5
    }

    func testFullAngleFloor() {
        settings.recordDarkAngle(8)
        XCTAssertEqual(settings.fullAngle, 20)
    }

    func testStartAngleDefaultsAndClamps() {
        XCTAssertEqual(settings.startAngle, EngineConstants.defaultStartAngle)
        settings.startAngle = 200
        XCTAssertEqual(settings.startAngle, 110)
        settings.startAngle = 75
        XCTAssertEqual(settings.startAngle, 75)
    }
}
