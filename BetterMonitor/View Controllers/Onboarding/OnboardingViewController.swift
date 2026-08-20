//  Copyright © BetterMonitor. @JoniVR, @theOneyouseek, @waydabber and others

import Cocoa

class OnboardingViewController: NSViewController {
  @IBOutlet private var permissionsButton: NSButton!

  override func viewDidLoad() {
    super.viewDidLoad()
    self.setPermissionsButtonState()
  }

  // MARK: - Actions

  @IBAction func toggleStartAtLoginTouched(_ sender: NSButton) {
    app.setStartAtLogin(enabled: sender.state == .on)
  }

  @IBAction func askForPermissionsButtonTouched(_: NSButton) {
    app.requestAccessibilityAccessFromOnboarding()
  }

  @IBAction func closeButtonTouched(_: NSButton) {
    self.view.window?.close()
  }

  // MARK: - Style

  private func setPermissionsButtonState() {
    let enabled: Bool = app.mediaKeyControlsRequireAccessibility() && !app.mediaKeyTap.accessibilityStatus()
    self.permissionsButton.image = enabled ? nil : NSImage(named: "onboarding_icon_checkmark")
  }
}
