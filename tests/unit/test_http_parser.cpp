#include "dipper/http_parser.hpp"

#include <fstream>
#include <gtest/gtest.h>
#include <sstream>
#include <string>
#include <vector>

using dipper::HttpParser;
using dipper::HttpRequest;
using dipper::HttpResponse;
using dipper::ParserMode;

namespace {

// Reads a fixture file byte for byte. The path is relative: CTest runs the tests from the
// tests/ folder (see tests/CMakeLists.txt), which avoids non-ASCII absolute paths on Windows.
std::string readFixture(const std::string& name) {
    std::ifstream file("fixtures/http/" + name, std::ios::binary);
    EXPECT_TRUE(file.is_open()) << "cannot open fixture " << name;
    std::stringstream contents;
    contents << file.rdbuf();
    return contents.str();
}

// Feeds a whole fixture in one call, like one big socket read.
bool feedAll(HttpParser& parser, const std::string& bytes) {
    return parser.feed(bytes.data(), bytes.size());
}

// Feeds a fixture one byte per call: the worst case of a slow network, where every piece
// of the message (method, URL, header names, chunk sizes) is cut in the middle.
bool feedOneByteAtATime(HttpParser& parser, const std::string& bytes) {
    for (std::size_t i = 0; i < bytes.size(); i++) {
        if (!parser.feed(&bytes[i], 1)) {
            return false;
        }
    }
    return true;
}

void expectSameHeaders(const dipper::Headers& expected, const dipper::Headers& actual) {
    ASSERT_EQ(expected.size(), actual.size());
    for (std::size_t i = 0; i < expected.size(); i++) {
        EXPECT_EQ(expected[i].name, actual[i].name);
        EXPECT_EQ(expected[i].value, actual[i].value);
    }
}

void expectSameRequests(const std::vector<HttpRequest>& expected,
                        const std::vector<HttpRequest>& actual) {
    ASSERT_EQ(expected.size(), actual.size());
    for (std::size_t i = 0; i < expected.size(); i++) {
        EXPECT_EQ(expected[i].method, actual[i].method);
        EXPECT_EQ(expected[i].url, actual[i].url);
        EXPECT_EQ(expected[i].version, actual[i].version);
        expectSameHeaders(expected[i].headers, actual[i].headers);
        EXPECT_EQ(expected[i].body, actual[i].body);
        EXPECT_EQ(expected[i].bodySize, actual[i].bodySize);
    }
}

void expectSameResponses(const std::vector<HttpResponse>& expected,
                         const std::vector<HttpResponse>& actual) {
    ASSERT_EQ(expected.size(), actual.size());
    for (std::size_t i = 0; i < expected.size(); i++) {
        EXPECT_EQ(expected[i].statusCode, actual[i].statusCode);
        EXPECT_EQ(expected[i].reason, actual[i].reason);
        EXPECT_EQ(expected[i].version, actual[i].version);
        expectSameHeaders(expected[i].headers, actual[i].headers);
        EXPECT_EQ(expected[i].body, actual[i].body);
        EXPECT_EQ(expected[i].bodySize, actual[i].bodySize);
    }
}

// Parses a request fixture fed all at once, then again one byte at a time, and checks both
// ways give the same requests.
void expectSameRequestsWhenSplit(const std::string& fixtureName) {
    SCOPED_TRACE(fixtureName);
    std::string bytes = readFixture(fixtureName);

    HttpParser whole(ParserMode::Requests);
    ASSERT_TRUE(feedAll(whole, bytes)) << whole.errorMessage();
    HttpParser split(ParserMode::Requests);
    ASSERT_TRUE(feedOneByteAtATime(split, bytes)) << split.errorMessage();

    std::vector<HttpRequest> expected = whole.takeRequests();
    EXPECT_FALSE(expected.empty());
    expectSameRequests(expected, split.takeRequests());
}

void expectSameResponsesWhenSplit(const std::string& fixtureName) {
    SCOPED_TRACE(fixtureName);
    std::string bytes = readFixture(fixtureName);

    HttpParser whole(ParserMode::Responses);
    ASSERT_TRUE(feedAll(whole, bytes)) << whole.errorMessage();
    ASSERT_TRUE(whole.finish()) << whole.errorMessage();
    HttpParser split(ParserMode::Responses);
    ASSERT_TRUE(feedOneByteAtATime(split, bytes)) << split.errorMessage();
    ASSERT_TRUE(split.finish()) << split.errorMessage();

    std::vector<HttpResponse> expected = whole.takeResponses();
    EXPECT_FALSE(expected.empty());
    expectSameResponses(expected, split.takeResponses());
}

} // namespace

