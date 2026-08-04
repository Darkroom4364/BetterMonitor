//  Copyright © BetterMonitor. @JoniVR, @theOneyouseek, @waydabber and others

import XCTest

final class ModeFavoritesTests: XCTestCase {
  private var defaults: UserDefaults!
  private var suiteName: String!

  override func setUp() {
    super.setUp()
    suiteName = "ModeFavoritesTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
    suiteName = nil
    super.tearDown()
  }

  func testSaveReplacesCaseAndDiacriticInsensitiveNameOnlyForSameDisplay() {
    let controller = FakeModeController(current: mode(refreshRate: 60))
    let manager = makeManager(controller: controller)
    let firstDisplay = target(id: 11, serial: 101)
    let secondDisplay = target(id: 22, serial: 202)

    XCTAssertSuccess(manager.saveCurrent(name: "Café", for: firstDisplay))
    controller.current = mode(refreshRate: 75)
    XCTAssertSuccess(manager.saveCurrent(name: "cafe", for: firstDisplay))
    XCTAssertSuccess(manager.saveCurrent(name: "CAFE", for: secondDisplay))

    let firstFavorites = manager.favorites(for: firstDisplay)
    XCTAssertEqual(firstFavorites.count, 1)
    XCTAssertEqual(firstFavorites[0].name, "cafe")
    XCTAssertEqual(firstFavorites[0].signature.refreshRate, 75)
    XCTAssertEqual(manager.favorites(for: secondDisplay).count, 1)
  }

  func testCorruptStorageReadsAsEmpty() {
    defaults.set(Data("not-json".utf8), forKey: ModeFavoriteManager.storageKey)
    let manager = ModeFavoriteManager(storage: UserDefaultsModeFavoriteStorage(defaults: defaults), modeController: FakeModeController(current: mode()))

    XCTAssertTrue(manager.favorites().isEmpty)
  }

  func testApplySetsOnlyTargetAndVerifiesExactFullSignature() {
    let savedMode = mode(refreshRate: 60, encoding: "IO32BitDirectPixels")
    let controller = FakeModeController(current: savedMode)
    let manager = makeManager(controller: controller)
    let display = target(id: 41, serial: 301)
    XCTAssertSuccess(manager.saveCurrent(name: "Work", for: display))

    controller.current = mode(refreshRate: 30, encoding: "IO32BitDirectPixels")
    controller.offered = [savedMode]
    controller.readbackOnSet = savedMode

    XCTAssertSuccess(manager.apply(name: "work", for: display))
    XCTAssertEqual(controller.setCalls, [41])
    XCTAssertEqual(controller.setSignatures, [savedMode])
  }

  func testApplyRejectsNearMatchAndDoesNotSet() {
    let savedMode = mode(encoding: "IO32BitDirectPixels")
    let controller = FakeModeController(current: savedMode)
    let manager = makeManager(controller: controller)
    let display = target(id: 42, serial: 302)
    XCTAssertSuccess(manager.saveCurrent(name: "Work", for: display))

    controller.offered = [mode(encoding: "IO30BitDirectPixels")]
    XCTAssertFailure(manager.apply(name: "Work", for: display), equals: .unavailableMode)
    XCTAssertTrue(controller.setCalls.isEmpty)
  }

  func testApplyRejectsUnusableSavedModeWithoutSettingDisplay() throws {
    let controller = FakeModeController(current: mode())
    let display = target(id: 44, serial: 304)
    let unusableFavorite = ModeFavorite(
      name: "Unsafe",
      normalizedName: "unsafe",
      displayIdentity: try XCTUnwrap(display.durableIdentity),
      displayName: display.name,
      signature: mode(usable: false)
    )
    defaults.set(try JSONEncoder().encode([unusableFavorite]), forKey: ModeFavoriteManager.storageKey)
    let manager = makeManager(controller: controller)

    XCTAssertFailure(manager.apply(name: "Unsafe", for: display), equals: .unusableMode)
    XCTAssertTrue(controller.setCalls.isEmpty)
  }

