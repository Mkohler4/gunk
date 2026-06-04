import GRDB
import XCTest
@testable import GunkApp

@MainActor
final class GunkListModelTests: XCTestCase {
  func testRefreshLoadsAll() throws {
    let store = try makeStore()
    _ = try store.insertSource(name: "older", path: "/code/older")
    _ = try store.insertSource(name: "newer", path: "/code/newer")
    let model = GunkListModel(store: store)

    model.refresh()

    XCTAssertEqual(model.sources.map(\.name), ["newer", "older"])
    XCTAssertNil(model.errorMessage)
  }

  func testDeleteRemovesOne() throws {
    let store = try makeStore()
    let removed = try store.insertSource(name: "removed", path: "/code/removed")
    _ = try store.insertSource(name: "active", path: "/code/active")
    let model = GunkListModel(store: store)
    model.refresh()

    model.delete(id: removed.id)

    XCTAssertEqual(model.sources.map(\.name), ["active"])
    XCTAssertNil(model.errorMessage)
  }

  func testDeleteUnknownIdIsNoOp() throws {
    let store = try makeStore()
    _ = try store.insertSource(name: "active", path: "/code/active")
    let model = GunkListModel(store: store)
    model.refresh()

    model.delete(id: 999)

    XCTAssertEqual(model.sources.map(\.name), ["active"])
    XCTAssertNil(model.errorMessage)
  }

  private func makeStore() throws -> Store {
    var timestamp: Int64 = 100
    return try Store(databaseQueue: DatabaseQueue()) {
      defer { timestamp += 100 }
      return timestamp
    }
  }
}