// ---- Requests ----

TEST(HttpParserRequests, ParsesGetWithAllHeadersInOrder) {
    HttpParser parser(ParserMode::Requests);
    ASSERT_TRUE(feedAll(parser, readFixture("request_get.http"))) << parser.errorMessage();

    std::vector<HttpRequest> requests = parser.takeRequests();
    ASSERT_EQ(requests.size(), 1U);
    const HttpRequest& request = requests[0];
    EXPECT_EQ(request.method, "GET");
    EXPECT_EQ(request.url, "http://example.com/index.html?page=1");
    EXPECT_EQ(request.version, "HTTP/1.1");
    EXPECT_EQ(request.body, "");
    EXPECT_EQ(request.bodySize, 0);

    // Repeated and mixed-case headers are kept exactly as sent, in order.
    ASSERT_EQ(request.headers.size(), 6U);
    EXPECT_EQ(request.headers[0].name, "Host");
    EXPECT_EQ(request.headers[0].value, "example.com");
    EXPECT_EQ(request.headers[3].name, "X-Custom");
    EXPECT_EQ(request.headers[3].value, "one");
    EXPECT_EQ(request.headers[4].name, "x-CUSTOM");
    EXPECT_EQ(request.headers[4].value, "two");
    EXPECT_EQ(request.headers[5].name, "X-Empty");
    EXPECT_EQ(request.headers[5].value, "");
    EXPECT_EQ(dipper::findHeader(request.headers, "x-custom").value_or(""), "one");
}

TEST(HttpParserRequests, ParsesPostWithContentLength) {
    HttpParser parser(ParserMode::Requests);
    ASSERT_TRUE(feedAll(parser, readFixture("request_post.http"))) << parser.errorMessage();

    std::vector<HttpRequest> requests = parser.takeRequests();
    ASSERT_EQ(requests.size(), 1U);
    EXPECT_EQ(requests[0].method, "POST");
    EXPECT_EQ(requests[0].body, "name=dipper&lang=c%2B%2B");
    EXPECT_EQ(requests[0].bodySize, 24);
}

TEST(HttpParserRequests, RemovesChunkedFramingFromBody) {
    HttpParser parser(ParserMode::Requests);
    ASSERT_TRUE(feedAll(parser, readFixture("request_post_chunked.http"))) << parser.errorMessage();

    std::vector<HttpRequest> requests = parser.takeRequests();
    ASSERT_EQ(requests.size(), 1U);
    EXPECT_EQ(requests[0].body, "Hello, World!");
    EXPECT_EQ(requests[0].bodySize, 13);
}

TEST(HttpParserRequests, KeepAliveConnectionGivesOneRequestPerFeed) {
    // Two requests on the same connection, arriving in two separate reads.
    HttpParser parser(ParserMode::Requests);

    ASSERT_TRUE(feedAll(parser, readFixture("request_get.http")));
    std::vector<HttpRequest> first = parser.takeRequests();
    ASSERT_EQ(first.size(), 1U);
    EXPECT_EQ(first[0].method, "GET");

    ASSERT_TRUE(feedAll(parser, readFixture("request_post.http")));
    std::vector<HttpRequest> second = parser.takeRequests();
    ASSERT_EQ(second.size(), 1U);
    EXPECT_EQ(second[0].method, "POST");
    // Nothing from the first request leaks into the second one.
    EXPECT_EQ(second[0].headers.size(), 3U);
}

