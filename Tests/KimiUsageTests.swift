import XCTest
@testable import Codenotch

/// Guards the shape of `GET https://api.kimi.com/coding/v1/usages` — the
/// endpoint behind the Kimi Code CLI's own `/usage` command. It is not a
/// published API, so these are the tests that will fail first if Kimi
/// changes it.
final class KimiUsageTests: XCTestCase {
    private func parse(_ json: String) throws -> KimiUsage.Payload {
        try KimiUsage.parse(Data(json.utf8))
    }

    /// Trimmed from a real response, captured live with a signed-in
    /// `managed:kimi-code` key: the rolling 5-hour window in `limits`, the
    /// weekly bucket on top, and the long tail of wallet detail the parser
    /// must not trip over.
    private let live = """
    {
        "user": {
            "userId": "d1sfvoqi597048sb9s6g",
            "region": "REGION_CN",
            "membership": { "level": "LEVEL_INTERMEDIATE" },
            "businessId": ""
        },
        "usage": {
            "limit": "100",
            "used": "22",
            "remaining": "78",
            "resetTime": "2026-09-15T03:00:42.014284Z"
        },
        "limits": [
            {
                "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
                "detail": {
                    "limit": "100",
                    "used": "26",
                    "remaining": "74",
                    "resetTime": "2026-09-09T06:00:42.014284Z"
                }
            }
        ],
        "parallel": { "limit": "20" },
        "authentication": { "method": "METHOD_API_KEY", "scope": "FEATURE_CODING" },
        "boosterWallet": { "status": "STATUS_DISABLED" }
    }
    """

    func testDecodesTheLiveShape() throws {
        let windows = try parse(live).windows
        XCTAssertEqual(windows.map(\.id), ["session", "weekly"])
        XCTAssertEqual(windows.map(\.label), ["5 hours", "Weekly"])
        XCTAssertEqual(windows[0].usedFraction ?? -1, 0.26, accuracy: 0.0001)
        XCTAssertEqual(windows[1].usedFraction ?? -1, 0.22, accuracy: 0.0001)
    }

    /// Reset times carry microsecond fractions — parsed as anything coarser
    /// they would land wrong or not at all.
    func testResetTimesParseWithMicrosecondFractions() throws {
        let windows = try parse(live).windows
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expected5h = fractional.date(from: "2026-09-09T06:00:42.014Z")
        let expectedWeekly = fractional.date(from: "2026-09-15T03:00:42.014Z")
        XCTAssertEqual(windows[0].resetsAt, expected5h)
        XCTAssertEqual(windows[1].resetsAt, expectedWeekly)
    }

    func testMultipleRollingWindowsKeepResponseOrder() throws {
        let json = """
        { "usage": { "limit": "100", "used": "10" },
          "limits": [
            { "window": { "duration": 60, "timeUnit": "TIME_UNIT_MINUTE" },
              "detail": { "limit": "50", "used": "5" } },
            { "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
              "detail": { "limit": "100", "used": "25" } } ] }
        """
        let windows = try parse(json).windows
        XCTAssertEqual(windows.map(\.label), ["1 hour", "5 hours", "Weekly"])
        XCTAssertEqual(windows.map(\.id), ["session", "limit-1", "weekly"])
        XCTAssertEqual(windows[1].usedFraction ?? -1, 0.25, accuracy: 0.0001)
    }

    func testWeeklyBucketAloneIsNotAnError() throws {
        let json = #"{ "usage": { "limit": "100", "used": "22" } }"#
        let windows = try parse(json).windows
        XCTAssertEqual(windows.map(\.id), ["weekly"])
    }

    func testRollingWindowAloneIsNotAnError() throws {
        let json = """
        { "limits": [ { "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
                        "detail": { "limit": "100", "used": "26" } } ] }
        """
        let windows = try parse(json).windows
        XCTAssertEqual(windows.map(\.id), ["session"])
    }

