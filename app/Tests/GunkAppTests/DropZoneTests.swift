import Foundation
import GRDB
import XCTest
@testable import GunkApp

final class DropZoneTests: XCTestCase {
  private var temporaryDirectory: URL!

  override func setUpWithError() throws {
    temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      at: temporaryDirectory,
      withIntermediateDirectories: true
    )
  }

  override func tearDownWithError() throws {
    try FileManager.default.removeItem(at: temporaryDirectory)
  }

  func testFilterAcceptsDirectoryURL() throws {
    let handler = try makeHandler()

    XCTAssertEqual(
      handler.filterDirectoryURLs([temporaryDirectory]),
      [temporaryDirectory]
    )
  }

  func testFilterRejectsFileURL() throws {
    let fileURL = temporaryDirectory.appendingPathComponent("fixture.txt")
    try Data("fixture".utf8).write(to: fileURL)
    let handler = try makeHandler()

    XCTAssertTrue(handler.filterDirectoryURLs([fileURL]).isEmpty)
  }

  func testDropHandlerInsertsSource() throws {
    let queue = try DatabaseQueue()
    let store = try Store(databaseQueue: queue, now: { 123 })
    let handler = DropZoneHandler(store: store)

    XCTAssertTrue(try handler.handleDrop(urls: [temporaryDirectory]))
    XCTAssertEqual(
      try store.listSources(),
      [
        Source(
          id: 1,
          name: temporaryDirectory.lastPathComponent,
          path: temporaryDirectory.path,
          droppedAt: 123,
          removedAt: nil
        )
      ]
    )
  }

  func testDropHandlerPostsGunkInsertedNotification() throws {
    let notificationCenter = NotificationCenter()
    let store = try Store(databaseQueue: DatabaseQueue(), now: { 123 })
    let handler = DropZoneHandler(
      store: store,
      notificationCenter: notificationCenter
    )
    var insertedSource: Source?
    let observer = notificationCenter.addObserver(
      forName: .gunkInserted,
      object: nil,
      queue: nil
    ) { notification in
      insertedSource = notification.object as? Source
    }
    defer { notificationCenter.removeObserver(observer) }

    try handler.handleDrop(urls: [temporaryDirectory])

    XCTAssertEqual(insertedSource?.path, temporaryDirectory.path)
  }

  private func makeHandler() throws -> DropZoneHandler {
    DropZoneHandler(store: try Store(databaseQueue: DatabaseQueue()))
  }
}
