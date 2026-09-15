import Darwin
import XCTest
@testable import Codenotch

/// The renewal the Kimi provider makes when the CLI has not run for a while.
///
/// These are the tests that matter for the whole design, because every part of
/// the protocol below is *the CLI's* rather than an interface Kimi promises:
/// the lock directory, the grant, the file it writes back. Each one pins a
/// behaviour whose failure would either sign the user out of the CLI (a refresh
/// token rotated away and not stored) or quietly destroy a working credential
/// (a failed renewal overwriting a good one).
final class KimiTokenRefreshTests: XCTestCase {
    override func setUp() {
        super.setUp()
        KimiEndpoints.reset(token: .success(KimiEndpoints.Answer(status: 200, body: "")),
                            usages: KimiEndpoints.Answer(status: 200, body: "{}"))
    }

    // MARK: - Renewal

    /// The whole point: an aged credential is renewed, and what lands on disk is
    /// something the CLI's own reader can pick up — six wire fields, mode 0600,
    /// written whole or not at all.
    func testAnAgedCredentialIsRenewedAndStoredTheWayTheCLIWritesIt() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let now = Date()
        try plant(credential(access: "access-old", refresh: "refresh-old", expiresAt: now.addingTimeInterval(-30)),
                  in: home)
        try plantDeviceIdentity(in: home)
        KimiEndpoints.reset(token: .success(KimiEndpoints.Answer(status: 200, body: """
        {"access_token":"access-new","refresh_token":"refresh-new","expires_in":900,\
        "scope":"kimi-code","token_type":"Bearer"}
        """)), usages: KimiEndpoints.Answer(status: 200, body: "{}"))

        let refresher = KimiTokenRefresher(session: stubbedSession(), home: home, environment: [:])
        let renewed = try await refresher.usableCredential()

        XCTAssertEqual(renewed.accessToken, "access-new")
        XCTAssertEqual(renewed.refreshToken, "refresh-new")
        XCTAssertEqual(renewed.expiresIn, 900)
        XCTAssertEqual(renewed.scope, "kimi-code")

        // Read back through the app's own reader, then through the raw file: the
        // second is what the CLI sees.
        let stored = try KimiCredentials.load(from: KimiCredentials.authURL(in: home))
        XCTAssertEqual(stored.accessToken, "access-new")
        XCTAssertEqual(stored.refreshToken, "refresh-new")
        XCTAssertEqual(stored.expiresAt.timeIntervalSinceNow, 900, accuracy: 5)
        XCTAssertFalse(stored.needsRenewal(now: Date()))

