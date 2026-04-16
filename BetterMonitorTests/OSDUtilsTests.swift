//  Copyright © BetterMonitor. @JoniVR, @theOneyouseek, @waydabber and others

@testable import BetterMonitor
import XCTest

class OSDUtilsTests: XCTestCase {

  // MARK: - chiclet(fromValue:maxValue:half:)

  func testChicletAtZero() {
    XCTAssertEqual(OSDUtils.chiclet(fromValue: 0, maxValue: 1), 0)
  }

  func testChicletAtMax() {
    XCTAssertEqual(OSDUtils.chiclet(fromValue: 1, maxValue: 1), 16)
  }

  func testChicletAtHalf() {
    XCTAssertEqual(OSDUtils.chiclet(fromValue: 0.5, maxValue: 1), 8)
  }

  func testChicletWithCustomMax() {
    XCTAssertEqual(OSDUtils.chiclet(fromValue: 50, maxValue: 100), 8)
  }

  func testChicletHalfMode() {
    // half mode doubles the chiclet count (32 steps instead of 16)
    XCTAssertEqual(OSDUtils.chiclet(fromValue: 1, maxValue: 1, half: true), 32)
    XCTAssertEqual(OSDUtils.chiclet(fromValue: 0.5, maxValue: 1, half: true), 16)
  }

  func testChicletQuarterValue() {
    XCTAssertEqual(OSDUtils.chiclet(fromValue: 0.25, maxValue: 1), 4)
  }

  // MARK: - value(fromChiclet:maxValue:half:)

  func testValueAtZeroChiclet() {
    XCTAssertEqual(OSDUtils.value(fromChiclet: 0, maxValue: 1), 0)
  }

  func testValueAtMaxChiclet() {
    XCTAssertEqual(OSDUtils.value(fromChiclet: 16, maxValue: 1), 1)
  }

  func testValueAtHalfChiclet() {
    XCTAssertEqual(OSDUtils.value(fromChiclet: 8, maxValue: 1), 0.5)
  }

  func testValueHalfMode() {
    XCTAssertEqual(OSDUtils.value(fromChiclet: 32, maxValue: 1, half: true), 1)
    XCTAssertEqual(OSDUtils.value(fromChiclet: 16, maxValue: 1, half: true), 0.5)
  }

  func testValueWithCustomMax() {
    XCTAssertEqual(OSDUtils.value(fromChiclet: 8, maxValue: 100), 50)
  }

  // MARK: - Roundtrip: value → chiclet → value

  func testRoundtripValueToChicletAndBack() {
    let testValues: [Float] = [0, 0.0625, 0.125, 0.25, 0.5, 0.75, 1.0]
    for value in testValues {
      let chiclet = OSDUtils.chiclet(fromValue: value, maxValue: 1)
      let result = OSDUtils.value(fromChiclet: chiclet, maxValue: 1)
      XCTAssertEqual(result, value, accuracy: 0.0001, "Roundtrip failed for value \(value)")
    }
  }

  func testRoundtripHalfMode() {
    let testValues: [Float] = [0, 0.03125, 0.25, 0.5, 1.0]
    for value in testValues {
      let chiclet = OSDUtils.chiclet(fromValue: value, maxValue: 1, half: true)
      let result = OSDUtils.value(fromChiclet: chiclet, maxValue: 1, half: true)
      XCTAssertEqual(result, value, accuracy: 0.0001, "Roundtrip (half) failed for value \(value)")
    }
  }

  // MARK: - getDistance(fromNearestChiclet:)

  func testDistanceAtExactChiclet() {
    XCTAssertEqual(OSDUtils.getDistance(fromNearestChiclet: 8.0), 0)
    XCTAssertEqual(OSDUtils.getDistance(fromNearestChiclet: 0.0), 0)
    XCTAssertEqual(OSDUtils.getDistance(fromNearestChiclet: 16.0), 0)
  }

  func testDistanceAtMidChiclet() {
    XCTAssertEqual(OSDUtils.getDistance(fromNearestChiclet: 8.5), 0.5)
  }

  func testDistanceNearChiclet() {
    XCTAssertEqual(OSDUtils.getDistance(fromNearestChiclet: 8.1), 0.1, accuracy: 0.0001)
    XCTAssertEqual(OSDUtils.getDistance(fromNearestChiclet: 8.9), 0.9, accuracy: 0.0001)
  }

  func testDistanceNegativeChiclet() {
    // getDistance uses .towardZero rounding, so negative values round toward 0
    XCTAssertEqual(OSDUtils.getDistance(fromNearestChiclet: -0.5), 0.5)
  }

  // MARK: - chicletCount

  func testChicletCountIs16() {
    XCTAssertEqual(OSDUtils.chicletCount, 16)
  }

  // MARK: - OSDImage mapping

  func testBrightnessCommandImage() {
    XCTAssertEqual(OSDUtils.getOSDImageByCommand(command: .brightness), .brightness)
  }

  func testAudioSpeakerVolumeImageNonZero() {
    XCTAssertEqual(OSDUtils.getOSDImageByCommand(command: .audioSpeakerVolume, value: 0.5), .audioSpeaker)
  }

  func testAudioSpeakerVolumeImageZero() {
    XCTAssertEqual(OSDUtils.getOSDImageByCommand(command: .audioSpeakerVolume, value: 0), .audioSpeakerMuted)
  }

  func testAudioMuteImage() {
    XCTAssertEqual(OSDUtils.getOSDImageByCommand(command: .audioMuteScreenBlank), .audioSpeakerMuted)
  }

  func testContrastImage() {
    XCTAssertEqual(OSDUtils.getOSDImageByCommand(command: .contrast), .contrast)
  }

  func testUnknownCommandDefaultsToBrightness() {
    XCTAssertEqual(OSDUtils.getOSDImageByCommand(command: .powerMode), .brightness)
  }
}
