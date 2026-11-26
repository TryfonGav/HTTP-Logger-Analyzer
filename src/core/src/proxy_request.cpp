#include "dipper/proxy_request.hpp"

#include <cstddef>
#include <string>
#include <vector>

namespace dipper {

namespace {

// Removes spaces and tabs from both ends of a piece of a header value.
std::string trimSpaces(const std::string& text) {
    std::size_t first = text.find_first_not_of(" \t");
    if (first == std::string::npos) {
        return "";
    }
    std::size_t last = text.find_last_not_of(" \t");
    return text.substr(first, last - first + 1);
}

// Splits "keep-alive, Upgrade" into {"keep-alive", "Upgrade"}.
std::vector<std::string> splitCommaList(const std::string& value) {
    std::vector<std::string> items;
    std::size_t start = 0;
    while (start <= value.size()) {
        std::size_t comma = value.find(',', start);
        if (comma == std::string::npos) {
            comma = value.size();
        }
        std::string item = trimSpaces(value.substr(start, comma - start));
        if (!item.empty()) {
            items.push_back(item);
        }
        start = comma + 1;
    }
    return items;
}

// Reads a port number such as "8080". Only digits, between 1 and 65535.
bool parsePort(const std::string& text, int& port) {
    if (text.empty() || text.size() > 5) {
        return false;
    }
    int value = 0;
    for (char digit : text) {
        if (digit < '0' || digit > '9') {
            return false;
        }
        value = value * 10 + (digit - '0');
    }
    if (value < 1 || value > 65535) {
        return false;
    }
    port = value;
    return true;
}

// Splits "example.com:8080" or "[::1]:8080" into host and port text. IPv6 addresses are
// written in square brackets because they contain ':' themselves.
bool splitHostAndPort(const std::string& authority, std::string& host, std::string& portText) {
    if (!authority.empty() && authority[0] == '[') {
        std::size_t closing = authority.find(']');
        if (closing == std::string::npos) {
            return false;
        }
        host = authority.substr(1, closing - 1);
        std::string after = authority.substr(closing + 1);
        if (after.empty()) {
            return true;
        }
        if (after[0] != ':') {
            return false;
        }
        portText = after.substr(1);
        return true;
    }

    std::size_t colon = authority.find(':');
    if (colon == std::string::npos) {
        host = authority;
        return true;
    }
    host = authority.substr(0, colon);
    portText = authority.substr(colon + 1);
    return portText.find(':') == std::string::npos; // a second ':' is not allowed
}

// The value for a Host header: "example.com", "example.com:8080" or "[::1]:8080".
std::string hostHeaderValue(const ProxyTarget& target) {
    std::string value = target.host;
    if (value.find(':') != std::string::npos) {
        value = "[" + value + "]";
    }
    if (target.port != 80) {
        value += ":" + std::to_string(target.port);
    }
    return value;
}

// Headers that describe only the connection between the client and the proxy, so they must
// not be passed on to the server (RFC 9110, section 7.6.1). "Expect: 100-continue" is also
// dropped because the proxy already has the whole body before it contacts the server.
bool isProxyOnlyHeader(const std::string& name, const Headers& allHeaders) {
    const std::vector<std::string> proxyOnlyNames = {
        "Connection", "Proxy-Connection", "Keep-Alive", "Proxy-Authorization",
        "TE",         "Trailer",          "Upgrade",    "Expect"};
    for (const std::string& proxyOnlyName : proxyOnlyNames) {
        if (equalsIgnoreCase(name, proxyOnlyName)) {
            return true;
        }
    }
    // "Connection: X-Secret" means the header X-Secret is also only for this hop.
    return hasConnectionToken(allHeaders, name);
}

} // namespace

bool parseProxyTarget(const std::string& url, ProxyTarget& target, std::string& error) {
    const std::string prefix = "http://";
    if (url.size() < prefix.size() || !equalsIgnoreCase(url.substr(0, prefix.size()), prefix)) {
        error = "a proxy request needs an absolute http:// URL, got \"" + url + "\"";
        return false;
    }

    // The host part ends at the first '/' or '?'. Everything from there is the path.
    std::string rest = url.substr(prefix.size());
    std::size_t authorityEnd = rest.find_first_of("/?");
    std::string authority = rest.substr(0, authorityEnd);
    std::string path = "/";
    if (authorityEnd != std::string::npos) {
        path = rest.substr(authorityEnd);
        if (path[0] == '?') {
            path = "/" + path; // "http://host?x=1" means "/?x=1"
        }
    }

    if (authority.find('@') != std::string::npos) {
        error = "user names in URLs are not supported";
        return false;
    }
    std::string host;
    std::string portText;
    if (!splitHostAndPort(authority, host, portText) || host.empty()) {
        error = "the URL has no valid host name: \"" + url + "\"";
        return false;
    }
    int port = 80;
    if (!portText.empty() && !parsePort(portText, port)) {
        error = "the URL has an invalid port: \"" + portText + "\"";
        return false;
    }

    target.host = host;
    target.port = port;
    target.path = path;
    return true;
}

bool hasConnectionToken(const Headers& headers, const std::string& token) {
    // There may be several Connection headers, each with a comma-separated list.
    for (const Header& header : headers) {
        if (!equalsIgnoreCase(header.name, "Connection")) {
            continue;
        }
        for (const std::string& item : splitCommaList(header.value)) {
            if (equalsIgnoreCase(item, token)) {
                return true;
            }
        }
    }
    return false;
}

bool wantsConnectionClose(const std::string& version, const Headers& headers) {
    if (hasConnectionToken(headers, "close")) {
        return true;
    }
    if (version == "HTTP/1.0") {
        return !hasConnectionToken(headers, "keep-alive");
    }
    return false;
}

bool isTunnelRequest(const HttpRequest& request) {
    if (request.method == "CONNECT") {
        return true;
    }
    // A protocol switch needs both "Upgrade: <protocol>" and "Connection: upgrade".
    bool hasUpgradeHeader = findHeader(request.headers, "Upgrade").has_value();
    return hasUpgradeHeader && hasConnectionToken(request.headers, "upgrade");
}

std::string buildUpstreamRequest(const HttpRequest& request, const ProxyTarget& target) {
    // A server expects only the path in the request line, not the full URL.
    std::string text = request.method + " " + target.path + " " + request.version + "\r\n";

    bool hasHost = false;
    bool hadBodyHeader = false;
    for (const Header& header : request.headers) {
        // The body is sent again below with its real length, so the old framing headers
        // (including "Transfer-Encoding: chunked", which the parser already decoded) go.
        if (equalsIgnoreCase(header.name, "Content-Length") ||
            equalsIgnoreCase(header.name, "Transfer-Encoding")) {
            hadBodyHeader = true;
            continue;
        }
        if (isProxyOnlyHeader(header.name, request.headers)) {
            continue;
        }
        if (equalsIgnoreCase(header.name, "Host")) {
            hasHost = true;
        }
        text += header.name + ": " + header.value + "\r\n";
    }

    // HTTP/1.0 clients may leave out Host, but many servers need it.
    if (!hasHost) {
        text += "Host: " + hostHeaderValue(target) + "\r\n";
    }
    if (hadBodyHeader || !request.body.empty()) {
        text += "Content-Length: " + std::to_string(request.body.size()) + "\r\n";
    }
    text += "\r\n";
    text += request.body;
    return text;
}

std::string buildErrorResponse(int statusCode, const std::string& reason,
                               const std::string& message) {
    std::string body = "Dipper proxy error: " + message + "\n";
    std::string text = "HTTP/1.1 " + std::to_string(statusCode) + " " + reason + "\r\n";
    text += "Content-Type: text/plain; charset=utf-8\r\n";
    text += "Content-Length: " + std::to_string(body.size()) + "\r\n";
    // After an error the proxy always closes the connection, and says so.
    text += "Connection: close\r\n";
    text += "\r\n";
    text += body;
    return text;
}

} // namespace dipper