        let raw = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try Data(contentsOf: KimiCredentials.authURL(in: home))) as? [String: Any])
        XCTAssertEqual(Set(raw.keys),
                       ["access_token", "refresh_token", "expires_at", "scope", "token_type", "expires_in"])
        XCTAssertEqual(raw["expires_in"] as? Int, 900)

        let mode = try XCTUnwrap(FileManager.default
            .attributesOfItem(atPath: KimiCredentials.authURL(in: home).path)[.posixPermissions] as? NSNumber)
        XCTAssertEqual(mode.intValue, 0o600)

        // The grant itself: the CLI's endpoint, the CLI's method and content
        // type, and the device identity the CLI sends with it.
        let request = try XCTUnwrap(KimiEndpoints.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://auth.kimi.com/api/oauth/token")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Msh-Device-Id"), "device-from-fixture")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Msh-Version"), "0.42.0")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Msh-Platform"), "kimi_code_cli")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Msh-Os-Version"), KimiDeviceIdentity.machine().release)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"),
                     "the token endpoint takes the grant, not a bearer token")

        // The lock is given back, and the sentinel the CLI expects is left in
        // place — it creates that file itself before it can lock.
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("oauth/kimi-code.lock").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent("oauth/kimi-code").path))
    }

    /// A credential still comfortably inside its life is used as found. Renewing
    /// early would spend a grant the CLI is about to make anyway.
    func testACredentialOutsideTheMarginIsNotRenewed() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        // Fifteen-minute tokens renew with 7m30s left; ten minutes is outside it.
        try plant(credential(expiresAt: Date().addingTimeInterval(600)), in: home)

        let refresher = KimiTokenRefresher(session: stubbedSession(), home: home, environment: [:])
        let credentials = try await refresher.usableCredential()

        XCTAssertEqual(credentials.accessToken, "access-old")
        XCTAssertEqual(KimiEndpoints.requests.count, 0)
    }

    /// The race the lock exists for: the CLI renewed the session while we waited
    /// for it. Nothing is posted, and the CLI's session is the one handed back —
    /// a grant here would rotate away the refresh token it has just stored.
    func testAPeerThatRenewedWhileWeWaitedIsUsedInstead() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try plant(credential(access: "access-old", refresh: "refresh-old",
                             expiresAt: Date().addingTimeInterval(-30)), in: home)
        // A live lock, so the first attempt has to wait — and the wait is where
        // the peer gets its turn.
        try plantLock(in: home, heldUntil: Date().addingTimeInterval(KimiRefreshLock.holdWindow))

        let peer = credential(access: "access-peer", refresh: "refresh-peer",
                              expiresAt: Date().addingTimeInterval(3600))
        let waiter = PeerRenewal(home: home, credentials: peer)
        let refresher = KimiTokenRefresher(session: stubbedSession(), home: home, environment: [:],
                                           sleep: { _ in await waiter.once() })

        let credentials = try await refresher.usableCredential()

        XCTAssertEqual(credentials.accessToken, "access-peer")
        XCTAssertEqual(KimiEndpoints.requests.count, 0, "a second grant would have rotated the peer's token away")
    }

    /// A lock its holder died inside is taken over rather than waited out.
    func testAStaleLockIsTakenOver() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try plant(credential(expiresAt: Date().addingTimeInterval(-30)), in: home)
        try plantLock(in: home, heldUntil: Date().addingTimeInterval(-120))
        KimiEndpoints.reset(token: .success(KimiEndpoints.Answer(status: 200, body: """
        {"access_token":"access-new","refresh_token":"refresh-new","expires_in":900}
        """)), usages: KimiEndpoints.Answer(status: 200, body: "{}"))

        let refresher = KimiTokenRefresher(session: stubbedSession(), home: home, environment: [:],
                                           sleep: { _ in })
        let credentials = try await refresher.usableCredential()

        XCTAssertEqual(credentials.accessToken, "access-new")
        XCTAssertEqual(KimiEndpoints.requests.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("oauth/kimi-code.lock").path))
    }

    // MARK: - Refusals, and what is left behind

    /// A refresh token the server refuses is a statement about the session:
    /// nothing can renew it. The file is left byte-for-byte as it was — writing
    /// a tombstone is the CLI's decision to make, not this app's.
    func testARefusedRefreshTokenAsksForSignInAndTouchesNothing() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try plant(credential(expiresAt: Date().addingTimeInterval(-30)), in: home)
        let before = try Data(contentsOf: KimiCredentials.authURL(in: home))
        KimiEndpoints.reset(token: .success(KimiEndpoints.Answer(status: 400, body: """
        {"error":"invalid_grant","error_description":"refresh token already used"}
        """)), usages: KimiEndpoints.Answer(status: 200, body: "{}"))

        let refresher = KimiTokenRefresher(session: stubbedSession(), home: home, environment: [:])
        do {
            _ = try await refresher.usableCredential()
            XCTFail("expected needsAuth")
        } catch UsageProviderError.needsAuth {
            // expected
        }

        XCTAssertEqual(try Data(contentsOf: KimiCredentials.authURL(in: home)), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("oauth/kimi-code.lock").path),
                       "the lock is released on the way out")
    }

    /// Ten minutes of offline is not a reason to lose a credential. The failure
    /// is reported as expiry — exactly what this provider reported before it
    /// could renew anything — and the file is untouched.
    func testAnUnreachableEndpointKeepsTheCredential() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try plant(credential(expiresAt: Date().addingTimeInterval(-30)), in: home)
        let before = try Data(contentsOf: KimiCredentials.authURL(in: home))
        KimiEndpoints.reset(token: .failure(URLError(.notConnectedToInternet)),
                            usages: KimiEndpoints.Answer(status: 200, body: "{}"))

        let refresher = KimiTokenRefresher(session: stubbedSession(), home: home, environment: [:])
        do {
            _ = try await refresher.usableCredential()
            XCTFail("expected credentialExpired")
        } catch UsageProviderError.credentialExpired {
            // expected
        }

        XCTAssertEqual(try Data(contentsOf: KimiCredentials.authURL(in: home)), before)
    }

    /// A 200 missing the refresh token is not a session: storing it would leave
    /// a credential that can neither be used nor renewed, and drop the only
    /// token that could still have been refreshed.
    func testAnAnswerWithoutARefreshTokenIsNotStored() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try plant(credential(expiresAt: Date().addingTimeInterval(-30)), in: home)
        let before = try Data(contentsOf: KimiCredentials.authURL(in: home))
        KimiEndpoints.reset(token: .success(KimiEndpoints.Answer(status: 200, body: """
        {"access_token":"access-new","expires_in":900}
        """)), usages: KimiEndpoints.Answer(status: 200, body: "{}"))

        let refresher = KimiTokenRefresher(session: stubbedSession(), home: home, environment: [:])
        do {
            _ = try await refresher.usableCredential()
            XCTFail("expected badResponse")
        } catch UsageProviderError.badResponse(let status) {
            XCTAssertEqual(status, 200)
        }

        XCTAssertEqual(try Data(contentsOf: KimiCredentials.authURL(in: home)), before)
    }

    /// A session with no refresh token cannot be renewed by anything, here or in
    /// the CLI. No request is worth making.
    func testASessionWithNoRefreshTokenAsksForSignInWithoutPosting() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try plant(credential(access: "access-old", refresh: "", expiresAt: Date().addingTimeInterval(-30)), in: home)

        let refresher = KimiTokenRefresher(session: stubbedSession(), home: home, environment: [:])
        do {
            _ = try await refresher.usableCredential()
            XCTFail("expected needsAuth")
        } catch UsageProviderError.needsAuth {
            // expected
        }

        XCTAssertEqual(KimiEndpoints.requests.count, 0)
    }

    // MARK: - The lock

    /// Two reapers of the same dead holder must not both end up inside the
    /// critical section.
    func testOnlyOneHolderGetsTheLock() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let sentinel = home.appendingPathComponent("oauth/kimi-code")
        let fixed = Date()
        var first = KimiRefreshLock(sentinel: sentinel, now: { fixed }, sleep: { _ in })
        try await first.acquire()

        var second = KimiRefreshLock(sentinel: sentinel, now: { fixed }, sleep: { _ in })
        do {
            try await second.acquire()
            XCTFail("expected the lock to be refused")
        } catch UsageProviderError.credentialExpired {
            // expected: the one-minute budget is spent and the caller is told the
            // credential was left alone.
        }

        first.release()
        var third = KimiRefreshLock(sentinel: sentinel, now: { fixed }, sleep: { _ in })
        try await third.acquire()
        third.release()
    }

    /// A lock taken from us as stale belongs to whoever took it. Releasing it
    /// would hand the critical section to a third process — which is the one way
    /// this could rotate two refresh tokens at once.
    func testReleasingALockThatWasTakenFromUsLeavesItAlone() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let sentinel = home.appendingPathComponent("oauth/kimi-code")
        let fixed = Date()
        var lock = KimiRefreshLock(sentinel: sentinel, now: { fixed }, sleep: { _ in })
        try await lock.acquire()

        // The thief only ever acts on a lock that looks dead, so its stamp is
        // far ahead of ours rather than beside it.
        let stolen = home.appendingPathComponent("oauth/kimi-code.lock")
        rmdir(stolen.path)
        try FileManager.default.createDirectory(at: stolen, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: fixed.addingTimeInterval(120)],
                                             ofItemAtPath: stolen.path)
        lock.release()

        XCTAssertTrue(FileManager.default.fileExists(atPath: stolen.path))
    }

    // MARK: - Which host to ask

    /// The second deployment, and the three ways the CLI works out that a
    /// session belongs to it.
    func testTheGlobalDeploymentIsFound() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        XCTAssertEqual(KimiAuthHost.resolve(environment: ["KIMI_CODE_OAUTH_HOST": "https://auth.example.test"],
                                            home: home, refreshToken: ""),
                       URL(string: "https://auth.example.test"))
        XCTAssertEqual(KimiAuthHost.resolve(environment: ["KIMI_OAUTH_HOST": "https://auth.example.test"],
                                            home: home, refreshToken: ""),
                       URL(string: "https://auth.example.test"))

        try "global\n".write(to: home.appendingPathComponent("region"), atomically: true, encoding: .utf8)
        XCTAssertEqual(KimiAuthHost.resolve(environment: [:], home: home, refreshToken: ""),
                       KimiAuthHost.global)

        try? FileManager.default.removeItem(at: home.appendingPathComponent("region"))
        XCTAssertEqual(KimiAuthHost.resolve(environment: [:], home: home,
                                           refreshToken: Self.jwt(region: "global")),
                       KimiAuthHost.global)
        XCTAssertEqual(KimiAuthHost.resolve(environment: [:], home: home,
                                           refreshToken: Self.jwt(region: "cn")),
                       KimiAuthHost.mainland)
        XCTAssertEqual(KimiAuthHost.resolve(environment: [:], home: home, refreshToken: "not-a-jwt"),
                       KimiAuthHost.mainland)
    }

    // MARK: - Identity

    func testTheDeviceIdentityIsReadFromTheCLIsData() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try plantDeviceIdentity(in: home)

        let headers = KimiDeviceIdentity.headers(home: home)
        XCTAssertEqual(headers["X-Msh-Device-Id"], "device-from-fixture")
        XCTAssertEqual(headers["X-Msh-Version"], "0.42.0")
        XCTAssertEqual(headers["X-Msh-Platform"], "kimi_code_cli")
        XCTAssertFalse(headers["X-Msh-Device-Name"]?.isEmpty ?? true)
        XCTAssertTrue(headers["X-Msh-Device-Model"]?.hasPrefix("macOS ") ?? false)

        // A machine with no CLI data simply cannot say some of these, and says
        // nothing rather than guessing.
        let bare = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: bare) }
        let bareHeaders = KimiDeviceIdentity.headers(home: bare)
        XCTAssertNil(bareHeaders["X-Msh-Device-Id"])
        XCTAssertNil(bareHeaders["X-Msh-Version"])
    }

    /// The version is telemetry, so it is scraped from the log the CLI keeps
    /// rather than resolved from whichever binary is on `PATH`.
    func testTheCLIVersionIsScrapedFromItsRolloutLog() {
        XCTAssertEqual(KimiDeviceIdentity.version(inRolloutLine:
            #"{"ts":"2026-09-15T02:26:42.409Z","phase":"startup-cache","current":"0.42.0","latest":"0.43.0"}"#),
            "0.42.0")
        XCTAssertNil(KimiDeviceIdentity.version(inRolloutLine: #"{"phase":"no-version-here"}"#))
        XCTAssertNil(KimiDeviceIdentity.version(inRolloutLine: #"{"current":""}"#))
    }

    func testTheGrantIsFormEncoded() {
        XCTAssertEqual(KimiTokenRefresher.form(["grant_type": "refresh_token",
                                                "client_id": "abc",
                                                "refresh_token": "a.b-c_d"]),
                       "client_id=abc&grant_type=refresh_token&refresh_token=a.b-c_d")
        XCTAssertEqual(KimiTokenRefresher.form(["refresh_token": "a b&c"]), "refresh_token=a%20b%26c")
    }

    // MARK: - When a renewal is worth making

    /// The CLI's own threshold: half the token's life, never less than five
    /// minutes. Sharing it is what keeps this from renewing on every tick or
    /// leaving a window where the token is dead.
    func testTheRenewalMarginMatchesTheCLIs() {
        XCTAssertEqual(KimiCredentials.renewalMargin(expiresIn: 900), 450)
        XCTAssertEqual(KimiCredentials.renewalMargin(expiresIn: 600), 300)
        XCTAssertEqual(KimiCredentials.renewalMargin(expiresIn: 0), 300)

        let now = Date()
        XCTAssertTrue(credential(expiresIn: 900, expiresAt: now.addingTimeInterval(449)).needsRenewal(now: now))
        XCTAssertFalse(credential(expiresIn: 900, expiresAt: now.addingTimeInterval(451)).needsRenewal(now: now))
        XCTAssertTrue(credential(expiresIn: 0, expiresAt: now.addingTimeInterval(-1)).needsRenewal(now: now))
        XCTAssertFalse(credential(expiresIn: 0, expiresAt: now.addingTimeInterval(600)).needsRenewal(now: now))
    }

    // MARK: - The provider, end to end

    /// The reading the whole exercise is for: an aged credential renewed in
    /// passing, and the usage request made with the token that came back.
    func testTheProviderRenewsAndThenReadsUsage() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try plant(credential(access: "access-old", refresh: "refresh-old",
                             expiresAt: Date().addingTimeInterval(-30)), in: home)
        KimiEndpoints.reset(token: .success(KimiEndpoints.Answer(status: 200, body: """
        {"access_token":"access-new","refresh_token":"refresh-new","expires_in":900}
        """)), usages: KimiEndpoints.Answer(status: 200, body: """
        {"user":{"userId":"u","membership":{"level":"LEVEL_ADVANCED"}},\
        "usage":{"limit":"100","used":"2","resetTime":"2026-09-15T19:39:34.389610Z"},\
        "limits":[{"window":{"duration":300,"timeUnit":"TIME_UNIT_MINUTE"},\
        "detail":{"limit":"100","used":"8","resetTime":"2026-09-16T16:39:34.389610Z"}}]}
        """))

        let authURL = KimiCredentials.authURL(in: home)
        let provider = KimiProvider(session: stubbedSession(), authURL: authURL)
        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.id, "kimi")
        XCTAssertEqual(snapshot.windows.map(\.id), ["weekly", "rolling"])
        XCTAssertEqual(snapshot.plan, "Advanced")

        let usage = try XCTUnwrap(KimiEndpoints.requests.last)
        XCTAssertEqual(usage.url?.absoluteString, "https://api.kimi.com/coding/v1/usages")
        XCTAssertEqual(usage.value(forHTTPHeaderField: "Authorization"), "Bearer access-new")
    }

    // MARK: - Fixtures

    private func temporaryHome() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kimi-home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func credential(access: String = "access-old",
                            refresh: String = "refresh-old",
                            expiresIn: TimeInterval = 900,
                            expiresAt: Date) -> KimiCredentials {
        KimiCredentials(accessToken: access, refreshToken: refresh, expiresAt: expiresAt,
                        expiresIn: expiresIn, scope: "kimi-code", tokenType: "Bearer")
    }

    private func plant(_ credentials: KimiCredentials, in home: URL) throws {
        try KimiCredentials.write(credentials, to: KimiCredentials.authURL(in: home))
    }

    /// The two files the CLI leaves for its own identity — the device id, and a
    /// rollout log it writes its version into.
    private func plantDeviceIdentity(in home: URL) throws {
        try "device-from-fixture".write(to: home.appendingPathComponent("device_id"),
                                        atomically: true, encoding: .utf8)
        let updates = home.appendingPathComponent("updates", isDirectory: true)
        try FileManager.default.createDirectory(at: updates, withIntermediateDirectories: true)
        try (#"{"ts":"2026-09-15T02:26:42.409Z","current":"0.42.0"}"# + "\n")
            .write(to: updates.appendingPathComponent("rollout.log"), atomically: true, encoding: .utf8)
    }

    /// A lock directory, as a holder would have left it: `heldUntil` in the
    /// future for a live one, in the past for one whose process died.
    private func plantLock(in home: URL, heldUntil: Date) throws {
        let lock = home.appendingPathComponent("oauth/kimi-code.lock")
        try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: heldUntil], ofItemAtPath: lock.path)
    }

    private func stubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [KimiEndpoints.self]
        return URLSession(configuration: configuration)
    }

    /// A JWT-shaped string carrying a `region` claim, unverified on purpose.
    private static func jwt(region: String) -> String {
        func encode(_ text: String) -> String {
            Data(text.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return "\(encode(#"{"alg":"ES256"}"#)).\(encode(#"{"region":"\#(region)"}"#)).signature"
    }
}

/// Stands in for the CLI while the caller is waiting on the lock: it renews the
/// session and gives the lock back, exactly as a `kimi` command would.
private actor PeerRenewal {
    private let home: URL
    private let credentials: KimiCredentials
    private var acted = false

    init(home: URL, credentials: KimiCredentials) {
        self.home = home
        self.credentials = credentials
    }

    func once() {
        guard !acted else { return }
        acted = true
        try? KimiCredentials.write(credentials, to: KimiCredentials.authURL(in: home))
        rmdir(home.appendingPathComponent("oauth/kimi-code.lock").path)
    }
}

/// Both endpoints Kimi answers on, so one stub covers a renewal and the usage
/// read that follows it.
private final class KimiEndpoints: URLProtocol {
    struct Answer {
        let status: Int
        let body: String
    }

    private static let lock = NSLock()
    private static var token: Result<Answer, Error> = .success(Answer(status: 200, body: ""))
    private static var usages = Answer(status: 200, body: "{}")
    private static var seen: [URLRequest] = []

    static var requests: [URLRequest] { lock.withLock { seen } }

    static func reset(token: Result<Answer, Error>, usages: Answer) {
        lock.withLock {
            Self.token = token
            Self.usages = usages
            seen = []
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.lock.withLock { Self.seen.append(request) }
        let answer: Result<Answer, Error> = request.url?.host == "auth.kimi.com"
            ? Self.lock.withLock { Self.token }
            : .success(Self.lock.withLock { Self.usages })

        switch answer {
        case .success(let answer):
            let response = HTTPURLResponse(url: request.url!, statusCode: answer.status,
                                           httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(answer.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}
