import Foundation
import Testing

@testable import UsageBarCore

@Suite("Update checks")
struct AppUpdateTests {
  /// Trimmed from the real `releases/latest` response for this repository.
  static let payload = Data(
    #"""
    {"tag_name":"v0.7.0","name":"v0.7.0","draft":false,"prerelease":false,
     "assets":[{"name":"UsageBar.zip","size":354117,
     "browser_download_url":"https://github.com/sergeykuzmich/UsageBar/releases/download/v0.7.0/UsageBar.zip"}]}
    """#.utf8
  )

  @Test func readsTheLatestRelease() throws {
    let release = try AppUpdate.release(from: Self.payload)

    #expect(release.tag == "v0.7.0")
    #expect(release.version == SemanticVersion("0.7.0"))
    #expect(release.downloadURL.lastPathComponent == "UsageBar.zip")
  }

  @Test func rejectsAReleaseWithoutTheAppArchive() {
    let payload = Data(
      #"{"tag_name":"v9.0.0","assets":[{"name":"source.tar.gz","browser_download_url":"https://x/y"}]}"#
        .utf8
    )

    #expect(throws: AppUpdate.ParseError.self) {
      try AppUpdate.release(from: payload)
    }
  }

  @Test func rejectsATagThatIsNotAVersion() {
    let payload = Data(
      #"{"tag_name":"nightly","assets":[{"name":"UsageBar.zip","browser_download_url":"https://x/y"}]}"#
        .utf8
    )

    #expect(throws: AppUpdate.ParseError.self) {
      try AppUpdate.release(from: payload)
    }
  }

  /// The tag carries a leading `v` and `CFBundleShortVersionString` does not, so the
  /// two have to compare equal or every launch would offer an update to itself.
  @Test func aTagMatchesTheBundleVersionItWasBuiltFrom() throws {
    #expect(SemanticVersion("v0.7.0") == SemanticVersion("0.7.0"))

    let tag = try #require(SemanticVersion("v0.7.0"))
    let bundle = try #require(SemanticVersion("0.7.0"))
    #expect((tag > bundle) == false, "a build must not offer an update to itself")
  }

  @Test(arguments: [
    ("0.7.0", "0.7.1", true), ("0.7.0", "0.8.0", true), ("0.7.0", "1.0.0", true),
    ("0.9.0", "0.10.0", true), ("0.7.0", "0.7.0", false), ("0.7.1", "0.7.0", false),
    ("1.0.0", "0.9.9", false), ("0.7", "0.7.0", false), ("0.7", "0.7.1", true),
  ])
  func comparesVersionsNumerically(current: String, latest: String, isNewer: Bool) throws {
    let a = try #require(SemanticVersion(current))
    let b = try #require(SemanticVersion(latest))

    #expect((b > a) == isNewer, "\(latest) newer than \(current) should be \(isNewer)")
  }

  @Test func toleratesSuffixedTags() {
    #expect(SemanticVersion("v1.2.0-beta1")?.components == [1, 2, 0])
    #expect(SemanticVersion("1.2.3+build9")?.components == [1, 2, 3])
  }

  @Test func rejectsNonVersions() {
    #expect(SemanticVersion("") == nil)
    #expect(SemanticVersion("latest") == nil)
    #expect(SemanticVersion("v") == nil)
  }

  @available(*, deprecated)
  @Test func legacyEndpointUsesTheCurrentRepository() {
    #expect(
      AppUpdate.latestReleaseEndpoint
        == URL(string: "https://api.github.com/repos/sergeykuzmich/UsageBar/releases/latest")
    )
  }

  @Test func createsEndpointForCanonicalRepository() {
    let endpoint = AppUpdate.latestReleaseEndpoint(repository: "sergeykuzmich/UsageBar")

    #expect(
      endpoint == URL(string: "https://api.github.com/repos/sergeykuzmich/UsageBar/releases/latest")
    )
  }

  @Test(arguments: [
    "", "owner", "/owner", "owner/", "owner//repo", "owner/repo/extra", "owner//", "/",
    " owner/repo", "owner /repo", "owner/repo ", "-owner/repo", "owner/repo?x=y",
    "owner/repo#fragment", "owner/re/po", "owner/.", "owner/..", "owner/../repo",
    "owner//../po",
  ])
  func rejectsInvalidRepositoryStrings(repository: String) {
    #expect(AppUpdate.latestReleaseEndpoint(repository: repository) == nil)
  }

  @Test(arguments: [
    "github/.github", "981011512/--", "owner/foo--bar", "owner/foo..bar", "owner/repo-",
    "owner/repo_",
  ])
  func acceptsGitHubRepositoryNamesInAnyPlacement(repository: String) {
    let endpoint = AppUpdate.latestReleaseEndpoint(repository: repository)

    #expect(endpoint?.path == "/repos/\(repository)/releases/latest")
  }

  @Test func acceptsGitHubLikeCanonicalRepository() {
    #expect(
      AppUpdate.latestReleaseEndpoint(repository: "or-gane/UsageBar-01")
        == URL(string: "https://api.github.com/repos/or-gane/UsageBar-01/releases/latest")
    )
  }
}
