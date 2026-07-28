//  Copyright © BetterMonitor. @victorchabbert, @JoniVR, @theOneyouseek, @waydabber and others

import Cocoa

class OSDUtils: NSObject {
  enum OSDImage: Int64 {
    case brightness = 1
    case audioSpeaker = 3
    case audioSpeakerMuted = 4
    case contrast = 0
  }

  static func getOSDImageByCommand(command: Command, value: Float = 1) -> OSDImage {
    var osdImage: OSDImage
    switch command {
    case .audioSpeakerVolume: osdImage = value > 0 ? .audioSpeaker : .audioSpeakerMuted
    case .audioMuteScreenBlank: osdImage = .audioSpeakerMuted
    case .contrast: osdImage = .contrast
    default: osdImage = .brightness
    }
    return osdImage
  }

  static func showOsd(displayID: CGDirectDisplayID, command: Command, value: Float, maxValue: Float = 1, roundChiclet: Bool = false, lock: Bool = false) {
    if TahoeHUD.shouldUseCustomHUD {
      let osdImage = self.getOSDImageByCommand(command: command, value: value)
      let progress: Float
      if roundChiclet {
        progress = TahoeHUD.normalizedProgress(value: Float(round(OSDUtils.chiclet(fromValue: value, maxValue: maxValue))), maxValue: OSDUtils.chicletCount)
      } else {
        progress = TahoeHUD.normalizedProgress(value: value, maxValue: maxValue)
      }
      TahoeHUD.show(displayID: displayID, kind: TahoeHUD.kind(for: osdImage), progress: progress)
      return
    }
    guard let manager = OSDManager.sharedManager() as? OSDManager else {
      return
    }
    let osdImage = self.getOSDImageByCommand(command: command, value: value)
    let filledChiclets: Int
    let totalChiclets: Int
    if roundChiclet {
      let osdChiclet = OSDUtils.chiclet(fromValue: value, maxValue: maxValue)
      filledChiclets = Int(round(osdChiclet))
      totalChiclets = 16
    } else {
      filledChiclets = Int(value * 100)
      totalChiclets = Int(maxValue * 100)
    }
    manager.showImage(osdImage.rawValue, onDisplayID: displayID, priority: 0x1F4, msecUntilFade: 1000, filledChiclets: UInt32(filledChiclets), totalChiclets: UInt32(totalChiclets), locked: lock)
  }

  static func showOsdVolumeDisabled(displayID: CGDirectDisplayID) {
    if TahoeHUD.shouldUseCustomHUD {
      TahoeHUD.show(displayID: displayID, kind: .volume, progress: 0, disabled: true)
      return
    }
    guard let manager = OSDManager.sharedManager() as? OSDManager else {
      return
    }
    manager.showImage(22, onDisplayID: displayID, priority: 0x1F4, msecUntilFade: 1000)
  }

  static func showOsdMuteDisabled(displayID: CGDirectDisplayID) {
    if TahoeHUD.shouldUseCustomHUD {
      TahoeHUD.show(displayID: displayID, kind: .mutedVolume, progress: 0, disabled: true)
      return
    }
    guard let manager = OSDManager.sharedManager() as? OSDManager else {
      return
    }
    manager.showImage(21, onDisplayID: displayID, priority: 0x1F4, msecUntilFade: 1000)
  }

  static func popEmptyOsd(displayID: CGDirectDisplayID, command: Command) {
    if TahoeHUD.shouldUseCustomHUD {
      TahoeHUD.show(displayID: displayID, kind: TahoeHUD.kind(for: self.getOSDImageByCommand(command: command)), progress: 0)
      return
    }
    guard let manager = OSDManager.sharedManager() as? OSDManager else {
      return
    }
    let osdImage = self.getOSDImageByCommand(command: command)
    manager.showImage(osdImage.rawValue, onDisplayID: displayID, priority: 0x1F4, msecUntilFade: 0)
  }

  static let chicletCount: Float = 16

  static func chiclet(fromValue value: Float, maxValue: Float, half: Bool = false) -> Float {
    (value * self.chicletCount * (half ? 2 : 1)) / maxValue
  }

  static func value(fromChiclet chiclet: Float, maxValue: Float, half: Bool = false) -> Float {
    (chiclet * maxValue) / (self.chicletCount * (half ? 2 : 1))
  }

  static func getDistance(fromNearestChiclet chiclet: Float) -> Float {
    abs(chiclet.rounded(.towardZero) - chiclet)
  }
}