    /// A bucket without a usable limit or count is not drawn as a zero —
    /// that would read as a limit that has never been touched.
    func testUnusableBucketsAreDropped() throws {
        let json = """
        { "usage": { "limit": "0", "used": "0" },
          "limits": [ { "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
                        "detail": { "limit": "abc", "used": "1" } } ] }
        """
        XCTAssertThrowsError(try parse(json)) { error in
            guard case UsageProviderError.nothingMetered = error else {
                return XCTFail("expected nothingMetered, got \(error)")
            }
        }
    }

    func testWindowLabels() {
        XCTAssertEqual(KimiUsage.label(duration: 300, timeUnit: "TIME_UNIT_MINUTE"), "5 hours")
        XCTAssertEqual(KimiUsage.label(duration: 60, timeUnit: "TIME_UNIT_MINUTE"), "1 hour")
        XCTAssertEqual(KimiUsage.label(duration: 1, timeUnit: "TIME_UNIT_DAY"), "1 day")
        XCTAssertEqual(KimiUsage.label(duration: 1, timeUnit: "TIME_UNIT_WEEK"), "Weekly")
        XCTAssertEqual(KimiUsage.label(duration: 2, timeUnit: "TIME_UNIT_WEEK"), "2 weeks")
        XCTAssertEqual(KimiUsage.label(duration: 90, timeUnit: "TIME_UNIT_MINUTE"), "90 minutes")
        XCTAssertEqual(KimiUsage.label(duration: nil, timeUnit: nil), "Rolling")
    }
}

/// Guards the borrow from `~/.kimi-code/config.toml`: which section is read,
/// and which must not be.
final class KimiCredentialsTests: XCTestCase {
    private var directory: URL!
    private var file: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kimi-credentials-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appendingPathComponent("config.toml")
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func write(_ toml: String) throws {
        try Data(toml.utf8).write(to: file)
    }

    /// Every "not set up" shape must throw needsAuth; asserting that here once
    /// keeps each case to a single line.
    private func assertNeedsAuth(_ expression: @autoclosure () throws -> KimiCredentials.Credential,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            guard case UsageProviderError.needsAuth = error else {
                return XCTFail("expected needsAuth, got \(error)", file: file, line: line)
            }
        }
    }

    private let config = """
        default_model = "kimi-code/k3-256k"

        [services.moonshot_search]
        base_url = "https://api.kimi.com/coding/v1/search"
        api_key = "search-key"

        [providers."managed:kimi-code"]
        type = "kimi"
        api_key = "sk-kimi-managed"
        base_url = "https://api.kimi.com/coding/v1"
        """

    func testManagedProviderKey() throws {
        try write(config)
        let credential = try KimiCredentials.load(from: file)
        XCTAssertEqual(credential.apiKey, "sk-kimi-managed")
        XCTAssertEqual(credential.baseURL.absoluteString, "https://api.kimi.com/coding/v1")
    }

    func testServiceKeysAreNotRead() throws {
        // The search service key lives in the same file; only the managed
        // provider's key is the account credential.
        try write("""
            [services.moonshot_search]
            api_key = "search-key"
            """)
        assertNeedsAuth(try KimiCredentials.load(from: file))
    }

    func testCustomBaseURL() throws {
        try write("""
            [providers."managed:kimi-code"]
            api_key = "sk-x"
            base_url = "https://kimi.example.com/coding/v1/"
            """)
        let credential = try KimiCredentials.load(from: file)
        XCTAssertEqual(credential.baseURL.absoluteString, "https://kimi.example.com/coding/v1")
    }

    func testMissingFileThrowsNeedsAuth() {
        assertNeedsAuth(try KimiCredentials.load(from: file))
    }

    func testEmptyKeyThrowsNeedsAuth() {
        try? write("""
            [providers."managed:kimi-code"]
            api_key = ""
            """)
        assertNeedsAuth(try KimiCredentials.load(from: file))
    }
}
