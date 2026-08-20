//  Copyright © BetterMonitor. @JoniVR, @theOneyouseek, @waydabber and others

import CoreGraphics
import Foundation

struct ModeCatalogTarget: Equatable {
  let identifier: CGDirectDisplayID
  let name: String
}

enum ModeCatalogError: Error, Equatable, LocalizedError {
  case displayTargetRequired
  case invalidDisplayTarget
  case displayNotFound
  case ambiguousDisplayTarget
  case offeredModesUnreadable
  case noUsableDesktopModes
  case invalidOfferedMode

  var errorDescription: String? {
    switch self {
    case .displayTargetRequired: return "Mode list requires exactly one --display <name-or-id>"
    case .invalidDisplayTarget: return "Invalid display target"
    case .displayNotFound: return "No matching display found"
    case .ambiguousDisplayTarget: return "Mode list requires exactly one matching display"
    case .offeredModesUnreadable: return "Display modes could not be read"
    case .noUsableDesktopModes: return "No usable desktop modes are currently offered"
    case .invalidOfferedMode: return "Display returned an invalid offered mode"
    }
  }
}

struct ModeCatalogTargetResolver {
  private static let matchingLocale = Locale(identifier: "en_US_POSIX")

  static func resolve(userInfo: [AnyHashable: Any], targets: [ModeCatalogTarget]) -> Result<ModeCatalogTarget, ModeCatalogError> {
    let displayIDValue = userInfo[CLIKey.displayId]
    let displayNameValue = userInfo[CLIKey.displayName]
    let hasDisplayID = displayIDValue != nil
    let hasDisplayName = displayNameValue != nil

    guard hasDisplayID != hasDisplayName else {
      return .failure(.displayTargetRequired)
    }

    if let displayIDValue {
      guard let displayID = exactDisplayID(from: displayIDValue) else {
        return .failure(.invalidDisplayTarget)
      }
      return resolve(targets.filter { $0.identifier == displayID })
    }

    guard let displayName = displayNameValue as? String else {
      return .failure(.invalidDisplayTarget)
    }
    guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return .failure(.invalidDisplayTarget)
    }
    let needle = foldedName(displayName)
    return resolve(targets.filter { foldedName($0.name) == needle })
  }

  private static func exactDisplayID(from value: Any) -> CGDirectDisplayID? {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID()
    else {
      return nil
    }
    let objcType = String(cString: number.objCType)
    guard ["c", "C", "s", "S", "i", "I", "l", "L", "q", "Q"].contains(objcType) else {
      return nil
    }
    let decimalValue = number.decimalValue
    guard decimalValue >= 0,
          decimalValue <= Decimal(UInt32.max),
          decimalValue == Decimal(number.uint32Value)
    else {
      return nil
    }
    return number.uint32Value
  }

  private static func foldedName(_ name: String) -> String {
    name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: matchingLocale)
      .lowercased(with: matchingLocale)
  }

  private static func resolve(_ matches: [ModeCatalogTarget]) -> Result<ModeCatalogTarget, ModeCatalogError> {
    switch matches.count {
    case 0: return .failure(.displayNotFound)
    case 1: return .success(matches[0])
    default: return .failure(.ambiguousDisplayTarget)
    }
  }
}

struct ModeCatalogRow: Equatable {
  let display: String
  let id: Int
  let logicalWidth: Int
  let logicalHeight: Int
  let pixelWidth: Int
  let pixelHeight: Int
  let refreshRate: Double
  let pixelEncoding: String
  let isUsableForDesktop: Bool
  let ioFlags: Int
  let isHiDPI: Bool
  let mode: String

  private static let labelLocale = Locale(identifier: "en_US_POSIX")

  init(target: ModeCatalogTarget, signature: DisplayModeSignature) {
    display = target.name
    id = Int(target.identifier)
    logicalWidth = signature.logicalWidth
    logicalHeight = signature.logicalHeight
    pixelWidth = signature.pixelWidth
    pixelHeight = signature.pixelHeight
    refreshRate = signature.refreshRate
    pixelEncoding = signature.pixelEncoding
    isUsableForDesktop = signature.isUsableForDesktop
    ioFlags = Int(signature.ioFlags)
    isHiDPI = signature.isHiDPI
    mode = Self.modeLabel(for: signature)
  }

