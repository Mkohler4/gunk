import AppKit
import SwiftUI

/// CP2 review surface: every design token and component on one scrollable,
/// glass-backed screen. Dev-only — reachable through the Debug menu, which
/// only exists when the app launches with `GUNK_DESIGN_GALLERY=1` (see
/// `ComponentGalleryLauncher`). Not part of the shipping UI.
struct ComponentGalleryView: View {
  /// Starts in dark; `GUNK_DESIGN_GALLERY_APPEARANCE=light|dark` overrides so
  /// scripted screenshot runs can launch straight into either mode.
  @State private var appearance: GalleryAppearance =
    GalleryAppearance(
      rawValue: ProcessInfo.processInfo.environment["GUNK_DESIGN_GALLERY_APPEARANCE"] ?? ""
    ) ?? .dark
  @State private var motionToggled = false

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [BrandColors.accent.opacity(0.35), BrandColors.backgroundPrimary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .ignoresSafeArea()

      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xl) {
            header.id("header")
            paletteSection.id("palette")
            typographySection.id("type")
            metricsSection.id("metrics")
            motionSection.id("motion")
            markSection.id("mark")
            buttonSection.id("buttons")
            chipAndBadgeSection.id("chips")
            cardSection.id("cards")
            sidebarSection.id("sidebar")
            emptyStateSection.id("empty")
          }
          .padding(BrandMetrics.Spacing.xl)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
          // Dev-only: lets scripted screenshot runs jump to a section, e.g.
          // GUNK_DESIGN_GALLERY_SECTION=buttons.
          if let section = ProcessInfo.processInfo.environment["GUNK_DESIGN_GALLERY_SECTION"] {
            proxy.scrollTo(section, anchor: .top)
          }
        }
      }
    }
    .background(WindowAppearanceSetter(appearanceName: appearance.appearanceName))
    .environment(\.colorScheme, appearance.colorScheme)
  }

  // MARK: Header

  private var header: some View {
    HStack(alignment: .center, spacing: BrandMetrics.Spacing.lg) {
      BrandMark(size: BrandMetrics.Mark.medium, isAnimated: true)
      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
        Text("Component gallery")
          .font(BrandTypography.title)
          .foregroundStyle(BrandColors.textPrimary)
        Text("Every brand token and component — CP2 review surface, dev-only.")
          .font(BrandTypography.callout)
          .foregroundStyle(BrandColors.textSecondary)
      }

      Spacer()

      Picker("Appearance", selection: $appearance) {
        ForEach(GalleryAppearance.allCases) { mode in
          Text(mode.label).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .frame(width: 160)
    }
  }

  // MARK: Tokens

  private var paletteSection: some View {
    section("Palette — BrandColors", systemImage: "paintpalette") {
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 132), spacing: BrandMetrics.Spacing.md)],
        alignment: .leading,
        spacing: BrandMetrics.Spacing.md
      ) {
        ForEach(Self.paletteTokens, id: \.0) { name, color in
          VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
            RoundedRectangle(cornerRadius: BrandMetrics.Radius.small)
              .fill(color)
              .frame(height: 36)
              .overlay(
                RoundedRectangle(cornerRadius: BrandMetrics.Radius.small)
                  .strokeBorder(BrandColors.separator)
              )
            Text(name)
              .font(BrandTypography.mono)
              .foregroundStyle(BrandColors.textSecondary)
          }
        }
      }
    }
  }

  private var typographySection: some View {
    section("Type scale — BrandTypography", systemImage: "textformat.size") {
      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
        ForEach(Self.typeSteps, id: \.0) { name, font in
          HStack(alignment: .firstTextBaseline, spacing: BrandMetrics.Spacing.lg) {
            Text(name)
              .font(BrandTypography.mono)
              .foregroundStyle(BrandColors.textTertiary)
              .frame(width: 76, alignment: .trailing)
            Text("Born from the goo.")
              .font(font)
              .foregroundStyle(BrandColors.textPrimary)
          }
        }
      }
    }
  }

  private var metricsSection: some View {
    section("Spacing & radius — BrandMetrics", systemImage: "ruler") {
      HStack(alignment: .top, spacing: BrandMetrics.Spacing.xl) {
        VStack(alignment: .leading, spacing: BrandMetrics.Spacing.sm) {
          ForEach(Self.spacingSteps, id: \.0) { name, value in
            HStack(spacing: BrandMetrics.Spacing.md) {
              Text(name)
                .font(BrandTypography.mono)
                .foregroundStyle(BrandColors.textTertiary)
                .frame(width: 24, alignment: .trailing)
              RoundedRectangle(cornerRadius: BrandMetrics.Radius.small)
                .fill(BrandColors.accent)
                .frame(width: value * 4, height: BrandMetrics.Spacing.sm)
              Text(Int(value), format: .number)
                .font(BrandTypography.caption)
                .foregroundStyle(BrandColors.textSecondary)
            }
          }
        }

        HStack(alignment: .bottom, spacing: BrandMetrics.Spacing.lg) {
          ForEach(Self.radiusSteps, id: \.0) { name, value in
            VStack(spacing: BrandMetrics.Spacing.xs) {
              RoundedRectangle(cornerRadius: value)
                .fill(BrandColors.surfaceGlass)
                .overlay(
                  RoundedRectangle(cornerRadius: value)
                    .strokeBorder(BrandColors.accent)
                )
                .frame(width: 56, height: 56)
              Text(name)
                .font(BrandTypography.mono)
                .foregroundStyle(BrandColors.textTertiary)
            }
          }
        }
      }
    }
  }

  private var motionSection: some View {
    section("Motion — BrandMotion", systemImage: "waveform.path") {
      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
        ForEach(Self.motionTokens, id: \.0) { name, animation in
          HStack(spacing: BrandMetrics.Spacing.lg) {
            Text(name)
              .font(BrandTypography.mono)
              .foregroundStyle(BrandColors.textSecondary)
              .frame(width: 76, alignment: .trailing)
            Circle()
              .fill(BrandColors.accent)
              .frame(width: 14, height: 14)
              .offset(x: motionToggled ? 200 : 0)
              .animation(animation, value: motionToggled)
          }
        }
        Button(motionToggled ? "Reset" : "Play") {
          motionToggled.toggle()
        }
        .buttonStyle(.brandSecondary)
      }
    }
  }

  private var markSection: some View {
    section("Brand mark — the Ooze", systemImage: "face.smiling") {
      HStack(alignment: .bottom, spacing: BrandMetrics.Spacing.xl) {
        VStack(spacing: BrandMetrics.Spacing.xs) {
          BrandMark(size: BrandMetrics.Mark.hero, isAnimated: true)
          Text("hero · alive")
            .font(BrandTypography.caption)
            .foregroundStyle(BrandColors.textTertiary)
        }
        ForEach(Self.markSizes, id: \.0) { name, size in
          VStack(spacing: BrandMetrics.Spacing.xs) {
            BrandMark(size: size)
            Text(name)
              .font(BrandTypography.caption)
              .foregroundStyle(BrandColors.textTertiary)
          }
        }
      }
    }
  }

  // MARK: Components

  private var buttonSection: some View {
    section("Buttons — BrandButton", systemImage: "button.horizontal") {
      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
        HStack(spacing: BrandMetrics.Spacing.md) {
          Button("Primary") {}.buttonStyle(.brandPrimary)
          Button("Secondary") {}.buttonStyle(.brandSecondary)
          Button("Destructive") {}.buttonStyle(.brandDestructive)
          Button {} label: { Image(systemName: "folder") }.buttonStyle(.brandIcon)
          Button {} label: { Image(systemName: "arrow.triangle.2.circlepath") }
            .buttonStyle(.brandIcon)
          Button {} label: { Image(systemName: "trash") }.buttonStyle(.brandIcon)
        }
        HStack(spacing: BrandMetrics.Spacing.md) {
          Button("Primary") {}.buttonStyle(.brandPrimary)
          Button("Secondary") {}.buttonStyle(.brandSecondary)
          Button("Destructive") {}.buttonStyle(.brandDestructive)
          Button {} label: { Image(systemName: "folder") }.buttonStyle(.brandIcon)
        }
        .disabled(true)
        Button {} label: {
          Label("With a glyph", systemImage: "sparkles")
        }
        .buttonStyle(.brandSecondary)
      }
    }
  }

  private var chipAndBadgeSection: some View {
    section("Chips & badges — TagChip / StatusBadge", systemImage: "tag") {
      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
        HStack(spacing: BrandMetrics.Spacing.xs) {
          TagChip("auth")
          TagChip("payments")
          TagChip("mobile")
          TagChip("api-client")
          TagChip("untagged")
        }
        HStack(spacing: BrandMetrics.Spacing.sm) {
          StatusBadge("Passed", variant: .success, systemImage: "checkmark.circle")
          StatusBadge("Needs attention", variant: .warning, systemImage: "exclamationmark.triangle")
          StatusBadge("Failed", variant: .danger, systemImage: "xmark.circle")
          StatusBadge("Not verified", variant: .neutral, systemImage: "questionmark.circle")
        }
        HStack(spacing: BrandMetrics.Spacing.sm) {
          StatusBadge("Approved", variant: .success)
          StatusBadge("Pending", variant: .neutral)
          StatusBadge("92%", variant: .success)
        }
      }
    }
  }

  private var cardSection: some View {
    section("Cards — GlassCard", systemImage: "rectangle.on.rectangle") {
      HStack(alignment: .top, spacing: BrandMetrics.Spacing.lg) {
        GlassCard {
          VStack(alignment: .leading, spacing: BrandMetrics.Spacing.sm) {
            SectionHeader("Elevated", systemImage: "square.stack.3d.up")
            Text("Default padding, large radius, floating shadow.")
              .font(BrandTypography.callout)
              .foregroundStyle(BrandColors.textSecondary)
            HStack(spacing: BrandMetrics.Spacing.xs) {
              TagChip("auth")
              StatusBadge("Passed", variant: .success)
            }
          }
        }

        GlassCard(
          padding: BrandMetrics.Spacing.md,
          cornerRadius: BrandMetrics.Radius.medium,
          elevated: false
        ) {
          VStack(alignment: .leading, spacing: BrandMetrics.Spacing.sm) {
            SectionHeader("Flat", systemImage: "square.on.square")
            Text("Tight padding, medium radius, no shadow.")
              .font(BrandTypography.callout)
              .foregroundStyle(BrandColors.textSecondary)
          }
        }
      }
    }
  }

  private var sidebarSection: some View {
    section("Sidebar shell — GlassSidebar", systemImage: "sidebar.left") {
      GlassSidebar {
        HStack(spacing: BrandMetrics.Spacing.sm) {
          BrandMark(size: BrandMetrics.Mark.medium)
          Text("gunk")
            .font(BrandTypography.title)
            .foregroundStyle(BrandColors.textPrimary)
        }
      } content: {
        VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
          ForEach(Self.sidebarItems, id: \.self) { item in
            Text(item)
              .font(BrandTypography.body)
              .foregroundStyle(
                item == "Modules" ? BrandColors.accent : BrandColors.textSecondary
              )
              .padding(.horizontal, BrandMetrics.Spacing.sm)
              .padding(.vertical, BrandMetrics.Spacing.xs)
          }
        }
      } footer: {
        Text("v0.7 · local store")
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.textTertiary)
      }
      .frame(width: 220, height: 320)
    }
  }

  private var emptyStateSection: some View {
    section("Empty state — EmptyStateView", systemImage: "tray") {
      EmptyStateView(
        "No modules",
        message: "Drop a folder on the bin to decompose it into reusable modules."
      ) {
        Button("Add a source") {}.buttonStyle(.brandPrimary)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 280)
    }
  }

  // MARK: Layout helpers

  private func section(
    _ title: String,
    systemImage: String,
    @ViewBuilder content: () -> some View
  ) -> some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
      SectionHeader(title, systemImage: systemImage)
      content()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandMetrics.Spacing.lg)
        .brandGlass(elevated: false)
    }
  }

  // MARK: Inventory

  private static let paletteTokens: [(String, Color)] = [
    ("backgroundPrimary", BrandColors.backgroundPrimary),
    ("backgroundSecondary", BrandColors.backgroundSecondary),
    ("backgroundElevated", BrandColors.backgroundElevated),
    ("backgroundElevatedHover", BrandColors.backgroundElevatedHover),
    ("surfaceGlass", BrandColors.surfaceGlass),
    ("accent", BrandColors.accent),
    ("accentSecondary", BrandColors.accentSecondary),
    ("textPrimary", BrandColors.textPrimary),
    ("textSecondary", BrandColors.textSecondary),
    ("textTertiary", BrandColors.textTertiary),
    ("success", BrandColors.success),
    ("warning", BrandColors.warning),
    ("danger", BrandColors.danger),
    ("separator", BrandColors.separator),
    ("provider.anthropic", BrandColors.Provider.anthropic),
    ("provider.openAI", BrandColors.Provider.openAI),
    ("provider.google", BrandColors.Provider.google),
    ("provider.neutral", BrandColors.Provider.neutral),
  ]

  private static let typeSteps: [(String, Font)] = [
    ("display", BrandTypography.display),
    ("title", BrandTypography.title),
    ("headline", BrandTypography.headline),
    ("body", BrandTypography.body),
    ("callout", BrandTypography.callout),
    ("caption", BrandTypography.caption),
    ("mono", BrandTypography.mono),
  ]

  private static let spacingSteps: [(String, CGFloat)] = [
    ("xs", BrandMetrics.Spacing.xs),
    ("sm", BrandMetrics.Spacing.sm),
    ("md", BrandMetrics.Spacing.md),
    ("lg", BrandMetrics.Spacing.lg),
    ("xl", BrandMetrics.Spacing.xl),
  ]

  private static let radiusSteps: [(String, CGFloat)] = [
    ("small", BrandMetrics.Radius.small),
    ("medium", BrandMetrics.Radius.medium),
    ("large", BrandMetrics.Radius.large),
    ("pill", BrandMetrics.Radius.pill),
  ]

  private static let motionTokens: [(String, Animation)] = [
    ("quick", BrandMotion.quick),
    ("standard", BrandMotion.standard),
    ("smooth", BrandMotion.smooth),
    ("settle", BrandMotion.settle),
    ("hop", BrandMotion.hop),
  ]

  private static let markSizes: [(String, CGFloat)] = [
    ("large", BrandMetrics.Mark.large),
    ("medium", BrandMetrics.Mark.medium),
    ("small", BrandMetrics.Mark.small),
  ]

  private static let sidebarItems = ["Sources", "Modules", "Runs", "Approval", "Settings"]
}

