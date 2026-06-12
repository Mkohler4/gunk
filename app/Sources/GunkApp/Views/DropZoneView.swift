import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
  static let gunkInserted = Notification.Name("gunkInserted")
}

@MainActor
final class DropZoneHandler {
  private let store: Store
  private let fileManager: FileManager
  private let notificationCenter: NotificationCenter
  private let processSource: (Source) -> Void

  init(
    store: Store,
    fileManager: FileManager = .default,
    notificationCenter: NotificationCenter = .default,
    processSource: @escaping (Source) -> Void = { _ in }
  ) {
    self.store = store
    self.fileManager = fileManager
    self.notificationCenter = notificationCenter
    self.processSource = processSource
  }

  func filterDirectoryURLs(_ urls: [URL]) -> [URL] {
    urls.filter(isDirectoryURL)
  }

  @discardableResult
  func handleDrop(urls: [URL]) throws -> Bool {
    let directories = filterDirectoryURLs(urls)

    for directory in directories {
      let url = directory.standardizedFileURL
      let source = try store.insertSource(
        name: url.lastPathComponent,
        path: url.path
      )

      notificationCenter.post(name: .gunkInserted, object: source)
      processSource(source)
    }

    return !directories.isEmpty
  }

  private func isDirectoryURL(_ url: URL) -> Bool {
    guard url.isFileURL else {
      return false
    }

    var isDirectory = ObjCBool(false)
    return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }
}

/// Loads the file URLs carried by a drag session's item providers and
/// delivers the whole batch on the main actor. Used by the shell's
/// whole-window drop target (T-8.5) so the insert happens once, for all
/// dropped folders together.
enum DropPayloadLoader {
  static func loadFileURLs(
    from providers: [NSItemProvider],
    completion: @escaping @MainActor ([URL]) -> Void
  ) {
    let fileURLProviders = providers.filter {
      $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
    }

    let group = DispatchGroup()
    let lock = NSLock()
    var urls: [URL] = []

    for provider in fileURLProviders {
      group.enter()
      provider.loadItem(
        forTypeIdentifier: UTType.fileURL.identifier,
        options: nil
      ) { item, error in
        defer { group.leave() }
        guard error == nil, let url = Self.fileURL(from: item) else {
          return
        }
        lock.lock()
        urls.append(url)
        lock.unlock()
      }
    }

    group.notify(queue: .main) {
      Task { @MainActor in
        completion(urls)
      }
    }
  }

  private static func fileURL(from item: NSSecureCoding?) -> URL? {
    if let url = item as? URL {
      return url
    }

    if let url = item as? NSURL {
      return url as URL
    }

    if let data = item as? Data {
      return URL(dataRepresentation: data, relativeTo: nil)
    }

    return nil
  }
}

/// The full-window drop overlay (toolbox-v2 `.drop` / `.dropcard`): a dimmed
/// scrim over the entire shell with a centered glass card. It *floats* —
/// nothing in the underlying layout moves, and hit-testing is disabled so
/// the drag falls through to the shell's `.onDrop` (D15 extended to the
/// drag gesture).
struct WindowDropOverlay: View {
  /// Mirrors the mockup's classes: `.drop.show` (drag entered the window)
  /// and `.drop.ready` (the system is actively negotiating the drop). The
  /// error case keeps the overlay up to show invalid-drop feedback inside
  /// the card before it dismisses.
  enum Phase: Equatable {
    case hidden
    case dragOver
    case ready
    case error(String)
  }

  let phase: Phase

  /// Mockup `.drop` scrim — `rgba(8,8,10,0.55)`.
  private static let scrimOpacity = 0.55
  /// Mockup `.dropcard` — `width: min(460px, 90%)`, `border: 2px dashed`.
  private static let cardMaxWidth: CGFloat = 460
  private static let borderWidth: CGFloat = 2
  /// Mockup `.drop.ready .dropcard` — `transform: scale(1.02)` with a
  /// `0 0 0 6px` accent glow ring.
  private static let readyScale: CGFloat = 1.02
  private static let glowWidth: CGFloat = 6
  private static let glowOpacity = 0.12
  /// Mockup `.dropcard .di` — the icon lifts 3px in the ready state.
  private static let readyIconLift: CGFloat = -3

