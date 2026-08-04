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
  static let favoriteName = "favoriteName"
}

enum CLIAction: String {
  case list
  case get
  case set
  case modeFavoriteList = "mode-favorite-list"
  case modeFavoriteSave = "mode-favorite-save"
  case modeFavoriteApply = "mode-favorite-apply"
  case modeFavoriteDelete = "mode-favorite-delete"
}

enum CLIProperty: String {
  case brightness
  case volume
  case contrast
  case input
}

enum DDCInputSource: UInt16, CaseIterable {
  case vga1 = 0x01
  case vga2 = 0x02
  case dvi1 = 0x03
  case dvi2 = 0x04
  case composite1 = 0x05
  case composite2 = 0x06
  case sVideo1 = 0x07
  case sVideo2 = 0x08
  case tuner1 = 0x09
  case tuner2 = 0x0A
  case tuner3 = 0x0B
  case component1 = 0x0C
  case component2 = 0x0D
  case component3 = 0x0E
  case displayPort1 = 0x0F
  case displayPort2 = 0x10
  case hdmi1 = 0x11
  case hdmi2 = 0x12

  var label: String {
    switch self {
    case .vga1: return "VGA-1"
    case .vga2: return "VGA-2"
    case .dvi1: return "DVI-1"
    case .dvi2: return "DVI-2"
    case .composite1: return "Composite-1"
    case .composite2: return "Composite-2"
    case .sVideo1: return "S-Video-1"
    case .sVideo2: return "S-Video-2"
    case .tuner1: return "Tuner-1"
    case .tuner2: return "Tuner-2"
    case .tuner3: return "Tuner-3"
    case .component1: return "Component-1"
    case .component2: return "Component-2"
    case .component3: return "Component-3"
    case .displayPort1: return "DisplayPort-1"
    case .displayPort2: return "DisplayPort-2"
    case .hdmi1: return "HDMI-1"
    case .hdmi2: return "HDMI-2"
    }
  }

  private var aliases: [String] {
    switch self {
    case .vga1: return ["vga1"]
    case .vga2: return ["vga2"]
    case .dvi1: return ["dvi1"]
    case .dvi2: return ["dvi2"]
    case .composite1: return ["composite1", "cvbs1"]
    case .composite2: return ["composite2", "cvbs2"]
    case .sVideo1: return ["svideo1"]
    case .sVideo2: return ["svideo2"]
    case .tuner1: return ["tuner1"]
    case .tuner2: return ["tuner2"]
    case .tuner3: return ["tuner3"]
    case .component1: return ["component1", "ypbpr1"]
    case .component2: return ["component2", "ypbpr2"]
    case .component3: return ["component3", "ypbpr3"]
    case .displayPort1: return ["dp1", "displayport1"]
    case .displayPort2: return ["dp2", "displayport2"]
    case .hdmi1: return ["hdmi1"]
    case .hdmi2: return ["hdmi2"]
    }
  }

  static func value(for argument: String) -> UInt16? {
    let normalized = argument.lowercased()
      .replacingOccurrences(of: "-", with: "")
      .replacingOccurrences(of: "_", with: "")
      .replacingOccurrences(of: " ", with: "")
    if let source = allCases.first(where: { $0.aliases.contains(normalized) }) {
      return source.rawValue
    }
    let value = normalized.hasPrefix("0x")
      ? UInt16(String(normalized.dropFirst(2)), radix: 16)
      : UInt16(normalized)
    guard let value, (1 ... UInt16(UInt8.max)).contains(value) else {
      return nil
    }
    return value
  }

  static func label(for value: UInt16) -> String {
    if value == 0 {
      return "No active input"
    }
    return DDCInputSource(rawValue: value)?.label ?? String(format: "Input 0x%02X", value)
  }
}
