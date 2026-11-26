#pragma once

#include "dipper/http_transaction.hpp"

#include <asio/io_context.hpp>
#include <asio/ip/tcp.hpp>
#include <atomic>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

/// A tiny HTTP server for the integration tests. It listens on 127.0.0.1 on a free port and
/// answers by path:
///   /hello    200 with a short text body (HEAD works too)
///   /echo     200 with the request body sent back
///   /chunked  200 with a chunked body
///   /big      200 with a 1 MiB body (bigger than the proxy's 16 KiB read size)
///   /close    200 whose body ends when the server closes the connection
///   /slow     never answers, to test the proxy's timeout
///   other     404
/// It serves one connection at a time on a single thread, which keeps it simple. It remembers
/// every request it received so tests can check what the proxy forwarded.
class TestHttpServer {
  public:
    TestHttpServer();
    ~TestHttpServer();
    TestHttpServer(const TestHttpServer&) = delete;
    TestHttpServer& operator=(const TestHttpServer&) = delete;

    bool start();
    int port() const { return port_; }
    void stop();

    std::vector<dipper::HttpRequest> receivedRequests();

    /// The body /big sends: 1 MiB of "abc...xyzabc...", so a lost or repeated piece is visible.
    static std::string bigBody();

  private:
    void run();
    void serveConnection(asio::ip::tcp::socket& socket);
    bool answer(asio::ip::tcp::socket& socket, const dipper::HttpRequest& request);
    void waitUntilClosed(asio::ip::tcp::socket& socket);

    asio::io_context ioContext_;
    asio::ip::tcp::acceptor acceptor_;
    int port_ = 0;
    std::thread thread_;
    std::atomic<bool> stopping_{false};

    std::mutex requestsMutex_;
    std::vector<dipper::HttpRequest> requests_;
};
