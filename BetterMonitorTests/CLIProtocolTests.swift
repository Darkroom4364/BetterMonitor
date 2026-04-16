//  Copyright © BetterMonitor. @JoniVR, @theOneyouseek, @waydabber and others

import XCTest

class CLIProtocolTests: XCTestCase {

  // MARK: - CLIAction

  func testCLIActionRawValues() {
    XCTAssertEqual(CLIAction.list.rawValue, "list")
    XCTAssertEqual(CLIAction.get.rawValue, "get")
    XCTAssertEqual(CLIAction.set.rawValue, "set")
  }

  func testCLIActionRoundtrip() {
    for action: CLIAction in [.list, .get, .set] {
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
  }

  func testCLIPropertyRoundtrip() {
    for prop: CLIProperty in [.brightness, .volume, .contrast] {
      XCTAssertEqual(CLIProperty(rawValue: prop.rawValue), prop)
    }
  }

  func testCLIPropertyInvalidRawValue() {
    XCTAssertNil(CLIProperty(rawValue: "color"))
    XCTAssertNil(CLIProperty(rawValue: ""))
    XCTAssertNil(CLIProperty(rawValue: "BRIGHTNESS"))
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
