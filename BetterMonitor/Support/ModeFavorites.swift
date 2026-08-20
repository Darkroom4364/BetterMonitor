//  Copyright © BetterMonitor. @JoniVR, @theOneyouseek, @waydabber and others

import Cocoa
import CoreGraphics
import Foundation

struct DisplayModeSignature: Codable, Equatable, Hashable {
  let logicalWidth: Int
  let logicalHeight: Int
  let pixelWidth: Int
  let pixelHeight: Int
  let refreshRate: Double
  let pixelEncoding: String
  let isUsableForDesktop: Bool
  let ioFlags: UInt32
  let isHiDPI: Bool

  init(mode: CGDisplayMode) {
    logicalWidth = mode.width
    logicalHeight = mode.height
    pixelWidth = mode.pixelWidth
    pixelHeight = mode.pixelHeight
    refreshRate = mode.refreshRate
    pixelEncoding = (mode.pixelEncoding ?? "" as CFString) as String
    isUsableForDesktop = mode.isUsableForDesktopGUI()
    ioFlags = mode.ioFlags
    isHiDPI = pixelWidth != logicalWidth || pixelHeight != logicalHeight
  }

  init(logicalWidth: Int, logicalHeight: Int, pixelWidth: Int, pixelHeight: Int, refreshRate: Double, pixelEncoding: String, isUsableForDesktop: Bool, ioFlags: UInt32, isHiDPI: Bool) {
    self.logicalWidth = logicalWidth
    self.logicalHeight = logicalHeight
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.refreshRate = refreshRate
    self.pixelEncoding = pixelEncoding
    self.isUsableForDesktop = isUsableForDesktop
    self.ioFlags = ioFlags
    self.isHiDPI = isHiDPI
  }

  var label: String {
    let refresh = refreshRate == 0 ? "variable" : String(format: "%.2f Hz", refreshRate)
    return "\(logicalWidth)×\(logicalHeight) (\(pixelWidth)×\(pixelHeight), \(refresh))"
  }
}

struct ModeFavoriteDisplayTarget: Equatable {
  let identifier: CGDirectDisplayID
  let name: String
  let vendorNumber: UInt32?
  let modelNumber: UInt32?
  let serialNumber: UInt32?
  let searchNames: [String]

  init(identifier: CGDirectDisplayID, name: String, vendorNumber: UInt32?, modelNumber: UInt32?, serialNumber: UInt32?, searchNames: [String] = []) {
    self.identifier = identifier
    self.name = name
    self.vendorNumber = vendorNumber
    self.modelNumber = modelNumber
    self.serialNumber = serialNumber
    self.searchNames = searchNames
  }

  var durableIdentity: String? {
    guard let vendorNumber, let modelNumber, let serialNumber,
          Self.isValidEDIDComponent(vendorNumber),
          Self.isValidEDIDComponent(modelNumber),
          Self.isValidEDIDComponent(serialNumber)
    else {
      return nil
    }
    return "edid:\(vendorNumber):\(modelNumber):\(serialNumber)"
  }

  private static func isValidEDIDComponent(_ value: UInt32) -> Bool {
    value != 0 && value != UInt32.max
  }
}

struct ModeFavorite: Codable, Equatable {
  let name: String
  let normalizedName: String
  let displayIdentity: String
  let displayName: String
  let signature: DisplayModeSignature
}

enum ModeFavoriteError: Error, Equatable, LocalizedError {
  case invalidName
  case stableIdentityUnavailable
  case maximumFavoritesReached
  case favoriteNotFound
  case duplicateFavoriteName
  case currentModeUnreadable
  case unavailableMode
  case unusableMode
  case setFailed
  case readbackUnreadable
  case readbackMismatch

