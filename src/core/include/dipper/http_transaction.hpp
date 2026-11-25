#pragma once

#include <chrono>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace dipper {

/// One HTTP header line, for example name "Content-Type" and value "text/html".
struct Header {
    std::string name;
    std::string value;
};

/// All headers of a request or response, in the order they arrived.
/// We use a vector (not a map) because HTTP allows the same header more than once
/// (for example several "Set-Cookie" lines) and the order can matter.
using Headers = std::vector<Header>;

/// Value used in Timings for a phase that was not measured or did not happen
/// (for example no TLS handshake on a plain HTTP request). We do not use 0 because
/// 0 milliseconds is a real (very fast) measurement.
constexpr double kNotMeasured = -1.0;

/// How long each phase of a transaction took, in milliseconds.
struct Timings {
    /// Wall-clock time when the proxy received the first byte of the request.
    std::chrono::system_clock::time_point startTime{};
    double dnsMs = kNotMeasured;     // looking up the server's IP address
    double connectMs = kNotMeasured; // opening the TCP connection to the server
    double tlsMs = kNotMeasured;     // TLS handshake (HTTPS only)
    double ttfbMs = kNotMeasured;    // time to first byte of the response, from startTime
    double totalMs = kNotMeasured;   // from startTime until the last response byte
};

/// The request the client sent.
struct HttpRequest {
    std::string method;  // "GET", "POST", ...
    std::string url;     // as sent by the client, e.g. "http://example.com/index.html"
    std::string version; // "HTTP/1.1"
    Headers headers;
    std::string body;          // body bytes we kept (may be cut short later, see #25)
    std::int64_t bodySize = 0; // real body size in bytes, even if we kept fewer
};

/// The response the server sent back.
struct HttpResponse {
    int statusCode = 0;  // 200, 404, ...; 0 means "no response"
    std::string reason;  // "OK", "Not Found", ...
    std::string version; // "HTTP/1.1"
    Headers headers;
    std::string body;
    std::int64_t bodySize = 0;
};

/// How the transaction was captured.
enum class CaptureMode {
    Proxy,          // plain HTTP through our proxy
    HttpsIntercept, // HTTPS decrypted by our proxy with the local CA
    Import          // loaded from a file (for example a HAR file)
};

/// What went wrong, if anything. None means the transaction finished normally.
enum class TransactionError {
    None,
    DnsFailed,         // the server name could not be resolved
    ConnectionRefused, // the server refused the TCP connection
    Timeout,           // the server did not answer in time
    ParseError,        // the request or response was not valid HTTP
    Other
};

/// One request together with its response (or the error that stopped it).
/// This is the main record that the proxy produces and the store saves.
struct HttpTransaction {
    std::int64_t id = 0;        // 0 until the store saves it and gives it an id
    std::int64_t sessionId = 0; // 0 until the store saves it

    // Connection information
    std::string clientAddress; // e.g. "127.0.0.1"
    int clientPort = 0;
    std::string serverHost; // e.g. "example.com"
    int serverPort = 0;
    std::string scheme; // "http" or "https"

    HttpRequest request;
    bool hasResponse = false; // false when the request failed before a response arrived
    HttpResponse response;

    Timings timings;
    CaptureMode captureMode = CaptureMode::Proxy;
    TransactionError error = TransactionError::None;
    std::string errorMessage; // extra detail for the user when error is not None
};

/// Compares two strings without caring about upper or lower case (ASCII only).
/// HTTP header names are case-insensitive, so "Content-Type" equals "content-type".
bool equalsIgnoreCase(const std::string& a, const std::string& b);

/// Returns the value of the first header called `name` (case-insensitive),
/// or no value if there is no such header.
std::optional<std::string> findHeader(const Headers& headers, const std::string& name);

/// Checks that a transaction makes sense. Returns an empty string if it does,
/// otherwise a short plain-English description of the first problem found.
std::string findProblem(const HttpTransaction& transaction);

} // namespace dipper
