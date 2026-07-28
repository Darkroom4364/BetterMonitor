//  Copyright © BetterMonitor. @JoniVR, @theOneyouseek, @waydabber and others

@testable import BetterMonitor
import XCTest

class DisplayValueConversionTests: XCTestCase {
  var display: OtherDisplay!

  override func setUp() {
    super.setUp()
    display = OtherDisplay(1, name: "Test", vendorNumber: 0, modelNumber: 0, serialNumber: 0, isVirtual: true, isDummy: true)
    setDefaultPrefs(for: .brightness)
    setDefaultPrefs(for: .audioSpeakerVolume)
    setDefaultPrefs(for: .contrast)
    display.removePref(key: .combinedBrightnessSwitchingPoint)
    addTeardownBlock { [self] in
      clearPrefs(for: .brightness)
      clearPrefs(for: .audioSpeakerVolume)
      clearPrefs(for: .contrast)
      display.removePref(key: .combinedBrightnessSwitchingPoint)
      display = nil
    }
  }

  // Uses the production preference-key helpers (Display.savePref/removePref)
  // instead of hand-built key strings, so tests cannot drift from the real key format.
  private func setDefaultPrefs(for command: Command) {
    display.savePref(false, key: .invertDDC, for: command)
    display.savePref(5, key: .curveDDC, for: command) // 5 = default, maps to 1.0
    display.savePref(0, key: .minDDCOverride, for: command)
    display.savePref(100, key: .maxDDC, for: command)
  }

  private func clearPrefs(for command: Command) {
    for key in [PrefKey.invertDDC, .curveDDC, .minDDCOverride, .maxDDC] {
      display.removePref(key: key, for: command)
    }
  }

  // MARK: - getCurveMultiplier

  func testCurveMultiplierDefault() {
    XCTAssertEqual(display.getCurveMultiplier(5), 1.0)
    XCTAssertEqual(display.getCurveMultiplier(0), 1.0)
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
    display.savePref(true, key: .invertDDC, for: .brightness)

    XCTAssertEqual(display.convValueToDDC(for: .brightness, from: 0), 100)
    XCTAssertEqual(display.convValueToDDC(for: .brightness, from: 1.0), 0)
    XCTAssertEqual(display.convValueToDDC(for: .brightness, from: 0.5), 50)
  }

  // MARK: - convValueToDDC with min/max overrides

  func testConvValueToDDCWithMinOverride() {
    display.savePref(20, key: .minDDCOverride, for: .brightness)

    // value=0 should map to min=20
    XCTAssertEqual(display.convValueToDDC(for: .brightness, from: 0), 20)
    // value=1 should map to max=100
    XCTAssertEqual(display.convValueToDDC(for: .brightness, from: 1.0), 100)
  }

  func testConvValueToDDCWithMaxOverride() {
    display.savePref(80, key: .maxDDC, for: .brightness)

    XCTAssertEqual(display.convValueToDDC(for: .brightness, from: 0), 0)
    XCTAssertEqual(display.convValueToDDC(for: .brightness, from: 1.0), 80)
  }

  func testConvValueToDDCWithMinAndMaxOverride() {
    display.savePref(10, key: .minDDCOverride, for: .brightness)
    display.savePref(90, key: .maxDDC, for: .brightness)

    XCTAssertEqual(display.convValueToDDC(for: .brightness, from: 0), 10)
    XCTAssertEqual(display.convValueToDDC(for: .brightness, from: 1.0), 90)
    XCTAssertEqual(display.convValueToDDC(for: .brightness, from: 0.5), 50)
  }

  // MARK: - convValueToDDC with curves

  func testConvValueToDDCWithCurve() {
    display.savePref(7, key: .curveDDC, for: .brightness) // 1.5 multiplier

    // pow(0.5, 1.5) ≈ 0.354, so DDC ≈ 35
    let result = display.convValueToDDC(for: .brightness, from: 0.5)
    XCTAssertEqualUInt16(result, UInt16(pow(0.5, 1.5) * 100), accuracy: 1)

    // Endpoints should be unaffected
    XCTAssertEqual(display.convValueToDDC(for: .brightness, from: 0), 0)
    XCTAssertEqual(display.convValueToDDC(for: .brightness, from: 1.0), 100)
  }

  // MARK: - Audio special case

  func testConvValueToDDCAudioNeverZeroForPositiveInput() {
    // For audioSpeakerVolume, value > 0 should produce DDC >= 1
    display.savePref(9, key: .curveDDC, for: .audioSpeakerVolume) // steep curve (1.88)
    display.savePref(0, key: .minDDCOverride, for: .audioSpeakerVolume)
    display.savePref(100, key: .maxDDC, for: .audioSpeakerVolume)

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
    display.savePref(true, key: .invertDDC, for: .brightness)

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
    display.savePref(3, key: .curveDDC, for: .brightness) // 0.8 multiplier

    let testValues: [Float] = [0, 0.25, 0.5, 0.75, 1.0]
    for value in testValues {
      let ddc = display.convValueToDDC(for: .brightness, from: value)
      let result = display.convDDCToValue(for: .brightness, from: ddc)
      XCTAssertEqual(result, value, accuracy: 0.02, "Roundtrip (curve) failed for value \(value)")
    }
  }

  // MARK: - combinedBrightnessSwitchingValue

  func testCombinedBrightnessSwitchingDefault() {
    // Pref cleared in setUp; default = 0, formula: (0 + 8) / 16 = 0.5
    let result = display.combinedBrightnessSwitchingValue()
    XCTAssertEqual(result, 0.5, accuracy: 0.001)
  }

  func testCombinedBrightnessSwitchingCustom() {
    display.savePref(4, key: .combinedBrightnessSwitchingPoint)
    let result = display.combinedBrightnessSwitchingValue()
    // (4 + 8) / 16 = 0.75
    XCTAssertEqual(result, 0.75, accuracy: 0.001)
  }
}

/// UInt16 accuracy comparison. Named distinctly so it does not shadow XCTest's `XCTAssertEqual`.
private func XCTAssertEqualUInt16(_ lhs: UInt16, _ rhs: UInt16, accuracy: UInt16, file: StaticString = #file, line: UInt = #line) {
  XCTAssertTrue(abs(Int(lhs) - Int(rhs)) <= Int(accuracy), "Expected \(lhs) to be within \(accuracy) of \(rhs)", file: file, line: line)
}
