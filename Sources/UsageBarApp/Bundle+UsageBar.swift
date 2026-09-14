import Foundation

extension Bundle {
  var usageBarUpdateRepository: String? {
    object(forInfoDictionaryKey: "UsageBarUpdateRepository") as? String
  }
}
