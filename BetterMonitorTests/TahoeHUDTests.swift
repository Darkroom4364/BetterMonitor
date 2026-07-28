//  Copyright © BetterMonitor. @JoniVR, @theOneyouseek, @waydabber and others

@testable import BetterMonitor
import XCTest

class TahoeHUDTests: XCTestCase {

  // MARK: - OSDImage → Kind mapping

  func testBrightnessImageMapsToBrightness() {
    XCTAssertEqual(TahoeHUD.kind(for: .brightness), .brightness)
  }

  func testAudioSpeakerImageMapsToVolume() {
    XCTAssertEqual(TahoeHUD.kind(for: .audioSpeaker), .volume)
  }

  func testAudioSpeakerMutedImageMapsToMutedVolume() {
    XCTAssertEqual(TahoeHUD.kind(for: .audioSpeakerMuted), .mutedVolume)
  }

  func testContrastImageMapsToContrast() {
    XCTAssertEqual(TahoeHUD.kind(for: .contrast), .contrast)
  }

  // MARK: - Command → Kind mapping (via OSDUtils.getOSDImageByCommand)

  func testBrightnessCommandMapsToBrightness() {
    XCTAssertEqual(TahoeHUD.kind(for: OSDUtils.getOSDImageByCommand(command: .brightness)), .brightness)
  }

  func testVolumeCommandNonZeroMapsToVolume() {
    XCTAssertEqual(TahoeHUD.kind(for: OSDUtils.getOSDImageByCommand(command: .audioSpeakerVolume, value: 0.5)), .volume)
  }

  func testVolumeCommandZeroMapsToMutedVolume() {
    XCTAssertEqual(TahoeHUD.kind(for: OSDUtils.getOSDImageByCommand(command: .audioSpeakerVolume, value: 0)), .mutedVolume)
  }

  func testMuteCommandMapsToMutedVolume() {
    XCTAssertEqual(TahoeHUD.kind(for: OSDUtils.getOSDImageByCommand(command: .audioMuteScreenBlank)), .mutedVolume)
  }

  func testContrastCommandMapsToContrast() {
    XCTAssertEqual(TahoeHUD.kind(for: OSDUtils.getOSDImageByCommand(command: .contrast)), .contrast)
  }

  func testUnknownCommandMapsToBrightness() {
    XCTAssertEqual(TahoeHUD.kind(for: OSDUtils.getOSDImageByCommand(command: .powerMode)), .brightness)
  }

  // MARK: - Kind symbol names

  func testSymbolNames() {
    XCTAssertEqual(TahoeHUD.Kind.brightness.symbolName, "sun.max.fill")
    XCTAssertEqual(TahoeHUD.Kind.volume.symbolName, "speaker.wave.2.fill")
    XCTAssertEqual(TahoeHUD.Kind.mutedVolume.symbolName, "speaker.slash.fill")
    XCTAssertEqual(TahoeHUD.Kind.contrast.symbolName, "circle.lefthalf.filled")
  }

  // MARK: - normalizedProgress clamping

  func testNormalizedProgressAtBounds() {
    XCTAssertEqual(TahoeHUD.normalizedProgress(value: 0, maxValue: 1), 0)
    XCTAssertEqual(TahoeHUD.normalizedProgress(value: 1, maxValue: 1), 1)
  }

  func testNormalizedProgressHalf() {
    XCTAssertEqual(TahoeHUD.normalizedProgress(value: 0.5, maxValue: 1), 0.5)
    XCTAssertEqual(TahoeHUD.normalizedProgress(value: 50, maxValue: 100), 0.5)
  }

  func testNormalizedProgressClampsAboveOne() {
    XCTAssertEqual(TahoeHUD.normalizedProgress(value: 2, maxValue: 1), 1)
  }

  func testNormalizedProgressClampsBelowZero() {
    XCTAssertEqual(TahoeHUD.normalizedProgress(value: -0.5, maxValue: 1), 0)
  }

  func testNormalizedProgressZeroMaxIsSafe() {
    XCTAssertEqual(TahoeHUD.normalizedProgress(value: 1, maxValue: 0), 0)
    XCTAssertEqual(TahoeHUD.normalizedProgress(value: 0, maxValue: 0), 0)
  }

  func testNormalizedProgressNegativeMaxIsSafe() {
    XCTAssertEqual(TahoeHUD.normalizedProgress(value: 1, maxValue: -1), 0)
  }

  func testNormalizedProgressNonFiniteIsSafe() {
    XCTAssertEqual(TahoeHUD.normalizedProgress(value: .nan, maxValue: 1), 0)
    XCTAssertEqual(TahoeHUD.normalizedProgress(value: 1, maxValue: .nan), 0)
    XCTAssertEqual(TahoeHUD.normalizedProgress(value: .infinity, maxValue: 1), 0)
    XCTAssertEqual(TahoeHUD.normalizedProgress(value: 1, maxValue: .infinity), 0)
  }

  // MARK: - Tahoe routing decision

  func testRoutingDecisionMatchesOSVersion() {
    let isTahoeOrLater = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26
    XCTAssertEqual(TahoeHUD.shouldUseCustomHUD, isTahoeOrLater)
  }
}
