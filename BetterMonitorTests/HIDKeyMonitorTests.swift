//  Copyright © BetterMonitor. @JoniVR, @theOneyouseek, @waydabber and others

@testable import BetterMonitor
import XCTest

/// Lifecycle tests for HIDKeyMonitor: ownership and shutdown safety are the
/// observable contract — no callback may target a released monitor, the
/// retained callback context must be balanced exactly once, and stop() must be
/// safe to call in any state. (Opening the HID manager can fail without input
/// monitoring permission, e.g. on CI; both outcomes must stay safe.)
class HIDKeyMonitorTests: XCTestCase {

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
}
