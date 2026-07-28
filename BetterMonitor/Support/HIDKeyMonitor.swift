//  Copyright © BetterMonitor.

import Foundation
import IOKit.hid
import MediaKeyTap
import os.log

/// Internal seam over the `IOHIDManager` C API surface `HIDKeyMonitor` relies on.
/// Production code uses `.live`, which forwards to the real IOKit calls unchanged;
/// tests inject a fake to exercise the lifecycle deterministically without hardware.
struct HIDKeyMonitorDriver {
  var createManager: () -> IOHIDManager?
  var setDeviceMatchingMultiple: (IOHIDManager, [[String: Any]]) -> Void
  var registerInputValueCallback: (IOHIDManager, IOHIDValueCallback?, UnsafeMutableRawPointer?) -> Void
  var scheduleWithRunLoop: (IOHIDManager, CFRunLoop, CFString) -> Void
  var unscheduleFromRunLoop: (IOHIDManager, CFRunLoop, CFString) -> Void
  var open: (IOHIDManager) -> IOReturn
  var close: (IOHIDManager) -> Void

  static let live = HIDKeyMonitorDriver(
    createManager: { IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone)) },
    setDeviceMatchingMultiple: { IOHIDManagerSetDeviceMatchingMultiple($0, $1 as CFArray) },
    registerInputValueCallback: { IOHIDManagerRegisterInputValueCallback($0, $1, $2) },
    scheduleWithRunLoop: { IOHIDManagerScheduleWithRunLoop($0, $1, $2) },
    unscheduleFromRunLoop: { IOHIDManagerUnscheduleFromRunLoop($0, $1, $2) },
    open: { IOHIDManagerOpen($0, IOOptionBits(kIOHIDOptionsTypeNone)) },
    close: { IOHIDManagerClose($0, IOOptionBits(kIOHIDOptionsTypeNone)) }
  )
}

/// Monitors HID consumer usage page events directly from USB/Bluetooth keyboards.
/// This catches brightness/volume keys from non-Apple keyboards that macOS
/// doesn't translate to NX_KEYTYPE system events (which MediaKeyTap relies on).
class HIDKeyMonitor {
  private var manager: IOHIDManager?
  /// Retained callback context, balanced exactly once in `stop()` (never inside the callback).
  private var callbackContext: UnsafeMutableRawPointer?
  private let driver: HIDKeyMonitorDriver
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

  init(driver: HIDKeyMonitorDriver = .live) {
    self.driver = driver
  }

  func start() {
    guard manager == nil else { return }
    manager = driver.createManager()
    guard let manager = manager else {
      os_log("HIDKeyMonitor: failed to create IOHIDManager", type: .error)
      return
    }

    // Match keyboards (usage page 0x01, usage 0x06) and consumer devices (usage page 0x0C)
    let matchingCriteria: [[String: Any]] = [
      [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard],
      [kIOHIDDeviceUsagePageKey: kHIDPage_Consumer, kIOHIDDeviceUsageKey: kHIDUsage_Csmr_ConsumerControl],
    ]
    driver.setDeviceMatchingMultiple(manager, matchingCriteria)

    let callback: IOHIDValueCallback = { context, _, _, value in
      guard let context = context else { return }
      let monitor = Unmanaged<HIDKeyMonitor>.fromOpaque(context).takeUnretainedValue()
      monitor.handleHIDValue(value)
    }

    // Retain self for as long as the callback is registered so the context can
    // never target a released monitor. The retain is balanced once in stop().
    let context = Unmanaged.passRetained(self).toOpaque()
    driver.registerInputValueCallback(manager, callback, context)
    self.callbackContext = context
    driver.scheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    let result = driver.open(manager)
    if result == kIOReturnSuccess {
      os_log("HIDKeyMonitor: started monitoring HID consumer keys", type: .info)
    } else {
      os_log("HIDKeyMonitor: failed to open IOHIDManager (0x%{public}08x)", type: .error, result)
      self.stop()
    }
  }

  func stop() {
    guard let manager = manager else { return }
    // Unregister and unschedule before closing so no in-flight callback can
    // fire against a closed manager, and balance the retained context exactly once.
    driver.registerInputValueCallback(manager, nil, nil)
    driver.unscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    driver.close(manager)
    self.manager = nil
    if let context = self.callbackContext {
      Unmanaged<HIDKeyMonitor>.fromOpaque(context).release()
      self.callbackContext = nil
    }
    os_log("HIDKeyMonitor: stopped", type: .info)
  }

  deinit {
    self.stop()
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
