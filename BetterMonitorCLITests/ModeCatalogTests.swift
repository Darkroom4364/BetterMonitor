//  Copyright © BetterMonitor. @JoniVR, @theOneyouseek, @waydabber and others

import CoreGraphics
import Foundation
import XCTest

final class ModeCatalogTests: XCTestCase {
  private let target = ModeCatalogTarget(identifier: 42, name: "Café Panel")

  func testTargetResolverUsesExactCaseAndDiacriticFoldedMatchingWithoutTrimming() {
    for query in ["CAFÉ PANEL", "cafe panel"] {
      XCTAssertEqual(
        try? ModeCatalogTargetResolver.resolve(userInfo: [CLIKey.displayName: query], targets: [target]).get(),
        target
      )
    }
    XCTAssertEqual(
      ModeCatalogTargetResolver.resolve(userInfo: [CLIKey.displayName: " Café Panel "], targets: [target]),
      .failure(.displayNotFound)
    )
    XCTAssertEqual(
      ModeCatalogTargetResolver.resolve(userInfo: [CLIKey.displayName: " \n\t"], targets: [target]),
      .failure(.invalidDisplayTarget)
    )
    for alias in ["Panel", "Café"] {
      XCTAssertEqual(
        ModeCatalogTargetResolver.resolve(userInfo: [CLIKey.displayName: alias], targets: [target]),
        .failure(.displayNotFound)
      )
    }
  }

  func testTargetResolverRequiresExactlyOneMatchingTarget() {
    XCTAssertEqual(
      ModeCatalogTargetResolver.resolve(userInfo: [:], targets: [target]),
      .failure(.displayTargetRequired)
    )
    XCTAssertEqual(
      ModeCatalogTargetResolver.resolve(
        userInfo: [CLIKey.displayId: NSNumber(value: 42), CLIKey.displayName: "Café Panel"],
        targets: [target]
      ),
      .failure(.displayTargetRequired)
    )
    XCTAssertEqual(
      ModeCatalogTargetResolver.resolve(
        userInfo: [CLIKey.displayName: "Cafe"],
        targets: [ModeCatalogTarget(identifier: 1, name: "Café"), ModeCatalogTarget(identifier: 2, name: "Cafe")]
      ),
      .failure(.ambiguousDisplayTarget)
    )
  }

  func testTargetResolverAcceptsOnlyExactNSNumberDisplayIDs() {
    XCTAssertEqual(
      try? ModeCatalogTargetResolver.resolve(userInfo: [CLIKey.displayId: NSNumber(value: UInt32(42))], targets: [target]).get(),
      target
    )

    for invalidValue: Any in [
      "42",
      NSNumber(value: true),
      NSNumber(value: -1),
      NSNumber(value: 42.5),
      NSNumber(value: UInt64(UInt32.max) + 1),
    ] {
      XCTAssertEqual(
        ModeCatalogTargetResolver.resolve(userInfo: [CLIKey.displayId: invalidValue], targets: [target]),
        .failure(.invalidDisplayTarget)
      )
    }
  }