  var body: some View {
    ZStack {
      BrandColors.scrim
        .opacity(Self.scrimOpacity)
        .ignoresSafeArea()

      card
    }
    // The overlay never participates in hit-testing: drags and drops land
    // on the shell's whole-window `.onDrop` beneath it.
    .allowsHitTesting(false)
    .animation(BrandMotion.quick, value: phase)
    .accessibilityLabel("Drop folders to add them to your library")
  }

  private var card: some View {
    VStack(spacing: BrandMetrics.Spacing.md) {
      Image(systemName: "folder.badge.plus")
        .font(BrandTypography.sans(size: 44, weight: .regular))
        .foregroundStyle(isReady ? BrandColors.accent : BrandColors.textSecondary)
        .offset(y: isReady ? Self.readyIconLift : 0)

      heading
        .multilineTextAlignment(.center)

      Text("gunk decomposes each folder into reusable, verified capabilities for your agent.")
        .font(BrandTypography.body)
        .foregroundStyle(BrandColors.textSecondary)
        .multilineTextAlignment(.center)

      if case .error(let message) = phase {
        Text(message)
          .font(BrandTypography.callout)
          .foregroundStyle(BrandColors.danger)
          .multilineTextAlignment(.center)
      }
    }
    .padding(.vertical, BrandMetrics.Spacing.xl + BrandMetrics.Spacing.md)
    .padding(.horizontal, BrandMetrics.Spacing.xl + BrandMetrics.Spacing.sm)
    .frame(maxWidth: Self.cardMaxWidth)
    .brandGlass(cornerRadius: BrandMetrics.Radius.xl, elevated: true)
    .overlay {
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.xl, style: .continuous)
        .strokeBorder(borderColor, style: borderStyle)
    }
    .overlay {
      // Accent wash inside the card while drop-ready (the mockup's
      // greener `rgba(46,58,50,0.7)` background shift).
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.xl, style: .continuous)
        .fill(BrandColors.accent.opacity(
          isReady ? BrandMetrics.Control.tintedFillOpacity / 2 : 0
        ))
    }
    .overlay {
      // The ready-state glow ring (mockup `box-shadow: 0 0 0 6px`).
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.xl, style: .continuous)
        .stroke(
          BrandColors.accent.opacity(isReady ? Self.glowOpacity : 0),
          lineWidth: Self.glowWidth
        )
    }
    .scaleEffect(isReady ? Self.readyScale : 1)
    .padding(BrandMetrics.Spacing.xl)
  }

  /// Mockup `.dropcard .dh` (19/600) with the ready-state "— let go"
  /// affordance appended in accent green.
  private var heading: Text {
    let title = Text("Drop folders to add them to your library")
      .font(BrandTypography.cardTitleHero)
      .foregroundStyle(BrandColors.textPrimary)

    guard isReady else {
      return title
    }

    return title + Text(" — let go")
      .font(BrandTypography.cardTitleHero)
      .foregroundStyle(BrandColors.accent)
  }

  private var isReady: Bool {
    phase == .ready
  }

  private var borderColor: Color {
    switch phase {
    case .ready:
      return BrandColors.accent
    case .error:
      return BrandColors.danger
    case .hidden, .dragOver:
      return BrandColors.textTertiary
    }
  }

  /// Dashed while merely drag-over; solid once drop-ready (or showing the
  /// invalid-drop error), per the mockup's `border-style` flip.
  private var borderStyle: StrokeStyle {
    switch phase {
    case .ready, .error:
      return StrokeStyle(lineWidth: Self.borderWidth)
    case .hidden, .dragOver:
      return StrokeStyle(
        lineWidth: Self.borderWidth,
        dash: [BrandMetrics.Spacing.sm, BrandMetrics.Spacing.xs]
      )
    }
  }
}

// MARK: - Previews

#Preview("Drop overlay — drag over") {
  WindowDropOverlay(phase: .dragOver)
    .frame(width: 960, height: 600)
    .background(BrandColors.backgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Drop overlay — ready") {
  WindowDropOverlay(phase: .ready)
    .frame(width: 960, height: 600)
    .background(BrandColors.backgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Drop overlay — error") {
  WindowDropOverlay(phase: .error("Only folders can be added."))
    .frame(width: 960, height: 600)
    .background(BrandColors.backgroundPrimary)
    .preferredColorScheme(.dark)
}
