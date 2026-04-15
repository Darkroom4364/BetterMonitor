//  Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others

import Foundation

enum CLINotification {
  static let request = "com.github.MonitorControl.cli.request"
  static let replyPrefix = "com.github.MonitorControl.cli.reply."
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
}
