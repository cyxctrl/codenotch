import Darwin
import Foundation
import os

/// Renews the Kimi Code credential the CLI leaves in `~/.kimi-code`, so a quota
/// reading does not die fifteen minutes after the last `kimi` command.
///
/// **Why this exists.** Kimi grants a 900-second access token and a single-use
/// refresh token beside it. Only the CLI renews them, and only while it is
/// running — on a day the user does not open `kimi`, nothing does. A provider
/// that merely reads the file therefore works for a quarter of an hour after
/// each sign-in and then reports `credentialExpired` for the rest of the day,
/// with the last reading kept. That is where "the Kimi ring is stuck on
/// Resetting…" comes from: the frozen reading's windows are past their reset
/// times, and `ResetCopy` says "Resetting…" for exactly that state, because it
/// assumes a refetch is a moment away.
///
/// **What renews it, and what that costs.** The request the CLI makes: a
/// `refresh_token` grant at the CLI's own token endpoint, with the CLI's own
/// public client id, under the CLI's own cross-process lock, written back in
/// the CLI's own file shape. Every part of that is private behaviour rather than
/// an interface Kimi promises, so it is treated the way `ClaudeTokenRefresher`
/// treats `claude -p` — as a compatibility mechanism judged by its outcome.
///
/// The failure modes are chosen rather than accidental:
///
/// - The endpoint cannot be reached, or answers with something unusable → the
///   credential is left exactly as it was found and the provider reports
///   `credentialExpired`, which is what it reported before this file existed.
/// - The endpoint refuses the refresh token (`invalid_grant`, 401, 403) →
///   `needsAuth`. Nothing on this machine can renew that session; only signing
///   in again can, and the CLI draws the same conclusion.
/// - The lock cannot be taken inside the CLI's own retry budget → the
///   credential is left alone. Somebody else is renewing it; waiting for them
///   is the answer, not a second renewal.
actor KimiTokenRefresher {
    /// The CLI's client id for the managed Kimi Code account, as the CLI itself
    /// hard-codes it. Required by the grant, and not a secret: it identifies the
    /// application, not the user.
    static let clientID = "17e5f671-d194-4dfb-9706-5516cb48c098"

    private let session: URLSession
    private let home: URL
    private let environment: [String: String]
    private let now: () -> Date
    private let sleep: (TimeInterval) async throws -> Void
    /// Only injected by a test that wants the request to look like a bare
    /// machine's. The real one is built on demand — see `identityHeaders`.
    private let injectedHeaders: (() -> [String: String])?


    /// The one renewal in flight, so ten ticks cannot become ten grants.
    private var inFlight: Task<KimiCredentials, Error>?

    init(session: URLSession = .shared,
         home: URL = KimiCredentials.homeURL,
         environment: [String: String] = ProcessInfo.processInfo.environment,
         now: @escaping () -> Date = Date.init,
         sleep: @escaping (TimeInterval) async throws -> Void = { seconds in
             try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
         },
         headers: (() -> [String: String])? = nil) {
        self.session = session
        self.home = home
        self.environment = environment
        self.now = now
        self.sleep = sleep
        self.injectedHeaders = headers
    }

    /// What the CLI sends as its own identity. Built here rather than handed
    /// in, so the only thing crossing into this actor is the session.
    private func identityHeaders() -> [String: String] {
        injectedHeaders?() ?? KimiDeviceIdentity.headers(home: home)
    }

    private var authURL: URL { KimiCredentials.authURL(in: home) }

    /// The file `proper-lockfile` names the refresh lock after. The CLI creates
    /// it (empty) before it can lock, and the lock itself is this path plus
    /// `.lock`.
    private var lockSentinel: URL { home.appendingPathComponent("oauth/kimi-code") }

    /// The credential to read usage with: the file as it stands, renewed first
    /// if it has aged into the renewal margin.
    ///
    /// One entry point on purpose. "Read the credential and renew it if it needs
    /// it" is a single question with a race inside it, and splitting it into two
    /// calls is how the race gets answered twice.
    func usableCredential() async throws -> KimiCredentials {
        if let running = inFlight { return try await running.value }
        let task = Task { try await self.renewIfAged() }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }

    private func renewIfAged() async throws -> KimiCredentials {
        let handed = try KimiCredentials.load(from: authURL)
        guard handed.needsRenewal(now: now()) else { return handed }

        do {
            return try await renewUnderLock()
        } catch let error as UsageProviderError {
            throw error
        } catch {
            // Anything unexpected is a renewal that did not happen, and the
            // credential is untouched — the same state as a network failure.
            Log.usage.error("kimi: renewing the credential failed: \(String(describing: error), privacy: .public)")
            throw UsageProviderError.credentialExpired
        }
    }

    private func renewUnderLock() async throws -> KimiCredentials {
        var lock = KimiRefreshLock(sentinel: lockSentinel, now: now, sleep: sleep)
        try await lock.acquire()
        defer { lock.release() }

        // Re-read under the lock. The CLI may have renewed the session while we
        // waited for it, and a second grant would rotate away a refresh token it
        // has just stored — the accident this lock exists to prevent.
        let active = try KimiCredentials.load(from: authURL)
        guard active.needsRenewal(now: now()) else {
            Log.usage.debug("kimi: the CLI renewed the credential first")
            return active
        }
        guard !active.refreshToken.isEmpty else {
            // Nothing here or in the CLI can renew a session with no refresh
            // token. The CLI's own answer is "re-login required".
            throw UsageProviderError.needsAuth
        }

        let renewed = try await requestGrant(using: active)
        return try store(renewed, unlessTheFileMovedOnFrom: active.refreshToken)
    }

    /// Write the renewed pair back, unless somebody stored a session while the
    /// request was in flight.
    ///
    /// That can happen two ways: the lock was taken from us as stale, or a
    /// `kimi login` run by hand, which does not consult the lock at all. Theirs
    /// is the newer session and ours may already be the rotated-away half of a
    /// pair, so the file is left exactly as it was found.
    private func store(_ renewed: KimiCredentials,
                       unlessTheFileMovedOnFrom refreshToken: String) throws -> KimiCredentials {
        if let incumbent = try? KimiCredentials.load(from: authURL),
           incumbent.refreshToken != refreshToken {
            Log.usage.notice("kimi: another process stored a session mid-renewal; keeping theirs")
            return incumbent
        }
        try KimiCredentials.write(renewed, to: authURL)
        return renewed
    }

    private func requestGrant(using credentials: KimiCredentials) async throws -> KimiCredentials {
        let host = KimiAuthHost.resolve(environment: environment, home: home,
                                        refreshToken: credentials.refreshToken)
        var request = URLRequest(url: host
            .appendingPathComponent("api")
            .appendingPathComponent("oauth")
            .appendingPathComponent("token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in identityHeaders() { request.setValue(value, forHTTPHeaderField: name) }
        // The CLI gives this request thirty seconds. The same budget is what
        // keeps a stalled network from outliving the lock's hold window.
        request.timeoutInterval = 30
        request.httpBody = Data(Self.form([
            "client_id": Self.clientID,
            "grant_type": "refresh_token",
            "refresh_token": credentials.refreshToken,
        ]).utf8)

        Log.usage.debug("POST \(host.host ?? "auth.kimi.com", privacy: .public): refresh_token grant")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Log.usage.error("kimi: the renewal request did not complete: \(String(describing: error), privacy: .public)")
            throw UsageProviderError.credentialExpired
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        Log.usage.debug("kimi: the token endpoint answered \(status)")

        // A refused refresh token is a statement about the session, not a
        // hiccup: nobody can renew it, and only signing in again can.
        if status == 401 || status == 403 || (root?["error"] as? String) == "invalid_grant" {
            throw UsageProviderError.needsAuth
        }
        if status == 429 { throw UsageProviderError.rateLimited(retryAfter: 60) }

        // As strict as the CLI's own reader: a response missing any of the three
        // fields is not a session, and storing it would leave a credential that
        // can neither be used nor renewed.
        guard status == 200,
              let token = root?["access_token"] as? String, !token.isEmpty,
              let refresh = root?["refresh_token"] as? String, !refresh.isEmpty,
              let lifetime = (root?["expires_in"] as? NSNumber)?.doubleValue, lifetime > 0
        else { throw UsageProviderError.badResponse(status: status) }

        return KimiCredentials(
            accessToken: token,
            refreshToken: refresh,
            expiresAt: Date(timeIntervalSince1970: now().timeIntervalSince1970.rounded(.down) + lifetime),
            expiresIn: lifetime,
            scope: root?["scope"] as? String ?? "",
            tokenType: root?["token_type"] as? String ?? "Bearer"
        )
    }

    /// `application/x-www-form-urlencoded`, the encoding the CLI posts with.
    /// Sorted so the same grant always produces the same bytes.
    static func form(_ fields: [String: String]) -> String {
        fields.keys.sorted().map { name in
            "\(escape(name))=\(escape(fields[name] ?? ""))"
        }.joined(separator: "&")
    }

    /// RFC 3986 unreserved characters, which is the set a JWT needs — its `-`,
    /// `_` and `.` all pass through unchanged.
    private static func escape(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

/// The CLI's own cross-process lock around a token refresh.
///
/// Reproduced rather than invented, because of what it protects: a single-use
/// refresh token. Two grants that overlap and the loser's stored token is dead,
/// which signs the CLI out — so the only safe way to renew is to hold the same
/// lock the CLI holds.
///
/// The CLI builds that lock with `proper-lockfile`, and its protocol is four
/// rules:
///
/// - `mkdir` is the acquisition: whoever creates `<home>/oauth/kimi-code.lock`
///   holds the critical section.
/// - A lock whose modification time is more than five seconds in the past
///   belonged to a process that died, and may be taken over.
/// - The holder stamps that time into the future and keeps it fresh while it
///   works; the CLI's own holder did this from a timer every 2.5 seconds.
/// - Release is `rmdir`, and the CLI waits five hundred milliseconds between
///   attempts for up to a minute before giving up.
///
/// **Where this departs, and why.** This holds the lock without a timer: it
/// stamps a single time far enough ahead to outlast its own request budget. A
/// timer here would be a background task touching a directory another process
/// may own, and `proper-lockfile` treats an mtime it did not write as proof its
/// lock was compromised — it throws from a timer callback, where nothing
/// catches it. One stamp cannot do that. The only costs are that a lock
/// abandoned by a crash takes a minute rather than ten seconds to clear, and
/// that a peer which arrives while this is stalled waits that long — inside the
/// CLI's own one-minute budget, so it still gets its turn.
struct KimiRefreshLock {
    /// `<home>/oauth/kimi-code`, the file `proper-lockfile` names the lock
    /// after. The lock itself is this path plus `.lock`.
    let sentinel: URL
    let now: () -> Date
    let sleep: (TimeInterval) async throws -> Void
    var fileManager: FileManager = .default

    /// The CLI's staleness rule, in seconds.
    static let staleAfter: TimeInterval = 5
    /// How far ahead the hold is stamped. Longer than the renewal's own thirty
    /// second request budget, so a stalled request cannot outlive its hold.
    static let holdWindow: TimeInterval = 45
    /// The CLI's retry budget: one hundred and twenty attempts half a second
    /// apart.
    static let attempts = 120
    static let retryInterval: TimeInterval = 0.5

    /// The time we last wrote, which is also the only proof of ownership this
    /// has: a lock stamped with anything else was taken from us.
    private(set) var held: Date?

    private var url: URL { URL(fileURLWithPath: sentinel.path + ".lock") }

    /// Take the lock, waiting on a live holder and taking over a dead one.
    mutating func acquire() async throws {
        try prepare()
        for _ in 0..<Self.attempts {
            if try hold() { return }
            if isStale() {
                // A holder that died. Its directory goes, and the next attempt
                // races whoever else noticed — one of us wins the `mkdir`.
                rmdir(url.path)
                if try hold() { return }
            }
            try await sleep(Self.retryInterval)
        }
        Log.usage.error("kimi: could not take the CLI's refresh lock; leaving the credential alone")
        throw UsageProviderError.credentialExpired
    }

    /// Give the lock back — but only if the stamp is still the one written here.
    /// A lock taken from us as stale now belongs to whoever took it, and
    /// removing it would hand the critical section to a third process.
    mutating func release() {
        guard let held, let current = stamp, abs(current.timeIntervalSince(held)) < 1 else { return }
        rmdir(url.path)
    }

    /// The two things the CLI does before it can lock at all: the directory the
    /// lock lives in, and the sentinel the lock is named after.
    private func prepare() throws {
        let directory = sentinel.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
        }
        if !fileManager.fileExists(atPath: sentinel.path) {
            fileManager.createFile(atPath: sentinel.path, contents: nil)
        }
    }

    /// One acquisition attempt. `false` means the lock is held by somebody else.
    private mutating func hold() throws -> Bool {
        guard mkdir(url.path, 0o700) == 0 else {
            if errno != EEXIST { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            // Not ours to interpret: something that is not a lock directory is
            // sitting where the lock goes, so waiting a minute for it to become
            // one would only hide that.
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw POSIXError(.EEXIST)
            }
            return false
        }

        guard let stamped = writeStamp() else {
            // A lock nobody can read a time off is one every peer sees as dead.
            rmdir(url.path)
            return false
        }
        held = stamped
        return true
    }

    /// Write the hold's time and read it back, the way the CLI's own probe does:
    /// the value that will later be compared against has to be the one the
    /// filesystem actually stored, not the one handed to it.
    private func writeStamp() -> Date? {
        let when = Date(timeIntervalSince1970: now().timeIntervalSince1970.rounded(.up) + Self.holdWindow)
        do {
            try fileManager.setAttributes([.modificationDate: when], ofItemAtPath: url.path)
        } catch {
            return nil
        }
        return stamp
    }

    private var stamp: Date? {
        (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// The CLI's rule verbatim: dead once its time is more than `staleAfter`
    /// behind us. A lock that has vanished counts as dead, because the next
    /// `mkdir` is then free to succeed.
    private func isStale() -> Bool {
        guard let stamp else { return true }
        return stamp < now().addingTimeInterval(-Self.staleAfter)
    }
}

/// Where the renewal grant is posted.
///
/// Kimi runs two deployments — mainland China and the rest of the world — and a
/// session belongs to exactly one of them. The order below is the CLI's own,
/// minus its config file: an environment override, then the region marker the
/// CLI writes beside its data, then the `region` claim inside the refresh token
/// itself, then mainland China — the region whose oauth key (`oauth/kimi-code`)
/// is the default slot in a config written by `kimi login`.
enum KimiAuthHost {
    static let mainland = URL(string: "https://auth.kimi.com")!
    static let global = URL(string: "https://auth.kimi.ai")!

    static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment,
                        home: URL,
                        refreshToken: String,
                        fileManager: FileManager = .default) -> URL {
        for key in ["KIMI_CODE_OAUTH_HOST", "KIMI_OAUTH_HOST"] {
            guard let raw = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty, let url = URL(string: raw), url.scheme != nil else { continue }
            return url
        }
        if let marker = markerRegion(home: home, fileManager: fileManager) {
            return marker == "global" ? global : mainland
        }
        if let claim = regionClaim(in: refreshToken) {
            return claim.contains("global") || claim.contains("oversea") ? global : mainland
        }
        return mainland
    }

    /// The region the CLI last signed in to, as it writes it (`<home>/region`).
    static func markerRegion(home: URL, fileManager: FileManager = .default) -> String? {
        let url = home.appendingPathComponent("region")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.isEmpty ? nil : value
    }

    /// The `region` claim of a JWT, lowercased.
    ///
    /// Not verification, and not a trust decision: the claim only picks which of
    /// Kimi's two hosts to ask, and the host is asked for a *new* token that the
    /// server issues against the account the refresh token actually belongs to.
    static func regionClaim(in token: String) -> String? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let region = root["region"] as? String
        else { return nil }
        return region.lowercased()
    }
}

/// The identity headers the CLI sends with its OAuth requests.
///
/// Sent because the request being imitated is the CLI's own: a header set the
/// server may or may not insist on, and the cheap way to find out is not to be
/// the first request that omits them. Every value is read from the machine or
/// from the CLI's data root; one that cannot be determined is left out rather
/// than guessed, which is what the CLI does when it has no host identity.
enum KimiDeviceIdentity {
    static func headers(home: URL, fileManager: FileManager = .default) -> [String: String] {
        let machine = machine()
        var headers = [
            "X-Msh-Platform": "kimi_code_cli",
            "X-Msh-Device-Name": ProcessInfo.processInfo.hostName,
            "X-Msh-Device-Model": deviceModel(architecture: machine.architecture),
            "X-Msh-Os-Version": machine.release,
        ]
        if let version = cliVersion(home: home, fileManager: fileManager) {
            headers["X-Msh-Version"] = version
        }
        if let device = deviceID(home: home, fileManager: fileManager) {
            headers["X-Msh-Device-Id"] = device
        }
        return headers
    }

    /// `macOS 14.3 arm64`, the shape the CLI builds from `sw_vers` and `arch`.
    /// A patch of zero is dropped, which is how `sw_vers -productVersion` writes
    /// it.
    static func deviceModel(architecture: String) -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let patch = version.patchVersion == 0 ? "" : ".\(version.patchVersion)"
        let suffix = architecture.isEmpty ? "" : " \(architecture)"
        return "macOS \(version.majorVersion).\(version.minorVersion)\(patch)\(suffix)"
    }

    /// The CLI's device id, minted on its first launch and stable after.
    static func deviceID(home: URL, fileManager: FileManager = .default) -> String? {
        let url = home.appendingPathComponent("device_id")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// The CLI's own version, best effort.
    ///
    /// It records the version it is running in the rollout log it keeps beside
    /// its data — `"current":"0.42.0"` on every line — which is steadier than
    /// resolving whichever `kimi` happens to be on `PATH` today. A version that
    /// cannot be read is simply not sent: this header is telemetry, not
    /// authentication, and an absent field is what the CLI itself sends when it
    /// has no identity to offer.
    static func cliVersion(home: URL, fileManager: FileManager = .default) -> String? {
        let url = home.appendingPathComponent("updates/rollout.log")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text.split(separator: "\n").reversed().lazy
            .compactMap { version(inRolloutLine: String($0)) }
            .first
    }

    /// `"current":"0.42.0"` out of one rollout-log line, or nil.
    static func version(inRolloutLine line: String) -> String? {
        guard let marker = line.range(of: "\"current\":\"") else { return nil }
        let rest = line[marker.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        let value = String(rest[rest.startIndex..<end])
        return value.isEmpty ? nil : value
    }

    /// `uname(3)` — the Darwin release and machine, which is what the CLI reads
    /// for `X-Msh-Os-Version` and its model string.
    static func machine() -> (release: String, architecture: String) {
        var info = utsname()
        guard Darwin.uname(&info) == 0 else { return ("", "") }
        return (field(info.release), field(info.machine))
    }

    /// One C fixed-size character field, up to its terminator.
    private static func field<T>(_ value: T) -> String {
        withUnsafeBytes(of: value) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
