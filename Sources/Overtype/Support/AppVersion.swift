import Foundation

/// What the running build declares about itself, formatted for display.
///
/// Read-only: nothing here is persisted, sent anywhere, or written back to the
/// bundle. The values are stamped into `Info.plist` at build time by
/// `scripts/build-app.sh`; see `specs/006-settings-version-display/`.
public struct AppVersion: Equatable {
  /// The released, user-facing version, e.g. `1.2.1` (`CFBundleShortVersionString`).
  public let shortVersion: String?

  /// The build identifier, e.g. `20` (`CFBundleVersion`). Treated as an opaque
  /// string and never parsed as a number.
  public let build: String?

  public static let unknownPlaceholder = "Unknown"

  public init(shortVersion: String?, build: String?) {
    self.shortVersion = shortVersion
    self.build = build
  }

  /// The version of the running application, read from its bundle metadata.
  ///
  /// Both keys are absent when the executable runs outside an app bundle (a raw
  /// `swift run`, or the test runner), which is why `displayString` has to cope
  /// with missing values rather than assume them.
  public static var current: AppVersion {
    let info = Bundle.main.infoDictionary
    return AppVersion(
      shortVersion: info?["CFBundleShortVersionString"] as? String,
      build: info?["CFBundleVersion"] as? String
    )
  }

  /// The exact text shown on the Settings General tab. Never empty.
  ///
  /// - Both values present: `1.2.1 (20)`
  /// - Build missing: `1.2.1` (a bare build number identifies nothing to a user,
  ///   but a version without one is still useful)
  /// - Version missing: `Unknown` (an explicit placeholder beats a blank)
  public var displayString: String {
    guard let version = Self.normalized(shortVersion) else {
      return Self.unknownPlaceholder
    }
    guard let build = Self.normalized(build) else {
      return version
    }
    return "\(version) (\(build))"
  }

  /// Trims surrounding whitespace and treats an empty result as absent, so a
  /// plist value of `""` or `"  "` behaves exactly like a missing key.
  private static func normalized(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !trimmed.isEmpty
    else {
      return nil
    }
    return trimmed
  }
}