  func testApplyReportsSetAndReadbackFailures() {
    let savedMode = mode()
    let controller = FakeModeController(current: savedMode)
    let manager = makeManager(controller: controller)
    let display = target(id: 43, serial: 303)
    XCTAssertSuccess(manager.saveCurrent(name: "Work", for: display))
    controller.offered = [savedMode]

    controller.setSucceeds = false
    XCTAssertFailure(manager.apply(name: "Work", for: display), equals: .setFailed)

    controller.setSucceeds = true
    controller.readbackOnSet = nil
    XCTAssertFailure(manager.apply(name: "Work", for: display), equals: .readbackUnreadable)

    controller.readbackOnSet = mode(refreshRate: 30)
    XCTAssertFailure(manager.apply(name: "Work", for: display), equals: .readbackMismatch)
  }

  func testDurableIdentityRequiresCompleteNonSentinelEDIDTriplet() {
    let complete = ModeFavoriteDisplayTarget(identifier: 1, name: "Display", vendorNumber: 10, modelNumber: 20, serialNumber: 30)
    XCTAssertEqual(complete.durableIdentity, "edid:10:20:30")

    XCTAssertNil(ModeFavoriteDisplayTarget(identifier: 2, name: "Display", vendorNumber: nil, modelNumber: 20, serialNumber: 30).durableIdentity)
    XCTAssertNil(ModeFavoriteDisplayTarget(identifier: 3, name: "Display", vendorNumber: 10, modelNumber: nil, serialNumber: 30).durableIdentity)
    XCTAssertNil(ModeFavoriteDisplayTarget(identifier: 4, name: "Display", vendorNumber: 10, modelNumber: 20, serialNumber: nil).durableIdentity)
    XCTAssertNil(ModeFavoriteDisplayTarget(identifier: 5, name: "Display", vendorNumber: 0, modelNumber: 20, serialNumber: 30).durableIdentity)
    XCTAssertNil(ModeFavoriteDisplayTarget(identifier: 6, name: "Display", vendorNumber: 10, modelNumber: UInt32.max, serialNumber: 30).durableIdentity)
    XCTAssertNil(ModeFavoriteDisplayTarget(identifier: 7, name: "Display", vendorNumber: 10, modelNumber: 20, serialNumber: UInt32.max).durableIdentity)
  }

  func testIncompleteSameNamedDisplaysCannotMutateDurableFavorite() {
    let controller = FakeModeController(current: mode())
    let manager = makeManager(controller: controller)
    let durable = ModeFavoriteDisplayTarget(identifier: 10, name: "Same Name", vendorNumber: 10, modelNumber: 20, serialNumber: 30)
    let incomplete = ModeFavoriteDisplayTarget(identifier: 11, name: "Same Name", vendorNumber: 10, modelNumber: 20, serialNumber: nil)
    let sentinel = ModeFavoriteDisplayTarget(identifier: 12, name: "Same Name", vendorNumber: UInt32.max, modelNumber: 20, serialNumber: 30)

    XCTAssertSuccess(manager.saveCurrent(name: "Keep", for: durable))
    XCTAssertFailure(manager.saveCurrent(name: "Keep", for: incomplete), equals: .stableIdentityUnavailable)
    XCTAssertFailure(manager.apply(name: "Keep", for: incomplete), equals: .stableIdentityUnavailable)
    XCTAssertFailure(manager.delete(name: "Keep", for: sentinel), equals: .stableIdentityUnavailable)

    XCTAssertEqual(manager.favorites(for: durable).map(\.name), ["Keep"])
    XCTAssertTrue(controller.setCalls.isEmpty)
  }

