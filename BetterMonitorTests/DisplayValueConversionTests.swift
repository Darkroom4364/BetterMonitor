//  Copyright © BetterMonitor. @JoniVR, @theOneyouseek, @waydabber and others

@testable import BetterMonitor
import XCTest

class DisplayValueConversionTests: XCTestCase {
  var display: OtherDisplay!
  let prefsId = "(Test00@0)"

  override func setUp() {
    super.setUp()
    display = OtherDisplay(1, name: "Test", vendorNumber: 0, modelNumber: 0, serialNumber: 0, isVirtual: true, isDummy: true)
    setDefaultPrefs(for: .brightness)
    setDefaultPrefs(for: .audioSpeakerVolume)
    setDefaultPrefs(for: .contrast)
    addTeardownBlock { [self] in
      clearPrefs(for: .brightness)
      clearPrefs(for: .audioSpeakerVolume)
      clearPrefs(for: .contrast)
      display = nil
    }
  }

  private func setDefaultPrefs(for command: Command) {
    let suffix = String(command.rawValue) + prefsId
    prefs.set(false, forKey: "invertDDC" + suffix)
    prefs.set(5, forKey: "curveDDC" + suffix) // 5 = default, maps to 1.0
    prefs.set(0, forKey: "minDDCOverride" + suffix)
    prefs.set(100, forKey: "maxDDC" + suffix)
  }

  private func clearPrefs(for command: Command) {
    let suffix = String(command.rawValue) + prefsId
    for key in ["invertDDC", "curveDDC", "minDDCOverride", "maxDDC"] {
      prefs.removeObject(forKey: key + suffix)
    }
  }

  // MARK: - getCurveMultiplier

  func testCurveMultiplierDefault() {
    XCTAssertEqual(display.getCurveMultiplier(5), 1.0)
    XCTAssertEqual(display.getCurveMultiplier(99), 1.0)
  }

  func testCurveMultiplierAllCases() {
    XCTAssertEqual(display.getCurveMultiplier(1), 0.6)
    XCTAssertEqual(display.getCurveMultiplier(2), 0.7)
    XCTAssertEqual(display.getCurveMultiplier(3), 0.8)
    XCTAssertEqual(display.getCurveMultiplier(4), 0.9)
    XCTAssertEqual(display.getCurveMultiplier(6), 1.3)
    XCTAssertEqual(display.getCurveMultiplier(7), 1.5)
    XCTAssertEqual(display.getCurveMultiplier(8), 1.7)
    XCTAssertEqual(display.getCurveMultiplier(9), 1.88)
  }

  // MARK: - convValueToDDC (linear, default curve)

  func testConvValueToDDCZero() {
    XCTAssertEqual(display.convValueToDDC(for: .brightness, from: 0), 0)
  }

  func testConvValueToDDCMax() {
    XCTAssertEqual(display.convValueToDDC(for: .brightness, from: 1.0), 100)
  }

  func testConvValueToDDCHalf() {
    XCTAssertEqual(display.convValueToDDC(for: .brightness, from: 0.5), 50)
  }

  func testConvValueToDDCClampsAboveOne() {
    XCTAssertEqual(display.convValueToDDC(for: .brightness, from: 1.5), 100)
  }

  func testConvValueToDDCClampsBelowZero() {
    XCTAssertEqual(display.convValueToDDC(for: .brightness, from: -0.5), 0)
  }

  // MARK: - convValueToDDC with inversion

  func testConvValueToDDCInverted() {
    let suffix = String(Command.brightness.rawValue) + prefsId
    prefs.set(true, forKey: "invertDDC" + suffix)

    XCTAssertEqual(display.convValueToDDC(for: .brightness, from: 0), 100)
    XCTAssertEqual(display.convValueToDDC(for: .brightness, from: 1.0), 0)
    XCTAssertEqual(display.convValueToDDC(for: .brightness, from: 0.5), 50)
  }

  // MARK: - convValueToDDC with min/max overrides

  func testConvValueToDDCWithMinOverride() {
    let suffix = String(Command.brightness.rawValue) + prefsId
    prefs.set(20, forKey: "minDDCOverride" + suffix)

    // value=0 should map to min=20
    XCTAssertEqual(display.convValueToDDC(for: .brightness, from: 0), 20)
    // value=1 should map to max=100
    XCTAssertEqual(display.convValueToDDC(for: .brightness, from: 1.0), 100)
  }

  func testConvValueToDDCWithMaxOverride() {
    let suffix = String(Command.brightness.rawValue) + prefsId
    prefs.set(80, forKey: "maxDDC" + suffix)

    XCTAssertEqual(display.convValueToDDC(for: .brightness, from: 0), 0)
    XCTAssertEqual(display.convValueToDDC(for: .brightness, from: 1.0), 80)
  }

  func testConvValueToDDCWithMinAndMaxOverride() {
    let suffix = String(Command.brightness.rawValue) + prefsId
    prefs.set(10, forKey: "minDDCOverride" + suffix)
    prefs.set(90, forKey: "maxDDC" + suffix)

    XCTAssertEqual(display.convValueToDDC(for: .brightness, from: 0), 10)
    XCTAssertEqual(display.convValueToDDC(for: .brightness, from: 1.0), 90)
    XCTAssertEqual(display.convValueToDDC(for: .brightness, from: 0.5), 50)
  }

