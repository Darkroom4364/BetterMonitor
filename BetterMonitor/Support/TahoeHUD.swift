//  Copyright © BetterMonitor. @JoniVR, @theOneyouseek, @waydabber and others

import Cocoa

// Custom AppKit HUD used on macOS 26+ where the private native OSD slider path is broken.
// The pure mapping/normalization/routing helpers are kept free of AppKit window state so they stay unit-testable.
enum TahoeHUD {
  enum Kind {
    case brightness
    case volume
    case mutedVolume
    case contrast

    var symbolName: String {
      switch self {
      case .brightness: return "sun.max.fill"
      case .volume: return "speaker.wave.2.fill"
      case .mutedVolume: return "speaker.slash.fill"
      case .contrast: return "circle.lefthalf.filled"
      }
    }

    // Tahoe ships these three OSD artwork files; contrast has no equivalent system asset.
    var stockOSDAssetName: String? {
      switch self {
      case .brightness: return "Brightness"
      case .volume: return "Volume"
      case .mutedVolume: return "Mute"
      case .contrast: return nil
      }
    }
  }

  static let chicletCount = 16

  // Keep Apple-owned artwork on the host rather than copying private OS assets into the app.
  // Failure to load any asset deliberately falls back to the matching SF Symbol.
  private static let stockOSDResourceURL = URL(fileURLWithPath: "/System/Library/CoreServices/OSDUIHelper.app/Contents/Resources", isDirectory: true)
  private static let stockOSDImages: [String: NSImage] = {
    var images = [String: NSImage]()
    for name in ["Brightness", "Volume", "Mute"] {
      guard let image = NSImage(contentsOf: TahoeHUD.stockOSDResourceURL.appendingPathComponent("\(name).pdf")) else {
        continue
      }
      image.isTemplate = true
      images[name] = image
    }
    return images
  }()

  static func stockIcon(for kind: Kind) -> NSImage? {
    guard let assetName = kind.stockOSDAssetName else {
      return nil
    }
    return self.stockOSDImages[assetName]
  }

  static func kind(for osdImage: OSDUtils.OSDImage) -> Kind {
    switch osdImage {
    case .brightness: return .brightness
    case .audioSpeaker: return .volume
    case .audioSpeakerMuted: return .mutedVolume
    case .contrast: return .contrast
    }
  }

  // Normalizes value/maxValue into [0, 1]; a zero, negative or non-finite maximum yields 0.
  static func normalizedProgress(value: Float, maxValue: Float) -> Float {
    guard value.isFinite, maxValue.isFinite, maxValue > 0 else {
      return 0
    }
    return min(max(value / maxValue, 0), 1)
  }

  // The single routing decision for the Tahoe fallback: true only on macOS 26+.
  static var shouldUseCustomHUD: Bool {
    if #available(macOS 26, *) {
      return true
    }
    return false
  }

  private static var panels: [CGDirectDisplayID: TahoeHUDPanel] = [:]

  static func show(displayID: CGDirectDisplayID, kind: Kind, progress: Float, disabled: Bool = false) {
    let run = {
      let effectiveDisplayID = DisplayManager.resolveEffectiveDisplayID(displayID)
      guard let screen = DisplayManager.getByDisplayID(displayID: effectiveDisplayID) else {
        return
      }
      let panel = self.panels[effectiveDisplayID] ?? TahoeHUDPanel()
      self.panels[effectiveDisplayID] = panel
      panel.update(screen: screen, kind: kind, progress: self.normalizedProgress(value: progress, maxValue: 1), disabled: disabled)
    }
    if Thread.isMainThread {
      run()
    } else {
      DispatchQueue.main.async(execute: run)
    }
  }

  static func closeHUD(for displayID: CGDirectDisplayID) {
    let run = {
      guard let panel = self.panels.removeValue(forKey: DisplayManager.resolveEffectiveDisplayID(displayID)) else {
        return
      }
      panel.cancelAndClose()
    }
    if Thread.isMainThread {
      run()
    } else {
      DispatchQueue.main.async(execute: run)
    }
  }
}

// A small non-activating, click-through panel mimicking the native OSD with stock Tahoe artwork plus a 16-chiclet progress bar.
final class TahoeHUDPanel: NSPanel {
  private static let panelSize = NSSize(width: 180, height: 180)
  private static let bottomOffset: CGFloat = 140
  private static let holdInterval: TimeInterval = 1.0
  private static let fadeInterval: TimeInterval = 0.4

  private let effectView = NSVisualEffectView()
  private let iconView = NSImageView()
  private let chicletView = TahoeHUDChicletView()
  private var fadeWorkItem: DispatchWorkItem?
  // Monotonic token invalidating any fade scheduled or already running for an older update. Main thread only.
  private var fadeGeneration = 0