  func testDurableIdentitySurvivesRuntimeDisplayIDAndNameChanges() {
    let savedMode = mode()
    let controller = FakeModeController(current: savedMode)
    let manager = makeManager(controller: controller)
    let original = ModeFavoriteDisplayTarget(identifier: 13, name: "Before", vendorNumber: 10, modelNumber: 20, serialNumber: 30)
    let reconnected = ModeFavoriteDisplayTarget(identifier: 14, name: "After", vendorNumber: 10, modelNumber: 20, serialNumber: 30)

    XCTAssertSuccess(manager.saveCurrent(name: "Work", for: original))
    XCTAssertEqual(manager.favorites(for: reconnected).map(\.name), ["Work"])

    controller.current = mode(refreshRate: 30)
    controller.offered = [savedMode]
    controller.readbackOnSet = savedMode
    XCTAssertSuccess(manager.apply(name: "Work", for: reconnected))
    XCTAssertEqual(controller.setCalls, [14])
  }

  func testSavePermitsReplacementAtFiveFavoritesButRejectsSixthDistinctName() {
    let controller = FakeModeController(current: mode())
    let manager = makeManager(controller: controller)
    let display = target(id: 15, serial: 31)

    for index in 1...5 {
      XCTAssertSuccess(manager.saveCurrent(name: "Favorite \(index)", for: display))
    }
    XCTAssertFailure(manager.saveCurrent(name: "Favorite 6", for: display), equals: .maximumFavoritesReached)
    XCTAssertEqual(manager.favorites(for: display).count, 5)

    controller.current = mode(refreshRate: 75)
    XCTAssertSuccess(manager.saveCurrent(name: "favorite 3", for: display))
    XCTAssertEqual(manager.favorites(for: display).count, 5)
    XCTAssertEqual(manager.favorites(for: display).first { $0.normalizedName == "favorite 3" }?.signature.refreshRate, 75)
  }

  func testCLIParserAndProtocolSerializeFavoriteCommands() {
    let command = CLICommand.parse(["bettermonitor", "mode-favorite-save", "Desk", "--display", "24"])

    XCTAssertEqual(command?.action, .modeFavoriteSave)
    XCTAssertEqual(command?.favoriteName, "Desk")
    XCTAssertEqual(command?.displayId, 24)
    XCTAssertEqual(command?.userInfo[CLIKey.favoriteName] as? String, "Desk")
    let untargetedList = CLICommand.parse(["bettermonitor", "mode-favorite-list"])
    XCTAssertEqual(untargetedList?.action, .modeFavoriteList)
    XCTAssertNil(untargetedList?.displayId)
    let targetedList = CLICommand.parse(["bettermonitor", "mode-favorite-list", "--display", "24"])
    XCTAssertEqual(targetedList?.displayId, 24)
    XCTAssertNil(CLICommand.parse(["bettermonitor", "mode-favorite-apply", " ", "--display", "24"]))
    XCTAssertNil(CLICommand.parse(["bettermonitor", "mode-favorite-delete", "Desk"]))
    XCTAssertNil(CLICommand.parse(["bettermonitor", "mode-favorite-save", "Desk", "Extra", "--display", "24"]))
    XCTAssertNil(CLICommand.parse(["bettermonitor", "mode-favorite-save", "Desk", "--display", "24", "--display", "25"]))
    XCTAssertNil(CLICommand.parse(["bettermonitor", "mode-favorite-list", "--display", "24", "--display", "25"]))
  }

