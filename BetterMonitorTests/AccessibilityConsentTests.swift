//  Copyright © BetterMonitor. @JoniVR, @theOneyouseek, @waydabber and others

@testable import BetterMonitor
import Foundation
import XCTest

class AccessibilityConsentTests: XCTestCase {
  private final class FakeAccessibilityTrust {
    var statusResult: Bool
    var requestResult: Bool
    private(set) var statusCallCount = 0
    private(set) var requestCallCount = 0

    init(status: Bool = false, request: Bool = false) {
      self.statusResult = status
      self.requestResult = request
    }

    func makeDriver() -> AccessibilityTrustDriver {
      AccessibilityTrustDriver(
        status: {
          self.statusCallCount += 1
          return self.statusResult
        },
        request: {
          self.requestCallCount += 1
          return self.requestResult
        }
      )
    }
  }

  private let brightnessModes: [KeyboardBrightness] = [.media, .custom, .both, .disabled]
  private let volumeModes: [KeyboardVolume] = [.media, .custom, .both, .disabled]

  func testStatusRefreshNeverRequestsForAllTypedModePairs() {
    for brightness in self.brightnessModes {
      for volume in self.volumeModes {
        let fake = FakeAccessibilityTrust()
        let manager = MediaKeyTapManager(accessibilityTrustDriver: fake.makeDriver())
        let isNative = brightness == .media || brightness == .both || volume == .media || volume == .both

        XCTAssertFalse(AppDelegate.handleAccessibilityConsent(.statusRefresh(brightness: brightness, volume: volume), using: manager))
        XCTAssertEqual(fake.statusCallCount, isNative ? 1 : 0)
        XCTAssertEqual(fake.requestCallCount, 0)
      }
    }
  }

  func testOnboardingRequestsOnlyForEligibleTypedModePairs() {
    for brightness in self.brightnessModes {
      for volume in self.volumeModes {
        let fake = FakeAccessibilityTrust()
        let manager = MediaKeyTapManager(accessibilityTrustDriver: fake.makeDriver())
        let isNative = brightness == .media || brightness == .both || volume == .media || volume == .both

        XCTAssertEqual(
          AppDelegate.handleAccessibilityConsent(.onboarding(brightness: brightness, volume: volume), using: manager),
          isNative
        )
        XCTAssertEqual(fake.statusCallCount, isNative ? 1 : 0)
        XCTAssertEqual(fake.requestCallCount, isNative ? 1 : 0)
      }
    }
  }

  func testBrightnessSelectionRequestsOnlyForNativeModes() {
    for mode in self.brightnessModes {
      let fake = FakeAccessibilityTrust()
      let manager = MediaKeyTapManager(accessibilityTrustDriver: fake.makeDriver())
      let isNative = mode == .media || mode == .both

      XCTAssertEqual(AppDelegate.handleAccessibilityConsent(.brightnessSelection(mode), using: manager), isNative)
      XCTAssertEqual(fake.statusCallCount, isNative ? 1 : 0)
      XCTAssertEqual(fake.requestCallCount, isNative ? 1 : 0)
    }
  }

  func testVolumeSelectionRequestsOnlyForNativeModes() {
    for mode in self.volumeModes {
      let fake = FakeAccessibilityTrust()
      let manager = MediaKeyTapManager(accessibilityTrustDriver: fake.makeDriver())
      let isNative = mode == .media || mode == .both

      XCTAssertEqual(AppDelegate.handleAccessibilityConsent(.volumeSelection(mode), using: manager), isNative)
      XCTAssertEqual(fake.statusCallCount, isNative ? 1 : 0)
      XCTAssertEqual(fake.requestCallCount, isNative ? 1 : 0)
    }
  }

  func testTrustedExplicitSelectionDoesNotRequestAccessibility() {
    let fake = FakeAccessibilityTrust(status: true)
    let manager = MediaKeyTapManager(accessibilityTrustDriver: fake.makeDriver())

    XCTAssertFalse(AppDelegate.handleAccessibilityConsent(.brightnessSelection(.both), using: manager))
    XCTAssertEqual(fake.statusCallCount, 1)
    XCTAssertEqual(fake.requestCallCount, 0)
  }

  func testDeniedSelectionDoesNotRetryDuringStatusRefresh() {
    let fake = FakeAccessibilityTrust()
    let manager = MediaKeyTapManager(accessibilityTrustDriver: fake.makeDriver())

    XCTAssertTrue(AppDelegate.handleAccessibilityConsent(.volumeSelection(.both), using: manager))
    XCTAssertFalse(AppDelegate.handleAccessibilityConsent(.statusRefresh(brightness: .disabled, volume: .both), using: manager))
    XCTAssertEqual(fake.statusCallCount, 2)
    XCTAssertEqual(fake.requestCallCount, 1)
  }

  func testPersistedSelectionSurvivesDeniedRequest() {
    let suiteName = "AccessibilityConsentTests.\(UUID().uuidString)"
    guard let preferences = UserDefaults(suiteName: suiteName) else {
      XCTFail("Could not create isolated preferences")
      return
    }
    defer {
      preferences.removePersistentDomain(forName: suiteName)
    }
    let brightness = KeyboardPrefsViewController.persistKeyboardBrightnessSelection(KeyboardBrightness.both.rawValue, in: preferences)
    let volume = KeyboardPrefsViewController.persistKeyboardVolumeSelection(KeyboardVolume.media.rawValue, in: preferences)
    let fake = FakeAccessibilityTrust()
    let manager = MediaKeyTapManager(accessibilityTrustDriver: fake.makeDriver())

    XCTAssertTrue(AppDelegate.handleAccessibilityConsent(.brightnessSelection(brightness), using: manager))
    XCTAssertEqual(preferences.integer(forKey: PrefKey.keyboardBrightness.rawValue), KeyboardBrightness.both.rawValue)
    XCTAssertEqual(preferences.integer(forKey: PrefKey.keyboardVolume.rawValue), KeyboardVolume.media.rawValue)
    XCTAssertEqual(volume, .media)
    XCTAssertEqual(fake.requestCallCount, 1)
  }

  func testInvalidPersistedSelectionsMapToDisabled() {
    let suiteName = "AccessibilityConsentTests.\(UUID().uuidString)"
    guard let preferences = UserDefaults(suiteName: suiteName) else {
      XCTFail("Could not create isolated preferences")
      return
    }
    defer {
      preferences.removePersistentDomain(forName: suiteName)
    }

    XCTAssertEqual(KeyboardPrefsViewController.persistKeyboardBrightnessSelection(-1, in: preferences), .disabled)
    XCTAssertEqual(KeyboardPrefsViewController.persistKeyboardVolumeSelection(-1, in: preferences), .disabled)
    XCTAssertEqual(preferences.integer(forKey: PrefKey.keyboardBrightness.rawValue), -1)
    XCTAssertEqual(preferences.integer(forKey: PrefKey.keyboardVolume.rawValue), -1)
    XCTAssertEqual(KeyboardPrefsViewController.persistKeyboardBrightnessSelection(0, in: preferences), .media)
    XCTAssertEqual(KeyboardPrefsViewController.persistKeyboardVolumeSelection(0, in: preferences), .media)
  }
}
