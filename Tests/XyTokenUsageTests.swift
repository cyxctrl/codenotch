import XCTest
@testable import Codenotch

/// Guards the shape of `GET https://api.xytoken.xyb2b.com/api/subscription/self`
/// — the call the station's wallet page makes right after refreshing its
/// session. It is not a published API, so these are the tests that will fail
/// first if the station changes it. The fixture keeps the recorded structure
/// but rewrites ids and token counts, so no account data is checked in.
final class XyTokenUsageTests: XCTestCase {
    /// Trimmed from a recorded response: the two active windows under
    /// `subscriptions`, the same subscription repeated under
    /// `all_subscriptions` (which the parser must not double-count), and the
    /// long tail of wallet detail the parser must not trip over.
    private let live = """
    {
        "code": true,
        "success": true,
        "message": "",
        "data": {
            "user_id": 99999,
            "quota": 12900000,
            "used_quota": 112000000,
            "request_count": 6400,
            "subscriptions": [
                {
                    "id": "99999",
                    "plan_name": "Pro",
                    "status": "active",
                    "quota_limits": [
                        {
                            "id": "13541",
                            "rule_key": "day:1|day:00:00",
                            "name": "每日",
                            "period_value": 1,
                            "period_unit": "day",
                            "reset_time": "00:00",
                            "amount": 60000000,
                            "amount_used": 3000000,
                            "remaining": 57000000,
                            "window_start": 1788940296,
                            "window_end": 1788969600
                        },
                        {
                            "id": "13542",
                            "rule_key": "week:1|day:1,00:00",
                            "name": "每周",
                            "period_value": 1,
                            "period_unit": "week",
                            "reset_time": "00:00",
                            "amount": 240000000,
                            "amount_used": 12000000,
                            "remaining": 228000000,
                            "window_start": 1788940296,
                            "window_end": 1789315200
                        }
                    ]
                }
            ],
            "all_subscriptions": [
                {
                    "id": "99999",
                    "plan_name": "Pro",
                    "status": "active",
                    "quota_limits": [
                        {
                            "id": "13541",
                            "rule_key": "day:1|day:00:00",
                            "name": "每日",
                            "amount": 60000000,
                            "amount_used": 3000000,
                            "remaining": 57000000,
                            "window_start": 1788940296,
                            "window_end": 1788969600
                        }
                    ]
                },
                {
                    "id": "99998",
                    "plan_name": "Trial",
                    "status": "expired",
                    "quota_limits": []
                }
            ]
        }
    }
    """

    func testDecodesTheLiveShape() throws {
        let windows = try XyTokenUsage.windows(fromJSON: live)
        XCTAssertEqual(windows.map(\.id), ["day:1|day:00:00", "week:1|day:1,00:00"])
        XCTAssertEqual(windows.map(\.label), ["每日", "每周"])
        XCTAssertEqual(windows[0].usedFraction ?? -1, 0.05, accuracy: 0.0001)
        XCTAssertEqual(windows[1].usedFraction ?? -1, 0.05, accuracy: 0.0001)
        XCTAssertEqual(windows[0].resetsAt, Date(timeIntervalSince1970: 1788969600))
        XCTAssertEqual(windows[1].resetsAt, Date(timeIntervalSince1970: 1789315200))
    }

    /// `all_subscriptions` repeats the active windows plus expired ones — only
    /// `subscriptions` may be read, or every window shows up twice.
    func testActiveSubscriptionsDoNotDuplicateWindows() throws {
        let windows = try XyTokenUsage.windows(fromJSON: live)
        XCTAssertEqual(windows.count, 2)
    }

    /// When nothing is active (e.g. the plan lapsed), fall back to
    /// `all_subscriptions` rather than reporting nothing at all.
    func testFallsBackToAllSubscriptions() throws {
        let json = """
        { "data": {
            "subscriptions": [],
            "all_subscriptions": [ { "quota_limits": [
                { "rule_key": "day:1|day:00:00", "name": "每日",
                  "amount": 60000000, "amount_used": 6000000,
                  "window_start": 1788940296, "window_end": 1788969600 } ] } ] } }
        """
        let windows = try XyTokenUsage.windows(fromJSON: json)
        XCTAssertEqual(windows.map(\.id), ["day:1|day:00:00"])
        XCTAssertEqual(windows[0].usedFraction ?? -1, 0.1, accuracy: 0.0001)
    }

    /// A limit with no quota is not drawn as a zero — that would read as a
    /// limit that has never been touched.
    func testUnusableLimitsAreDropped() throws {
        let json = """
        { "data": { "subscriptions": [ { "quota_limits": [
            { "rule_key": "day:1|day:00:00", "name": "每日",
              "amount": 0, "amount_used": 0, "window_end": 1788969600 } ] } ] } }
        """
        XCTAssertThrowsError(try XyTokenUsage.windows(fromJSON: json)) { error in
            guard case UsageProviderError.nothingMetered = error else {
                return XCTFail("expected nothingMetered, got \(error)")
            }
        }
    }

    func testMalformedBodyThrowsBadResponse() {
        XCTAssertThrowsError(try XyTokenUsage.windows(fromJSON: "sign in to continue")) { error in
            guard case UsageProviderError.badResponse = error else {
                return XCTFail("expected badResponse, got \(error)")
            }
        }
    }
}