  var errorDescription: String? {
    switch self {
    case .invalidName: return "Favorite name must not be blank"
    case .stableIdentityUnavailable: return "Stable identity unavailable: mode favorites require a complete vendor/model/serial identity"
    case .maximumFavoritesReached: return "A display can have at most five mode favorites"
    case .favoriteNotFound: return "No saved mode favorite with that name"
    case .duplicateFavoriteName: return "Multiple saved mode favorites have that name"
    case .currentModeUnreadable: return "Current display mode could not be read"
    case .unavailableMode: return "Saved mode is not currently offered by this display"
    case .unusableMode: return "Saved mode is not usable for the desktop"
    case .setFailed: return "Failed to set the saved display mode"
    case .readbackUnreadable: return "Display mode could not be verified after setting it"
    case .readbackMismatch: return "Display mode did not match the saved mode after setting it"
    }
  }
}

protocol ModeFavoriteStoring: AnyObject {
  func data(forKey key: String) -> Data?
  func set(_ data: Data?, forKey key: String)
}

final class UserDefaultsModeFavoriteStorage: ModeFavoriteStoring {
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func data(forKey key: String) -> Data? {
    defaults.data(forKey: key)
  }

  func set(_ data: Data?, forKey key: String) {
    defaults.set(data, forKey: key)
  }
}

protocol ModeFavoriteModeControlling {
  func currentModeSignature(displayID: CGDirectDisplayID) -> DisplayModeSignature?
  func offeredModeSignatures(displayID: CGDirectDisplayID) -> [DisplayModeSignature]?
  func setMode(displayID: CGDirectDisplayID, signature: DisplayModeSignature) -> Bool
}

final class CoreGraphicsModeFavoriteController: ModeFavoriteModeControlling {
  func currentModeSignature(displayID: CGDirectDisplayID) -> DisplayModeSignature? {
    CGDisplayCopyDisplayMode(displayID).map(DisplayModeSignature.init)
  }

  func offeredModeSignatures(displayID: CGDirectDisplayID) -> [DisplayModeSignature]? {
    guard let modes = CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode] else {
      return nil
    }
    return modes.map(DisplayModeSignature.init)
  }

  func setMode(displayID: CGDirectDisplayID, signature: DisplayModeSignature) -> Bool {
    guard let modes = CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode],
          let mode = modes.first(where: { DisplayModeSignature(mode: $0) == signature })
    else {
      return false
    }
    return CGDisplaySetDisplayMode(displayID, mode, nil) == .success
  }
}

protocol ModeFavoriteManaging: AnyObject {
  func favorites(for target: ModeFavoriteDisplayTarget?) -> [ModeFavorite]
  func saveCurrent(name: String, for target: ModeFavoriteDisplayTarget) -> Result<ModeFavorite, ModeFavoriteError>
  func apply(name: String, for target: ModeFavoriteDisplayTarget) -> Result<ModeFavorite, ModeFavoriteError>
  func delete(name: String, for target: ModeFavoriteDisplayTarget) -> Result<ModeFavorite, ModeFavoriteError>
}

final class ModeFavoriteManager: ModeFavoriteManaging {
  static let shared = ModeFavoriteManager()
  static let storageKey = "ModeFavorites.v1"
  static let maximumFavoritesPerDisplay = 5

  private let storage: ModeFavoriteStoring
  private let modeController: ModeFavoriteModeControlling

  init(storage: ModeFavoriteStoring = UserDefaultsModeFavoriteStorage(), modeController: ModeFavoriteModeControlling = CoreGraphicsModeFavoriteController()) {
    self.storage = storage
    self.modeController = modeController
  }

  static func normalizedName(_ name: String) -> String {
    name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased(with: Locale(identifier: "en_US_POSIX"))
  }

