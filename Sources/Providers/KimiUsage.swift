import Foundation

/// Parses the answer from Kimi Code's own usage endpoint — the one behind
/// the CLI's `/usage` command, recorded from a live session:
///
/// `GET https://api.kimi.com/coding/v1/usages` (Bearer the managed API key)
///
/// ```json
/// { "user": { "membership": { "level": "LEVEL_INTERMEDIATE" } },
///   "usage":  { "limit": "100", "used": "22", "resetTime": "2026-09-15T03:00:42.014284Z" },
///   "limits": [ { "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
///                 "detail": { "limit": "100", "used": "26", "resetTime": "2026-09-09T06:00:42.014284Z" } } ] }
/// ```
///
/// `limits` carries the rolling windows — the five-hour one Kimi Code rings
/// the same alarm on — while the top-level `usage` is the weekly bucket.
/// That is the whole reading: the membership endpoint's monthly balance and
/// booster wallets are a different audience (a kimi.com session token) and
/// no business of this key. Amounts are strings in the wire shape; a bucket
/// without a parseable limit or used count is not drawn — a zero would read
/// as a limit that has never been touched. A missing or unreadable reset
/// time is dropped, not faked — see `date(_:)`.
///
/// The shape is pinned by tests, including a response recorded from a live
/// session: the endpoint is not a published API, and this is the first place
/// a change would show.
enum KimiUsage {
    struct Payload {
        let windows: [LimitWindow]
    }

    struct Response: Decodable {
        struct Bucket: Decodable {
            let limit: String?
            let used: String?
            let resetTime: String?
        }
        struct WindowLimit: Decodable {
            struct Window: Decodable {
                let duration: Int?
                let timeUnit: String?
            }
            let window: Window?
            let detail: Bucket?
        }

        let usage: Bucket?
        let limits: [WindowLimit]?
    }

    static func parse(_ data: Data) throws -> Payload {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let windows = self.windows(in: response)
        guard !windows.isEmpty else {
            throw UsageProviderError.nothingMetered("Kimi has nothing metered on this account yet")
        }
        return Payload(windows: windows)
    }

    /// Rolling windows first — the shortest one leads, the way Kimi Code's
    /// own usage display orders them — then the weekly bucket. The first
    /// window is the headline, so the 5-hour limit stays the ring reading.
    static func windows(in response: Response) -> [LimitWindow] {
        var windows: [LimitWindow] = []
        for (index, entry) in (response.limits ?? []).enumerated() {
            guard let detail = entry.detail,
                  let fraction = fraction(used: detail.used, limit: detail.limit) else { continue }
            windows.append(LimitWindow(
                id: index == 0 ? "session" : "limit-\(index)",
                label: label(duration: entry.window?.duration, timeUnit: entry.window?.timeUnit),
                usedFraction: fraction,
                resetsAt: date(detail.resetTime)
            ))
        }
        if let weekly = response.usage,
           let fraction = fraction(used: weekly.used, limit: weekly.limit) {
            windows.append(LimitWindow(
                id: "weekly", label: "Weekly",
                usedFraction: fraction, resetsAt: date(weekly.resetTime)
            ))
        }
        return windows
    }

    /// used / limit, both wire strings; nil when either is unparsable or the
    /// limit is zero — there is nothing honest to draw in those cases.
    static func fraction(used: String?, limit: String?) -> Double? {
        guard let used = used.flatMap(Double.init),
              let limit = limit.flatMap(Double.init), limit > 0 else { return nil }
        return used / limit
    }

    /// "5 hours" for the 300-minute window, "Weekly" for seven days; a
    /// generic duration otherwise, so an unknown new window still gets an
    /// honest label instead of a crash or a blank.
    static func label(duration: Int?, timeUnit: String?) -> String {
        guard let duration, duration > 0 else { return "Rolling" }
        let minutes: Int
        switch timeUnit {
        case "TIME_UNIT_HOUR": minutes = duration * 60
        case "TIME_UNIT_DAY": minutes = duration * 60 * 24
        case "TIME_UNIT_WEEK": minutes = duration * 60 * 24 * 7
        default: minutes = duration
        }
        if minutes == 60 * 24 * 7 { return "Weekly" }
        if minutes % (60 * 24 * 7) == 0 { return "\(minutes / (60 * 24 * 7)) weeks" }
        if minutes % (60 * 24) == 0 {
            let days = minutes / (60 * 24)
            return days == 1 ? "1 day" : "\(days) days"
        }
        if minutes % 60 == 0 {
            let hours = minutes / 60
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }

    /// RFC 3339, tolerating the microsecond fractions this endpoint sends:
    /// the fraction is trimmed to milliseconds and retried when the strict
    /// parse fails. A reset time that cannot be read is dropped, not faked —
    /// the percentage is still a reading.
    static func date(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let trimmed = text.replacingOccurrences(
            of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression)

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) ?? fractional.date(from: trimmed) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text) ?? plain.date(from: trimmed)
    }
}
