import Foundation

enum LLMSettings {
  static let confidenceThresholdKey = "llm.confidenceThreshold"
  static let defaultConfidenceThreshold = Extractor.defaultConfidenceThreshold

  static func confidenceThreshold(userDefaults: UserDefaults = .standard) -> Double {
    guard userDefaults.object(forKey: confidenceThresholdKey) != nil else {
      return defaultConfidenceThreshold
    }

    return userDefaults.double(forKey: confidenceThresholdKey)
  }
}
