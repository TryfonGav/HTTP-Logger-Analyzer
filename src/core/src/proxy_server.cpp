#include "dipper/proxy_server.hpp"

#include "dipper/socket_wait.hpp"

#include <algorithm>
#include <asio/buffer.hpp>
#include <asio/connect.hpp>
#include <asio/error.hpp>
#include <asio/ip/address.hpp>
#include <asio/write.hpp>
#include <chrono>
#include <exception>
#include <spdlog/spdlog.h>
#include <system_error>
#include <utility>

namespace dipper {

using asio::ip::tcp;

namespace {

// Bytes read from a socket at a time. A response is passed on in pieces of this size as soon
// as each piece arrives, so the proxy never holds a whole large response in memory.
constexpr std::size_t kChunkSize = 16 * 1024;

// Longest single wait. Between waits, every thread checks whether stop() was called.
constexpr int kWaitSliceMs = 250;

std::string reasonPhrase(int statusCode) {
    switch (statusCode) {
    case 400:
        return "Bad Request";
    case 413:
        return "Content Too Large";
    case 501:
        return "Not Implemented";
    case 504:
        return "Gateway Timeout";
    default:
        return "Bad Gateway";
    }
}

// The status code the client sees when the proxy cannot reach the server.
int gatewayStatusFor(TransactionError error) {
    if (error == TransactionError::Timeout) {
        return 504;
    }
    return 502;
}

// Sends the proxy's own short error page to the client.
void sendErrorResponse(tcp::socket& client, int statusCode, const std::string& message) {
    std::string response = buildErrorResponse(statusCode, reasonPhrase(statusCode), message);
    asio::error_code ignored; // if the client has already gone, there is nothing more to do
    asio::write(client, asio::buffer(response), ignored);
}

void setError(HttpTransaction& transaction, TransactionError error, const std::string& message) {
    transaction.error = error;
    transaction.errorMessage = message;
}

// A transaction with the details we know as soon as a request has arrived.
HttpTransaction newTransaction(const tcp::endpoint& client) {
    HttpTransaction transaction;
    transaction.clientAddress = client.address().to_string();
    transaction.clientPort = client.port();
    transaction.scheme = "http";
    transaction.captureMode = CaptureMode::Proxy;
    transaction.timings.startTime = std::chrono::system_clock::now(); // more timings in #23
    return transaction;
}

// Stores the first final (status 200 or more) response the parser has finished. Earlier
// 1xx responses such as "100 Continue" were already passed to the client; we do not record them.
bool takeFinalResponse(HttpParser& responseParser, HttpTransaction& transaction) {
    for (HttpResponse& response : responseParser.takeResponses()) {
        if (response.statusCode >= 200) {
            transaction.hasResponse = true;
            transaction.response = std::move(response);
            return true;
        }
    }
    return false;
}

// The server closed its connection. That can be the normal end of a response that has no
// Content-Length, or the server giving up early. Returns false: the client connection must be
// closed too, because the client can only see where such a body ends by the close.
bool finishResponseAtClose(HttpParser& responseParser, bool sentAnything, tcp::socket& client,
                           HttpTransaction& transaction) {
    if (!responseParser.finish()) {
        setError(transaction, TransactionError::ParseError,
                 "the server closed the connection in the middle of the response (" +
                     responseParser.errorMessage() + ")");
        return false;
    }
    if (takeFinalResponse(responseParser, transaction)) {
        return false;
    }
    std::string message = "the server closed the connection without answering";
    if (!sentAnything) {
        sendErrorResponse(client, 502, message);
    }
    setError(transaction, TransactionError::Other, message);
    return false;
}

} // namespace

ProxyServer::ProxyServer(const ProxyConfig& config, TransactionCallback onTransaction)
    : config_(config), onTransaction_(std::move(onTransaction)), acceptor_(ioContext_) {}

ProxyServer::~ProxyServer() {
    stop();
}

bool ProxyServer::start(std::string& error) {
    if (started_) {
        error = "the proxy is already running";
        return false;
    }
    if (config_.port < 0 || config_.port > 65535 || config_.timeoutMs <= 0) {
        error = "invalid proxy settings: the port must be 0-65535 and the timeout above 0 ms";
        return false;
    }
    asio::error_code code;
    asio::ip::address address = asio::ip::make_address(config_.listenAddress, code);
    if (code) {
        error = "invalid listen address \"" + config_.listenAddress + "\"";
        return false;
    }

    // Each step can fail, for example when another program already uses the port.
    tcp::endpoint endpoint(address, static_cast<unsigned short>(config_.port));
    acceptor_.open(endpoint.protocol(), code);
#ifndef _WIN32
    // Lets the proxy restart at once on Linux/macOS instead of waiting about a minute for old
    // connections to clear. Not on Windows, where this option would let two programs share a port.
    if (!code) {
        acceptor_.set_option(asio::socket_base::reuse_address(true), code);
    }
#endif
    if (!code) {
        acceptor_.bind(endpoint, code);
    }
    if (!code) {
        acceptor_.listen(asio::socket_base::max_listen_connections, code);
    }
    if (code) {
        error = "cannot listen on " + config_.listenAddress + ":" + std::to_string(config_.port) +
                ": " + code.message();
        asio::error_code ignored;
        acceptor_.close(ignored);
        return false;
    }

    port_ = acceptor_.local_endpoint(code).port();
    stopping_ = false;
    acceptThread_ = std::thread(&ProxyServer::acceptLoop, this);
    started_ = true;
    spdlog::info("Dipper proxy listening on {}:{}", config_.listenAddress, port_);
    return true;
}

void ProxyServer::stop() {
    if (!started_) {
        return;
    }
    // Every thread notices this within kWaitSliceMs and finishes.
    stopping_ = true;
    acceptThread_.join();
    asio::error_code ignored;
    acceptor_.close(ignored);

    std::unique_lock<std::mutex> lock(connectionsMutex_);
    while (activeConnections_ > 0) {
        connectionsFinished_.wait(lock); // woken by runConnection when a thread ends
    }
    started_ = false;
    spdlog::info("Dipper proxy stopped");
}

void ProxyServer::acceptLoop() {
    while (!stopping_) {
        WaitResult wait = waitForConnection(acceptor_, kWaitSliceMs);
        if (wait == WaitResult::Failed) {
            spdlog::error("the proxy's listening socket failed; no new connections accepted");
            return;
        }
        if (wait == WaitResult::NotYet) {
            continue; // nobody connected yet: check stopping_ and wait again
        }

        std::unique_ptr<tcp::socket> client = std::make_unique<tcp::socket>(ioContext_);
        asio::error_code error;
        acceptor_.accept(*client, error);
        if (error) {
            spdlog::warn("could not accept a connection: {}", error.message());
            continue;
        }

        // Count the connection before its thread starts, so stop() cannot miss it.
        {
            std::lock_guard<std::mutex> lock(connectionsMutex_);
            activeConnections_++;
        }
        // One thread per connection. detach() lets it run on its own; stop() still waits for
        // it through activeConnections_.
        try {
            std::thread worker(&ProxyServer::runConnection, this, std::move(client));
            worker.detach();
        } catch (const std::system_error& exception) {
            // The system could not create another thread (far too many connections).
            spdlog::error("could not start a thread for a new connection: {}", exception.what());
            std::lock_guard<std::mutex> lock(connectionsMutex_);
            activeConnections_--;
        }
    }
}

void ProxyServer::runConnection(std::unique_ptr<tcp::socket> client) {
    // An exception that leaves a thread ends the whole program, so catch everything here.
    try {
        handleClient(*client);
    } catch (const std::exception& exception) {
        spdlog::error("a proxy connection failed: {}", exception.what());
    }

    // Close and destroy the socket now. It belongs to ioContext_, which stop() may destroy as
    // soon as we report that this thread is finished. This is why the socket is kept in a
    // unique_ptr: we can destroy it at exactly this point.
    asio::error_code ignored;
    client->shutdown(tcp::socket::shutdown_both, ignored);
    client->close(ignored);
    client.reset();

    // Tell stop() this thread is done. We notify while still holding the lock, so stop() cannot
    // continue (and destroy this object) until we have finished touching it.
    std::lock_guard<std::mutex> lock(connectionsMutex_);
    activeConnections_--;
    connectionsFinished_.notify_all();
}

void ProxyServer::handleClient(tcp::socket& client) {
    asio::error_code error;
    tcp::endpoint clientEndpoint = client.remote_endpoint(error);
    HttpParser requestParser(ParserMode::Requests, config_.maxBodyBytes);
    std::vector<char> buffer(kChunkSize);

    // Keep-alive: one client connection can carry many requests, one after another.
    while (!stopping_) {
        for (const HttpRequest& request : requestParser.takeRequests()) {
            HttpTransaction transaction = newTransaction(clientEndpoint);
            transaction.request = request;
            if (!handleRequest(client, request, transaction)) {
                return; // this connection must be closed
            }
        }

        // The client closing, staying silent longer than the timeout, or stop() all end here.
        std::size_t count = readSome(client, buffer, error);
        if (error) {
            return;
        }
        if (!requestParser.feed(buffer.data(), count)) {
            HttpTransaction transaction = newTransaction(clientEndpoint);
            failRequest(client, transaction, 400, TransactionError::ParseError,
                        "the request is not valid HTTP (" + requestParser.errorMessage() + ")");
            return;
        }
    }
}

bool ProxyServer::handleRequest(tcp::socket& client, const HttpRequest& request,
                                HttpTransaction& transaction) {
    if (isTunnelRequest(request)) {
        failRequest(client, transaction, 501, TransactionError::Other,
                    "CONNECT and protocol upgrades are not supported yet");
        return false;
    }
    // The parser stops keeping body bytes after maxBodyBytes, so we cannot forward the rest.
    if (request.bodySize > static_cast<std::int64_t>(request.body.size())) {
        failRequest(client, transaction, 413, TransactionError::Other,
                    "the request body is larger than " + std::to_string(config_.maxBodyBytes) +
                        " bytes");
        return false;
    }
    ProxyTarget target;
    std::string targetError;
    if (!parseProxyTarget(request.url, target, targetError)) {
        failRequest(client, transaction, 400, TransactionError::Other, targetError);
        return false;
    }
    transaction.serverHost = target.host;
    transaction.serverPort = target.port;

    tcp::socket server(ioContext_);
    if (!connectToServer(server, target, transaction)) {
        failRequest(client, transaction, gatewayStatusFor(transaction.error), transaction.error,
                    transaction.errorMessage);
        return false;
    }
    asio::error_code writeError;
    asio::write(server, asio::buffer(buildUpstreamRequest(request, target)), writeError);
    if (writeError) {
        failRequest(client, transaction, 502, TransactionError::Other,
                    "could not send the request to the server: " + writeError.message());
        return false;
    }

    bool keepOpen = relayResponse(server, client, request, transaction);
    reportTransaction(transaction);
    return keepOpen && !wantsConnectionClose(request.version, request.headers);
}

bool ProxyServer::connectToServer(tcp::socket& server, const ProxyTarget& target,
                                  HttpTransaction& transaction) {
    // DNS: turn the host name into one or more IP addresses.
    asio::error_code error;
    tcp::resolver resolver(ioContext_);
    tcp::resolver::results_type addresses =
        resolver.resolve(target.host, std::to_string(target.port), error);
    if (error) {
        setError(transaction, TransactionError::DnsFailed,
                 "could not find the server \"" + target.host + "\": " + error.message());
        return false;
    }

    // Try each address until one accepts. The operating system decides how long to wait.
    asio::connect(server, addresses, error);
    if (!error) {
        return true;
    }
    TransactionError kind = TransactionError::Other;
    if (error == asio::error::connection_refused) {
        kind = TransactionError::ConnectionRefused;
    } else if (error == asio::error::timed_out) {
        kind = TransactionError::Timeout;
    }
    setError(transaction, kind,
             "could not connect to " + target.host + ":" + std::to_string(target.port) + ": " +
                 error.message());
    return false;
}

bool ProxyServer::relayResponse(tcp::socket& server, tcp::socket& client,
                                const HttpRequest& request, HttpTransaction& transaction) {
    HttpParser responseParser(ParserMode::Responses, config_.maxBodyBytes);
    if (request.method == "HEAD") {
        responseParser.setNextResponseIsForHead();
    }
    std::vector<char> buffer(kChunkSize);
    bool sentAnything = false;

    while (true) {
        asio::error_code error;
        std::size_t count = readSome(server, buffer, error);
        if (error == asio::error::eof) {
            return finishResponseAtClose(responseParser, sentAnything, client, transaction);
        }
        if (error) {
            TransactionError kind = TransactionError::Other;
            std::string message = "reading the response failed: " + error.message();
            if (error == asio::error::timed_out) {
                kind = TransactionError::Timeout;
                message =
                    "the server did not answer within " + std::to_string(config_.timeoutMs) + " ms";
            }
            // Once part of the response has gone to the client we cannot send an error page.
            if (!sentAnything) {
                sendErrorResponse(client, gatewayStatusFor(kind), message);
            }
            setError(transaction, kind, message);
            return false;
        }

        // Pass the bytes on unchanged straight away, then let the parser look at them.
        asio::write(client, asio::buffer(buffer.data(), count), error);
        if (error) {
            setError(transaction, TransactionError::Other,
                     "the client closed the connection during the response");
            return false;
        }
        sentAnything = true;
        if (!responseParser.feed(buffer.data(), count)) {
            setError(transaction, TransactionError::ParseError,
                     "the server's response is not valid HTTP (" + responseParser.errorMessage() +
                         ")");
            return false;
        }
        if (takeFinalResponse(responseParser, transaction)) {
            return !wantsConnectionClose(transaction.response.version,
                                         transaction.response.headers);
        }
    }
}

std::size_t ProxyServer::readSome(tcp::socket& socket, std::vector<char>& buffer,
                                  asio::error_code& error) {
    // Wait in short slices so that stop() is noticed quickly, up to timeoutMs in total.
    int waitedMs = 0;
    while (waitedMs < config_.timeoutMs) {
        if (stopping_) {
            error = asio::error::operation_aborted;
            return 0;
        }
        int sliceMs = std::min(kWaitSliceMs, config_.timeoutMs - waitedMs);
        WaitResult wait = waitForData(socket, sliceMs);
        if (wait == WaitResult::Ready) {
            return socket.read_some(asio::buffer(buffer), error);
        }
        if (wait == WaitResult::Failed) {
            error = asio::error::bad_descriptor;
            return 0;
        }
        waitedMs += sliceMs;
    }
    error = asio::error::timed_out;
    return 0;
}

void ProxyServer::failRequest(tcp::socket& client, HttpTransaction& transaction, int statusCode,
                              TransactionError error, const std::string& message) {
    sendErrorResponse(client, statusCode, message);
    setError(transaction, error, message);
    reportTransaction(transaction);
}

void ProxyServer::reportTransaction(const HttpTransaction& transaction) {
    std::lock_guard<std::mutex> lock(callbackMutex_);
    const HttpRequest& request = transaction.request;
    if (transaction.error == TransactionError::None) {
        spdlog::info("{} {} -> {} ({} bytes)", request.method, request.url,
                     transaction.response.statusCode, transaction.response.bodySize);
    } else {
        spdlog::warn("{} {} -> failed: {}", request.method, request.url, transaction.errorMessage);
    }
    if (onTransaction_) {
        onTransaction_(transaction);
    }
}

} // namespace dipper
