import Darwin
import Foundation

/// Token from `~/.kimi-code/credentials/kimi-code.json`.
///
/// Kimi Code CLI signs in through auth.kimi.com and writes the OAuth session
/// here — one file per managed provider, and `kimi-code` is the Kimi Code
/// account itself. The access token lives fifteen minutes (`expires_in: 900`)
/// and the refresh token beside it is single-use: it mints the next pair, and
/// whoever holds the newest one holds the session. Reading the file is
/// therefore not enough on its own — `KimiTokenRefresher` renews it the way the
/// CLI does, and that file is where the argument lives.
///
/// `KIMI_CODE_HOME` moves the whole data root, so every path below honours it.
struct KimiCredentials {
    /// The CLI's data root: `KIMI_CODE_HOME`, else `~/.kimi-code`.
    ///
    /// Everything this app touches inside it — the credential, the refresh
    /// lock, the device id — is addressed from here, so a single URL is enough
    /// to point a test at a temporary directory.
    static var homeURL: URL {
        let override = ProcessInfo.processInfo.environment["KIMI_CODE_HOME"]
            .flatMap { value -> String? in value.isEmpty ? nil : value }
        return override.map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".kimi-code")
    }

    static var authURL: URL { authURL(in: homeURL) }

    static func authURL(in home: URL) -> URL {
        home.appendingPathComponent("credentials/kimi-code.json")
    }

    /// The data root that holds the credential at `url` — the inverse of
    /// `authURL(in:)`, for callers handed the file rather than the root.
    static func homeURL(containing url: URL) -> URL {
        url.deletingLastPathComponent().deletingLastPathComponent()
    }

    let accessToken: String
    /// The token that mints the next access token. Empty when the file carries
    /// none — a session nobody can renew, the CLI included.
    let refreshToken: String
    let expiresAt: Date
    /// The lifetime the server granted, in seconds. Zero when the file carries
    /// none, which is what the CLI's tombstone for a rejected credential holds.
    let expiresIn: TimeInterval
    /// Both come from the server and are carried through so a file this app
    /// renews still looks like one the CLI wrote.
    let scope: String
    let tokenType: String

    var isExpired: Bool { expiresAt <= Date() }

    /// How close to expiry a renewal is worth making, matching the CLI's own
    /// rule: half the token's life, never less than five minutes. Fifteen-minute
    /// tokens therefore renew with 7m30s left.
    ///
    /// Sharing the CLI's arithmetic is the point of the exercise. Renewing
    /// earlier spends a request the CLI is about to make anyway; renewing later
    /// leaves a window in which the token is dead and a reading is missed —
    /// which, at the store's idle cadence, is five minutes of a frozen ring.
    static func renewalMargin(expiresIn: TimeInterval) -> TimeInterval {
        expiresIn > 0 ? max(300, expiresIn / 2) : 300
    }

    /// Whether the token is inside the renewal margin.
    ///
    /// A file that does not say how long its token lives falls back to plain
    /// expiry: nothing is known about the lifetime, so the honest moment to
    /// renew is when it has run out.
    func needsRenewal(now: Date = Date()) -> Bool {
        guard expiresIn > 0 else { return expiresAt <= now }
        return expiresAt.timeIntervalSince(now) < Self.renewalMargin(expiresIn: expiresIn)
    }

    static func account(from url: URL = authURL) -> ProviderAccount? {
        guard (try? load(from: url)) != nil else { return nil }
        return ProviderAccount(
            label: nil,   // the token carries no address
            plan: nil,
            source: "Kimi Code",
            manageURL: URL(string: "https://www.kimi.com/code/console")
        )
    }

    static func load(from url: URL = authURL) throws -> KimiCredentials {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = root["access_token"] as? String, !token.isEmpty
        else { throw UsageProviderError.needsAuth }

        // `expires_at` is epoch seconds. A file without one is not a session
        // to trust with a request that cannot succeed.
        guard let expires = (root["expires_at"] as? NSNumber)?.doubleValue, expires > 0
        else { throw UsageProviderError.needsAuth }

        return KimiCredentials(accessToken: token,
                               refreshToken: root["refresh_token"] as? String ?? "",
                               expiresAt: Date(timeIntervalSince1970: expires),
                               expiresIn: (root["expires_in"] as? NSNumber)?.doubleValue ?? 0,
                               scope: root["scope"] as? String ?? "",
                               tokenType: root["token_type"] as? String ?? "")
    }

    /// Store a renewed credential the way the CLI stores one: the same six
    /// snake_case keys, the same mode 0600, and the same atomicity — a
    /// temporary file built to completion and then renamed over the target, so
    /// nothing can read a half-written session.
    ///
    /// Byte-for-byte identity with the CLI is not the goal and is not claimed:
    /// the keys are written sorted rather than in the CLI's order. What has to
    /// hold is that the CLI's own reader sees every field it looks for, and
    /// `KimiCredentialsTests` pins that by reading a written file back.
    static func write(_ credentials: KimiCredentials, to url: URL,
                      fileManager: FileManager = .default) throws {
        let root: [String: Any] = [
            "access_token": credentials.accessToken,
            "refresh_token": credentials.refreshToken,
            "expires_at": Int(credentials.expiresAt.timeIntervalSince1970.rounded(.down)),
            "scope": credentials.scope,
            "token_type": credentials.tokenType,
            "expires_in": Int(credentials.expiresIn),
        ]
        var data = try JSONSerialization.data(withJSONObject: root,
                                             options: [.prettyPrinted, .sortedKeys])
        data.append(0x0A)   // the CLI's file ends in a newline

        let directory = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
        }

        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        guard fileManager.createFile(atPath: temporary.path, contents: data,
                                     attributes: [.posixPermissions: 0o600]) else {
            throw POSIXError(.EIO)
        }
        // `createFile` passes the mode through `open(2)`, which umask filters —
        // so the mode is set again, while the file is still unreachable under
        // its temporary name.
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)

        guard rename(temporary.path, url.path) == 0 else {
            let code = errno
            try? fileManager.removeItem(at: temporary)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }
}