  var responseDictionary: [String: Any] {
    [
      "display": display,
      "id": id,
      "logicalWidth": logicalWidth,
      "logicalHeight": logicalHeight,
      "pixelWidth": pixelWidth,
      "pixelHeight": pixelHeight,
      "refreshRate": refreshRate,
      "pixelEncoding": pixelEncoding,
      "isUsableForDesktop": isUsableForDesktop,
      "ioFlags": ioFlags,
      "isHiDPI": isHiDPI,
      "mode": mode,
    ]
  }

  private static func modeLabel(for signature: DisplayModeSignature) -> String {
    let refresh = signature.refreshRate == 0
      ? "variable"
      : String(format: "%.2f Hz", locale: labelLocale, arguments: [signature.refreshRate])
    return "\(signature.logicalWidth)×\(signature.logicalHeight) (\(signature.pixelWidth)×\(signature.pixelHeight), \(refresh))"
  }
}

final class ModeCatalog {
  private let reader: OfferedDisplayModeReading

  init(reader: OfferedDisplayModeReading) {
    self.reader = reader
  }

  func rows(for target: ModeCatalogTarget) -> Result<[ModeCatalogRow], ModeCatalogError> {
    guard let offeredModes = reader.offeredModeSignatures(displayID: target.identifier) else {
      return .failure(.offeredModesUnreadable)
    }
    let usableModes = offeredModes.filter(\.isUsableForDesktop)
    guard !usableModes.isEmpty else {
      return .failure(.noUsableDesktopModes)
    }
    guard usableModes.allSatisfy(Self.isValid) else {
      return .failure(.invalidOfferedMode)
    }
    let sortedModes = Array(Set(usableModes)).sorted(by: Self.isOrdered)
    return .success(sortedModes.map { ModeCatalogRow(target: target, signature: $0) })
  }

  private static func isValid(_ signature: DisplayModeSignature) -> Bool {
    signature.logicalWidth > 0 &&
      signature.logicalHeight > 0 &&
      signature.pixelWidth > 0 &&
      signature.pixelHeight > 0 &&
      signature.refreshRate.isFinite &&
      signature.refreshRate >= 0
  }

  private static func isOrdered(_ lhs: DisplayModeSignature, _ rhs: DisplayModeSignature) -> Bool {
    if lhs.logicalWidth != rhs.logicalWidth { return lhs.logicalWidth > rhs.logicalWidth }
    if lhs.logicalHeight != rhs.logicalHeight { return lhs.logicalHeight > rhs.logicalHeight }
    if lhs.pixelWidth != rhs.pixelWidth { return lhs.pixelWidth > rhs.pixelWidth }
    if lhs.pixelHeight != rhs.pixelHeight { return lhs.pixelHeight > rhs.pixelHeight }
    if lhs.refreshRate != rhs.refreshRate { return lhs.refreshRate > rhs.refreshRate }

    let leftEncoding = Array(lhs.pixelEncoding.utf8)
    let rightEncoding = Array(rhs.pixelEncoding.utf8)
    if leftEncoding != rightEncoding { return leftEncoding.lexicographicallyPrecedes(rightEncoding) }
    if lhs.isUsableForDesktop != rhs.isUsableForDesktop { return !lhs.isUsableForDesktop && rhs.isUsableForDesktop }
    if lhs.ioFlags != rhs.ioFlags { return lhs.ioFlags < rhs.ioFlags }
    if lhs.isHiDPI != rhs.isHiDPI { return !lhs.isHiDPI && rhs.isHiDPI }
    return false
  }
}

struct ModeCatalogRequestProcessor {
  let catalog: ModeCatalog

  func handle(userInfo: [AnyHashable: Any], targets: [ModeCatalogTarget]) -> [[String: Any]] {
    switch ModeCatalogTargetResolver.resolve(userInfo: userInfo, targets: targets) {
    case let .failure(error):
      return [["error": error.localizedDescription]]
    case let .success(target):
      switch catalog.rows(for: target) {
      case let .failure(error):
        return [["error": error.localizedDescription]]
      case let .success(rows):
        return rows.map(\.responseDictionary)
      }
    }
  }
}
