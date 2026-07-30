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

  static func fallbackSymbolName(for kind: Kind, stockIconAvailable: Bool) -> String? {
    stockIconAvailable ? nil : kind.symbolName
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
  private static let lifecycle = TahoeHUDLifecycle()

  static func show(displayID: CGDirectDisplayID, kind: Kind, progress: Float, disabled: Bool = false) {
    let lifecycleGeneration = self.lifecycle.captureGeneration()
    let run = {
      guard self.lifecycle.isCurrent(lifecycleGeneration) else {
        return
      }
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

  static func invalidateAndCloseAllHUDs() {
    self.lifecycle.invalidate()
    let run = {
      let panels = self.panels.values
      self.panels.removeAll()
      panels.forEach { $0.cancelAndClose() }
    }
    if Thread.isMainThread {
      run()
    } else {
      DispatchQueue.main.async(execute: run)
    }
  }
}

// Serializes the generation token that invalidates HUD updates queued before display teardown.
final class TahoeHUDLifecycle {
  private let lock = NSLock()
  private var generation = 0

  func captureGeneration() -> Int {
    self.lock.lock()
    defer { self.lock.unlock() }
    return self.generation
  }

  func invalidate() {
    self.lock.lock()
    self.generation &+= 1
    self.lock.unlock()
  }

  func isCurrent(_ capturedGeneration: Int) -> Bool {
    self.lock.lock()
    defer { self.lock.unlock() }
    return capturedGeneration == self.generation
  }
}

// A compact horizontal HUD with stock Tahoe artwork and a native-style progress bar.
final class TahoeHUDPanel: NSPanel {
  private static let panelSize = NSSize(width: 280, height: 56)
  private static let bottomOffset: CGFloat = 96
  private static let holdInterval: TimeInterval = 1.0
  private static let fadeInterval: TimeInterval = 0.4

  private let effectView = NSVisualEffectView()
  private let iconView = NSImageView()
  private let progressView = TahoeHUDProgressView()
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
    self.progressView.translatesAutoresizingMaskIntoConstraints = false
    self.effectView.addSubview(self.iconView)
    self.effectView.addSubview(self.progressView)
    NSLayoutConstraint.activate([
      self.iconView.leadingAnchor.constraint(equalTo: self.effectView.leadingAnchor, constant: 16),
      self.iconView.centerYAnchor.constraint(equalTo: self.effectView.centerYAnchor),
      self.iconView.widthAnchor.constraint(equalToConstant: 24),
      self.iconView.heightAnchor.constraint(equalToConstant: 24),
      self.progressView.leadingAnchor.constraint(equalTo: self.iconView.trailingAnchor, constant: 12),
      self.progressView.trailingAnchor.constraint(equalTo: self.effectView.trailingAnchor, constant: -18),
      self.progressView.centerYAnchor.constraint(equalTo: self.effectView.centerYAnchor),
      self.progressView.heightAnchor.constraint(equalToConstant: 6),
    ])
  }

  // Must be called on the main thread. Reuses the panel: updates content, fronts without activating, restarts the fade-out.
  func update(screen: NSScreen, kind: TahoeHUD.Kind, progress: Float, disabled: Bool) {
    self.fadeGeneration += 1
    self.fadeWorkItem?.cancel()
    self.fadeWorkItem = nil
    if #available(macOS 11, *) {
      let stockIcon = TahoeHUD.stockIcon(for: kind)
      if let fallbackSymbolName = TahoeHUD.fallbackSymbolName(for: kind, stockIconAvailable: stockIcon != nil) {
        self.iconView.image = NSImage(systemSymbolName: fallbackSymbolName, accessibilityDescription: nil)
      } else {
        self.iconView.image = stockIcon
      }
    }
    self.iconView.contentTintColor = disabled ? .tertiaryLabelColor : .labelColor
    self.progressView.progress = disabled ? 0 : progress
    self.progressView.needsDisplay = true

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

// Draws the continuous progress bar used by the horizontal Tahoe HUD.
final class TahoeHUDProgressView: NSView {
  var progress: Float = 0

  override func draw(_ dirtyRect: NSRect) {
    guard !self.bounds.isEmpty else {
      return
    }
    let radius = self.bounds.height / 2
    NSColor.labelColor.withAlphaComponent(0.25).setFill()
    NSBezierPath(roundedRect: self.bounds, xRadius: radius, yRadius: radius).fill()

    let fillWidth = self.bounds.width * CGFloat(min(max(self.progress, 0), 1))
    guard fillWidth > 0 else {
      return
    }
    let fillRect = NSRect(x: self.bounds.minX, y: self.bounds.minY, width: fillWidth, height: self.bounds.height)
    NSColor.labelColor.setFill()
    NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
  }
}
