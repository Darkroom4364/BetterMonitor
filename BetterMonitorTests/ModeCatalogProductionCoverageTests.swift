//  Copyright © BetterMonitor. @JoniVR, @theOneyouseek, @waydabber and others

import CoreGraphics
import Foundation
import XCTest
@testable import BetterMonitor

final class ModeCatalogProductionCoverageTests: XCTestCase {
  func testProductionCatalogRequestReturnsSortedRowsAndStructuredTargetErrors() {
    let target = BetterMonitor.ModeCatalogTarget(identifier: 42, name: "Café Panel")
    let reader = ProductionModeReader(modes: [
      signature(logicalWidth: 1920, logicalHeight: 1080, pixelEncoding: "ARGB", ioFlags: 1),
      signature(logicalWidth: 3840, logicalHeight: 2160, pixelEncoding: "", ioFlags: 2),
    ])
    let processor = BetterMonitor.ModeCatalogRequestProcessor(
      catalog: BetterMonitor.ModeCatalog(reader: reader)
    )

    let rows = processor.handle(
      userInfo: [BetterMonitor.CLIKey.displayId: NSNumber(value: UInt32(42))],
      targets: [target]
    )

    XCTAssertEqual(reader.displayIDs, [target.identifier])
    XCTAssertEqual(rows.count, 2)
    XCTAssertEqual(rows.map { $0["logicalWidth"] as? Int }, [3840, 1920])
    XCTAssertEqual(rows.map { $0["logicalHeight"] as? Int }, [2160, 1080])
    XCTAssertEqual(rows.map { $0["pixelWidth"] as? Int }, [3840, 1920])
    XCTAssertEqual(rows.map { $0["pixelHeight"] as? Int }, [2160, 1080])
    XCTAssertEqual(rows.map { $0["refreshRate"] as? Double }, [60, 60])
    XCTAssertEqual(rows.map { $0["display"] as? String }, ["Café Panel", "Café Panel"])
    XCTAssertEqual(rows.map { $0["id"] as? Int }, [42, 42])
    XCTAssertEqual(rows.map { $0["pixelEncoding"] as? String }, ["", "ARGB"])
    XCTAssertEqual(rows.map { $0["isUsableForDesktop"] as? Bool }, [true, true])
    XCTAssertEqual(rows.map { $0["ioFlags"] as? Int }, [2, 1])
    XCTAssertEqual(rows.map { $0["isHiDPI"] as? Bool }, [false, false])
    XCTAssertEqual(rows.map { $0["mode"] as? String }, [
      "3840×2160 (3840×2160, 60.00 Hz)",
      "1920×1080 (1920×1080, 60.00 Hz)",
    ])
    XCTAssertEqual(rows.map { $0.keys.sorted() }, Array(repeating: [
      "display", "id", "ioFlags", "isHiDPI", "isUsableForDesktop", "logicalHeight", "logicalWidth",
      "mode", "pixelEncoding", "pixelHeight", "pixelWidth", "refreshRate",
    ], count: 2))

    let missingTarget = processor.handle(userInfo: [:], targets: [target])
    XCTAssertEqual(missingTarget.count, 1)
    XCTAssertEqual(missingTarget[0]["error"] as? String, "Mode list requires exactly one --display <name-or-id>")

    let invalidTarget = processor.handle(
      userInfo: [BetterMonitor.CLIKey.displayId: "42"],
      targets: [target]
    )
    XCTAssertEqual(invalidTarget.count, 1)
    XCTAssertEqual(invalidTarget[0]["error"] as? String, "Invalid display target")
    XCTAssertEqual(reader.displayIDs, [target.identifier])
  }

  private func signature(
    logicalWidth: Int,
    logicalHeight: Int,
    pixelEncoding: String,
    ioFlags: UInt32
  ) -> BetterMonitor.DisplayModeSignature {
    BetterMonitor.DisplayModeSignature(
      logicalWidth: logicalWidth,
      logicalHeight: logicalHeight,
      pixelWidth: logicalWidth,
      pixelHeight: logicalHeight,
      refreshRate: 60,
      pixelEncoding: pixelEncoding,
      isUsableForDesktop: true,
      ioFlags: ioFlags,
      isHiDPI: false
    )
  }
}

private final class ProductionModeReader: BetterMonitor.OfferedDisplayModeReading {
  private let modes: [BetterMonitor.DisplayModeSignature]
  private(set) var displayIDs: [CGDirectDisplayID] = []

  init(modes: [BetterMonitor.DisplayModeSignature]) {
    self.modes = modes
  }

  func offeredModeSignatures(displayID: CGDirectDisplayID) -> [BetterMonitor.DisplayModeSignature]? {
    displayIDs.append(displayID)
    return modes
  }
}
