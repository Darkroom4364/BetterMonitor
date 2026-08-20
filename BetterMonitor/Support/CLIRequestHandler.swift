//  Copyright © BetterMonitor. @JoniVR, @theOneyouseek, @waydabber and others

import Foundation
import os.log

private extension CLIProperty {
  var command: Command {
    switch self {
    case .brightness: return .brightness
    case .volume: return .audioSpeakerVolume
    case .contrast: return .contrast
    case .input: return .inputSelect
    }
  }
}


class CLIRequestHandler {
  private let modeCatalog = ModeCatalog(reader: CoreGraphicsModeFavoriteController())

  init() {
    DistributedNotificationCenter.default().addObserver(
      self,
      selector: #selector(handleRequest(_:)),
      name: NSNotification.Name(CLINotification.request),
      object: nil,
      suspensionBehavior: .deliverImmediately
    )
    os_log("CLI request handler initialized.", type: .info)
  }

  deinit {
    DistributedNotificationCenter.default().removeObserver(self)
  }

  @objc private func handleRequest(_ notification: Notification) {
    guard let userInfo = notification.userInfo,
          let actionString = userInfo[CLIKey.action] as? String,
          let action = CLIAction(rawValue: actionString),
          let replyId = userInfo[CLIKey.replyId] as? String,
          UUID(uuidString: replyId) != nil
    else {
      return
    }
    DispatchQueue.main.async {
      let result: [[String: Any]]
      switch action {
      case .list:
        result = self.handleList()
      case .get:
        result = self.handleGet(userInfo: userInfo)
      case .set:
        result = self.handleSet(userInfo: userInfo)
      case .modeList:
        result = self.handleModeList(userInfo: userInfo)
      case .modeFavoriteList, .modeFavoriteSave, .modeFavoriteApply, .modeFavoriteDelete:
        result = self.handleModeFavorite(action: action, userInfo: userInfo)
      }
      let hasErrors = result.contains { $0["error"] != nil }
      self.postReply(replyId: replyId, result: ["success": !hasErrors, "data": result])
    }
  }


  private func handleList() -> [[String: Any]] {
    DisplayManager.shared.getAllDisplays().map { display in
      var info: [String: Any] = [
        "id": display.identifier,
        "name": display.name,
        "brightness": Int(round(display.getBrightness() * 100)),
      ]
      if let otherDisplay = display as? OtherDisplay {
        info["type"] = otherDisplay.isSw() ? "software" : "ddc"
        info["volume"] = Int(round(otherDisplay.readPrefAsFloat(for: .audioSpeakerVolume) * 100))
        info["contrast"] = Int(round(otherDisplay.readPrefAsFloat(for: .contrast) * 100))
      } else if display is AppleDisplay {
        info["type"] = "apple"
      }
      return info
    }
  }

  private func handleGet(userInfo: [AnyHashable: Any]) -> [[String: Any]] {
    guard let propertyString = userInfo[CLIKey.property] as? String,
          let property = CLIProperty(rawValue: propertyString)
    else {
      return [["error": "Invalid property. Use: brightness, volume, contrast, input"]]
    }
    let displays = resolveDisplays(userInfo: userInfo)
    if displays.isEmpty {
      return [["error": "No matching display found"]]
    }
    return displays.map { display in
      switch property {
      case .input:
        guard let otherDisplay = display as? OtherDisplay,
              !otherDisplay.isSw(),
              let input = otherDisplay.readDDCValues(for: property.command, tries: 1, minReplyDelay: nil)?.current
        else {
          return ["name": display.name, "error": "Input source is unavailable — DDC unavailable, software-only, or unsupported"]
        }
        return [
          "name": display.name,
          "id": display.identifier,
          property.rawValue: DDCInputSource.label(for: input),
          "inputValue": Int(input),
        ] as [String: Any]
      case .brightness:
        return [
          "name": display.name,
          "id": display.identifier,
          property.rawValue: Int(round(display.getBrightness() * 100)),
        ] as [String: Any]
      case .volume, .contrast:
        guard let otherDisplay = display as? OtherDisplay else {
          return ["name": display.name, "error": "Property not available for Apple displays"]
        }
        return [
          "name": display.name,
          "id": display.identifier,
          property.rawValue: Int(round(otherDisplay.readPrefAsFloat(for: property.command) * 100)),
        ] as [String: Any]
      }
    }
  }