  func favorites(for target: ModeFavoriteDisplayTarget? = nil) -> [ModeFavorite] {
    let displayIdentity: String?
    if let target {
      guard let durableIdentity = target.durableIdentity else {
        return []
      }
      displayIdentity = durableIdentity
    } else {
      displayIdentity = nil
    }
    return storedFavorites()
      .filter { displayIdentity == nil || $0.displayIdentity == displayIdentity }
      .sorted {
        if $0.displayIdentity == $1.displayIdentity {
          if $0.normalizedName == $1.normalizedName {
            return $0.name < $1.name
          }
          return $0.normalizedName < $1.normalizedName
        }
        return $0.displayIdentity < $1.displayIdentity
      }
  }

  func saveCurrent(name: String, for target: ModeFavoriteDisplayTarget) -> Result<ModeFavorite, ModeFavoriteError> {
    let normalizedName = Self.normalizedName(name)
    guard !normalizedName.isEmpty else {
      return .failure(.invalidName)
    }
    guard let displayIdentity = target.durableIdentity else {
      return .failure(.stableIdentityUnavailable)
    }
    var favorites = storedFavorites()
    let existingNames = Set(favorites.lazy
      .filter { $0.displayIdentity == displayIdentity }
      .map(\.normalizedName))
    guard existingNames.contains(normalizedName) || existingNames.count < Self.maximumFavoritesPerDisplay else {
      return .failure(.maximumFavoritesReached)
    }
    guard let signature = modeController.currentModeSignature(displayID: target.identifier) else {
      return .failure(.currentModeUnreadable)
    }
    guard signature.isUsableForDesktop else {
      return .failure(.unusableMode)
    }

    guard let offeredModes = modeController.offeredModeSignatures(displayID: target.identifier),
          offeredModes.contains(signature)
    else {
      return .failure(.unavailableMode)
    }

    let favorite = ModeFavorite(
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      normalizedName: normalizedName,
      displayIdentity: displayIdentity,
      displayName: target.name,
      signature: signature
    )
    favorites.removeAll {
      $0.displayIdentity == displayIdentity && $0.normalizedName == normalizedName
    }
    favorites.append(favorite)
    save(favorites)
    return .success(favorite)
  }

  func apply(name: String, for target: ModeFavoriteDisplayTarget) -> Result<ModeFavorite, ModeFavoriteError> {
    guard let displayIdentity = target.durableIdentity else {
      return .failure(.stableIdentityUnavailable)
    }
    guard let favorite = favorite(named: name, displayIdentity: displayIdentity) else {
      return .failure(Self.normalizedName(name).isEmpty ? .invalidName : .favoriteNotFound)
    }
    let matching = matchingFavorites(named: name, displayIdentity: displayIdentity)
    guard matching.count == 1 else {
      return .failure(.duplicateFavoriteName)
    }
    guard favorite.signature.isUsableForDesktop else {
      return .failure(.unusableMode)
    }
    guard let offeredModes = modeController.offeredModeSignatures(displayID: target.identifier) else {
      return .failure(.unavailableMode)
    }
    guard offeredModes.contains(favorite.signature) else {
      return .failure(.unavailableMode)
    }
    guard modeController.setMode(displayID: target.identifier, signature: favorite.signature) else {
      return .failure(.setFailed)
    }
    guard let readback = modeController.currentModeSignature(displayID: target.identifier) else {
      return .failure(.readbackUnreadable)
    }
    guard readback == favorite.signature else {
      return .failure(.readbackMismatch)
    }
    return .success(favorite)
  }

  func delete(name: String, for target: ModeFavoriteDisplayTarget) -> Result<ModeFavorite, ModeFavoriteError> {
    guard let displayIdentity = target.durableIdentity else {
      return .failure(.stableIdentityUnavailable)
    }
    guard let favorite = favorite(named: name, displayIdentity: displayIdentity) else {
      return .failure(Self.normalizedName(name).isEmpty ? .invalidName : .favoriteNotFound)
    }
    let matching = matchingFavorites(named: name, displayIdentity: displayIdentity)
    guard matching.count == 1 else {
      return .failure(.duplicateFavoriteName)
    }
    var favorites = storedFavorites()
    favorites.removeAll {
      $0.displayIdentity == displayIdentity && $0.normalizedName == favorite.normalizedName
    }
    save(favorites)
    return .success(favorite)
  }

