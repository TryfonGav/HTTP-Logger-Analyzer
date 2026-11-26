// End-to-end tests: a test client talks to the real ProxyServer, which talks to a local
// TestHttpServer. Everything runs on 127.0.0.1, so no internet connection is needed.

#include "dipper/http_parser.hpp"
#include "dipper/proxy_server.hpp"
#include "dipper/socket_wait.hpp"
#include "test_server.hpp"

#include <asio/buffer.hpp>
#include <asio/connect.hpp>
#include <asio/error.hpp>
#include <asio/ip/address.hpp>
#include <asio/write.hpp>
#include <chrono>
#include <condition_variable>
#include <gtest/gtest.h>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

using asio::ip::tcp;
using dipper::HttpResponse;
using dipper::HttpTransaction;
using dipper::ProxyConfig;
using dipper::ProxyServer;
using dipper::TransactionError;
using dipper::WaitResult;

namespace {

// Longest time a test waits for anything before it counts as a failure (instead of hanging).
constexpr int kTestWaitMs = 10000;

// A client like a browser that uses the proxy: connect, send raw bytes, read responses.
class TestClient {
  public:
    explicit TestClient(int proxyPort) : socket_(ioContext_) {
        asio::error_code error;
        socket_.connect(tcp::endpoint(asio::ip::make_address("127.0.0.1"),
                                      static_cast<unsigned short>(proxyPort)),
                        error);
        connected_ = !error;
    }

    bool send(const std::string& bytes) {
        asio::error_code error;
        asio::write(socket_, asio::buffer(bytes), error);
        return connected_ && !error;
    }

    // The next response answers a HEAD request, so it has no body.
    void expectHeadResponse() { parser_.setNextResponseIsForHead(); }

    // Reads until one whole response has arrived. False if none arrives in time.
    bool readResponse(HttpResponse& response) {
        std::vector<char> buffer(16 * 1024);
        while (waiting_.empty()) {
            if (dipper::waitForData(socket_, kTestWaitMs) != WaitResult::Ready) {
                return false;
            }
            asio::error_code error;
            std::size_t count = socket_.read_some(asio::buffer(buffer), error);
            if (error == asio::error::eof) {
                parser_.finish(); // the body may end with the close
                collectResponses();
                break;
            }
            if (error || !parser_.feed(buffer.data(), count)) {
                return false;
            }
            collectResponses();
        }
        if (waiting_.empty()) {
            return false;
        }
        response = waiting_.front();
        waiting_.erase(waiting_.begin());
        return true;
    }

    // True if the proxy closes the connection (within the test wait time).
    bool isClosedByProxy() {
        if (dipper::waitForData(socket_, kTestWaitMs) != WaitResult::Ready) {
            return false;
        }
        std::vector<char> buffer(1024);
        asio::error_code error;
        socket_.read_some(asio::buffer(buffer), error);
        return static_cast<bool>(error);
    }

  private:
    void collectResponses() {
        for (const HttpResponse& response : parser_.takeResponses()) {
            waiting_.push_back(response);
        }
    }

    asio::io_context ioContext_;
    tcp::socket socket_;
    bool connected_ = false;
    dipper::HttpParser parser_{dipper::ParserMode::Responses};
    std::vector<HttpResponse> waiting_;
};

// Collects the transactions the proxy reports. The proxy reports a transaction just after it
// has sent the response, so a test may have to wait a moment for it.
class TransactionCollector {
  public:
    void add(const HttpTransaction& transaction) {
        std::lock_guard<std::mutex> lock(mutex_);
        transactions_.push_back(transaction);
        changed_.notify_all();
    }

    // Waits until at least `count` transactions have arrived (or the wait time runs out).
    std::vector<HttpTransaction> waitFor(std::size_t count) {
        std::unique_lock<std::mutex> lock(mutex_);
        std::chrono::steady_clock::time_point deadline =
            std::chrono::steady_clock::now() + std::chrono::milliseconds(kTestWaitMs);
        while (transactions_.size() < count) {
            if (changed_.wait_until(lock, deadline) == std::cv_status::timeout) {
                break;
            }
        }
        return transactions_;
    }