TEST(HttpParserRequests, ParsesPipelinedRequestsFromOneBuffer) {
    HttpParser parser(ParserMode::Requests);
    ASSERT_TRUE(feedAll(parser, readFixture("request_pipelined.http"))) << parser.errorMessage();

    std::vector<HttpRequest> requests = parser.takeRequests();
    ASSERT_EQ(requests.size(), 3U);
    EXPECT_EQ(requests[0].url, "http://example.com/one");
    EXPECT_EQ(requests[1].url, "http://example.com/two");
    EXPECT_EQ(requests[2].url, "http://example.com/three");
}

TEST(HttpParserRequests, TakeRequestsEmptiesTheList) {
    HttpParser parser(ParserMode::Requests);
    ASSERT_TRUE(feedAll(parser, readFixture("request_get.http")));
    EXPECT_EQ(parser.takeRequests().size(), 1U);
    EXPECT_TRUE(parser.takeRequests().empty());
}

TEST(HttpParserRequests, ConnectStopsParsingAndIgnoresTunnelBytes) {
    HttpParser parser(ParserMode::Requests);
    // The fixture has TLS bytes after the CONNECT request; they must not cause an error.
    ASSERT_TRUE(feedAll(parser, readFixture("request_connect.http"))) << parser.errorMessage();
    EXPECT_TRUE(parser.isUpgraded());
    EXPECT_FALSE(parser.hasError());

    std::vector<HttpRequest> requests = parser.takeRequests();
    ASSERT_EQ(requests.size(), 1U);
    EXPECT_EQ(requests[0].method, "CONNECT");
    EXPECT_EQ(requests[0].url, "example.com:443");

    // More tunnel bytes later are ignored as well.
    EXPECT_TRUE(parser.feed("\x17\x03\x03", 3));
    EXPECT_TRUE(parser.finish());
    EXPECT_TRUE(parser.takeRequests().empty());
}

// ---- Responses ----

TEST(HttpParserResponses, ParsesResponseWithContentLength) {
    HttpParser parser(ParserMode::Responses);
    ASSERT_TRUE(feedAll(parser, readFixture("response_200.http"))) << parser.errorMessage();

    std::vector<HttpResponse> responses = parser.takeResponses();
    ASSERT_EQ(responses.size(), 1U);
    const HttpResponse& response = responses[0];
    EXPECT_EQ(response.statusCode, 200);
    EXPECT_EQ(response.reason, "OK");
    EXPECT_EQ(response.version, "HTTP/1.1");
    EXPECT_EQ(response.body, "<html><body>Hello from Dipper</body></html>");
    EXPECT_EQ(response.bodySize, 43);
    // Both Set-Cookie headers are kept.
    ASSERT_EQ(response.headers.size(), 4U);
    EXPECT_EQ(response.headers[2].value, "a=1");
    EXPECT_EQ(response.headers[3].value, "b=2");
}

TEST(HttpParserResponses, ParsesChunkedResponseWithTrailer) {
    HttpParser parser(ParserMode::Responses);
    ASSERT_TRUE(feedAll(parser, readFixture("response_chunked.http"))) << parser.errorMessage();

    std::vector<HttpResponse> responses = parser.takeResponses();
    ASSERT_EQ(responses.size(), 1U);
    // Chunk sizes and the chunk extension ";note=first" are not part of the body.
    EXPECT_EQ(responses[0].body, "Hello Dipper");
    EXPECT_EQ(responses[0].bodySize, 12);
    // The trailer header after the last chunk is added after the normal headers.
    EXPECT_EQ(dipper::findHeader(responses[0].headers, "X-Checksum").value_or(""), "abc123");
}

TEST(HttpParserResponses, BodyUntilCloseNeedsFinish) {
    HttpParser parser(ParserMode::Responses);
    std::string bytes = readFixture("response_until_close.http");
    ASSERT_TRUE(feedAll(parser, bytes)) << parser.errorMessage();
    // No Content-Length: the parser cannot know the body has ended yet.
    EXPECT_TRUE(parser.takeResponses().empty());

    ASSERT_TRUE(parser.finish()) << parser.errorMessage();
    std::vector<HttpResponse> responses = parser.takeResponses();
    ASSERT_EQ(responses.size(), 1U);
    EXPECT_EQ(responses[0].body,
              "This body has no length; it ends when the server closes the connection.");
}

