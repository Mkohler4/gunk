import AppKit
import SwiftUI

@MainActor
final class MenubarController {
  private let statusItem: NSStatusItem
  private let popover: NSPopover

  init(
    store: Store,
    processingModel: ProcessingModel,
    sourceProcessingRunner: SourceProcessingRunner
  ) {
    self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.popover = NSPopover()

    configureStatusItem()
    configurePopover(
      store: store,
      processingModel: processingModel,
      sourceProcessingRunner: sourceProcessingRunner
    )
  }

  private func configureStatusItem() {
    guard let button = statusItem.button else {
      return
    }

    button.title = "G"
    button.toolTip = "gunk"
    button.target = self
    button.action = #selector(togglePopover)
  }

  private func configurePopover(
    store: Store,
    processingModel: ProcessingModel,
    sourceProcessingRunner: SourceProcessingRunner
  ) {
    popover.behavior = .transient
    popover.contentSize = NSSize(width: 520, height: 560)
    popover.contentViewController = NSHostingController(
      rootView: PopoverView(
        browseModel: BrowseModel(store: store),
        store: store,
        processingModel: processingModel,
        sourceProcessingRunner: sourceProcessingRunner
      )
    )
  }

  @objc
  private func togglePopover() {
    guard let button = statusItem.button else {
      return
    }

    if popover.isShown {
      popover.performClose(nil)
    } else {
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      popover.contentViewController?.view.window?.becomeKey()
    }
  }
}
