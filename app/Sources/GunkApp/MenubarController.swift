import AppKit
import SwiftUI

@MainActor
final class MenubarController {
  private let statusItem: NSStatusItem
  private let popover: NSPopover

  init(store: Store) {
    self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.popover = NSPopover()

    configureStatusItem()
    configurePopover(store: store)
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

  private func configurePopover(store: Store) {
    popover.behavior = .transient
    popover.contentSize = NSSize(width: 320, height: 220)
    popover.contentViewController = NSHostingController(
      rootView: PopoverView(dropHandler: DropZoneHandler(store: store))
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
