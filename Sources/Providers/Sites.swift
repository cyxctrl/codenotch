import Foundation

/// The site-specific halves of `WebSessionProvider`.
enum Sites {
    static let perplexity = WebSessionProvider.Site(
        id: "perplexity",
        displayName: "Perplexity",
        glyph: .third,
        origin: URL(string: "https://www.perplexity.ai/")!,
        script: """
        const response = await fetch('/rest/rate-limit/all', {
            credentials: 'include',
            headers: { 'Accept': 'application/json' }
        });
        const text = await response.text();
        // `sources.source_to_limit` is a long tail of connector quotas with
        // nothing to do with model usage; drop it so the rest stays legible.
        let trimmed = text;
        try { const p = JSON.parse(text); delete p.sources; trimmed = JSON.stringify(p); } catch (_) {}
        return JSON.stringify({ status: response.status, body: trimmed });
        """,
        parse: PerplexityUsage.windows(fromJSON:)
    )

    /// XyToken relay station (api.xytoken.xyb2b.com). Its wallet page calls
    /// POST /api/user/auth/refresh (empty body, authenticated solely by the
    /// HttpOnly `xy_token_api_refresh` cookie, which the server rotates on
    /// every call) and then GET /api/subscription/self with the short-lived
    /// bearer token that refresh returns. The cookie is invisible to page JS
    /// and unreachable for URLSession, so the sequence runs in the app's
    /// WebView: the user signs in once, the session lives up to 30 days, and
    /// when the server answers 401 the ring asks for sign-in again.
    static let xytoken = WebSessionProvider.Site(
        id: "xytoken",
        displayName: "XyToken",
        glyph: .third,
        origin: URL(string: "https://api.xytoken.xyb2b.com/")!,
        script: """
        const r = await fetch('/api/user/auth/refresh', {
            method: 'POST',
            credentials: 'include',
            headers: { 'Accept': 'application/json' }
        });
        const refreshBody = await r.text();
        if (!r.ok) return JSON.stringify({ status: r.status, body: refreshBody });
        let token = null;
        try { token = JSON.parse(refreshBody).data.access_token; } catch (_) {}
        if (!token) return JSON.stringify({ status: 502, body: refreshBody });
        const s = await fetch('/api/subscription/self', {
            credentials: 'include',
            headers: { 'Accept': 'application/json', 'Authorization': 'Bearer ' + token }
        });
        return JSON.stringify({ status: s.status, body: await s.text() });
        """,
        parse: XyTokenUsage.windows(fromJSON:)
    )

}
