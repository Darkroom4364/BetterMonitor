//  Copyright © BetterMonitor.

import AppKit
import os.log

class InputSourceHandler {
  let display: OtherDisplay
  let title: String
  var view: NSView?

  static let inputSources: [(name: String, value: UInt16)] = [
    ("HDMI 1", 5),
    ("HDMI 2", 6),
    ("DisplayPort", 4),
    ("USB-C", 9),
    ("VGA", 1),
    ("DVI", 3),
    ("Mini DisplayPort", 10),
    ("Thunderbolt", 16),
  ]

  private var popup: NSPopUpButton?

  init(display: OtherDisplay, title: String) {
    self.display = display
    self.title = title

    let containerWidth: CGFloat = 260
    let containerHeight: CGFloat = 30
    let container = NSView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: containerHeight))

    let icon = NSImageView(frame: NSRect(x: 13, y: 5, width: 18, height: 18))
    if #available(macOS 11.0, *) {
      icon.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "Input Source")
    }
    icon.imageScaling = .scaleProportionallyUpOrDown
    container.addSubview(icon)

    let popupButton = NSPopUpButton(frame: NSRect(x: 35, y: 2, width: containerWidth - 48, height: 24), pullsDown: false)
    popupButton.controlSize = .small
    popupButton.font = NSFont.systemFont(ofSize: 11)
    for source in Self.inputSources {
      popupButton.addItem(withTitle: source.name)
      popupButton.lastItem?.tag = Int(source.value)
    }

    let savedValue = display.readPrefAsInt(for: .inputSelect)
    if savedValue > 0, let index = Self.inputSources.firstIndex(where: { $0.value == UInt16(savedValue) }) {
      popupButton.selectItem(at: index)
    }

    popupButton.target = self
    popupButton.action = #selector(inputSourceChanged(_:))
    container.addSubview(popupButton)
    self.popup = popupButton
    self.view = container
  }

  @objc func inputSourceChanged(_ sender: NSPopUpButton) {
    guard let selectedItem = sender.selectedItem else { return }
    let ddcValue = UInt16(selectedItem.tag)
    os_log("Input source switch: %{public}@ (DDC value %{public}@) on %{public}@", type: .info, selectedItem.title, String(ddcValue), display.name)
    display.writeDDCValues(command: .inputSelect, value: ddcValue)
    display.savePref(Int(ddcValue), for: .inputSelect)
  }

  func setSelectedInput(_ value: UInt16) {
    if let index = Self.inputSources.firstIndex(where: { $0.value == value }) {
      popup?.selectItem(at: index)
    }
  }
}
