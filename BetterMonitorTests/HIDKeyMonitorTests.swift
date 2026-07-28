//  Copyright © BetterMonitor. @JoniVR, @theOneyouseek, @waydabber and others

@testable import BetterMonitor
import IOKit.hid
import XCTest

/// Lifecycle tests for HIDKeyMonitor: ownership and shutdown safety are the
/// observable contract — no callback may target a released monitor, the
/// retained callback context must be balanced exactly once, and stop() must be
/// safe to call in any state. The deterministic tests inject a fake
/// HIDKeyMonitorDriver so they never depend on live Input Monitoring
/// permission or hardware.
class HIDKeyMonitorTests: XCTestCase {

  /// Records every driver call without touching hardware. `createManager`
  /// returns a real IOHIDManager object solely so the monitor holds a valid
  /// opaque handle; no IOKit call is ever made against it.
  private final class FakeHIDKeyMonitorDriver {
    var openResult: IOReturn = kIOReturnSuccess
    private(set) var createCount = 0
    private(set) var matchingCount = 0
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var scheduleCount = 0
    private(set) var unscheduleCount = 0
    private(set) var openCount = 0
    private(set) var closeCount = 0
    private(set) var capturedCallback: IOHIDValueCallback?
    private(set) var capturedContext: UnsafeMutableRawPointer?

    func makeDriver() -> HIDKeyMonitorDriver {
      HIDKeyMonitorDriver(
        createManager: {
          self.createCount += 1
          return IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        },
        setDeviceMatchingMultiple: { _, _ in self.matchingCount += 1 },
        registerInputValueCallback: { _, callback, context in
          if callback == nil {
            self.unregisterCount += 1
          } else {
            self.registerCount += 1
            self.capturedCallback = callback
            self.capturedContext = context
          }
        },
        scheduleWithRunLoop: { _, _, _ in self.scheduleCount += 1 },
        unscheduleFromRunLoop: { _, _, _ in self.unscheduleCount += 1 },
        open: { _ in
          self.openCount += 1
          return self.openResult
        },
        close: { _ in self.closeCount += 1 }
      )
    }
  }

  func testStopWithoutStartIsSafe() {
    let monitor = HIDKeyMonitor()
    monitor.stop()
    monitor.stop()
  }

  func testRepeatedStartStopCyclesAreSafe() {
    let monitor = HIDKeyMonitor()
    for _ in 0 ..< 3 {
      monitor.start()
      monitor.start() // second start while running must not double-register
      monitor.stop()
      monitor.stop() // second stop must not double-release the callback context
    }
  }

  func testMonitorIsReleasedAfterStop() {
    weak var weakMonitor: HIDKeyMonitor?
    autoreleasepool {
      let monitor = HIDKeyMonitor()
      weakMonitor = monitor
      monitor.start()
      // stop() unregisters the callback and balances the retained context,
      // so the monitor can be deallocated here without any dangling callback.
      monitor.stop()
    }
    XCTAssertNil(weakMonitor)
  }

  // MARK: - Deterministic lifecycle coverage via the injected driver seam

  func testSuccessfulStartRegistersCallbackExactlyOnce() {
    let fake = FakeHIDKeyMonitorDriver()
    let monitor = HIDKeyMonitor(driver: fake.makeDriver())

    monitor.start()
    XCTAssertEqual(fake.createCount, 1)
    XCTAssertEqual(fake.matchingCount, 1)
    XCTAssertEqual(fake.registerCount, 1)
    XCTAssertEqual(fake.scheduleCount, 1)
    XCTAssertEqual(fake.openCount, 1)
    XCTAssertNotNil(fake.capturedCallback)

    // While running, the retained callback context must refer to the monitor.
    let context = fake.capturedContext
    XCTAssertNotNil(context)
    XCTAssertTrue(Unmanaged<HIDKeyMonitor>.fromOpaque(context!).takeUnretainedValue() === monitor)

    // A repeated start while running must not double-register.
    monitor.start()
    XCTAssertEqual(fake.createCount, 1)
    XCTAssertEqual(fake.registerCount, 1)

    monitor.stop()
  }

  func testStopCleansUpOnceAndReleasesOwnership() {
    let fake = FakeHIDKeyMonitorDriver()
    weak var weakMonitor: HIDKeyMonitor?
    autoreleasepool {
      let monitor = HIDKeyMonitor(driver: fake.makeDriver())
      weakMonitor = monitor
      monitor.start()
      XCTAssertEqual(fake.registerCount, 1)

      monitor.stop()
      XCTAssertEqual(fake.unregisterCount, 1)
      XCTAssertEqual(fake.unscheduleCount, 1)
      XCTAssertEqual(fake.closeCount, 1)

      // A repeated stop must not repeat cleanup or release the context again.
      monitor.stop()
      XCTAssertEqual(fake.unregisterCount, 1)
      XCTAssertEqual(fake.unscheduleCount, 1)
      XCTAssertEqual(fake.closeCount, 1)
    }
    // stop() balanced the retained callback context, so the monitor is gone.
    // (The captured opaque context is not dereferenced here: it was released.)
    XCTAssertNil(weakMonitor)
  }

  func testForcedOpenFailureCleansUpDeterministically() {
    let fake = FakeHIDKeyMonitorDriver()
    fake.openResult = kIOReturnNotPermitted
    weak var weakMonitor: HIDKeyMonitor?
    autoreleasepool {
      let monitor = HIDKeyMonitor(driver: fake.makeDriver())
      weakMonitor = monitor
      monitor.start()
      XCTAssertEqual(fake.openCount, 1)
      XCTAssertEqual(fake.registerCount, 1)
      // The failed open must fall back to the same single cleanup as stop().
      XCTAssertEqual(fake.unregisterCount, 1)
      XCTAssertEqual(fake.unscheduleCount, 1)
      XCTAssertEqual(fake.closeCount, 1)
    }
    XCTAssertNil(weakMonitor)
  }
}