TEST(HttpParserResponses, NoBodyFor204And304EvenWithContentLength) {
    HttpParser parser(ParserMode::Responses);
    ASSERT_TRUE(feedAll(parser, readFixture("response_204_then_304.http")))
        << parser.errorMessage();

    // If the parser had wrongly read a body for 204 or 304, the 200 after them would be lost.
    std::vector<HttpResponse> responses = parser.takeResponses();
    ASSERT_EQ(responses.size(), 3U);
    EXPECT_EQ(responses[0].statusCode, 204);
    EXPECT_EQ(responses[0].bodySize, 0);
    EXPECT_EQ(responses[1].statusCode, 304);
    EXPECT_EQ(responses[1].bodySize, 0);
    EXPECT_EQ(responses[2].statusCode, 200);
    EXPECT_EQ(responses[2].body, "ok");
}

TEST(HttpParserResponses, ResponseToHeadHasNoBody) {
    HttpParser parser(ParserMode::Responses);
    parser.setNextResponseIsForHead();
    ASSERT_TRUE(feedAll(parser, readFixture("response_head_then_200.http")))
        << parser.errorMessage();

    // The first response says Content-Length: 5000 but answers HEAD, so it has no body.
    // The second one answers a normal GET again.
    std::vector<HttpResponse> responses = parser.takeResponses();
    ASSERT_EQ(responses.size(), 2U);
    EXPECT_EQ(responses[0].bodySize, 0);
    EXPECT_EQ(dipper::findHeader(responses[0].headers, "Content-Length").value_or(""), "5000");
    EXPECT_EQ(responses[1].body, "ok");
}

TEST(HttpParserResponses, InformationalResponseComesBeforeTheFinalOne) {
    HttpParser parser(ParserMode::Responses);
    ASSERT_TRUE(feedAll(parser, readFixture("response_100_continue.http")))
        << parser.errorMessage();

    std::vector<HttpResponse> responses = parser.takeResponses();
    ASSERT_EQ(responses.size(), 2U);
    EXPECT_EQ(responses[0].statusCode, 100);
    EXPECT_EQ(responses[0].reason, "Continue");
    EXPECT_EQ(responses[1].statusCode, 201);
    EXPECT_EQ(responses[1].body, "done");
}

// ---- Split input ----

TEST(HttpParserSplitInput, RequestsAreTheSameWhenFedOneByteAtATime) {
    expectSameRequestsWhenSplit("request_get.http");
    expectSameRequestsWhenSplit("request_post.http");
    expectSameRequestsWhenSplit("request_post_chunked.http");
    expectSameRequestsWhenSplit("request_pipelined.http");
    expectSameRequestsWhenSplit("request_connect.http");
}

TEST(HttpParserSplitInput, ResponsesAreTheSameWhenFedOneByteAtATime) {
    expectSameResponsesWhenSplit("response_200.http");
    expectSameResponsesWhenSplit("response_chunked.http");
    expectSameResponsesWhenSplit("response_until_close.http");
    expectSameResponsesWhenSplit("response_204_then_304.http");
    expectSameResponsesWhenSplit("response_100_continue.http");
}

// ---- Body size cap ----

TEST(HttpParserBodyCap, KeepsOnlyMaxBodyBytesButCountsAll) {
    HttpParser parser(ParserMode::Requests, 4);
    ASSERT_TRUE(feedAll(parser, readFixture("request_post.http")));

    std::vector<HttpRequest> requests = parser.takeRequests();
    ASSERT_EQ(requests.size(), 1U);
    EXPECT_EQ(requests[0].body, "name");
    EXPECT_EQ(requests[0].bodySize, 24);
}

TEST(HttpParserBodyCap, CapWorksAcrossChunks) {
    // The cap (8 bytes) ends in the middle of the second chunk ("Hello, " + "W").
    HttpParser parser(ParserMode::Requests, 8);
    ASSERT_TRUE(feedOneByteAtATime(parser, readFixture("request_post_chunked.http")));

    std::vector<HttpRequest> requests = parser.takeRequests();
    ASSERT_EQ(requests.size(), 1U);
    EXPECT_EQ(requests[0].body, "Hello, W");
    EXPECT_EQ(requests[0].bodySize, 13);
}

