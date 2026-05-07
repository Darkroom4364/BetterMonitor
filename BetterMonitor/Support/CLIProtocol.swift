//  Copyright © BetterMonitor. @JoniVR, @theOneyouseek, @waydabber and others

import Foundation

enum CLINotification {
  static let request = "com.github.BetterMonitor.cli.request"
  static let replyPrefix = "com.github.BetterMonitor.cli.reply."
}

enum CLIKey {
  static let action = "action"
  static let property = "property"
  static let value = "value"
  static let displayId = "displayId"
  static let displayName = "displayName"
  static let replyId = "replyId"
  static let json = "json"
}

enum CLIAction: String {
  case list
  case get
  case set
}

enum CLIProperty: String {
  case brightness
  case volume
  case contrast
  case input
}

enum CLIInputSource {
  static let minValue = 1
  static let maxValue = Int(UInt16.max)

  static func parse(_ string: String) -> Int? {
    let lowercased = string.lowercased()
    if lowercased.hasPrefix("0x") {
      return Int(String(lowercased.dropFirst(2)), radix: 16)
    }
    return Int(string)
  }

  static func uint16Value(_ value: Int) -> UInt16? {
    guard value >= minValue, value <= maxValue else {
      return nil
    }
    return UInt16(value)
  }
}
