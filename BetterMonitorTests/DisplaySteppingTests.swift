//  Copyright © BetterMonitor. @JoniVR, @theOneyouseek, @waydabber and others

@testable import BetterMonitor
import XCTest

class DisplaySteppingTests: XCTestCase {
  var display: OtherDisplay!

  override func setUp() {
    super.setUp()
    display = OtherDisplay(1, name: "Test", vendorNumber: 0, modelNumber: 0, serialNumber: 0, isVirtual: true, isDummy: true)
  }

  override func tearDown() {
    display = nil
    super.tearDown()
  }

  // MARK: - calcNewValue: small increments

  func testSmallIncrementUp() {
    let result = display.calcNewValue(currentValue: 0.5, isUp: true, isSmallIncrement: true)
    XCTAssertEqual(result, 0.51, accuracy: 0.001)
  }

  func testSmallIncrementDown() {
    let result = display.calcNewValue(currentValue: 0.5, isUp: false, isSmallIncrement: true)
    XCTAssertEqual(result, 0.49, accuracy: 0.001)
  }

  func testSmallIncrementClampsAtZero() {
    let result = display.calcNewValue(currentValue: 0.005, isUp: false, isSmallIncrement: true)
    XCTAssertEqual(result, 0, accuracy: 0.001)
  }

  func testSmallIncrementClampsAtOne() {
    let result = display.calcNewValue(currentValue: 0.995, isUp: true, isSmallIncrement: true)
    XCTAssertEqual(result, 1.0, accuracy: 0.001)
  }

  // MARK: - calcNewValue: chiclet stepping

  func testChicletStepUpFromZero() {
    let result = display.calcNewValue(currentValue: 0, isUp: true, isSmallIncrement: false)
    // One chiclet step = 1/16 = 0.0625
    XCTAssertEqual(result, 1.0 / 16.0, accuracy: 0.001)
  }

  func testChicletStepDownFromMax() {
    let result = display.calcNewValue(currentValue: 1.0, isUp: false, isSmallIncrement: false)
    XCTAssertEqual(result, 15.0 / 16.0, accuracy: 0.001)
  }

  func testChicletStepFromExactChiclet() {
    // At exactly 0.5 (chiclet 8), stepping up should go to chiclet 9
    let result = display.calcNewValue(currentValue: 0.5, isUp: true, isSmallIncrement: false)
    XCTAssertEqual(result, 9.0 / 16.0, accuracy: 0.001)
  }

  func testChicletStepDownFromExactChiclet() {
    let result = display.calcNewValue(currentValue: 0.5, isUp: false, isSmallIncrement: false)
    XCTAssertEqual(result, 7.0 / 16.0, accuracy: 0.001)
  }

  func testChicletStepClampsAtZero() {
    let result = display.calcNewValue(currentValue: 0, isUp: false, isSmallIncrement: false)
    XCTAssertEqual(result, 0)
  }

  func testChicletStepClampsAtOne() {
    let result = display.calcNewValue(currentValue: 1.0, isUp: true, isSmallIncrement: false)
    XCTAssertEqual(result, 1.0)
  }

  // MARK: - calcNewValue: half mode

  func testHalfModeStepSize() {
    // In half mode, step size = 1/32
    let result = display.calcNewValue(currentValue: 0, isUp: true, isSmallIncrement: false, half: true)
    XCTAssertEqual(result, 1.0 / 32.0, accuracy: 0.001)
  }

  // MARK: - calcNewValue: near-chiclet snapping

  func testStepUpFromNearChiclet() {
    // 0.49 → chiclet 7.84, distance 0.84 > 0.75 threshold → skips to chiclet 9
    let result = display.calcNewValue(currentValue: 0.49, isUp: true, isSmallIncrement: false)
    XCTAssertEqual(result, 9.0 / 16.0, accuracy: 0.001)
  }

  func testStepDownFromNearChiclet() {
    // 0.51 → chiclet 8.16, distance 0.16 < 0.25 threshold → skips to chiclet 7
    let result = display.calcNewValue(currentValue: 0.51, isUp: false, isSmallIncrement: false)
    XCTAssertEqual(result, 7.0 / 16.0, accuracy: 0.001)
  }

  // MARK: - swBrightnessTransform

  func testSwBrightnessTransformForward() {
    // Default: lowThreshold = 0.15
    // transform(0) = 0 * (1 - 0.15) + 0.15 = 0.15
    let result = display.swBrightnessTransform(value: 0)
    XCTAssertEqual(result, 0.15, accuracy: 0.001)
  }

  func testSwBrightnessTransformForwardMax() {
    // transform(1) = 1 * (1 - 0.15) + 0.15 = 1.0
    let result = display.swBrightnessTransform(value: 1.0)
    XCTAssertEqual(result, 1.0, accuracy: 0.001)
  }

  func testSwBrightnessTransformReverse() {
    // reverse(0.15) = (0.15 - 0.15) / (1 - 0.15) = 0
    let result = display.swBrightnessTransform(value: 0.15, reverse: true)
    XCTAssertEqual(result, 0, accuracy: 0.001)
  }

  func testSwBrightnessTransformReverseMax() {
    let result = display.swBrightnessTransform(value: 1.0, reverse: true)
    XCTAssertEqual(result, 1.0, accuracy: 0.001)
  }

  func testSwBrightnessTransformRoundtrip() {
    let values: [Float] = [0, 0.25, 0.5, 0.75, 1.0]
    for value in values {
      let transformed = display.swBrightnessTransform(value: value)
      let reversed = display.swBrightnessTransform(value: transformed, reverse: true)
      XCTAssertEqual(reversed, value, accuracy: 0.001, "Roundtrip failed for \(value)")
    }
  }

  func testSwBrightnessTransformWithZeroAllowed() {
    prefs.set(true, forKey: PrefKey.allowZeroSwBrightness.rawValue)
    addTeardownBlock { prefs.removeObject(forKey: PrefKey.allowZeroSwBrightness.rawValue) }
    // lowThreshold = 0.0
    // transform(0) = 0 * 1 + 0 = 0
    let result = display.swBrightnessTransform(value: 0)
    XCTAssertEqual(result, 0, accuracy: 0.001)
  }
}