  init() {
    super.init(contentRect: .init(origin: .zero, size: TahoeHUDPanel.panelSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    self.isOpaque = false
    self.backgroundColor = .clear
    self.ignoresMouseEvents = true
    self.level = .statusBar
    self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    self.isMovableByWindowBackground = false
    self.hasShadow = false

    self.effectView.material = .hudWindow
    self.effectView.state = .active
    self.effectView.blendingMode = .behindWindow
    self.effectView.wantsLayer = true
    self.effectView.layer?.cornerRadius = 18
    self.effectView.layer?.masksToBounds = true
    self.contentView = self.effectView

    self.iconView.imageScaling = .scaleProportionallyUpOrDown
    self.iconView.contentTintColor = .labelColor
    self.iconView.translatesAutoresizingMaskIntoConstraints = false
    self.chicletView.translatesAutoresizingMaskIntoConstraints = false
    self.effectView.addSubview(self.iconView)
    self.effectView.addSubview(self.chicletView)
    NSLayoutConstraint.activate([
      self.iconView.centerXAnchor.constraint(equalTo: self.effectView.centerXAnchor),
      self.iconView.centerYAnchor.constraint(equalTo: self.effectView.centerYAnchor, constant: 10),
      self.iconView.widthAnchor.constraint(equalToConstant: 64),
      self.iconView.heightAnchor.constraint(equalToConstant: 64),
      self.chicletView.centerXAnchor.constraint(equalTo: self.effectView.centerXAnchor),
      self.chicletView.bottomAnchor.constraint(equalTo: self.effectView.bottomAnchor, constant: -24),
      self.chicletView.widthAnchor.constraint(equalToConstant: 140),
      self.chicletView.heightAnchor.constraint(equalToConstant: 8),
    ])
  }

  // Must be called on the main thread. Reuses the panel: updates content, fronts without activating, restarts the fade-out.
  func update(screen: NSScreen, kind: TahoeHUD.Kind, progress: Float, disabled: Bool) {
    self.fadeGeneration += 1
    self.fadeWorkItem?.cancel()
    self.fadeWorkItem = nil
    if #available(macOS 11, *) {
      self.iconView.image = TahoeHUD.stockIcon(for: kind) ?? NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: nil)
    }
    self.iconView.contentTintColor = disabled ? .tertiaryLabelColor : .labelColor
    self.chicletView.progress = disabled ? 0 : progress
    self.chicletView.chicletCount = TahoeHUD.chicletCount
    self.chicletView.needsDisplay = true

    let frame = screen.visibleFrame
    self.setFrameOrigin(NSPoint(x: frame.midX - TahoeHUDPanel.panelSize.width / 2, y: frame.minY + TahoeHUDPanel.bottomOffset))
    // Restore opacity immediately so an in-flight fade from a previous update cannot linger.
    self.alphaValue = 1
    self.orderFrontRegardless()
    self.scheduleFade()
  }

  private func scheduleFade() {
    let generation = self.fadeGeneration
    let workItem = DispatchWorkItem { [weak self] in
      guard let self = self, generation == self.fadeGeneration else {
        return
      }
      NSAnimationContext.runAnimationGroup({ context in
        context.duration = TahoeHUDPanel.fadeInterval
        self.animator().alphaValue = 0
      }, completionHandler: {
        guard generation == self.fadeGeneration else {
          return
        }
        self.orderOut(nil)
      })
    }
    self.fadeWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + TahoeHUDPanel.holdInterval, execute: workItem)
  }

  func cancelAndClose() {
    self.fadeGeneration += 1
    self.fadeWorkItem?.cancel()
    self.fadeWorkItem = nil
    self.close()
  }
}

// Draws the segmented (chiclet) progress bar of the native OSD.
final class TahoeHUDChicletView: NSView {
  var progress: Float = 0
  var chicletCount: Int = TahoeHUD.chicletCount

  override func draw(_ dirtyRect: NSRect) {
    guard self.chicletCount > 0 else {
      return
    }
    let spacing: CGFloat = 2
    let totalSpacing = spacing * CGFloat(self.chicletCount - 1)
    let chicletWidth = (self.bounds.width - totalSpacing) / CGFloat(self.chicletCount)
    guard chicletWidth > 0 else {
      return
    }
    let filledCount = Int((self.progress * Float(self.chicletCount)).rounded())
    for index in 0 ..< self.chicletCount {
      let rect = NSRect(x: CGFloat(index) * (chicletWidth + spacing), y: 0, width: chicletWidth, height: self.bounds.height)
      let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
      if index < filledCount {
        NSColor.labelColor.setFill()
      } else {
        NSColor.labelColor.withAlphaComponent(0.25).setFill()
      }
      path.fill()
    }
  }
}
