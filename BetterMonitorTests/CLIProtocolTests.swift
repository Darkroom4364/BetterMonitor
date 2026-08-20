//  Copyright © BetterMonitor. @JoniVR, @theOneyouseek, @waydabber and others

import XCTest

class CLIProtocolTests: XCTestCase {

  // MARK: - CLIAction

  func testCLIActionRawValues() {
    let expected: [(CLIAction, String)] = [
      (.list, "list"),
      (.get, "get"),
      (.set, "set"),
      (.modeFavoriteList, "mode-favorite-list"),
      (.modeFavoriteSave, "mode-favorite-save"),
      (.modeFavoriteApply, "mode-favorite-apply"),
      (.modeFavoriteDelete, "mode-favorite-delete"),
      (.modeList, "mode-list"),
    ]

    for (action, rawValue) in expected {
      XCTAssertEqual(action.rawValue, rawValue)
    }
  }

  func testCLIActionRoundtrip() {
    for action: CLIAction in [.list, .get, .set, .modeFavoriteList, .modeFavoriteSave, .modeFavoriteApply, .modeFavoriteDelete, .modeList] {
      XCTAssertEqual(CLIAction(rawValue: action.rawValue), action)
    }
  }

  func testCLIActionInvalidRawValue() {
    XCTAssertNil(CLIAction(rawValue: "delete"))
    XCTAssertNil(CLIAction(rawValue: ""))
    XCTAssertNil(CLIAction(rawValue: "LIST"))
  }

  // MARK: - CLIProperty

  func testCLIPropertyRawValues() {
    XCTAssertEqual(CLIProperty.brightness.rawValue, "brightness")
    XCTAssertEqual(CLIProperty.volume.rawValue, "volume")
    XCTAssertEqual(CLIProperty.contrast.rawValue, "contrast")
    XCTAssertEqual(CLIProperty.input.rawValue, "input")
  }

  func testCLIPropertyRoundtrip() {
    for prop: CLIProperty in [.brightness, .volume, .contrast, .input] {
      XCTAssertEqual(CLIProperty(rawValue: prop.rawValue), prop)
    }
  }

  func testCLIPropertyInvalidRawValue() {
    XCTAssertNil(CLIProperty(rawValue: "color"))
    XCTAssertNil(CLIProperty(rawValue: ""))
    XCTAssertNil(CLIProperty(rawValue: "BRIGHTNESS"))
  }

  // MARK: - DDC input sources

  func testDDCInputSourceRecognizesStandardAliases() {
    XCTAssertEqual(DDCInputSource.value(for: "hdmi1"), 0x11)
    XCTAssertEqual(DDCInputSource.value(for: "DP-2"), 0x10)
    XCTAssertEqual(DDCInputSource.value(for: "display_port_1"), 0x0F)
  }

  func testDDCInputSourceRecognizesLegacyAnalogAliases() {
    XCTAssertEqual(DDCInputSource.value(for: "composite-2"), 0x06)
    XCTAssertEqual(DDCInputSource.value(for: "s_video_1"), 0x07)
    XCTAssertEqual(DDCInputSource.value(for: "tuner3"), 0x0B)
    XCTAssertEqual(DDCInputSource.value(for: "component-2"), 0x0D)
  }

  func testDDCInputSourceAcceptsRawValues() {
    XCTAssertEqual(DDCInputSource.value(for: "0x12"), 0x12)
    XCTAssertEqual(DDCInputSource.value(for: "15"), 0x0F)
  }

  func testDDCInputSourceRejectsInvalidValues() {
    XCTAssertNil(DDCInputSource.value(for: "0"))
    XCTAssertNil(DDCInputSource.value(for: "0x100"))
    XCTAssertNil(DDCInputSource.value(for: "hdmi7"))
  }

  func testDDCInputSourceLabelsKnownAndUnknownValues() {
    XCTAssertEqual(DDCInputSource.label(for: 0x0C), "Component-1")
    XCTAssertEqual(DDCInputSource.label(for: 0x11), "HDMI-1")
    XCTAssertEqual(DDCInputSource.label(for: 0x7F), "Input 0x7F")
    XCTAssertEqual(DDCInputSource.label(for: 0), "No active input")
  }

  // MARK: - CLIKey constants

  func testCLIKeyConstants() {
    XCTAssertEqual(CLIKey.action, "action")
    XCTAssertEqual(CLIKey.property, "property")
    XCTAssertEqual(CLIKey.value, "value")
    XCTAssertEqual(CLIKey.displayId, "displayId")
    XCTAssertEqual(CLIKey.displayName, "displayName")
    XCTAssertEqual(CLIKey.replyId, "replyId")
    XCTAssertEqual(CLIKey.json, "json")
  }

  // MARK: - CLINotification constants

  func testCLINotificationRequest() {
    XCTAssertEqual(CLINotification.request, "com.github.BetterMonitor.cli.request")
  }

  func testCLINotificationReplyPrefix() {
    XCTAssertEqual(CLINotification.replyPrefix, "com.github.BetterMonitor.cli.reply.")
    XCTAssertTrue(CLINotification.replyPrefix.hasSuffix("."))
  }

  func testReplyNotificationNameWithUUID() {
    let uuid = UUID().uuidString
    let name = CLINotification.replyPrefix + uuid
    XCTAssertTrue(name.hasPrefix("com.github.BetterMonitor.cli.reply."))
    XCTAssertTrue(name.hasSuffix(uuid))
  }
}
