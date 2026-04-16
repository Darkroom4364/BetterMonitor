//  Copyright © BetterMonitor. @JoniVR, @theOneyouseek, @waydabber and others

import XCTest

class CLICommandParsingTests: XCTestCase {

  // MARK: - Valid commands

  func testParseListCommand() {
    let cmd = CLICommand.parse(["bettermonitor", "list"])
    XCTAssertNotNil(cmd)
    XCTAssertEqual(cmd?.action, .list)
    XCTAssertNil(cmd?.property)
    XCTAssertNil(cmd?.value)
    XCTAssertFalse(cmd?.jsonOutput ?? true)
  }

  func testParseGetBrightness() {
    let cmd = CLICommand.parse(["bettermonitor", "get", "brightness"])
    XCTAssertNotNil(cmd)
    XCTAssertEqual(cmd?.action, .get)
    XCTAssertEqual(cmd?.property, .brightness)
    XCTAssertNil(cmd?.value)
  }

  func testParseGetVolume() {
    let cmd = CLICommand.parse(["bettermonitor", "get", "volume"])
    XCTAssertEqual(cmd?.property, .volume)
  }

  func testParseGetContrast() {
    let cmd = CLICommand.parse(["bettermonitor", "get", "contrast"])
    XCTAssertEqual(cmd?.property, .contrast)
  }

  func testParseSetBrightness() {
    let cmd = CLICommand.parse(["bettermonitor", "set", "brightness", "50"])
    XCTAssertNotNil(cmd)
    XCTAssertEqual(cmd?.action, .set)
    XCTAssertEqual(cmd?.property, .brightness)
    XCTAssertEqual(cmd?.value, 50)
  }

  func testParseSetBrightnessZero() {
    let cmd = CLICommand.parse(["bettermonitor", "set", "brightness", "0"])
    XCTAssertNotNil(cmd)
    XCTAssertEqual(cmd?.action, .set)
    XCTAssertEqual(cmd?.property, .brightness)
    XCTAssertEqual(cmd?.value, 0)
  }

  func testParseSetBrightnessMax() {
    let cmd = CLICommand.parse(["bettermonitor", "set", "brightness", "100"])
    XCTAssertNotNil(cmd)
    XCTAssertEqual(cmd?.action, .set)
    XCTAssertEqual(cmd?.property, .brightness)
    XCTAssertEqual(cmd?.value, 100)
  }

  // MARK: - Flags

  func testJsonFlag() {
    let cmd = CLICommand.parse(["bettermonitor", "--json", "list"])
    XCTAssertNotNil(cmd)
    XCTAssertTrue(cmd?.jsonOutput ?? false)
    XCTAssertEqual(cmd?.action, .list)
  }

  func testJsonFlagAfterCommand() {
    let cmd = CLICommand.parse(["bettermonitor", "list", "--json"])
    XCTAssertNotNil(cmd)
    XCTAssertEqual(cmd?.action, .list)
    XCTAssertTrue(cmd?.jsonOutput ?? false)
  }

  func testDisplayNameFlag() {
    let cmd = CLICommand.parse(["bettermonitor", "--display", "Dell", "get", "brightness"])
    XCTAssertNotNil(cmd)
    XCTAssertEqual(cmd?.displayName, "Dell")
    XCTAssertNil(cmd?.displayId)
  }

  func testDisplayIdFlag() {
    let cmd = CLICommand.parse(["bettermonitor", "--display", "12345", "get", "brightness"])
    XCTAssertNotNil(cmd)
    XCTAssertEqual(cmd?.displayId, 12345)
    XCTAssertNil(cmd?.displayName)
  }

  func testDisplayFlagAfterCommand() {
    let cmd = CLICommand.parse(["bettermonitor", "get", "brightness", "--display", "LG"])
    XCTAssertNotNil(cmd)
    XCTAssertEqual(cmd?.action, .get)
    XCTAssertEqual(cmd?.property, .brightness)
    XCTAssertEqual(cmd?.displayName, "LG")
  }

