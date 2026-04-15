//  Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others

import Foundation

struct CLICommand {
  let action: CLIAction
  let property: CLIProperty?
  let value: Int?
  let displayName: String?
  let displayId: UInt32?
  let jsonOutput: Bool

  var userInfo: [String: Any] {
    var info: [String: Any] = [
      CLIKey.action: action.rawValue,
      CLIKey.replyId: UUID().uuidString,
    ]
    if let property = property {
      info[CLIKey.property] = property.rawValue
    }
    if let value = value {
      info[CLIKey.value] = value
    }
    if let displayName = displayName {
      info[CLIKey.displayName] = displayName
    }
    if let displayId = displayId {
      info[CLIKey.displayId] = displayId
    }
    return info
  }

  static func parse(_ args: [String]) -> CLICommand? {
    let args = Array(args.dropFirst()) // drop executable path
    guard !args.isEmpty else {
      printUsage()
      return nil
    }

    var jsonOutput = false
    var displayName: String?
    var displayId: UInt32?
    var positional: [String] = []

    var i = 0
    while i < args.count {
      switch args[i] {
      case "--json":
        jsonOutput = true
      case "--display":
        i += 1
        guard i < args.count else {
          printError("--display requires a value")
          return nil
        }
        if let id = UInt32(args[i]) {
          displayId = id
        } else {
          displayName = args[i]
        }
      case "--help", "-h":
        printUsage()
        exit(0)
      default:
        positional.append(args[i])
      }
      i += 1
    }

    guard let actionString = positional.first, let action = CLIAction(rawValue: actionString) else {
      printError("Unknown command: \(positional.first ?? "")")
      printUsage()
      return nil
    }

    switch action {
    case .list:
      return CLICommand(action: .list, property: nil, value: nil, displayName: displayName, displayId: displayId, jsonOutput: jsonOutput)

    case .get:
      guard positional.count >= 2, let property = CLIProperty(rawValue: positional[1]) else {
        printError("Usage: monitorcontrol get <brightness|volume|contrast>")
        return nil
      }
      return CLICommand(action: .get, property: property, value: nil, displayName: displayName, displayId: displayId, jsonOutput: jsonOutput)

    case .set:
      guard positional.count >= 3,
            let property = CLIProperty(rawValue: positional[1]),
            let value = Int(positional[2]),
            value >= 0, value <= 100
      else {
        printError("Usage: monitorcontrol set <brightness|volume|contrast> <0-100>")
        return nil
      }
      return CLICommand(action: .set, property: property, value: value, displayName: displayName, displayId: displayId, jsonOutput: jsonOutput)
    }
  }

  static func printUsage() {
    let usage = """
    Usage: monitorcontrol <command> [options]

    Commands:
      list                                      List connected displays
      get <brightness|volume|contrast>           Get current value
      set <brightness|volume|contrast> <0-100>   Set value

    Options:
      --display <name-or-id>    Target a specific display
      --json                    Output as JSON
      --help                    Show this help
    """
    print(usage)
  }

  static func printError(_ message: String) {
    fputs("Error: \(message)\n", stderr)
  }
}
