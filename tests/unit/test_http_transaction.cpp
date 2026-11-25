#include "dipper/http_transaction.hpp"

#include <gtest/gtest.h>

using dipper::findHeader;
using dipper::findProblem;
using dipper::Headers;
using dipper::HttpTransaction;
using dipper::kNotMeasured;
using dipper::TransactionError;

// Builds a normal, successful GET transaction that the tests can then break on purpose.
static HttpTransaction makeOkTransaction() {
    HttpTransaction t;
    t.clientAddress = "127.0.0.1";
    t.clientPort = 50000;
    t.serverHost = "example.com";
    t.serverPort = 80;
    t.scheme = "http";
    t.request.method = "GET";
    t.request.url = "http://example.com/";
    t.request.version = "HTTP/1.1";
    t.request.headers.push_back({"Host", "example.com"});
    t.hasResponse = true;
    t.response.statusCode = 200;
    t.response.reason = "OK";
    t.response.version = "HTTP/1.1";
    t.response.body = "hello";
    t.response.bodySize = 5;
    t.timings.ttfbMs = 12.5;
    t.timings.totalMs = 20.0;
    return t;
}

// --- Construction defaults ---

TEST(HttpTransaction, DefaultHasNoResponseAndNoError) {
    const HttpTransaction t;
    EXPECT_EQ(t.id, 0);
    EXPECT_FALSE(t.hasResponse);
    EXPECT_EQ(t.response.statusCode, 0);
    EXPECT_EQ(t.error, TransactionError::None);
    EXPECT_TRUE(t.errorMessage.empty());
    EXPECT_EQ(t.captureMode, dipper::CaptureMode::Proxy);
}

TEST(HttpTransaction, DefaultTimingsAreNotMeasured) {
    const HttpTransaction t;
    EXPECT_EQ(t.timings.dnsMs, kNotMeasured);
    EXPECT_EQ(t.timings.connectMs, kNotMeasured);
    EXPECT_EQ(t.timings.tlsMs, kNotMeasured);
    EXPECT_EQ(t.timings.ttfbMs, kNotMeasured);
    EXPECT_EQ(t.timings.totalMs, kNotMeasured);
}

// --- Header lookup ---

TEST(Headers, EqualsIgnoreCase) {
    EXPECT_TRUE(dipper::equalsIgnoreCase("Content-Type", "content-type"));
    EXPECT_TRUE(dipper::equalsIgnoreCase("", ""));
    EXPECT_FALSE(dipper::equalsIgnoreCase("Host", "Hosts"));
    EXPECT_FALSE(dipper::equalsIgnoreCase("Host", "Post"));
}

TEST(Headers, FindHeaderIgnoresCase) {
    const Headers headers = {{"Content-Type", "text/html"}};
    EXPECT_EQ(findHeader(headers, "content-type"), "text/html");
    EXPECT_EQ(findHeader(headers, "CONTENT-TYPE"), "text/html");
}

TEST(Headers, FindHeaderReturnsFirstOfRepeatedHeaders) {
    const Headers headers = {{"Set-Cookie", "a=1"}, {"Set-Cookie", "b=2"}};
    EXPECT_EQ(findHeader(headers, "Set-Cookie"), "a=1");
    EXPECT_EQ(headers.size(), 2U); // both are kept, nothing is merged
}

TEST(Headers, FindHeaderMissingReturnsNoValue) {
    const Headers headers = {{"Host", "example.com"}};
    EXPECT_FALSE(findHeader(headers, "Content-Length").has_value());
    EXPECT_FALSE(findHeader(Headers{}, "Host").has_value());
}

// --- Invariants checked by findProblem ---

TEST(FindProblem, AcceptsNormalTransaction) {
    EXPECT_EQ(findProblem(makeOkTransaction()), "");
}

TEST(FindProblem, AcceptsFailedTransactionWithoutResponse) {
    HttpTransaction t = makeOkTransaction();
    t.hasResponse = false;
    t.response = {};
    t.error = TransactionError::DnsFailed;
    t.errorMessage = "could not resolve example.com";
    t.timings.ttfbMs = kNotMeasured;
    EXPECT_EQ(findProblem(t), "");
}

TEST(FindProblem, RejectsErrorTogetherWithResponse) {
    HttpTransaction t = makeOkTransaction();
    t.error = TransactionError::Timeout;
    EXPECT_NE(findProblem(t), "");
}

TEST(FindProblem, RejectsNoResponseAndNoError) {
    const HttpTransaction t; // default: no response, no error
    EXPECT_NE(findProblem(t), "");
}

TEST(FindProblem, RejectsStatusCodeOutOfRange) {
    HttpTransaction t = makeOkTransaction();
    t.response.statusCode = 99;
    EXPECT_NE(findProblem(t), "");
    t.response.statusCode = 600;
    EXPECT_NE(findProblem(t), "");
    t.response.statusCode = 100;
    EXPECT_EQ(findProblem(t), "");
    t.response.statusCode = 599;
    EXPECT_EQ(findProblem(t), "");
}

TEST(FindProblem, RejectsNegativeBodySize) {
    HttpTransaction t = makeOkTransaction();
    t.request.bodySize = -1;
    EXPECT_NE(findProblem(t), "");
}

TEST(FindProblem, RejectsTtfbLongerThanTotal) {
    HttpTransaction t = makeOkTransaction();
    t.timings.ttfbMs = 30.0;
    t.timings.totalMs = 20.0;
    EXPECT_NE(findProblem(t), "");
}

TEST(FindProblem, RejectsNegativeTiming) {
    HttpTransaction t = makeOkTransaction();
    t.timings.dnsMs = -5.0;
    EXPECT_NE(findProblem(t), "");
}