  func testCLIProcessorRejectsMalformedAndAmbiguousTargetsWithoutCallingManager() {
    let manager = StubModeFavoriteManager()
    let processor = ModeFavoriteCLIProcessor(manager: manager)
    let one = target(id: 51, serial: 401)
    let two = target(id: 52, serial: 402)
    let ambiguous = ModeFavoriteTargetResolver.resolve(
      userInfo: [CLIKey.displayName: "Display"],
      targets: [one, two]
    )

    let ambiguousResult = processor.handle(action: .modeFavoriteSave, name: "Desk", targetResult: ambiguous)
    XCTAssertNotNil(ambiguousResult.first?["error"])
    XCTAssertEqual(manager.mutationCalls, 0)

    let unmatched = ModeFavoriteTargetResolver.resolve(
      userInfo: [CLIKey.displayId: NSNumber(value: 999)],
      targets: [one, two]
    )
    let unmatchedResult = processor.handle(action: .modeFavoriteSave, name: "Desk", targetResult: unmatched)
    XCTAssertNotNil(unmatchedResult.first?["error"])
    XCTAssertEqual(manager.mutationCalls, 0)

    let malformed = ModeFavoriteTargetResolver.resolve(
      userInfo: [CLIKey.displayId: NSNumber(value: 51), CLIKey.displayName: "Display"],
      targets: [one, two]
    )
    let malformedResult = processor.handle(action: .modeFavoriteSave, name: "Desk", targetResult: malformed)
    XCTAssertNotNil(malformedResult.first?["error"])
    XCTAssertEqual(manager.mutationCalls, 0)

    let missingTargetResult = processor.handle(action: .modeFavoriteDelete, name: "Desk", targetResult: .success(nil))
    XCTAssertNotNil(missingTargetResult.first?["error"])
    XCTAssertEqual(manager.mutationCalls, 0)

    let blankNameResult = processor.handle(action: .modeFavoriteApply, name: " ", targetResult: .success(one))
    XCTAssertNotNil(blankNameResult.first?["error"])
    XCTAssertEqual(manager.mutationCalls, 0)
  }

  func testCLIRejectsUnavailableTargetIdentityWithoutCallingManager() {
    let manager = StubModeFavoriteManager()
    let processor = ModeFavoriteCLIProcessor(manager: manager)
    let incomplete = ModeFavoriteDisplayTarget(identifier: 53, name: "Display", vendorNumber: 10, modelNumber: 20, serialNumber: nil)

    for action in [CLIAction.modeFavoriteList, .modeFavoriteSave, .modeFavoriteApply, .modeFavoriteDelete] {
      let result = processor.handle(action: action, name: "Desk", targetResult: .success(incomplete))
      XCTAssertEqual(result.first?["error"] as? String, ModeFavoriteError.stableIdentityUnavailable.localizedDescription)
    }
    XCTAssertEqual(manager.listCalls, 0)
    XCTAssertEqual(manager.mutationCalls, 0)
  }

  func testTargetResolverRejectsInvalidNumericNotificationsWithoutCallingManager() {
    let manager = StubModeFavoriteManager()
    let processor = ModeFavoriteCLIProcessor(manager: manager)
    let display = target(id: 51, serial: 401)
    let invalidValues: [NSNumber] = [
      NSNumber(value: true),
      NSNumber(value: -1),
      NSNumber(value: 51.0),
      NSNumber(value: 1.5),
      NSNumber(value: UInt64(UInt32.max) + 1),
      NSNumber(value: Double.nan),
    ]

    for value in invalidValues {
      let targetResult = ModeFavoriteTargetResolver.resolve(
        userInfo: [CLIKey.displayId: value],
        targets: [display]
      )
      let result = processor.handle(action: .modeFavoriteList, name: nil, targetResult: targetResult)
      XCTAssertNotNil(result.first?["error"])
    }
    XCTAssertEqual(manager.listCalls, 0)

    let validTarget = ModeFavoriteTargetResolver.resolve(
      userInfo: [CLIKey.displayId: NSNumber(value: 51)],
      targets: [display]
    )
    XCTAssertTrue(processor.handle(action: .modeFavoriteList, name: nil, targetResult: validTarget).isEmpty)
    XCTAssertEqual(manager.listCalls, 1)

    let noTarget = ModeFavoriteTargetResolver.resolve(userInfo: [:], targets: [display])
    XCTAssertTrue(processor.handle(action: .modeFavoriteList, name: nil, targetResult: noTarget).isEmpty)
    XCTAssertEqual(manager.listCalls, 2)
  }

