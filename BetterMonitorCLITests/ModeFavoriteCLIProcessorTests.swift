//  Copyright © BetterMonitor. @JoniVR, @theOneyouseek, @waydabber and others

import XCTest

final class ModeFavoriteCLIProcessorTests: XCTestCase {
  func testModeListActionDoesNotConsultFavoriteManager() {
    let manager = SpyModeFavoriteManager()
    let target = ModeFavoriteDisplayTarget(identifier: 42, name: "Display", vendorNumber: 10, modelNumber: 20, serialNumber: 30)

    let result = ModeFavoriteCLIProcessor(manager: manager).handle(
      action: .modeList,
      name: nil,
      targetResult: .success(target)
    )

    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result.first?["error"] as? String, "Invalid mode favorite command")
    XCTAssertEqual(manager.listCalls, 0)
    XCTAssertEqual(manager.mutationCalls, 0)
  }
}

private final class SpyModeFavoriteManager: ModeFavoriteManaging {
  private(set) var listCalls = 0
  private(set) var mutationCalls = 0

  func favorites(for _: ModeFavoriteDisplayTarget?) -> [ModeFavorite] {
    listCalls += 1
    return []
  }

  func saveCurrent(name _: String, for _: ModeFavoriteDisplayTarget) -> Result<ModeFavorite, ModeFavoriteError> {
    mutationCalls += 1
    return .failure(.currentModeUnreadable)
  }

  func apply(name _: String, for _: ModeFavoriteDisplayTarget) -> Result<ModeFavorite, ModeFavoriteError> {
    mutationCalls += 1
    return .failure(.favoriteNotFound)
  }

  func delete(name _: String, for _: ModeFavoriteDisplayTarget) -> Result<ModeFavorite, ModeFavoriteError> {
    mutationCalls += 1
    return .failure(.favoriteNotFound)
  }
}