// MARK: - Appearance switching (dev-only review aid)

private enum GalleryAppearance: String, CaseIterable, Identifiable {
  case light
  case dark

  var id: String { rawValue }

  var label: String {
    switch self {
    case .light: return "Light"
    case .dark: return "Dark"
    }
  }

  var colorScheme: ColorScheme {
    switch self {
    case .light: return .light
    case .dark: return .dark
    }
  }

  var appearanceName: NSAppearance.Name {
    switch self {
    case .light: return .aqua
    case .dark: return .darkAqua
    }
  }
}

/// Applies the selected appearance to the hosting window so the real glass
/// material re-renders, not just the SwiftUI color tokens.
private struct WindowAppearanceSetter: NSViewRepresentable {
  let appearanceName: NSAppearance.Name

  func makeNSView(context: Context) -> NSView {
    NSView()
  }

  func updateNSView(_ view: NSView, context: Context) {
    DispatchQueue.main.async {
      view.window?.appearance = NSAppearance(named: appearanceName)
    }
  }
}

// MARK: - Dev-only launcher

/// Opens the gallery in its own window. The Debug menu (and therefore any
/// path to this) only exists when the app is launched with
/// `GUNK_DESIGN_GALLERY=1`, keeping the gallery out of the shipping UI.
@MainActor
final class ComponentGalleryLauncher: NSObject {
  static let shared = ComponentGalleryLauncher()
  static let environmentFlag = "GUNK_DESIGN_GALLERY"

  static var isEnabled: Bool {
    ProcessInfo.processInfo.environment[environmentFlag] == "1"
  }

  private var window: NSWindow?

  @objc
  func showGallery(_ sender: Any? = nil) {
    if let window {
      window.makeKeyAndOrderFront(nil)
      return
    }

    let hostingController = NSHostingController(rootView: ComponentGalleryView())
    // Keep the window at its set frame; otherwise the hosting controller
    // collapses it to the ScrollView's ideal (near-zero) height.
    hostingController.sizingOptions = []
    let galleryWindow = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    galleryWindow.title = "gunk — Component Gallery"
    galleryWindow.contentViewController = hostingController
    galleryWindow.setContentSize(NSSize(width: 1080, height: 760))
    galleryWindow.isReleasedWhenClosed = false
    galleryWindow.center()
    window = galleryWindow
    galleryWindow.makeKeyAndOrderFront(nil)
  }
}

#Preview("Component gallery") {
  ComponentGalleryView()
    .frame(width: 1080, height: 760)
}