  func testModeFavoriteMenuBuilderSortsAndWiresApplyAndDeleteActions() {
    let display = target(id: 61, serial: 501)
    let alpha = favorite(name: "Alpha", display: display)
    let zulu = favorite(name: "Zulu", display: display)

    XCTAssertEqual(
      ModeFavoriteMenuBuilder.items(favorites: [zulu, alpha]),
      [
        .action(title: "Save Current…", action: .saveCurrent),
        .separator,
        .submenu(title: "Apply", items: [
          .action(title: "Alpha", action: .apply(name: "Alpha")),
          .action(title: "Zulu", action: .apply(name: "Zulu")),
        ]),
        .submenu(title: "Delete", items: [
          .action(title: "Alpha", action: .delete(name: "Alpha")),
          .action(title: "Zulu", action: .delete(name: "Zulu")),
        ]),
      ]
    )
  }

  func testModeFavoriteMenuBuilderShowsUnavailableIdentityWithoutActions() {
    XCTAssertEqual(
      ModeFavoriteMenuBuilder.items(favorites: [], identityAvailable: false),
      [.disabled(title: ModeFavoriteMenuBuilder.stableIdentityUnavailableTitle)]
    )
  }

  private func makeManager(controller: FakeModeController) -> ModeFavoriteManager {
    ModeFavoriteManager(storage: UserDefaultsModeFavoriteStorage(defaults: defaults), modeController: controller)
  }

  private func target(id: UInt32 = 1, serial: UInt32 = 1) -> ModeFavoriteDisplayTarget {
    ModeFavoriteDisplayTarget(identifier: id, name: "Display \(serial)", vendorNumber: 10, modelNumber: 20, serialNumber: serial)
  }
  private func mode(refreshRate: Double = 60, encoding: String = "IO32BitDirectPixels", usable: Bool = true) -> DisplayModeSignature {
    DisplayModeSignature(
      logicalWidth: 1920,
      logicalHeight: 1080,
      pixelWidth: 3840,
      pixelHeight: 2160,
      refreshRate: refreshRate,
      pixelEncoding: encoding,
      isUsableForDesktop: usable,
      ioFlags: 7,
      isHiDPI: true
    )
  }

  private func favorite(name: String, display: ModeFavoriteDisplayTarget) -> ModeFavorite {
    ModeFavorite(
      name: name,
      normalizedName: ModeFavoriteManager.normalizedName(name),
      displayIdentity: display.durableIdentity!,
      displayName: display.name,
      signature: mode()
    )
  }

  private func XCTAssertSuccess(_ result: Result<ModeFavorite, ModeFavoriteError>, file: StaticString = #filePath, line: UInt = #line) {
    if case let .failure(error) = result {
      XCTFail("Unexpected error: \(error.localizedDescription)", file: file, line: line)
    }
  }

  private func XCTAssertFailure(_ result: Result<ModeFavorite, ModeFavoriteError>, equals expected: ModeFavoriteError, file: StaticString = #filePath, line: UInt = #line) {
    guard case let .failure(error) = result else {
      return XCTFail("Expected failure", file: file, line: line)
    }
    XCTAssertEqual(error, expected, file: file, line: line)
  }
}

private final class FakeModeController: ModeFavoriteModeControlling {
  var current: DisplayModeSignature?
  var offered: [DisplayModeSignature]?
  var setSucceeds = true
  var readbackOnSet: DisplayModeSignature?
  var setCalls: [CGDirectDisplayID] = []
  var setSignatures: [DisplayModeSignature] = []

  init(current: DisplayModeSignature?) {
    self.current = current
  }

  func currentModeSignature(displayID _: CGDirectDisplayID) -> DisplayModeSignature? {
    current
  }

  func offeredModeSignatures(displayID _: CGDirectDisplayID) -> [DisplayModeSignature]? {
    offered
  }

  func setMode(displayID: CGDirectDisplayID, signature: DisplayModeSignature) -> Bool {
    setCalls.append(displayID)
    setSignatures.append(signature)
    guard setSucceeds else {
      return false
    }
    current = readbackOnSet
    return true
  }
}

private final class StubModeFavoriteManager: ModeFavoriteManaging {
  var mutationCalls = 0
  var listCalls = 0

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
