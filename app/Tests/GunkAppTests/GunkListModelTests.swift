import GRDB
import XCTest
@testable import GunkApp

@MainActor
final class GunkListModelTests: XCTestCase {
  func testRefreshLoadsAll() throws {
    let store = try makeStore()
    _ = try store.insertGunk(name: "older", path: "/code/older")
    _ = try store.insertGunk(name: "newer", path: "/code/newer")
    let model = GunkListModel(store: store)

    model.refresh()

    XCTAssertEqual(model.gunks.map(\.name), ["newer", "older"])
    XCTAssertNil(model.errorMessage)
  }

  func testDeleteRemovesOne() throws {
    let store = try makeStore()
    let removed = try store.insertGunk(name: "removed", path: "/code/removed")
    _ = try store.insertGunk(name: "active", path: "/code/active")
    let model = GunkListModel(store: store)
    model.refresh()

    model.delete(id: removed.id)

    XCTAssertEqual(model.gunks.map(\.name), ["active"])
    XCTAssertNil(model.errorMessage)
  }

  func testDeleteUnknownIdIsNoOp() throws {
    let store = try makeStore()
    _ = try store.insertGunk(name: "active", path: "/code/active")
    let model = GunkListModel(store: store)
    model.refresh()

    model.delete(id: 999)

    XCTAssertEqual(model.gunks.map(\.name), ["active"])
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