  private:
    std::mutex mutex_;
    std::condition_variable changed_;
    std::vector<HttpTransaction> transactions_;
};

// A port nothing is listening on: open a listening socket, note its port, close it again.
int findClosedPort() {
    asio::io_context ioContext;
    tcp::acceptor acceptor(ioContext, tcp::endpoint(asio::ip::make_address("127.0.0.1"), 0));
    return acceptor.local_endpoint().port();
}

// Sends GET /hello through the proxy and stores the status code (used by several threads).
void fetchHello(int proxyPort, int serverPort, int* statusCode) {
    TestClient client(proxyPort);
    std::string url = "http://127.0.0.1:" + std::to_string(serverPort) + "/hello";
    HttpResponse response;
    if (client.send("GET " + url + " HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n") &&
        client.readResponse(response)) {
        *statusCode = response.statusCode;
    }
}

class ProxyTest : public ::testing::Test {
  protected:
    void SetUp() override { ASSERT_TRUE(server.start()); }
    void TearDown() override { server.stop(); }

    // Settings for a proxy on a free port with a short timeout, so failing tests end quickly.
    static ProxyConfig testConfig() {
        ProxyConfig config;
        config.port = 0;
        config.timeoutMs = 5000;
        return config;
    }

    dipper::TransactionCallback collect() {
        TransactionCollector* collector = &collected;
        return [collector](const HttpTransaction& transaction) { collector->add(transaction); };
    }

    // The absolute URL a proxy client sends, e.g. "http://127.0.0.1:50123/hello".
    std::string urlFor(const std::string& path) const {
        return "http://127.0.0.1:" + std::to_string(server.port()) + path;
    }

    std::string getRequest(const std::string& path) const {
        return "GET " + urlFor(path) + " HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n";
    }

    TestHttpServer server;
    TransactionCollector collected;
};

} // namespace

// ---- Successful requests ----

TEST_F(ProxyTest, ForwardsGetAndReportsTheTransaction) {
    ProxyServer proxy(testConfig(), collect());
    std::string error;
    ASSERT_TRUE(proxy.start(error)) << error;

    TestClient client(proxy.port());
    ASSERT_TRUE(
        client.send("GET " + urlFor("/hello") +
                    " HTTP/1.1\r\nHost: 127.0.0.1\r\nProxy-Connection: keep-alive\r\n\r\n"));
    HttpResponse response;
    ASSERT_TRUE(client.readResponse(response));
    EXPECT_EQ(response.statusCode, 200);
    EXPECT_EQ(response.body, "Hello from the test server");

    std::vector<HttpTransaction> transactions = collected.waitFor(1);
    ASSERT_EQ(transactions.size(), 1U);
    const HttpTransaction& transaction = transactions[0];
    EXPECT_EQ(transaction.error, TransactionError::None);
    EXPECT_EQ(dipper::findProblem(transaction), "");
    EXPECT_EQ(transaction.request.method, "GET");
    EXPECT_EQ(transaction.request.url, urlFor("/hello"));
    EXPECT_TRUE(transaction.hasResponse);
    EXPECT_EQ(transaction.response.statusCode, 200);
    EXPECT_EQ(transaction.response.body, "Hello from the test server");
    EXPECT_EQ(transaction.serverHost, "127.0.0.1");
    EXPECT_EQ(transaction.serverPort, server.port());
    EXPECT_EQ(transaction.clientAddress, "127.0.0.1");
    EXPECT_EQ(transaction.scheme, "http");

    // The server got the path only, without the header meant for the proxy.
    std::vector<dipper::HttpRequest> received = server.receivedRequests();
    ASSERT_EQ(received.size(), 1U);
    EXPECT_EQ(received[0].url, "/hello");
    EXPECT_FALSE(dipper::findHeader(received[0].headers, "Proxy-Connection").has_value());
}

TEST_F(ProxyTest, ForwardsRequestBody) {
    ProxyServer proxy(testConfig(), collect());
    std::string error;
    ASSERT_TRUE(proxy.start(error)) << error;

    TestClient client(proxy.port());
    ASSERT_TRUE(client.send("POST " + urlFor("/echo") +
                            " HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 11\r\n\r\n"
                            "hello=world"));
    HttpResponse response;
    ASSERT_TRUE(client.readResponse(response));
    EXPECT_EQ(response.body, "hello=world");
    EXPECT_EQ(collected.waitFor(1)[0].request.body, "hello=world");
}

TEST_F(ProxyTest, PassesChunkedResponseThrough) {
    ProxyServer proxy(testConfig(), collect());
    std::string error;
    ASSERT_TRUE(proxy.start(error)) << error;

    TestClient client(proxy.port());
    ASSERT_TRUE(client.send(getRequest("/chunked")));
    HttpResponse response;
    ASSERT_TRUE(client.readResponse(response));
    EXPECT_EQ(response.body, "Hello chunked");
    EXPECT_EQ(collected.waitFor(1)[0].response.body, "Hello chunked");
}