  // MARK: - convValueToDDC with curves

  func testConvValueToDDCWithCurve() {
    let suffix = String(Command.brightness.rawValue) + prefsId
    prefs.set(7, forKey: "curveDDC" + suffix) // 1.5 multiplier

    // pow(0.5, 1.5) ≈ 0.354, so DDC ≈ 35
    let result = display.convValueToDDC(for: .brightness, from: 0.5)
    XCTAssertEqual(result, UInt16(pow(0.5, 1.5) * 100), accuracy: 1)

    // Endpoints should be unaffected
    XCTAssertEqual(display.convValueToDDC(for: .brightness, from: 0), 0)
    XCTAssertEqual(display.convValueToDDC(for: .brightness, from: 1.0), 100)
  }

  // MARK: - Audio special case

  func testConvValueToDDCAudioNeverZeroForPositiveInput() {
    // For audioSpeakerVolume, value > 0 should produce DDC >= 1
    let suffix = String(Command.audioSpeakerVolume.rawValue) + prefsId
    prefs.set(9, forKey: "curveDDC" + suffix) // steep curve (1.88)
    prefs.set(0, forKey: "minDDCOverride" + suffix)
    prefs.set(100, forKey: "maxDDC" + suffix)

    // Even a tiny value should map to at least 1
    let result = display.convValueToDDC(for: .audioSpeakerVolume, from: 0.01)
    XCTAssertGreaterThanOrEqual(result, 1)
  }

  func testConvValueToDDCAudioZeroForZeroInput() {
    XCTAssertEqual(display.convValueToDDC(for: .audioSpeakerVolume, from: 0), 0)
  }

  // MARK: - convDDCToValue

  func testConvDDCToValueZero() {
    let result = display.convDDCToValue(for: .brightness, from: 0)
    XCTAssertEqual(result, 0, accuracy: 0.001)
  }

  func testConvDDCToValueMax() {
    let result = display.convDDCToValue(for: .brightness, from: 100)
    XCTAssertEqual(result, 1.0, accuracy: 0.001)
  }

  func testConvDDCToValueHalf() {
    let result = display.convDDCToValue(for: .brightness, from: 50)
    XCTAssertEqual(result, 0.5, accuracy: 0.001)
  }

  func testConvDDCToValueClampsAboveMax() {
    let result = display.convDDCToValue(for: .brightness, from: 150)
    XCTAssertEqual(result, 1.0, accuracy: 0.001)
  }

  func testConvDDCToValueInverted() {
    let suffix = String(Command.brightness.rawValue) + prefsId
    prefs.set(true, forKey: "invertDDC" + suffix)

    XCTAssertEqual(display.convDDCToValue(for: .brightness, from: 0), 1.0, accuracy: 0.001)
    XCTAssertEqual(display.convDDCToValue(for: .brightness, from: 100), 0, accuracy: 0.001)
  }

  // MARK: - Roundtrip: value → DDC → value

  func testRoundtripLinear() {
    let testValues: [Float] = [0, 0.1, 0.25, 0.5, 0.75, 1.0]
    for value in testValues {
      let ddc = display.convValueToDDC(for: .brightness, from: value)
      let result = display.convDDCToValue(for: .brightness, from: ddc)
      XCTAssertEqual(result, value, accuracy: 0.02, "Roundtrip failed for value \(value)")
    }
  }

  func testRoundtripWithCurve() {
    let suffix = String(Command.brightness.rawValue) + prefsId
    prefs.set(3, forKey: "curveDDC" + suffix) // 0.8 multiplier

    let testValues: [Float] = [0, 0.25, 0.5, 0.75, 1.0]
    for value in testValues {
      let ddc = display.convValueToDDC(for: .brightness, from: value)
      let result = display.convDDCToValue(for: .brightness, from: ddc)
      XCTAssertEqual(result, value, accuracy: 0.02, "Roundtrip (curve) failed for value \(value)")
    }
  }

  // MARK: - combinedBrightnessSwitchingValue

  func testCombinedBrightnessSwitchingDefault() {
    // Default pref = 0, formula: (0 + 8) / 16 = 0.5
    let result = display.combinedBrightnessSwitchingValue()
    XCTAssertEqual(result, 0.5, accuracy: 0.001)
  }

  func testCombinedBrightnessSwitchingCustom() {
    let suffix = prefsId
    prefs.set(4, forKey: "combinedBrightnessSwitchingPoint" + suffix)
    let result = display.combinedBrightnessSwitchingValue()
    // (4 + 8) / 16 = 0.75
    XCTAssertEqual(result, 0.75, accuracy: 0.001)
  }
}

private func XCTAssertEqual(_ lhs: UInt16, _ rhs: UInt16, accuracy: UInt16, file: StaticString = #file, line: UInt = #line) {
  XCTAssertTrue(abs(Int(lhs) - Int(rhs)) <= Int(accuracy), "Expected \(lhs) to be within \(accuracy) of \(rhs)", file: file, line: line)
}
