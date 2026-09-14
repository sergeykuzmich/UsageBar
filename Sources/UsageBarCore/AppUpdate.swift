import Foundation

public struct SemanticVersion: Sendable, Equatable, Comparable, CustomStringConvertible {
  public let components: [Int]

  /// Accepts `v0.7.0` and `0.7.0` alike, since the tag carries the `v` and the bundle
  /// version does not.
  public init?(_ raw: String) {
    let trimmed = raw.trimmingCharacters(in: .whitespaces).drop { $0 == "v" || $0 == "V" }
    let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
    guard !parts.isEmpty else { return nil }
    var parsed: [Int] = []
    for part in parts {
      // Stops at the first pre-release or build suffix, e.g. `1.2.0-beta1`.
      let digits = part.prefix { $0.isNumber }
      guard let value = Int(digits) else { return nil }
      parsed.append(value)
      if digits.count != part.count { break }
    }
    components = parsed
  }

  public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
    for index in 0..<max(lhs.components.count, rhs.components.count) {
      let left = index < lhs.components.count ? lhs.components[index] : 0
      let right = index < rhs.components.count ? rhs.components[index] : 0
      if left != right { return left < right }
    }
    return false
  }

  public var description: String {
    components.map(String.init).joined(separator: ".")
  }
}

public struct AppRelease: Sendable, Equatable {
  public let version: SemanticVersion
  public let tag: String
  public let downloadURL: URL

  public init(version: SemanticVersion, tag: String, downloadURL: URL) {
    self.version = version
    self.tag = tag
    self.downloadURL = downloadURL
  }
}

public enum AppUpdate {
  @available(
    *, deprecated,
    message: "Pass an explicit repository to latestReleaseEndpoint(repository:) instead."
  )
  public static let latestReleaseEndpoint = URL(
    string: "https://api.github.com/repos/sergeykuzmich/UsageBar/releases/latest"
  )!

  public static let assetName = "UsageBar.zip"
  /// Unauthenticated GitHub API calls are capped per hour per address, and a menu bar
  /// app has no business asking more often than this anyway.
  public static let checkInterval: TimeInterval = 6 * 3600

  public struct ParseError: Error, LocalizedError, Equatable {
    public let message: String

    public init(message: String) {
      self.message = message
    }

    public var errorDescription: String? { message }
  }

  private static let maxOwnerLength = 39
  private static let maxRepositoryLength = 100

  private static func isASCIIAlphanumeric(_ character: Character) -> Bool {
    guard
      character.unicodeScalars.count == 1,
      let scalar = character.unicodeScalars.first,
      scalar.value < 128
    else {
      return false
    }

    return CharacterSet.alphanumerics.contains(scalar)
  }

  private static func isCanonicalOwner(_ value: Substring) -> Bool {
    guard !value.isEmpty, value.count <= maxOwnerLength else { return false }
    guard
      let first = value.first,
      let last = value.last,
      isASCIIAlphanumeric(first),
      isASCIIAlphanumeric(last)
    else {
      return false
    }

    var previousCharacterWasSeparator = false
    for character in value {
      if isASCIIAlphanumeric(character) {
        previousCharacterWasSeparator = false
        continue
      }

      if character == "-" {
        if previousCharacterWasSeparator { return false }
        previousCharacterWasSeparator = true
        continue
      }

      return false
    }

    return true
  }

  private static func isCanonicalRepository(_ value: Substring) -> Bool {
    guard
      !value.isEmpty,
      value.count <= maxRepositoryLength,
      value != ".",
      value != ".."
    else {
      return false
    }

    return value.allSatisfy {
      isASCIIAlphanumeric($0) || $0 == "-" || $0 == "_" || $0 == "."
    }
  }

  private struct Payload: Decodable {
    struct Asset: Decodable {
      let name: String
      let browserDownloadURL: URL

      private enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
      }
    }

    let tagName: String
    let assets: [Asset]

    private enum CodingKeys: String, CodingKey {
      case tagName = "tag_name"
      case assets
    }
  }

  public static func release(from data: Data) throws -> AppRelease {
    guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
      throw ParseError(message: "Could not read the release feed.")
    }
    guard let version = SemanticVersion(payload.tagName) else {
      throw ParseError(message: "Release \(payload.tagName) is not a version number.")
    }
    guard let asset = payload.assets.first(where: { $0.name == assetName }) else {
      throw ParseError(message: "Release \(payload.tagName) has no \(assetName).")
    }
    return AppRelease(
      version: version,
      tag: payload.tagName,
      downloadURL: asset.browserDownloadURL
    )
  }

  public static func latestReleaseEndpoint(repository: String) -> URL? {
    let components = repository.split(separator: "/", omittingEmptySubsequences: false)

    guard
      components.count == 2,
      isCanonicalOwner(components[0]),
      isCanonicalRepository(components[1])
    else {
      return nil
    }

    var url = URLComponents()
    url.scheme = "https"
    url.host = "api.github.com"
    url.path = "/repos/\(components[0])/\(components[1])/releases/latest"
    return url.url
  }

  @available(
    *, deprecated,
    message: "Pass an explicit repository to fetchLatest(repository:session:) instead."
  )
  public static func fetchLatest(session: URLSession = .shared) async throws -> AppRelease {
    try await fetchLatest(repository: "lucas-barake/usagebar", session: session)
  }

  public static func fetchLatest(
    repository: String,
    session: URLSession = .shared
  ) async throws -> AppRelease {
    guard let endpoint = latestReleaseEndpoint(repository: repository) else {
      throw ParseError(message: "Could not determine the update repository.")
    }

    var request = URLRequest(url: endpoint)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.timeoutInterval = 15

    let (data, response) = try await session.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else {
      throw ParseError(message: "Update check failed (HTTP \(status)).")
    }
    return try release(from: data)
  }
}