TEST(HttpParserBodyCap, ZeroCapKeepsNoBody) {
    HttpParser parser(ParserMode::Responses, 0);
    ASSERT_TRUE(feedAll(parser, readFixture("response_200.http")));

    std::vector<HttpResponse> responses = parser.takeResponses();
    ASSERT_EQ(responses.size(), 1U);
    EXPECT_EQ(responses[0].body, "");
    EXPECT_EQ(responses[0].bodySize, 43);
}

// ---- Malformed input: always an error, never a crash ----

TEST(HttpParserErrors, BadRequestLineIsAnError) {
    HttpParser parser(ParserMode::Requests);
    EXPECT_FALSE(feedAll(parser, readFixture("bad_request_line.http")));
    EXPECT_TRUE(parser.hasError());
    // The message names the llhttp error, e.g. "HPE_INVALID_CONSTANT: Expected HTTP/".
    EXPECT_EQ(parser.errorMessage().rfind("HPE_", 0), 0U) << parser.errorMessage();
    EXPECT_TRUE(parser.takeRequests().empty());
}

TEST(HttpParserErrors, HeaderWithoutColonIsAnError) {
    HttpParser parser(ParserMode::Requests);
    EXPECT_FALSE(feedAll(parser, readFixture("bad_header.http")));
    EXPECT_TRUE(parser.hasError());
}

TEST(HttpParserErrors, BadChunkSizeIsAnError) {
    HttpParser parser(ParserMode::Requests);
    EXPECT_FALSE(feedAll(parser, readFixture("bad_chunk_size.http")));
    EXPECT_NE(parser.errorMessage().find("HPE_INVALID_CHUNK_SIZE"), std::string::npos)
        << parser.errorMessage();
}

TEST(HttpParserErrors, BadStatusLineIsAnError) {
    HttpParser parser(ParserMode::Responses);
    EXPECT_FALSE(feedAll(parser, readFixture("bad_status_line.http")));
    EXPECT_TRUE(parser.hasError());
}

TEST(HttpParserErrors, ConnectionClosedInsideHeadersIsAnError) {
    HttpParser parser(ParserMode::Requests);
    ASSERT_TRUE(feedAll(parser, readFixture("truncated_request.http")));
    EXPECT_FALSE(parser.finish());
    EXPECT_TRUE(parser.hasError());
    EXPECT_TRUE(parser.takeRequests().empty());
}

TEST(HttpParserErrors, ConnectionClosedInsideBodyIsAnError) {
    HttpParser parser(ParserMode::Responses);
    // Content-Length says 100 bytes but only 10 arrive before the close.
    ASSERT_TRUE(feedAll(parser, readFixture("truncated_response.http")));
    EXPECT_FALSE(parser.finish());
    EXPECT_TRUE(parser.hasError());
    EXPECT_TRUE(parser.takeResponses().empty());
}

TEST(HttpParserErrors, ParserStaysFailedAfterAnError) {
    HttpParser parser(ParserMode::Requests);
    EXPECT_FALSE(feedAll(parser, readFixture("bad_header.http")));
    std::string firstMessage = parser.errorMessage();

    // Even valid bytes are refused now: we cannot know where the next message starts.
    EXPECT_FALSE(feedAll(parser, readFixture("request_get.http")));
    EXPECT_FALSE(parser.finish());
    EXPECT_EQ(parser.errorMessage(), firstMessage);
    EXPECT_TRUE(parser.takeRequests().empty());
}

TEST(HttpParserErrors, RandomBytesAreAnErrorNotACrash) {
    std::string garbage;
    for (int i = 0; i < 256; i++) {
        garbage.push_back(static_cast<char>(i));
    }
    HttpParser requests(ParserMode::Requests);
    EXPECT_FALSE(feedAll(requests, garbage));
    HttpParser responses(ParserMode::Responses);
    EXPECT_FALSE(feedAll(responses, garbage));
}
