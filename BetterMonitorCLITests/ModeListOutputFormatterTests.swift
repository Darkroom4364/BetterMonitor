//  Copyright © BetterMonitor. @JoniVR, @theOneyouseek, @waydabber and others

import XCTest

final class ModeListOutputFormatterTests: XCTestCase {
  func testFormatsCompleteValidModeListRow() {
    XCTAssertEqual(
      try? ModeListOutputFormatter.line(from: validRow()).get(),
      "Café Panel (id: 42): 3840×2160 (3840×2160, 60.00 Hz)"
    )
  }

  func testRejectsMissingExtraAndMalformedModeListRows() {
    var missing = validRow()
    missing.removeValue(forKey: "mode")
    XCTAssertEqual(ModeListOutputFormatter.line(from: missing), .failure(.invalidResponse))

    var extra = validRow()
    extra["unexpected"] = "value"
    XCTAssertEqual(ModeListOutputFormatter.line(from: extra), .failure(.invalidResponse))

    var malformed = validRow()
    malformed["refreshRate"] = Double.nan
    XCTAssertEqual(ModeListOutputFormatter.line(from: malformed), .failure(.invalidResponse))
  }

  private func validRow() -> [String: Any] {
    [
      "display": "Café Panel",
      "id": 42,
      "logicalWidth": 3840,
      "logicalHeight": 2160,
      "pixelWidth": 3840,
      "pixelHeight": 2160,
      "refreshRate": 60.0,
      "pixelEncoding": "ARGB",
      "isUsableForDesktop": true,
      "ioFlags": 1,
      "isHiDPI": false,
      "mode": "3840×2160 (3840×2160, 60.00 Hz)",
    ]
  }
}
