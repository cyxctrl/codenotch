import Foundation
import os

/// Reads Kimi Code usage from the endpoint behind the CLI's own `/usage`
/// command, with the managed API key borrowed from `~/.kimi-code/config.toml`
/// — the same "read the credential the tool already holds" bargain as the
/// rest of the notch.
///
/// The numbers are Kimi's, so this is `.official`. The endpoint is not a
/// published API, though; its shape is pinned by tests, including a response
/// recorded from a live session, and this is the first place a change would
/// show. A 429 backs off for a minute rather than polling into the limit.
actor KimiProvider: UsageProvider {
    nonisolated let id = "kimi"
    nonisolated let displayName = "Kimi"
    nonisolated let glyph = ProviderGlyph.kimi

    private let session: URLSession
    private let configURL: URL

    init(session: URLSession = .shared, configURL: URL = KimiCredentials.configURL) {
        self.session = session
        self.configURL = configURL
    }

    nonisolated var signInRoute: SignInRoute {
        .guidance("""
                Sign in to the Kimi Code CLI: run `kimi` and finish the browser login. \
                The key it writes into ~/.kimi-code/config.toml is what Codenotch reads — \
                no account, no keychain prompt, nothing to paste.
                """)
    }

    nonisolated func account() -> ProviderAccount? {
        // Re-reads the same plain file as the fetch; a settings draw can come
        // after the login changed it.
        guard (try? KimiCredentials.load(from: configURL)) != nil else { return nil }
        return ProviderAccount(
            label: nil,
            plan: nil,
            source: "~/.kimi-code",
            manageURL: URL(string: "https://www.kimi.com/")
        )
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        // Re-read on every fetch: an ordinary file, not a keychain item —
        // reading it puts no prompt in front of anyone.
        let credentials = try KimiCredentials.load(from: configURL)
        let data = try await fetch(credentials: credentials)
        let payload = try KimiUsage.parse(data)

        return ProviderSnapshot(
            id: id,
            displayName: displayName,
            glyph: glyph,
            fidelity: .official,
            status: .ok,
            windows: payload.windows,
            headlineID: "session"
        )
    }

    private func fetch(credentials: KimiCredentials.Credential) async throws -> Data {
        var request = URLRequest(url: credentials.baseURL.appendingPathComponent("usages"))
        request.httpMethod = "GET"
        // The endpoint wants the scheme — the opposite of the kimi.com web
        // gateway, which wants the raw token. This is the coding endpoint's
        // own convention, straight from the CLI's request.
        request.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        Log.usage.debug("GET kimi coding /usages")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        Log.usage.debug("kimi /usages answered \(status)")

        if status == 401 || status == 403 { throw UsageProviderError.needsAuth }
        if status == 429 { throw UsageProviderError.rateLimited(retryAfter: 60) }
        guard (200..<300).contains(status) else {
            throw UsageProviderError.badResponse(status: status)
        }
        return data
    }
}