TEST_F(ProxyTest, StreamsLargeResponseIntact) {
    ProxyServer proxy(testConfig(), collect());
    std::string error;
    ASSERT_TRUE(proxy.start(error)) << error;

    TestClient client(proxy.port());
    ASSERT_TRUE(client.send(getRequest("/big")));
    HttpResponse response;
    ASSERT_TRUE(client.readResponse(response));
    EXPECT_TRUE(response.body == TestHttpServer::bigBody()); // EXPECT_EQ would print 1 MiB
    EXPECT_EQ(collected.waitFor(1)[0].response.bodySize, 1024 * 1024);
}

TEST_F(ProxyTest, HeadResponseHasNoBodyAndConnectionStaysUsable) {
    ProxyServer proxy(testConfig(), collect());
    std::string error;
    ASSERT_TRUE(proxy.start(error)) << error;

    TestClient client(proxy.port());
    ASSERT_TRUE(client.send("HEAD " + urlFor("/hello") + " HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"));
    client.expectHeadResponse();
    HttpResponse head;
    ASSERT_TRUE(client.readResponse(head));
    EXPECT_EQ(head.statusCode, 200);
    EXPECT_EQ(head.bodySize, 0);

    // If the proxy had waited for a body after HEAD, this second request would time out.
    ASSERT_TRUE(client.send(getRequest("/hello")));
    HttpResponse get;
    ASSERT_TRUE(client.readResponse(get));
    EXPECT_EQ(get.body, "Hello from the test server");
}

TEST_F(ProxyTest, KeepAliveServesSeveralRequestsOnOneConnection) {
    ProxyServer proxy(testConfig(), collect());
    std::string error;
    ASSERT_TRUE(proxy.start(error)) << error;

    TestClient client(proxy.port());
    for (int i = 0; i < 3; i++) {
        ASSERT_TRUE(client.send(getRequest("/hello")));
        HttpResponse response;
        ASSERT_TRUE(client.readResponse(response)) << "request " << i;
        EXPECT_EQ(response.statusCode, 200);
    }
    EXPECT_EQ(collected.waitFor(3).size(), 3U);
}

TEST_F(ProxyTest, AnswersPipelinedRequestsInOrder) {
    ProxyServer proxy(testConfig(), collect());
    std::string error;
    ASSERT_TRUE(proxy.start(error)) << error;

    // Both requests in one write, before any answer.
    TestClient client(proxy.port());
    ASSERT_TRUE(client.send(getRequest("/hello") + getRequest("/chunked")));
    HttpResponse first;
    HttpResponse second;
    ASSERT_TRUE(client.readResponse(first));
    ASSERT_TRUE(client.readResponse(second));
    EXPECT_EQ(first.body, "Hello from the test server");
    EXPECT_EQ(second.body, "Hello chunked");
}

TEST_F(ProxyTest, BodyEndingAtCloseClosesClientConnection) {
    ProxyServer proxy(testConfig(), collect());
    std::string error;
    ASSERT_TRUE(proxy.start(error)) << error;

    TestClient client(proxy.port());
    ASSERT_TRUE(client.send(getRequest("/close")));
    HttpResponse response;
    ASSERT_TRUE(client.readResponse(response));
    EXPECT_EQ(response.body, "This body ends at the close.");
    EXPECT_EQ(collected.waitFor(1)[0].response.body, "This body ends at the close.");
}

TEST_F(ProxyTest, HandlesConcurrentClients) {
    ProxyServer proxy(testConfig(), collect());
    std::string error;
    ASSERT_TRUE(proxy.start(error)) << error;

    const int clientCount = 8;
    std::vector<int> statusCodes(clientCount, 0);
    std::vector<std::thread> clients;
    clients.reserve(clientCount);
    for (int i = 0; i < clientCount; i++) {
        clients.emplace_back(fetchHello, proxy.port(), server.port(), &statusCodes[i]);
    }
    for (std::thread& client : clients) {
        client.join();
    }
    for (int i = 0; i < clientCount; i++) {
        EXPECT_EQ(statusCodes[i], 200) << "client " << i;
    }
    EXPECT_EQ(collected.waitFor(clientCount).size(), 8U);
}

// ---- Failures: reported as transactions with an error, never a crash ----

TEST_F(ProxyTest, UnknownHostGives502AndDnsFailed) {
    ProxyServer proxy(testConfig(), collect());
    std::string error;
    ASSERT_TRUE(proxy.start(error)) << error;

    // ".invalid" is reserved: it can never resolve (RFC 2606).
    TestClient client(proxy.port());
    ASSERT_TRUE(
        client.send("GET http://nothing.invalid/ HTTP/1.1\r\nHost: nothing.invalid\r\n\r\n"));
    HttpResponse response;
    ASSERT_TRUE(client.readResponse(response));
    EXPECT_EQ(response.statusCode, 502);

    HttpTransaction transaction = collected.waitFor(1)[0];
    EXPECT_EQ(transaction.error, TransactionError::DnsFailed);
    EXPECT_FALSE(transaction.hasResponse);
    EXPECT_EQ(dipper::findProblem(transaction), "");
}

