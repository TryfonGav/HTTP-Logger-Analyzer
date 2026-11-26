#pragma once

#include "dipper/http_transaction.hpp"

#include <string>

// Small helper functions the proxy uses to understand and rewrite requests. They do no
// networking, so they can be unit-tested on their own.

namespace dipper {

/// Where a proxied request must go, taken from its absolute URL.
/// "http://example.com:8080/a?b=1" gives host "example.com", port 8080, path "/a?b=1".
struct ProxyTarget {
    std::string host;
    int port = 80;
    std::string path = "/";
};

/// Splits an absolute "http://" URL (the form a browser sends to a proxy) into a target.
/// Returns false and sets `error` to a plain-English reason if the URL cannot be used.
bool parseProxyTarget(const std::string& url, ProxyTarget& target, std::string& error);

/// True if a "Connection" header lists `token`, for example "close" or "upgrade" (ignoring case).
bool hasConnectionToken(const Headers& headers, const std::string& token);

/// True if the side that sent these headers wants the connection closed after this message.
/// HTTP/1.1 keeps connections open unless "Connection: close" is sent; HTTP/1.0 closes them
/// unless "Connection: keep-alive" is sent.
bool wantsConnectionClose(const std::string& version, const Headers& headers);

/// True for requests that turn the connection into a tunnel (CONNECT) or another protocol
/// (for example WebSocket). The proxy cannot forward these yet (see issue #22).
bool isTunnelRequest(const HttpRequest& request);

/// Builds the bytes the proxy sends to the real server: the request line with only the path
/// ("GET /a?b=1 HTTP/1.1"), the headers without the ones meant only for the proxy hop, and the
/// body with a fresh Content-Length.
std::string buildUpstreamRequest(const HttpRequest& request, const ProxyTarget& target);

/// Builds a short plain-text response the proxy sends when it cannot forward a request, for
/// example buildErrorResponse(502, "Bad Gateway", "could not resolve example.invalid").
std::string buildErrorResponse(int statusCode, const std::string& reason,
                               const std::string& message);

} // namespace dipper
