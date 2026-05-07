//  Copyright © BetterMonitor.

import AppKit
import os.log

class InputSourceHandler {
  let display: OtherDisplay
  let title: String
  var view: NSView?

  // MCCS VCP 0x60 standard values. USB-C/Thunderbolt values are vendor-specific.
  static let inputSources: [(name: String, value: UInt16)] = [
    ("HDMI 1", 0x11),
    ("HDMI 2", 0x12),
    ("DisplayPort 1", 0x0f),
    ("DisplayPort 2", 0x10),
    ("VGA 1", 0x01),
    ("VGA 2", 0x02),
    ("DVI 1", 0x03),
    ("DVI 2", 0x04),
  ]

  private var popup: NSPopUpButton?

  private static func customTitle(for value: UInt16) -> String {
    String(format: "Custom (0x%02X)", value)
  }

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
    if let savedInputValue = CLIInputSource.uint16Value(savedValue) {
      if let index = Self.inputSources.firstIndex(where: { $0.value == savedInputValue }) {
        popupButton.selectItem(at: index)
      } else {
        popupButton.addItem(withTitle: Self.customTitle(for: savedInputValue))
        popupButton.lastItem?.tag = Int(savedInputValue)
        popupButton.selectItem(at: popupButton.numberOfItems - 1)
      }
    }

    popupButton.target = self
    popupButton.action = #selector(inputSourceChanged(_:))
    container.addSubview(popupButton)
    self.popup = popupButton
    self.view = container
  }

  @objc func inputSourceChanged(_ sender: NSPopUpButton) {
    guard let selectedItem = sender.selectedItem,
          let ddcValue = CLIInputSource.uint16Value(selectedItem.tag)
    else {
      return
    }
    os_log("Input source switch: %{public}@ (DDC value %{public}@) on %{public}@", type: .info, selectedItem.title, String(ddcValue), display.name)
    display.writeDDCValues(command: .inputSelect, value: ddcValue)
    display.savePref(Int(ddcValue), for: .inputSelect)
  }

  func setSelectedInput(_ value: UInt16) {
    if let index = Self.inputSources.firstIndex(where: { $0.value == value }) {
      popup?.selectItem(at: index)
    } else if let popup = popup {
      if !popup.itemArray.contains(where: { $0.tag == Int(value) }) {
        popup.addItem(withTitle: Self.customTitle(for: value))
        popup.lastItem?.tag = Int(value)
      }
      popup.selectItem(withTag: Int(value))
    }
  }
}