TEST_F(ProxyTest, RefusedConnectionGives502) {
    ProxyServer proxy(testConfig(), collect());
    std::string error;
    ASSERT_TRUE(proxy.start(error)) << error;

    std::string url = "http://127.0.0.1:" + std::to_string(findClosedPort()) + "/";
    TestClient client(proxy.port());
    ASSERT_TRUE(client.send("GET " + url + " HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"));
    HttpResponse response;
    ASSERT_TRUE(client.readResponse(response));
    EXPECT_EQ(response.statusCode, 502);
    EXPECT_EQ(collected.waitFor(1)[0].error, TransactionError::ConnectionRefused);
}

TEST_F(ProxyTest, SilentServerGives504AfterTimeout) {
    ProxyConfig config = testConfig();
    config.timeoutMs = 300;
    ProxyServer proxy(config, collect());
    std::string error;
    ASSERT_TRUE(proxy.start(error)) << error;

    TestClient client(proxy.port());
    ASSERT_TRUE(client.send(getRequest("/slow")));
    HttpResponse response;
    ASSERT_TRUE(client.readResponse(response));
    EXPECT_EQ(response.statusCode, 504);
    EXPECT_EQ(collected.waitFor(1)[0].error, TransactionError::Timeout);
}

TEST_F(ProxyTest, ConnectGives501) {
    ProxyServer proxy(testConfig(), collect());
    std::string error;
    ASSERT_TRUE(proxy.start(error)) << error;

    TestClient client(proxy.port());
    ASSERT_TRUE(client.send("CONNECT example.com:443 HTTP/1.1\r\nHost: example.com:443\r\n\r\n"));
    HttpResponse response;
    ASSERT_TRUE(client.readResponse(response));
    EXPECT_EQ(response.statusCode, 501);
    EXPECT_EQ(collected.waitFor(1)[0].request.method, "CONNECT");
}

TEST_F(ProxyTest, MalformedRequestGives400) {
    ProxyServer proxy(testConfig(), collect());
    std::string error;
    ASSERT_TRUE(proxy.start(error)) << error;

    TestClient client(proxy.port());
    ASSERT_TRUE(client.send("GET / HTTX/1.1\r\n\r\n"));
    HttpResponse response;
    ASSERT_TRUE(client.readResponse(response));
    EXPECT_EQ(response.statusCode, 400);
    EXPECT_EQ(collected.waitFor(1)[0].error, TransactionError::ParseError);
    EXPECT_TRUE(client.isClosedByProxy());
}

TEST_F(ProxyTest, RequestWithoutFullUrlGives400) {
    ProxyServer proxy(testConfig(), collect());
    std::string error;
    ASSERT_TRUE(proxy.start(error)) << error;

    // A client talking to the proxy as if it were the web server itself.
    TestClient client(proxy.port());
    ASSERT_TRUE(client.send("GET /hello HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"));
    HttpResponse response;
    ASSERT_TRUE(client.readResponse(response));
    EXPECT_EQ(response.statusCode, 400);
    EXPECT_TRUE(server.receivedRequests().empty());
}

// ---- Start and stop ----

TEST_F(ProxyTest, StopEndsIdleConnectionsQuickly) {
    ProxyServer proxy(testConfig(), collect());
    std::string error;
    ASSERT_TRUE(proxy.start(error)) << error;

    // A connected client that never sends anything keeps its connection thread waiting.
    TestClient idleClient(proxy.port());
    std::this_thread::sleep_for(std::chrono::milliseconds(100));

    std::chrono::steady_clock::time_point before = std::chrono::steady_clock::now();
    proxy.stop();
    std::chrono::steady_clock::duration took = std::chrono::steady_clock::now() - before;
    EXPECT_LT(took, std::chrono::seconds(2));
    EXPECT_TRUE(idleClient.isClosedByProxy());
}

TEST_F(ProxyTest, StartFailsWhenPortIsTaken) {
    ProxyServer first(testConfig(), collect());
    std::string error;
    ASSERT_TRUE(first.start(error)) << error;

    ProxyConfig config = testConfig();
    config.port = first.port();
    ProxyServer second(config, collect());
    EXPECT_FALSE(second.start(error));
    EXPECT_NE(error.find("cannot listen"), std::string::npos) << error;
}
