import Foundation

/// The Kimi Code credential, borrowed from the tool that holds it — the
/// same way Codenotch reads Claude's or Grok's login rather than owning one.
/// Signing in to the Kimi Code CLI (`kimi`, the managed provider) writes an
/// API key into `~/.kimi-code/config.toml`; that key is what this reads.
/// Only the `managed:kimi-code` provider section is consulted — the config
/// also carries service keys (search, fetch) that are no business of the
/// usage ring.
enum KimiCredentials {
    static var configURL: URL {
        URL(fileURLWithPath: kimiHome).appendingPathComponent("config.toml")
    }

    /// The CLI honors $KIMI_CODE_HOME; a GUI app usually inherits no shell
    /// environment, but when one is present it wins, exactly as it does for
    /// the CLI itself.
    static var kimiHome: String {
        let override = ProcessInfo.processInfo.environment["KIMI_CODE_HOME"]
        if let override, !override.isEmpty { return override }
        return NSHomeDirectory() + "/.kimi-code"
    }

    static let defaultBaseURL = "https://api.kimi.com/coding/v1"

    struct Credential {
        let apiKey: String
        let baseURL: URL
    }

    static func load(from url: URL = configURL) throws -> Credential {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw UsageProviderError.needsAuth
        }
        let section = providerSection(named: "managed:kimi-code", in: text)
        guard let apiKey = normalized(section?["api_key"]) else {
            throw UsageProviderError.needsAuth
        }
        let base = ProcessInfo.processInfo.environment["KIMI_CODE_BASE_URL"]
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? section?["base_url"]
            ?? defaultBaseURL
        return Credential(
            apiKey: apiKey,
            baseURL: URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
                ?? URL(string: defaultBaseURL)!
        )
    }

    /// The `api_key`/`base_url` values inside one `[providers."<name>"]`
    /// table. Line-based, pinned to the shape the CLI writes — full TOML
    /// would be a dependency this one table does not earn.
    static func providerSection(named name: String, in text: String) -> [String: String]? {
        let header = "[providers.\"\(name)\"]"
        var inside = false
        var values: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                inside = trimmed == header
                continue
            }
            guard inside, let equals = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[trimmed.startIndex..<equals].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            values[key] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return values.isEmpty ? nil : values
    }

    /// Keys copied out of another tool's config sometimes carry a "Bearer"
    /// scheme; the usages endpoint is sent the key with the scheme added at
    /// request time, so a prefixed copy would be doubled.
    static func normalized(_ string: String?) -> String? {
        guard let string, !string.isEmpty else { return nil }
        let stripped = string.lowercased().hasPrefix("bearer ") ? String(string.dropFirst(7)) : string
        return stripped.isEmpty ? nil : stripped
    }
}
