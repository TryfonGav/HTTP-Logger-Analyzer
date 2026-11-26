#pragma once

#include "dipper/http_transaction.hpp"

#include <cstddef>
#include <cstdint>
#include <llhttp.h>
#include <string>
#include <vector>

namespace dipper {

/// How many body bytes we keep per message by default (10 MiB). Bigger bodies are still
/// parsed and counted in bodySize, but only this many bytes are stored in body.
constexpr std::int64_t kDefaultMaxBodyBytes = 10 * 1024 * 1024;

/// Which side of a connection a parser reads.
enum class ParserMode {
    Requests, // bytes the client sends to the server
    Responses // bytes the server sends back
};

/// Turns a stream of bytes from one direction of a connection into finished HTTP/1.x
/// messages. It is a thin wrapper around the llhttp library, which does the real parsing.
///
/// Usage: create one parser per direction, call feed() with every block of bytes read from
/// the socket (blocks can be cut anywhere, even in the middle of a header), and collect the
/// finished messages with takeRequests() / takeResponses(). Call finish() when the connection
/// closes, because some responses only end when the server closes the connection.
class HttpParser {
  public:
    explicit HttpParser(ParserMode mode, std::int64_t maxBodyBytes = kDefaultMaxBodyBytes);

    // llhttp keeps a pointer to our settings, so copying or moving the parser would leave
    // that pointer aimed at the old object. We forbid copies to make that mistake impossible.
    HttpParser(const HttpParser&) = delete;
    HttpParser& operator=(const HttpParser&) = delete;

    /// Parses the next block of bytes. Returns false if the bytes are not valid HTTP; the
    /// parser then stays failed and errorMessage() says why.
    bool feed(const char* data, std::size_t size);

    /// Tells the parser that the connection was closed. Finishes a response whose body runs
    /// "until the connection closes". Returns false if the close cut a message in half.
    bool finish();

    /// Responses mode only: the next response answers a HEAD request, so it has headers but
    /// no body (even if it has a Content-Length). Cleared after the next final (>= 200) response.
    void setNextResponseIsForHead();

    bool hasError() const { return failed_; }
    const std::string& errorMessage() const { return errorMessage_; }

    /// True after a CONNECT request or a protocol upgrade (e.g. WebSocket). The bytes after
    /// that point are not HTTP any more, so feed() ignores them (tunnelling is issue #22).
    bool isUpgraded() const { return upgraded_; }

    /// Returns the messages finished since the last call and forgets them.
    std::vector<HttpRequest> takeRequests();
    std::vector<HttpResponse> takeResponses();

  private:
    // llhttp is a C library: it calls plain functions, not member functions. These static
    // functions are those callbacks. Each one gets back to our object through parser->data.
    static HttpParser& fromLlhttp(llhttp_t* parser);
    static int onMessageBegin(llhttp_t* parser);
    static int onUrl(llhttp_t* parser, const char* at, std::size_t length);
    static int onStatus(llhttp_t* parser, const char* at, std::size_t length);
    static int onHeaderField(llhttp_t* parser, const char* at, std::size_t length);
    static int onHeaderValue(llhttp_t* parser, const char* at, std::size_t length);
    static int onHeaderValueComplete(llhttp_t* parser);
    static int onHeadersComplete(llhttp_t* parser);
    static int onBody(llhttp_t* parser, const char* at, std::size_t length);
    static int onMessageComplete(llhttp_t* parser);

    void setError(llhttp_errno_t code);

    ParserMode mode_;
    std::int64_t maxBodyBytes_;
    llhttp_settings_t settings_{};
    llhttp_t parser_{};

    // The message being parsed right now. llhttp may hand us the URL, header names and
    // values in several pieces, so we append each piece until llhttp says it is complete.
    std::string method_;
    std::string url_;
    int statusCode_ = 0;
    std::string reason_;
    std::string version_;
    std::string headerName_;
    std::string headerValue_;
    Headers headers_;
    std::string body_;
    std::int64_t bodySize_ = 0;

    // Finished messages waiting for takeRequests() / takeResponses().
    std::vector<HttpRequest> requests_;
    std::vector<HttpResponse> responses_;

    bool nextResponseIsForHead_ = false;
    bool upgraded_ = false;
    bool failed_ = false;
    std::string errorMessage_;
};

} // namespace dipper
