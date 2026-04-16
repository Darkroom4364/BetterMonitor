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
      return [["error": "Invalid property. Use: brightness, volume, contrast"]]
    }
    let displays = resolveDisplays(userInfo: userInfo)
    if displays.isEmpty {
      return [["error": "No matching display found"]]
    }
    return displays.map { display in
      switch property {
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
      case .input:
        guard let otherDisplay = display as? OtherDisplay else {
          return ["name": display.name, "error": "Property not available for Apple displays"]
        }
        return [
          "name": display.name,
          "id": display.identifier,
          "input": otherDisplay.readPrefAsInt(for: .inputSelect),
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
        guard let otherDisplay = display as? OtherDisplay else {
          return ["name": display.name, "error": "Property not available for Apple displays"]
        }
        if otherDisplay.isSw() {
          success = false
        } else {
          otherDisplay.writeDDCValues(command: .inputSelect, value: UInt16(valueInt))
          otherDisplay.savePref(valueInt, for: .inputSelect)
          otherDisplay.inputSourceHandler?.setSelectedInput(UInt16(valueInt))
        }
      }
      var result: [String: Any] = [
        "name": display.name,
        "id": display.identifier,
      ]
      if property == .input {
        result[property.rawValue] = valueInt
      } else {
        result[property.rawValue] = Int(round(floatValue * 100))
      }
      if !success {
        result["error"] = "Failed to set \(property.rawValue) — DDC unavailable or software-only display"
      }
      return result
    }
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
