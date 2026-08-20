//  Copyright © BetterMonitor. @JoniVR, @theOneyouseek, @waydabber and others

import Foundation

enum ModeListOutputFormatError: Error, Equatable, LocalizedError {
  case invalidResponse

  var errorDescription: String? {
    "Invalid mode-list response"
  }
}

enum ModeListOutputFormatter {
  private static let expectedKeys: Set<String> = [
    "display",
    "id",
    "logicalWidth",
    "logicalHeight",
    "pixelWidth",
    "pixelHeight",
    "refreshRate",
    "pixelEncoding",
    "isUsableForDesktop",
    "ioFlags",
    "isHiDPI",
    "mode",
  ]

  static func line(from row: [String: Any]) -> Result<String, ModeListOutputFormatError> {
    guard Set(row.keys) == expectedKeys,
          let display = row["display"] as? String,
          let id = row["id"] as? Int,
          let logicalWidth = row["logicalWidth"] as? Int,
          let logicalHeight = row["logicalHeight"] as? Int,
          let pixelWidth = row["pixelWidth"] as? Int,
          let pixelHeight = row["pixelHeight"] as? Int,
          let refreshRate = row["refreshRate"] as? Double,
          let pixelEncoding = row["pixelEncoding"] as? String,
          let isUsableForDesktop = row["isUsableForDesktop"] as? Bool,
          let ioFlags = row["ioFlags"] as? Int,
          let isHiDPI = row["isHiDPI"] as? Bool,
          let mode = row["mode"] as? String,
          !display.isEmpty,
          id >= 0,
          logicalWidth > 0,
          logicalHeight > 0,
          pixelWidth > 0,
          pixelHeight > 0,
          refreshRate.isFinite,
          refreshRate >= 0,
          isUsableForDesktop,
          ioFlags >= 0,
          !mode.isEmpty
    else {
      return .failure(.invalidResponse)
    }

    _ = isHiDPI
    return .success("\(display) (id: \(id)): \(mode)")
  }
}
