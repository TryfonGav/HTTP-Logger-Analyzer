#include "dipper/http_parser.hpp"

#include <algorithm>
#include <string>
#include <utility>

namespace dipper {

namespace {

// Builds "HTTP/1.1" from the version numbers llhttp found.
std::string versionText(const llhttp_t* parser) {
    return "HTTP/" + std::to_string(parser->http_major) + "." + std::to_string(parser->http_minor);
}

} // namespace

HttpParser::HttpParser(ParserMode mode, std::int64_t maxBodyBytes)
    : mode_(mode), maxBodyBytes_(maxBodyBytes) {
    // Tell llhttp which of our functions to call for each part of a message. Callbacks we do
    // not set stay empty and llhttp skips them.
    llhttp_settings_init(&settings_);
    settings_.on_message_begin = onMessageBegin;
    settings_.on_url = onUrl;
    settings_.on_status = onStatus;
    settings_.on_header_field = onHeaderField;
    settings_.on_header_value = onHeaderValue;
    settings_.on_header_value_complete = onHeaderValueComplete;
    settings_.on_headers_complete = onHeadersComplete;
    settings_.on_body = onBody;
    settings_.on_message_complete = onMessageComplete;

    llhttp_type_t type = HTTP_REQUEST;
    if (mode == ParserMode::Responses) {
        type = HTTP_RESPONSE;
    }
    llhttp_init(&parser_, type, &settings_);

    // llhttp gives this pointer back to every callback, so the callbacks can find this object.
    parser_.data = this;
}

bool HttpParser::feed(const char* data, std::size_t size) {
    if (failed_) {
        return false;
    }
    // After an upgrade the bytes are a tunnel or another protocol, not HTTP. Ignore them.
    if (upgraded_) {
        return true;
    }

    llhttp_errno_t result = llhttp_execute(&parser_, data, size);
    if (result == HPE_OK) {
        return true;
    }
    // CONNECT or "Upgrade:" finished: llhttp stops here on purpose. This is not an error.
    if (result == HPE_PAUSED_UPGRADE) {
        upgraded_ = true;
        return true;
    }
    setError(result);
    return false;
}

bool HttpParser::finish() {
    if (failed_) {
        return false;
    }
    if (upgraded_) {
        return true;
    }
    // llhttp_finish completes a body that runs until the connection closes. It reports an
    // error if the connection closed in the middle of a message (for example half a header).
    llhttp_errno_t result = llhttp_finish(&parser_);
    if (result != HPE_OK) {
        setError(result);
        return false;
    }
    return true;
}

void HttpParser::setNextResponseIsForHead() {
    nextResponseIsForHead_ = true;
}

std::vector<HttpRequest> HttpParser::takeRequests() {
    std::vector<HttpRequest> finished;
    finished.swap(requests_); // hand over the list and leave ours empty
    return finished;
}

std::vector<HttpResponse> HttpParser::takeResponses() {
    std::vector<HttpResponse> finished;
    finished.swap(responses_);
    return finished;
}

void HttpParser::setError(llhttp_errno_t code) {
    failed_ = true;
    // Example: "HPE_INVALID_METHOD: Invalid method encountered"
    errorMessage_ = std::string(llhttp_errno_name(code)) + ": " + llhttp_get_error_reason(&parser_);
}

HttpParser& HttpParser::fromLlhttp(llhttp_t* parser) {
    return *static_cast<HttpParser*>(parser->data);
}

// ---- llhttp callbacks ----
// Each returns 0 to tell llhttp "carry on".

int HttpParser::onMessageBegin(llhttp_t* parser) {
    // A new message starts: forget everything about the previous one.
    HttpParser& self = fromLlhttp(parser);
    self.method_.clear();
    self.url_.clear();
    self.statusCode_ = 0;
    self.reason_.clear();
    self.version_.clear();
    self.headerName_.clear();
    self.headerValue_.clear();
    self.headers_.clear();
    self.body_.clear();
    self.bodySize_ = 0;
    return 0;
}

int HttpParser::onUrl(llhttp_t* parser, const char* at, std::size_t length) {
    fromLlhttp(parser).url_.append(at, length);
    return 0;
}

int HttpParser::onStatus(llhttp_t* parser, const char* at, std::size_t length) {
    fromLlhttp(parser).reason_.append(at, length);
    return 0;
}

int HttpParser::onHeaderField(llhttp_t* parser, const char* at, std::size_t length) {
    fromLlhttp(parser).headerName_.append(at, length);
    return 0;
}

int HttpParser::onHeaderValue(llhttp_t* parser, const char* at, std::size_t length) {
    fromLlhttp(parser).headerValue_.append(at, length);
    return 0;
}

int HttpParser::onHeaderValueComplete(llhttp_t* parser) {
    // Name and value are both complete now, so store the header and start the next one.
    // Trailer headers after a chunked body also arrive here and are added to the same list.
    HttpParser& self = fromLlhttp(parser);
    self.headers_.push_back(Header{self.headerName_, self.headerValue_});
    self.headerName_.clear();
    self.headerValue_.clear();
    return 0;
}

int HttpParser::onHeadersComplete(llhttp_t* parser) {
    HttpParser& self = fromLlhttp(parser);
    self.version_ = versionText(parser);

    if (self.mode_ == ParserMode::Requests) {
        llhttp_method_t method = static_cast<llhttp_method_t>(llhttp_get_method(parser));
        self.method_ = llhttp_method_name(method);
        return 0;
    }

    self.statusCode_ = llhttp_get_status_code(parser);
    // A 1xx response (e.g. "100 Continue") comes before the real answer, so a HEAD request
    // is only answered by the first response with status 200 or more.
    if (self.nextResponseIsForHead_ && self.statusCode_ >= 200) {
        self.nextResponseIsForHead_ = false;
        return 1; // 1 tells llhttp "this response has no body"
    }
    return 0;
}

int HttpParser::onBody(llhttp_t* parser, const char* at, std::size_t length) {
    // llhttp has already removed chunked framing, so these are the real body bytes.
    HttpParser& self = fromLlhttp(parser);
    std::int64_t pieceSize = static_cast<std::int64_t>(length);
    self.bodySize_ += pieceSize;

    // Keep at most maxBodyBytes_ bytes, but always count the full size above.
    std::int64_t spaceLeft = self.maxBodyBytes_ - static_cast<std::int64_t>(self.body_.size());
    if (spaceLeft > 0) {
        std::int64_t bytesToKeep = std::min(pieceSize, spaceLeft);
        self.body_.append(at, static_cast<std::size_t>(bytesToKeep));
    }
    return 0;
}

int HttpParser::onMessageComplete(llhttp_t* parser) {
    // Hand the finished message to the matching list. std::move hands over the body instead
    // of copying it (a body can be 10 MiB); onMessageBegin clears our fields for the next one.
    HttpParser& self = fromLlhttp(parser);
    if (self.mode_ == ParserMode::Requests) {
        HttpRequest request;
        request.method = self.method_;
        request.url = self.url_;
        request.version = self.version_;
        request.headers = std::move(self.headers_);
        request.body = std::move(self.body_);
        request.bodySize = self.bodySize_;
        self.requests_.push_back(std::move(request));
    } else {
        HttpResponse response;
        response.statusCode = self.statusCode_;
        response.reason = self.reason_;
        response.version = self.version_;
        response.headers = std::move(self.headers_);
        response.body = std::move(self.body_);
        response.bodySize = self.bodySize_;
        self.responses_.push_back(std::move(response));
    }
    return 0;
}

} // namespace dipper