  private func handleSet(userInfo: [AnyHashable: Any]) -> [[String: Any]] {
    guard let propertyString = userInfo[CLIKey.property] as? String,
          let property = CLIProperty(rawValue: propertyString),
          let valueInt = userInfo[CLIKey.value] as? Int
    else {
      return [["error": "Invalid property or value"]]
    }
    if property == .input {
      return handleSetInput(userInfo: userInfo, value: valueInt)
    }
    let floatValue = max(0, min(1, Float(valueInt) / 100.0))
    let displays = resolveDisplays(userInfo: userInfo)
    if displays.isEmpty {
      return [["error": "No matching display found"]]
    }
    return displays.map { display in
      var success = true
      switch property {
      case .brightness:
        success = display.setBrightness(floatValue)
        if success, let slider = display.sliderHandler[.brightness] {
          slider.setValue(floatValue, displayID: display.identifier)
        }
      case .volume:
        guard let otherDisplay = display as? OtherDisplay else {
          return ["name": display.name, "error": "Property not available for Apple displays"]
        }
        if otherDisplay.readPrefAsBool(key: .unavailableDDC, for: .audioSpeakerVolume) || otherDisplay.isSw() {
          success = false
        } else {
          otherDisplay.writeDDCValues(command: .audioSpeakerVolume, value: otherDisplay.convValueToDDC(for: .audioSpeakerVolume, from: floatValue))
          otherDisplay.savePref(floatValue, for: .audioSpeakerVolume)
          if let slider = otherDisplay.sliderHandler[.audioSpeakerVolume] {
            slider.setValue(floatValue, displayID: otherDisplay.identifier)
          }
        }
      case .contrast:
        guard let otherDisplay = display as? OtherDisplay else {
          return ["name": display.name, "error": "Property not available for Apple displays"]
        }
        if otherDisplay.readPrefAsBool(key: .unavailableDDC, for: .contrast) || otherDisplay.isSw() {
          success = false
        } else {
          otherDisplay.writeDDCValues(command: .contrast, value: otherDisplay.convValueToDDC(for: .contrast, from: floatValue))
          otherDisplay.savePref(floatValue, for: .contrast)
          if let slider = otherDisplay.sliderHandler[.contrast] {
            slider.setValue(floatValue, displayID: otherDisplay.identifier)
          }
        }
      case .input:
        fatalError("Input source is handled before brightness conversion")
      }
      var result: [String: Any] = [
        "name": display.name,
        "id": display.identifier,
        property.rawValue: Int(round(floatValue * 100)),
      ]
      if !success {
        result["error"] = "Failed to set \(property.rawValue) — DDC unavailable or software-only display"
      }
      return result
    }
  }

  private func handleSetInput(userInfo: [AnyHashable: Any], value: Int) -> [[String: Any]] {
    guard let input = UInt16(exactly: value),
          input > 0, input <= UInt16(UInt8.max)
    else {
      return [["error": "Invalid DDC input source value"]]
    }
    let hasDisplayId = userInfo[CLIKey.displayId] is NSNumber
    let hasDisplayName = !(userInfo[CLIKey.displayName] as? String ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    guard hasDisplayId || hasDisplayName else {
      return [["error": "Input source changes require --display <name-or-id>"]]
    }
    let displays = resolveDisplays(userInfo: userInfo)
    guard displays.count == 1 else {
      return [[
        "error": displays.isEmpty
          ? "No matching display found"
          : "Input source changes require exactly one matching display",
      ]]
    }
    guard let otherDisplay = displays[0] as? OtherDisplay,
          !otherDisplay.isSw(),
          !otherDisplay.readPrefAsBool(key: .unavailableDDC, for: .inputSelect),
          otherDisplay.queueInputSource(input)
    else {
      return [["name": displays[0].name, "error": "Input source is unavailable — DDC unavailable or software-only display"]]
    }
    return [[
      "name": otherDisplay.name,
      "id": otherDisplay.identifier,
      "input": DDCInputSource.label(for: input),
      "inputValue": Int(input),
      "queued": true,
    ]]
  }

  private func handleModeList(userInfo: [AnyHashable: Any]) -> [[String: Any]] {
    let targets = DisplayManager.shared.getAllDisplays().map {
      ModeCatalogTarget(identifier: $0.identifier, name: $0.name)
    }
    return ModeCatalogRequestProcessor(catalog: self.modeCatalog).handle(userInfo: userInfo, targets: targets)
  }

  private func handleModeFavorite(action: CLIAction, userInfo: [AnyHashable: Any]) -> [[String: Any]] {
    let targets = DisplayManager.shared.getAllDisplays().map {
      ModeFavoriteDisplayTarget(
        identifier: $0.identifier,
        name: $0.name,
        vendorNumber: $0.vendorNumber,
        modelNumber: $0.modelNumber,
        serialNumber: $0.serialNumber,
        searchNames: [$0.readPrefAsString(key: .friendlyName)]
      )
    }
    let targetResult = ModeFavoriteTargetResolver.resolve(userInfo: userInfo, targets: targets)
    return ModeFavoriteCLIProcessor(onSuccessfulMutation: {
      menu.updateMenus(dontClose: true)
    }).handle(
      action: action,
      name: userInfo[CLIKey.favoriteName] as? String,
      targetResult: targetResult
    )
  }

  private func resolveDisplays(userInfo: [AnyHashable: Any]) -> [Display] {
    let allDisplays = DisplayManager.shared.getAllDisplays()
    if let displayIdNumber = userInfo[CLIKey.displayId] as? NSNumber {
      let displayId = UInt32(displayIdNumber.uint32Value)
      return allDisplays.filter { $0.identifier == displayId }
    }
    if let displayName = userInfo[CLIKey.displayName] as? String,
       !displayName.trimmingCharacters(in: .whitespaces).isEmpty {
      let lowered = displayName.lowercased()
      return allDisplays.filter {
        $0.name.lowercased().contains(lowered) ||
          $0.readPrefAsString(key: .friendlyName).lowercased().contains(lowered)
      }
    }
    return allDisplays
  }

  private func postReply(replyId: String, result: [String: Any]) {
    guard let jsonData = try? JSONSerialization.data(withJSONObject: result),
          let jsonString = String(data: jsonData, encoding: .utf8)
    else {
      os_log("CLI reply serialization failed for replyId: %{public}@", type: .error, replyId)
      return
    }
    DistributedNotificationCenter.default().postNotificationName(
      NSNotification.Name(CLINotification.replyPrefix + replyId),
      object: nil,
      userInfo: ["result": jsonString],
      deliverImmediately: true
    )
  }
}
