import SwiftUI

/// The brand glyphs that ride the provider provenance marks (`ProviderMark`,
/// `ProviderWatermark`). Only the providers we ship artwork for resolve here;
/// everything else (Google, custom gateways, …) falls back to the mark's
/// initial-letter glyph.
enum ProviderIcon {
  case openAI
  case anthropic
  case ollama

  /// Resolves a `RunTrace.provider` string (case-insensitive, same matching
  /// vocabulary as `BrandColors.providerAccent`) to a shipped brand glyph, or
  /// `nil` when we have no artwork for it.
  static func resolve(for provider: String) -> ProviderIcon? {
    let normalized = provider.lowercased()
    if normalized.contains("anthropic") || normalized.contains("claude") {
      return .anthropic
    }
    if normalized.contains("openai") || normalized.contains("gpt") {
      return .openAI
    }
    if normalized.contains("ollama") {
      return .ollama
    }
    return nil
  }

  /// Basename of the SVG in `Resources/ProviderIcons`.
  var resourceName: String {
    switch self {
    case .openAI:
      return "openai"
    case .anthropic:
      return "anthropic"
    case .ollama:
      return "ollama"
    }
  }
}

/// Loads (and memoizes) the bundled provider SVGs as template images so they
/// can be tinted to sit on the colored provenance badge. The catalog isn't
/// compiled in the SwiftPM build, so these live as a plain copied folder and
/// load straight off disk — same approach as `DockIconController`.
@MainActor
enum ProviderIconLoader {
  private static var cache: [String: NSImage] = [:]

  static func image(for icon: ProviderIcon, bundle: Bundle = .module) -> NSImage? {
    if let cached = cache[icon.resourceName] {
      return cached
    }

    guard let url = bundle.url(
      forResource: icon.resourceName,
      withExtension: "svg",
      subdirectory: "ProviderIcons"
    ), let image = NSImage(contentsOf: url) else {
      return nil
    }

    // Template rendering lets the badge tint the glyph (white at ~95%) the
    // same way the initial-letter fallback is tinted.
    image.isTemplate = true
    cache[icon.resourceName] = image
    return image
  }
}
