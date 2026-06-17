import Foundation

enum LLMSettings {
  static let confidenceThresholdKey = "llm.confidenceThreshold"
  static let defaultConfidenceThreshold = Extractor.defaultConfidenceThreshold
  static let monthlyCostCapEnabledKey = "llm.monthlyCostCap.enabled"
  static let monthlyCostCapUSDKey = "llm.monthlyCostCap.usd"
  static let defaultMonthlyCostCapUSD = 25.0

  static func confidenceThreshold(userDefaults: UserDefaults = .standard) -> Double {
    guard userDefaults.object(forKey: confidenceThresholdKey) != nil else {
      return defaultConfidenceThreshold
    }

    return userDefaults.double(forKey: confidenceThresholdKey)
  }

  static func monthlyCostCapEnabled(userDefaults: UserDefaults = .standard) -> Bool {
    userDefaults.bool(forKey: monthlyCostCapEnabledKey)
  }

  static func monthlyCostCapUSD(userDefaults: UserDefaults = .standard) -> Double? {
    guard monthlyCostCapEnabled(userDefaults: userDefaults) else {
      return nil
    }

    let cap = userDefaults.double(forKey: monthlyCostCapUSDKey)
    return cap > 0 ? cap : nil
  }
}
