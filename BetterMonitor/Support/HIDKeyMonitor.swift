//  Copyright © BetterMonitor.

import Foundation
import IOKit.hid
import MediaKeyTap
import os.log

/// Monitors HID consumer usage page events directly from USB/Bluetooth keyboards.
/// This catches brightness/volume keys from non-Apple keyboards that macOS
/// doesn't translate to NX_KEYTYPE system events (which MediaKeyTap relies on).
class HIDKeyMonitor {
  private var manager: IOHIDManager?
  weak var delegate: MediaKeyTapDelegate?

  // HID Consumer Usage IDs
  private static let usageBrightnessUp: Int = 0x6F
  private static let usageBrightnessDown: Int = 0x70
  private static let usageVolumeUp: Int = 0xE9
  private static let usageVolumeDown: Int = 0xEA
  private static let usageMute: Int = 0xE2

  private static let monitoredUsages: Set<Int> = [
    usageBrightnessUp, usageBrightnessDown,
    usageVolumeUp, usageVolumeDown, usageMute,
  ]

  func start() {
    guard manager == nil else { return }
    manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    guard let manager = manager else {
      os_log("HIDKeyMonitor: failed to create IOHIDManager", type: .error)
      return
    }

    // Match keyboards (usage page 0x01, usage 0x06) and consumer devices (usage page 0x0C)
    let matchingCriteria: [[String: Any]] = [
      [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard],
      [kIOHIDDeviceUsagePageKey: kHIDPage_Consumer, kIOHIDDeviceUsageKey: kHIDUsage_Csmr_ConsumerControl],
    ]
    IOHIDManagerSetDeviceMatchingMultiple(manager, matchingCriteria as CFArray)

    let callback: IOHIDValueCallback = { context, _, _, value in
      guard let context = context else { return }
      let monitor = Unmanaged<HIDKeyMonitor>.fromOpaque(context).takeUnretainedValue()
      monitor.handleHIDValue(value)
    }

    IOHIDManagerRegisterInputValueCallback(manager, callback, Unmanaged.passUnretained(self).toOpaque())
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    if result == kIOReturnSuccess {
      os_log("HIDKeyMonitor: started monitoring HID consumer keys", type: .info)
    } else {
      os_log("HIDKeyMonitor: failed to open IOHIDManager (0x%{public}08x)", type: .error, result)
    }
  }

  func stop() {
    guard let manager = manager else { return }
    IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    self.manager = nil
    os_log("HIDKeyMonitor: stopped", type: .info)
  }

  private func handleHIDValue(_ value: IOHIDValue) {
    let element = IOHIDValueGetElement(value)
    let usagePage = Int(IOHIDElementGetUsagePage(element))
    let usage = Int(IOHIDElementGetUsage(element))
    let intValue = IOHIDValueGetIntegerValue(value)

    guard usagePage == kHIDPage_Consumer, Self.monitoredUsages.contains(usage), intValue == 1 else {
      return
    }

    let mediaKey: MediaKey?
    switch usage {
    case Self.usageBrightnessUp: mediaKey = .brightnessUp
    case Self.usageBrightnessDown: mediaKey = .brightnessDown
    case Self.usageVolumeUp: mediaKey = .volumeUp
    case Self.usageVolumeDown: mediaKey = .volumeDown
    case Self.usageMute: mediaKey = .mute
    default: mediaKey = nil
    }

    guard let key = mediaKey else { return }
    os_log("HIDKeyMonitor: consumer key detected — usage=0x%{public}02x (%{public}@)", type: .debug, usage, String(describing: key))

    DispatchQueue.main.async { [weak self] in
      self?.delegate?.handle(mediaKey: key, event: nil, modifiers: nil)
    }
  }
}
