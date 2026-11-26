#include "dipper/proxy_request.hpp"

#include <gtest/gtest.h>
#include <string>
#include <vector>

using dipper::Headers;
using dipper::HttpRequest;
using dipper::ProxyTarget;

namespace {

HttpRequest makeRequest(const std::string& method, const std::string& url, const Headers& headers) {
    HttpRequest request;
    request.method = method;
    request.url = url;
    request.version = "HTTP/1.1";
    request.headers = headers;
    return request;
}

} // namespace

// ---- parseProxyTarget ----

TEST(ParseProxyTarget, SplitsHostPortAndPath) {
    ProxyTarget target;
    std::string error;
    ASSERT_TRUE(dipper::parseProxyTarget("http://example.com:8080/a/b?x=1", target, error));
    EXPECT_EQ(target.host, "example.com");
    EXPECT_EQ(target.port, 8080);
    EXPECT_EQ(target.path, "/a/b?x=1");
}

TEST(ParseProxyTarget, UsesPort80AndRootPathByDefault) {
    ProxyTarget target;
    std::string error;
    ASSERT_TRUE(dipper::parseProxyTarget("HTTP://Example.com", target, error));
    EXPECT_EQ(target.host, "Example.com");
    EXPECT_EQ(target.port, 80);
    EXPECT_EQ(target.path, "/");
}

TEST(ParseProxyTarget, QueryWithoutPathGetsRootPath) {
    ProxyTarget target;
    std::string error;
    ASSERT_TRUE(dipper::parseProxyTarget("http://example.com?q=1", target, error));
    EXPECT_EQ(target.path, "/?q=1");
}

TEST(ParseProxyTarget, AcceptsIpv6InBrackets) {
    ProxyTarget target;
    std::string error;
    ASSERT_TRUE(dipper::parseProxyTarget("http://[::1]:9000/x", target, error));
    EXPECT_EQ(target.host, "::1");
    EXPECT_EQ(target.port, 9000);
    EXPECT_EQ(target.path, "/x");
}

TEST(ParseProxyTarget, RejectsUrlsAProxyCannotUse) {
    const std::vector<std::string> badUrls = {
        "/index.html",               // no host: the client did not treat us as a proxy
        "https://example.com/",      // HTTPS goes through CONNECT instead (#22)
        "http://",                   // no host
        "http://:8080/",             // no host
        "http://example.com:0/",     // port out of range
        "http://example.com:99999/", // port out of range
        "http://example.com:80x/",   // port not a number
        "http://user@example.com/",  // user names not supported
        "http://[::1/",              // missing ']'
        "http://a:1:2/",             // two colons without brackets
    };
    for (const std::string& url : badUrls) {
        ProxyTarget target;
        std::string error;
        EXPECT_FALSE(dipper::parseProxyTarget(url, target, error)) << url;
        EXPECT_FALSE(error.empty()) << url;
    }
}

// ---- Connection header ----

TEST(ConnectionHeader, FindsTokensInListsAndRepeatedHeaders) {
    Headers headers = {{"Connection", "keep-alive, X-Secret"}, {"connection", " Upgrade "}};
    EXPECT_TRUE(dipper::hasConnectionToken(headers, "keep-alive"));
    EXPECT_TRUE(dipper::hasConnectionToken(headers, "x-secret"));
    EXPECT_TRUE(dipper::hasConnectionToken(headers, "upgrade"));
    EXPECT_FALSE(dipper::hasConnectionToken(headers, "close"));
}

TEST(ConnectionHeader, DecidesWhetherToClose) {
    EXPECT_FALSE(dipper::wantsConnectionClose("HTTP/1.1", {}));
    EXPECT_TRUE(dipper::wantsConnectionClose("HTTP/1.1", {{"Connection", "close"}}));
    EXPECT_TRUE(dipper::wantsConnectionClose("HTTP/1.0", {}));
    EXPECT_FALSE(dipper::wantsConnectionClose("HTTP/1.0", {{"Connection", "Keep-Alive"}}));
}