  private func favorite(named name: String, displayIdentity: String) -> ModeFavorite? {
    matchingFavorites(named: name, displayIdentity: displayIdentity).first
  }

  private func matchingFavorites(named name: String, displayIdentity: String) -> [ModeFavorite] {
    let normalizedName = Self.normalizedName(name)
    guard !normalizedName.isEmpty else {
      return []
    }
    return storedFavorites().filter {
      $0.displayIdentity == displayIdentity && $0.normalizedName == normalizedName
    }
  }

  private func storedFavorites() -> [ModeFavorite] {
    guard let data = storage.data(forKey: Self.storageKey),
          let favorites = try? JSONDecoder().decode([ModeFavorite].self, from: data)
    else {
      return []
    }
    return favorites
  }

  private func save(_ favorites: [ModeFavorite]) {
    storage.set(try? JSONEncoder().encode(favorites), forKey: Self.storageKey)
  }
}

struct ModeFavoriteTargetError: Error, Equatable {
  let message: String
}

struct ModeFavoriteTargetResolver {
  static func resolve(userInfo: [AnyHashable: Any], targets: [ModeFavoriteDisplayTarget]) -> Result<ModeFavoriteDisplayTarget?, ModeFavoriteTargetError> {
    let displayIDValue = userInfo[CLIKey.displayId]
    let displayNameValue = userInfo[CLIKey.displayName]
    let hasDisplayID = displayIDValue != nil
    let hasDisplayName = displayNameValue != nil

    guard !(hasDisplayID && hasDisplayName) else {
      return .failure(ModeFavoriteTargetError(message: "Mode favorites require exactly one --display <name-or-id>"))
    }
    guard hasDisplayID || hasDisplayName else {
      return .success(nil)
    }

    if let displayIDValue {
      guard let displayID = exactDisplayID(from: displayIDValue) else {
        return .failure(ModeFavoriteTargetError(message: "Invalid display target"))
      }
      let matches = targets.filter { $0.identifier == displayID }
      return resolve(matches)
    }

    guard let displayName = displayNameValue as? String,
          !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return .failure(ModeFavoriteTargetError(message: "Invalid display target"))
    }
    let needle = displayName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    let matches = targets.filter { target in
      ([target.name] + target.searchNames).contains {
        $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(needle)
      }
    }
    return resolve(matches)
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

  private static func resolve(_ matches: [ModeFavoriteDisplayTarget]) -> Result<ModeFavoriteDisplayTarget?, ModeFavoriteTargetError> {
    if matches.isEmpty {
      return .failure(ModeFavoriteTargetError(message: "No matching display found"))
    }
    if matches.count > 1 {
      return .failure(ModeFavoriteTargetError(message: "Mode favorites require exactly one matching display"))
    }
    return .success(matches[0])
  }
}

final class ModeFavoriteCLIProcessor {
  private let manager: ModeFavoriteManaging
  private let onSuccessfulMutation: () -> Void

  init(manager: ModeFavoriteManaging = ModeFavoriteManager.shared, onSuccessfulMutation: @escaping () -> Void = {}) {
    self.manager = manager
    self.onSuccessfulMutation = onSuccessfulMutation
  }