  func testCatalogFiltersDeduplicatesSerializesAndReadsTargetOnce() throws {
    let usable = signature(logicalWidth: 2560, logicalHeight: 1440, pixelWidth: 5120, pixelHeight: 2880)
    let reader = SpyReader(modes: [
      usable,
      usable,
      signature(logicalWidth: 2560, logicalHeight: 1440, pixelWidth: 5120, pixelHeight: 2880, isUsableForDesktop: false),
    ])

    let rows = try ModeCatalog(reader: reader).rows(for: target).get()

    XCTAssertEqual(reader.displayIDs, [target.identifier])
    XCTAssertEqual(rows.count, 1)
    XCTAssertEqual(rows[0].display, target.name)
    XCTAssertEqual(rows[0].id, Int(target.identifier))
    XCTAssertEqual(rows[0].responseDictionary.keys.sorted(), ["display", "id", "ioFlags", "isHiDPI", "isUsableForDesktop", "logicalHeight", "logicalWidth", "mode", "pixelEncoding", "pixelHeight", "pixelWidth", "refreshRate"])

    let response = rows.map(\.responseDictionary)
    XCTAssertTrue(JSONSerialization.isValidJSONObject(response))
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: response))
  }

  func testCatalogFormatsEmptyPixelEncodingAfterJSONRoundTrip() throws {
    let emptyEncoding = DisplayModeSignature(
      logicalWidth: 1920,
      logicalHeight: 1080,
      pixelWidth: 1920,
      pixelHeight: 1080,
      refreshRate: 60,
      pixelEncoding: "",
      isUsableForDesktop: true,
      ioFlags: 1,
      isHiDPI: false
    )
    let row = try XCTUnwrap(try ModeCatalog(reader: SpyReader(modes: [emptyEncoding])).rows(for: target).get().first)
    let plainLine = try ModeListOutputFormatter.line(from: row.responseDictionary).get()
    let data = try JSONSerialization.data(withJSONObject: [row.responseDictionary])
    let decodedRows = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    let jsonLine = try ModeListOutputFormatter.line(from: try XCTUnwrap(decodedRows.first)).get()

    XCTAssertEqual(row.pixelEncoding, "")
    XCTAssertEqual(jsonLine, plainLine)
    XCTAssertEqual(jsonLine, "Café Panel (id: 42): 1920×1080 (1920×1080, 60.00 Hz)")
  }

  func testCatalogOrdersEverySignatureTiebreaker() throws {
    let reader = SpyReader(modes: [
      signature(logicalWidth: 2000, logicalHeight: 800, pixelWidth: 1, pixelHeight: 1, refreshRate: 0, pixelEncoding: "Z"),
      signature(logicalWidth: 1000, logicalHeight: 900, pixelWidth: 1, pixelHeight: 1, refreshRate: 0, pixelEncoding: "Z"),
      signature(logicalWidth: 1000, logicalHeight: 800, pixelWidth: 4000, pixelHeight: 3000, refreshRate: 10, pixelEncoding: "ZZZ", ioFlags: 9, isHiDPI: true),
      signature(logicalWidth: 1000, logicalHeight: 800, pixelWidth: 4000, pixelHeight: 2000, refreshRate: 240, pixelEncoding: "AAAA"),
      signature(logicalWidth: 1000, logicalHeight: 800, pixelWidth: 3000, pixelHeight: 9000, refreshRate: 240, pixelEncoding: "AAAA"),
      signature(logicalWidth: 1000, logicalHeight: 800, pixelWidth: 2000, pixelHeight: 1000, refreshRate: 120, pixelEncoding: "AAAA"),
      signature(logicalWidth: 1000, logicalHeight: 800, pixelWidth: 2000, pixelHeight: 1000, refreshRate: 60, pixelEncoding: "ARGB"),
      signature(logicalWidth: 1000, logicalHeight: 800, pixelWidth: 2000, pixelHeight: 1000, refreshRate: 60, pixelEncoding: "BGRA"),
      signature(logicalWidth: 1000, logicalHeight: 800, pixelWidth: 2000, pixelHeight: 1000, refreshRate: 60, pixelEncoding: "RGBA", ioFlags: 1),
      signature(logicalWidth: 1000, logicalHeight: 800, pixelWidth: 2000, pixelHeight: 1000, refreshRate: 60, pixelEncoding: "RGBA", ioFlags: 2),
      signature(logicalWidth: 1000, logicalHeight: 800, pixelWidth: 2000, pixelHeight: 1000, refreshRate: 60, pixelEncoding: "RGBX", ioFlags: 4, isHiDPI: false),
      signature(logicalWidth: 1000, logicalHeight: 800, pixelWidth: 2000, pixelHeight: 1000, refreshRate: 60, pixelEncoding: "RGBX", ioFlags: 4, isHiDPI: true),
    ])

    let rows = try ModeCatalog(reader: reader).rows(for: target).get()

    XCTAssertEqual(rows.map { "\($0.logicalWidth)x\($0.logicalHeight)|\($0.pixelWidth)x\($0.pixelHeight)|\($0.refreshRate)|\($0.pixelEncoding)|\($0.ioFlags)|\($0.isHiDPI)" }, [
      "2000x800|1x1|0.0|Z|1|false",
      "1000x900|1x1|0.0|Z|1|false",
      "1000x800|4000x3000|10.0|ZZZ|9|true",
      "1000x800|4000x2000|240.0|AAAA|1|false",
      "1000x800|3000x9000|240.0|AAAA|1|false",
      "1000x800|2000x1000|120.0|AAAA|1|false",
      "1000x800|2000x1000|60.0|ARGB|1|false",
      "1000x800|2000x1000|60.0|BGRA|1|false",
      "1000x800|2000x1000|60.0|RGBA|1|false",
      "1000x800|2000x1000|60.0|RGBA|2|false",
      "1000x800|2000x1000|60.0|RGBX|4|false",
      "1000x800|2000x1000|60.0|RGBX|4|true",
    ])
  }

  func testCatalogLabelsZeroRefreshAsVariable() throws {
    let rows = try ModeCatalog(reader: SpyReader(modes: [signature(refreshRate: 0)])).rows(for: target).get()

    XCTAssertEqual(rows.map(\.mode), ["1920×1080 (1920×1080, variable)"])
  }

  func testCatalogRejectsUnreadableNoUsableAndInvalidOfferedModes() {
    XCTAssertEqual(
      ModeCatalog(reader: SpyReader(modes: nil)).rows(for: target),
      .failure(.offeredModesUnreadable)
    )
    XCTAssertEqual(
      ModeCatalog(reader: SpyReader(modes: [signature(isUsableForDesktop: false)])).rows(for: target),
      .failure(.noUsableDesktopModes)
    )
    XCTAssertEqual(
      ModeCatalog(reader: SpyReader(modes: [signature(logicalWidth: 0)])).rows(for: target),
      .failure(.invalidOfferedMode)
    )
    XCTAssertEqual(
      ModeCatalog(reader: SpyReader(modes: [signature(refreshRate: .nan)])).rows(for: target),
      .failure(.invalidOfferedMode)
    )
  }

  func testRequestProcessorReturnsCatalogRowsAndStructuredErrors() {
    let reader = SpyReader(modes: [signature()])
    let processor = ModeCatalogRequestProcessor(catalog: ModeCatalog(reader: reader))

    let rows = processor.handle(userInfo: [CLIKey.displayId: NSNumber(value: UInt32(42))], targets: [target])
    XCTAssertEqual(rows.count, 1)
    XCTAssertEqual(rows[0]["display"] as? String, "Café Panel")
    XCTAssertEqual(rows[0]["id"] as? Int, 42)
    XCTAssertNil(rows[0]["error"])
    XCTAssertEqual(reader.displayIDs, [target.identifier])

    let error = processor.handle(userInfo: [:], targets: [target])
    XCTAssertEqual(error.count, 1)
    XCTAssertEqual(error.first?["error"] as? String, ModeCatalogError.displayTargetRequired.localizedDescription)
    XCTAssertEqual(reader.displayIDs, [target.identifier])
  }

  private func signature(
    logicalWidth: Int = 1920,
    logicalHeight: Int = 1080,
    pixelWidth: Int = 1920,
    pixelHeight: Int = 1080,
    refreshRate: Double = 60,
    pixelEncoding: String = "ARGB",
    isUsableForDesktop: Bool = true,
    ioFlags: UInt32 = 1,
    isHiDPI: Bool = false
  ) -> DisplayModeSignature {
    DisplayModeSignature(
      logicalWidth: logicalWidth,
      logicalHeight: logicalHeight,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      refreshRate: refreshRate,
      pixelEncoding: pixelEncoding,
      isUsableForDesktop: isUsableForDesktop,
      ioFlags: ioFlags,
      isHiDPI: isHiDPI
    )
  }
}

private final class SpyReader: OfferedDisplayModeReading {
  let modes: [DisplayModeSignature]?
  private(set) var displayIDs: [CGDirectDisplayID] = []

  init(modes: [DisplayModeSignature]?) {
    self.modes = modes
  }

  func offeredModeSignatures(displayID: CGDirectDisplayID) -> [DisplayModeSignature]? {
    displayIDs.append(displayID)
    return modes
  }
}
