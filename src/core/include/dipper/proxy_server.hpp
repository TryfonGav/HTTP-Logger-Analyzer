#pragma once

#include "dipper/http_parser.hpp"
#include "dipper/http_transaction.hpp"
#include "dipper/proxy_request.hpp"

#include <asio/error_code.hpp>
#include <asio/io_context.hpp>
#include <asio/ip/tcp.hpp>
#include <atomic>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace dipper {

/// Settings for the proxy.
struct ProxyConfig {
    std::string listenAddress = "127.0.0.1"; // only this computer can use the proxy
    int port = 8080;                         // 0 = let the operating system pick a free port
    int timeoutMs = 30000;                   // longest wait for the client or server to send data
    std::int64_t maxBodyBytes = kDefaultMaxBodyBytes; // body bytes kept per message
};

/// Called once for every finished transaction (successful or failed). Calls never overlap,
/// but they come from the proxy's connection threads, not from the thread that started it.
using TransactionCallback = std::function<void(const HttpTransaction&)>;

/// A forward HTTP proxy. Browsers or tools send their requests to it; it forwards each one to
/// the real server, sends the answer back, and reports a HttpTransaction for every exchange.
///
/// Design (see docs/architecture/ARCHITECTURE.md, section 6): blocking Asio calls, one
/// accept thread, and one std::thread per client connection. Call start() and stop() from the
/// same thread.
class ProxyServer {
  public:
    ProxyServer(const ProxyConfig& config, TransactionCallback onTransaction);
    ~ProxyServer(); // calls stop()

    // The proxy owns sockets and threads, which cannot be copied.
    ProxyServer(const ProxyServer&) = delete;
    ProxyServer& operator=(const ProxyServer&) = delete;

    /// Opens the listening socket and starts accepting connections in the background.
    /// Returns false and sets `error` if the address or port cannot be used.
    bool start(std::string& error);

    /// The port the proxy listens on (useful when the config asked for port 0).
    int port() const { return port_; }

    /// Stops accepting connections and waits until every connection thread has finished.
    void stop();

  private:
    void acceptLoop();
    void runConnection(std::unique_ptr<asio::ip::tcp::socket> client);
    void handleClient(asio::ip::tcp::socket& client);
    bool handleRequest(asio::ip::tcp::socket& client, const HttpRequest& request,
                       HttpTransaction& transaction);
    bool connectToServer(asio::ip::tcp::socket& server, const ProxyTarget& target,
                         HttpTransaction& transaction);
    bool relayResponse(asio::ip::tcp::socket& server, asio::ip::tcp::socket& client,
                       const HttpRequest& request, HttpTransaction& transaction);
    std::size_t readSome(asio::ip::tcp::socket& socket, std::vector<char>& buffer,
                         asio::error_code& error);
    void failRequest(asio::ip::tcp::socket& client, HttpTransaction& transaction, int statusCode,
                     TransactionError error, const std::string& message);
    void reportTransaction(const HttpTransaction& transaction);

    ProxyConfig config_;
    TransactionCallback onTransaction_;
    asio::io_context ioContext_;
    asio::ip::tcp::acceptor acceptor_;
    int port_ = 0;
    bool started_ = false;
    std::thread acceptThread_;

    // Set by stop(). Every thread checks it between short waits and finishes when it is true.
    // std::atomic makes it safe to read from many threads while one thread writes it.
    std::atomic<bool> stopping_{false};

    // Counts the running connection threads so stop() can wait for all of them.
    std::mutex connectionsMutex_;
    std::condition_variable connectionsFinished_;
    int activeConnections_ = 0;

    // Makes sure only one thread at a time calls onTransaction_.
    std::mutex callbackMutex_;
};

} // namespace dipper