  func handle(action: CLIAction, name: String?, targetResult: Result<ModeFavoriteDisplayTarget?, ModeFavoriteTargetError>) -> [[String: Any]] {
    switch targetResult {
    case let .failure(error):
      return [["error": error.message]]
    case let .success(target):
      switch action {
      case .modeFavoriteList:
        if let target, target.durableIdentity == nil {
          return [["error": ModeFavoriteError.stableIdentityUnavailable.localizedDescription]]
        }
        return manager.favorites(for: target).map { favorite in
          [
            "name": favorite.name,
            "display": target?.name ?? favorite.displayName,
            "displayIdentity": favorite.displayIdentity,
            "mode": favorite.signature.label,
          ]
        }
      case .modeFavoriteSave, .modeFavoriteApply, .modeFavoriteDelete:
        guard let target else {
          return [["error": "Mode favorites require --display <name-or-id>"]]
        }
        guard target.durableIdentity != nil else {
          return [["error": ModeFavoriteError.stableIdentityUnavailable.localizedDescription]]
        }
        guard let name, !ModeFavoriteManager.normalizedName(name).isEmpty else {
          return [["error": ModeFavoriteError.invalidName.localizedDescription]]
        }
        let result: Result<ModeFavorite, ModeFavoriteError>
        switch action {
        case .modeFavoriteSave:
          result = manager.saveCurrent(name: name, for: target)
        case .modeFavoriteApply:
          result = manager.apply(name: name, for: target)
        case .modeFavoriteDelete:
          result = manager.delete(name: name, for: target)
        case .list, .get, .set, .modeFavoriteList:
          fatalError("Unexpected action")
        }
        switch result {
        case let .success(favorite):
          if action == .modeFavoriteSave || action == .modeFavoriteDelete {
            onSuccessfulMutation()
          }
          let operation: String
          switch action {
          case .modeFavoriteSave: operation = "saved"
          case .modeFavoriteApply: operation = "applied"
          case .modeFavoriteDelete: operation = "deleted"
          case .list, .get, .set, .modeFavoriteList: fatalError("Unexpected action")
          }
          return [[
            "name": favorite.name,
            "display": target.name,
            "id": target.identifier,
            "mode": favorite.signature.label,
            "operation": operation,
          ]]
        case let .failure(error):
          return [["name": target.name, "error": error.localizedDescription]]
        }
      case .list, .get, .set:
        return [["error": "Invalid mode favorite command"]]
      }
    }
  }
}

indirect enum ModeFavoriteMenuItem: Equatable {
  case action(title: String, action: ModeFavoriteMenuAction)
  case submenu(title: String, items: [ModeFavoriteMenuItem])
  case separator
  case disabled(title: String)
}

enum ModeFavoriteMenuAction: Equatable {
  case saveCurrent
  case apply(name: String)
  case delete(name: String)
}

struct ModeFavoriteMenuBuilder {
  static let stableIdentityUnavailableTitle = NSLocalizedString("Stable identity unavailable", comment: "Unavailable state in Favorite Modes menu")
  static let saveCurrentTitle = NSLocalizedString("Save Current…", comment: "Save action in Favorite Modes menu")
  static let noSavedModesTitle = NSLocalizedString("No saved modes", comment: "Empty state in Favorite Modes menu")
  static let applyTitle = NSLocalizedString("Apply", comment: "Apply submenu in Favorite Modes menu")
  static let deleteTitle = NSLocalizedString("Delete", comment: "Delete submenu in Favorite Modes menu")

  static func items(favorites: [ModeFavorite], identityAvailable: Bool = true) -> [ModeFavoriteMenuItem] {
    guard identityAvailable else {
      return [.disabled(title: stableIdentityUnavailableTitle)]
    }
    let sortedFavorites = favorites.sorted {
      $0.normalizedName == $1.normalizedName ? $0.name < $1.name : $0.normalizedName < $1.normalizedName
    }
    guard !sortedFavorites.isEmpty else {
      return [
        .action(title: saveCurrentTitle, action: .saveCurrent),
        .separator,
        .disabled(title: noSavedModesTitle),
      ]
    }
    return [
      .action(title: saveCurrentTitle, action: .saveCurrent),
      .separator,
      .submenu(title: applyTitle, items: sortedFavorites.map { .action(title: $0.name, action: .apply(name: $0.name)) }),
      .submenu(title: deleteTitle, items: sortedFavorites.map { .action(title: $0.name, action: .delete(name: $0.name)) }),
    ]
  }
}
