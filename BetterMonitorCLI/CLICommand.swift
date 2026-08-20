//  Copyright © BetterMonitor. @JoniVR, @theOneyouseek, @waydabber and others

import Foundation

struct CLICommand {
  let action: CLIAction
  let property: CLIProperty?
  let value: Int?
  let displayName: String?
  let displayId: UInt32?
  let favoriteName: String?
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
    if let favoriteName = favoriteName {
      info[CLIKey.favoriteName] = favoriteName
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
    var displayTargetCount = 0
    var positional: [String] = []

    var i = 0
    while i < args.count {
      switch args[i] {
      case "--json":
        jsonOutput = true
      case "--display":
        displayTargetCount += 1
        i += 1
        guard i < args.count, !isKnownOption(args[i]) else {
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
    let hasExplicitDisplayTarget = displayId != nil || !(displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

    switch action {
    case .list:
      return CLICommand(action: .list, property: nil, value: nil, displayName: displayName, displayId: displayId, favoriteName: nil, jsonOutput: jsonOutput)

    case .get:
      guard positional.count >= 2, let property = CLIProperty(rawValue: positional[1]) else {
        printError("Usage: bettermonitor get <brightness|volume|contrast|input>")
        return nil
      }
      return CLICommand(action: .get, property: property, value: nil, displayName: displayName, displayId: displayId, favoriteName: nil, jsonOutput: jsonOutput)

    case .set:
      guard positional.count >= 3,
            let property = CLIProperty(rawValue: positional[1]),
            let value = parseSetValue(positional[2], for: property)
      else {
        printError("Usage: bettermonitor set <brightness|volume|contrast> <0-100> or bettermonitor set input <source> --display <name-or-id>")
        return nil
      }
      guard property != .input || displayName != nil || displayId != nil else {
        printError("Input source changes require --display <name-or-id>")
        return nil
      }
      return CLICommand(action: .set, property: property, value: value, displayName: displayName, displayId: displayId, favoriteName: nil, jsonOutput: jsonOutput)

    case .modeList:
      let hasOverflowedNumericTarget = displayName.map(Self.isASCIIUnsignedDecimal) ?? false
      guard positional.count == 1,
            displayTargetCount == 1,
            hasExplicitDisplayTarget,
            !hasOverflowedNumericTarget
      else {
        printError("Usage: bettermonitor mode-list --display <name-or-id>")
        return nil
      }
      return CLICommand(action: action, property: nil, value: nil, displayName: displayName, displayId: displayId, favoriteName: nil, jsonOutput: jsonOutput)

    case .modeFavoriteList:
      guard positional.count == 1,
            displayTargetCount <= 1,
            displayTargetCount == 0 || hasExplicitDisplayTarget
      else {
        printError("Usage: bettermonitor mode-favorite-list [--display <name-or-id>]")
        return nil
      }
      return CLICommand(action: action, property: nil, value: nil, displayName: displayName, displayId: displayId, favoriteName: nil, jsonOutput: jsonOutput)

    case .modeFavoriteSave, .modeFavoriteApply, .modeFavoriteDelete:
      guard positional.count == 2,
            !ModeFavoriteManager.normalizedName(positional[1]).isEmpty,
            displayTargetCount == 1,
            hasExplicitDisplayTarget
      else {
        printError("Usage: bettermonitor \(action.rawValue) <name> --display <name-or-id>")
        return nil
      }
      return CLICommand(action: action, property: nil, value: nil, displayName: displayName, displayId: displayId, favoriteName: positional[1], jsonOutput: jsonOutput)
    }
  }

  private static func isKnownOption(_ argument: String) -> Bool {
    switch argument {
    case "--json", "--display", "--help", "-h":
      true
    default:
      false
    }
  }

  private static func parseSetValue(_ value: String, for property: CLIProperty) -> Int? {
    switch property {
    case .input:
      return DDCInputSource.value(for: value).map { Int($0) }
    case .brightness, .volume, .contrast:
      guard let percentage = Int(value), (0 ... 100).contains(percentage) else {
        return nil
      }
      return percentage
    }
  }

  private static func isASCIIUnsignedDecimal(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
  }

  static func printUsage() {
    let usage = """
    Usage: bettermonitor <command> [options]

      list                                      List connected displays
      get <brightness|volume|contrast|input>     Get current value
      set <brightness|volume|contrast> <0-100>   Set value
      set input <source> --display <name-or-id>  Queue DDC input (hdmi1, dp1, or 0x01-0xFF)
      mode-list --display <name-or-id>            List offered usable desktop modes
      mode-favorite-list [--display <target>]     List saved exact offered-mode favorites
      mode-favorite-save <name> --display <target>
      mode-favorite-apply <name> --display <target>
      mode-favorite-delete <name> --display <target>

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