  func testMultipleFlags() {
    let cmd = CLICommand.parse(["bettermonitor", "--json", "--display", "Dell", "list"])
    XCTAssertNotNil(cmd)
    XCTAssertTrue(cmd?.jsonOutput ?? false)
    XCTAssertEqual(cmd?.displayName, "Dell")
    XCTAssertEqual(cmd?.action, .list)
  }

  // MARK: - Error cases

  func testEmptyArgs() {
    let cmd = CLICommand.parse(["bettermonitor"])
    XCTAssertNil(cmd)
  }

  func testUnknownCommand() {
    let cmd = CLICommand.parse(["bettermonitor", "reset"])
    XCTAssertNil(cmd)
  }

  func testGetMissingProperty() {
    let cmd = CLICommand.parse(["bettermonitor", "get"])
    XCTAssertNil(cmd)
  }

  func testGetInvalidProperty() {
    let cmd = CLICommand.parse(["bettermonitor", "get", "color"])
    XCTAssertNil(cmd)
  }

  func testSetMissingValue() {
    let cmd = CLICommand.parse(["bettermonitor", "set", "brightness"])
    XCTAssertNil(cmd)
  }

  func testSetNegativeValue() {
    let cmd = CLICommand.parse(["bettermonitor", "set", "brightness", "-1"])
    XCTAssertNil(cmd)
  }

  func testSetValueTooHigh() {
    let cmd = CLICommand.parse(["bettermonitor", "set", "brightness", "101"])
    XCTAssertNil(cmd)
  }

  func testSetNonNumericValue() {
    let cmd = CLICommand.parse(["bettermonitor", "set", "brightness", "abc"])
    XCTAssertNil(cmd)
  }

  func testDisplayFlagMissingValue() {
    let cmd = CLICommand.parse(["bettermonitor", "--display"])
    XCTAssertNil(cmd)
  }

  // MARK: - userInfo serialization

  func testUserInfoContainsAction() {
    guard let cmd = CLICommand.parse(["bettermonitor", "list"]) else { return XCTFail("parse returned nil") }
    XCTAssertEqual(cmd.userInfo[CLIKey.action] as? String, "list")
  }

  func testUserInfoContainsReplyId() {
    guard let cmd = CLICommand.parse(["bettermonitor", "list"]) else { return XCTFail("parse returned nil") }
    let replyId = cmd.userInfo[CLIKey.replyId] as? String
    XCTAssertNotNil(replyId)
    XCTAssertNotNil(replyId.flatMap { UUID(uuidString: $0) })
  }

  func testUserInfoContainsProperty() {
    guard let cmd = CLICommand.parse(["bettermonitor", "get", "brightness"]) else { return XCTFail("parse returned nil") }
    XCTAssertEqual(cmd.userInfo[CLIKey.property] as? String, "brightness")
  }

  func testUserInfoContainsValue() {
    guard let cmd = CLICommand.parse(["bettermonitor", "set", "volume", "75"]) else { return XCTFail("parse returned nil") }
    XCTAssertEqual(cmd.userInfo[CLIKey.value] as? Int, 75)
  }

  func testUserInfoContainsDisplayName() {
    guard let cmd = CLICommand.parse(["bettermonitor", "--display", "Dell", "list"]) else { return XCTFail("parse returned nil") }
    XCTAssertEqual(cmd.userInfo[CLIKey.displayName] as? String, "Dell")
  }

  func testUserInfoContainsDisplayId() {
    guard let cmd = CLICommand.parse(["bettermonitor", "--display", "999", "list"]) else { return XCTFail("parse returned nil") }
    XCTAssertEqual(cmd.userInfo[CLIKey.displayId] as? UInt32, 999)
  }

  func testUserInfoOmitsNilFields() {
    guard let cmd = CLICommand.parse(["bettermonitor", "list"]) else { return XCTFail("parse returned nil") }
    let info = cmd.userInfo
    XCTAssertNil(info[CLIKey.property])
    XCTAssertNil(info[CLIKey.value])
    XCTAssertNil(info[CLIKey.displayName])
    XCTAssertNil(info[CLIKey.displayId])
  }
}