TEST(TunnelRequest, ConnectAndUpgradeAreTunnels) {
    EXPECT_TRUE(dipper::isTunnelRequest(makeRequest("CONNECT", "example.com:443", {})));
    EXPECT_TRUE(dipper::isTunnelRequest(makeRequest(
        "GET", "http://example.com/chat", {{"Upgrade", "websocket"}, {"Connection", "Upgrade"}})));
    // "Upgrade" alone, without "Connection: upgrade", does not switch protocols.
    EXPECT_FALSE(dipper::isTunnelRequest(
        makeRequest("GET", "http://example.com/", {{"Upgrade", "websocket"}})));
    EXPECT_FALSE(dipper::isTunnelRequest(makeRequest("GET", "http://example.com/", {})));
}

// ---- buildUpstreamRequest ----

TEST(BuildUpstreamRequest, UsesPathAndDropsProxyOnlyHeaders) {
    HttpRequest request = makeRequest("GET", "http://example.com/a?b=1",
                                      {{"Host", "example.com"},
                                       {"Proxy-Connection", "keep-alive"},
                                       {"Connection", "keep-alive, X-Secret"},
                                       {"X-Secret", "for the proxy only"},
                                       {"Proxy-Authorization", "Basic abc"},
                                       {"Accept", "*/*"}});
    ProxyTarget target;
    std::string error;
    ASSERT_TRUE(dipper::parseProxyTarget(request.url, target, error));

    EXPECT_EQ(dipper::buildUpstreamRequest(request, target), "GET /a?b=1 HTTP/1.1\r\n"
                                                             "Host: example.com\r\n"
                                                             "Accept: */*\r\n"
                                                             "\r\n");
}

TEST(BuildUpstreamRequest, ResendsDecodedBodyWithContentLength) {
    // The parser already decoded the chunked body, so it is sent with a plain length.
    HttpRequest request = makeRequest(
        "POST", "http://example.com/upload",
        {{"Host", "example.com"}, {"Transfer-Encoding", "chunked"}, {"Expect", "100-continue"}});
    request.body = "Hello, World!";
    request.bodySize = 13;
    ProxyTarget target;
    std::string error;
    ASSERT_TRUE(dipper::parseProxyTarget(request.url, target, error));

    EXPECT_EQ(dipper::buildUpstreamRequest(request, target), "POST /upload HTTP/1.1\r\n"
                                                             "Host: example.com\r\n"
                                                             "Content-Length: 13\r\n"
                                                             "\r\n"
                                                             "Hello, World!");
}

TEST(BuildUpstreamRequest, KeepsEmptyBodyLengthAndAddsMissingHost) {
    // An HTTP/1.0 POST with an empty body and no Host header.
    HttpRequest request =
        makeRequest("POST", "http://example.com:8080/", {{"Content-Length", "0"}});
    request.version = "HTTP/1.0";
    ProxyTarget target;
    std::string error;
    ASSERT_TRUE(dipper::parseProxyTarget(request.url, target, error));

    EXPECT_EQ(dipper::buildUpstreamRequest(request, target), "POST / HTTP/1.0\r\n"
                                                             "Host: example.com:8080\r\n"
                                                             "Content-Length: 0\r\n"
                                                             "\r\n");
}

// ---- buildErrorResponse ----

TEST(BuildErrorResponse, IsAValidClosingResponse) {
    std::string expectedBody = "Dipper proxy error: could not find the server\n";
    EXPECT_EQ(dipper::buildErrorResponse(502, "Bad Gateway", "could not find the server"),
              "HTTP/1.1 502 Bad Gateway\r\n"
              "Content-Type: text/plain; charset=utf-8\r\n"
              "Content-Length: " +
                  std::to_string(expectedBody.size()) +
                  "\r\n"
                  "Connection: close\r\n"
                  "\r\n" +
                  expectedBody);
}
