#include "test_server.hpp"

#include "dipper/http_parser.hpp"
#include "dipper/socket_wait.hpp"

#include <asio/buffer.hpp>
#include <asio/ip/address.hpp>
#include <asio/write.hpp>
#include <cstddef>

using asio::ip::tcp;
using dipper::HttpRequest;
using dipper::WaitResult;

namespace {

// Short waits, so stop() is noticed quickly.
constexpr int kWaitSliceMs = 50;

std::string makeResponse(const std::string& body, bool isHead) {
    std::string text = "HTTP/1.1 200 OK\r\n";
    text += "Content-Type: text/plain\r\n";
    text += "Content-Length: " + std::to_string(body.size()) + "\r\n";
    text += "\r\n";
    if (!isHead) {
        text += body;
    }
    return text;
}

} // namespace

TestHttpServer::TestHttpServer() : acceptor_(ioContext_) {}

TestHttpServer::~TestHttpServer() {
    stop();
}

bool TestHttpServer::start() {
    asio::error_code error;
    tcp::endpoint endpoint(asio::ip::make_address("127.0.0.1"), 0); // port 0 = any free port
    acceptor_.open(endpoint.protocol(), error);
    if (!error) {
        acceptor_.bind(endpoint, error);
    }
    if (!error) {
        acceptor_.listen(asio::socket_base::max_listen_connections, error);
    }
    if (error) {
        return false;
    }
    port_ = acceptor_.local_endpoint().port();
    thread_ = std::thread(&TestHttpServer::run, this);
    return true;
}

void TestHttpServer::stop() {
    stopping_ = true;
    if (thread_.joinable()) {
        thread_.join();
    }
    asio::error_code ignored;
    acceptor_.close(ignored);
}

std::vector<HttpRequest> TestHttpServer::receivedRequests() {
    std::lock_guard<std::mutex> lock(requestsMutex_);
    return requests_;
}

std::string TestHttpServer::bigBody() {
    std::string body;
    for (int i = 0; i < 1024 * 1024; i++) {
        body.push_back(static_cast<char>('a' + (i % 26)));
    }
    return body;
}

void TestHttpServer::run() {
    while (!stopping_) {
        WaitResult wait = dipper::waitForConnection(acceptor_, kWaitSliceMs);
        if (wait == WaitResult::Failed) {
            return;
        }
        if (wait == WaitResult::NotYet) {
            continue;
        }
        tcp::socket socket(ioContext_);
        asio::error_code error;
        acceptor_.accept(socket, error);
        if (!error) {
            serveConnection(socket);
        }
        asio::error_code ignored;
        socket.shutdown(tcp::socket::shutdown_both, ignored);
        socket.close(ignored);
    }
}

void TestHttpServer::serveConnection(tcp::socket& socket) {
    dipper::HttpParser parser(dipper::ParserMode::Requests);
    std::vector<char> buffer(16 * 1024);
    while (!stopping_) {
        WaitResult wait = dipper::waitForData(socket, kWaitSliceMs);
        if (wait == WaitResult::Failed) {
            return;
        }
        if (wait == WaitResult::NotYet) {
            continue;
        }
        asio::error_code error;
        std::size_t count = socket.read_some(asio::buffer(buffer), error);
        if (error || !parser.feed(buffer.data(), count)) {
            return; // the proxy closed the connection, or sent something that is not HTTP
        }
        for (const HttpRequest& request : parser.takeRequests()) {
            {
                std::lock_guard<std::mutex> lock(requestsMutex_);
                requests_.push_back(request);
            }
            if (!answer(socket, request)) {
                return;
            }
        }
    }
}

// Sends the answer for one request. Returns false if the connection must be closed afterwards.
bool TestHttpServer::answer(tcp::socket& socket, const HttpRequest& request) {
    std::string response;
    bool keepOpen = true;
    if (request.url == "/hello") {
        response = makeResponse("Hello from the test server", request.method == "HEAD");
    } else if (request.url == "/echo") {
        response = makeResponse(request.body, false);
    } else if (request.url == "/chunked") {
        response = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"
                   "5\r\nHello\r\n8\r\n chunked\r\n0\r\n\r\n";
    } else if (request.url == "/big") {
        response = makeResponse(bigBody(), false);
    } else if (request.url == "/close") {
        response = "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\nThis body ends at the close.";
        keepOpen = false;
    } else if (request.url == "/slow") {
        waitUntilClosed(socket);
        return false;
    } else {
        response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n";
    }
    asio::error_code error;
    asio::write(socket, asio::buffer(response), error);
    return keepOpen && !error;
}

// For /slow: say nothing until the proxy gives up and closes the connection.
void TestHttpServer::waitUntilClosed(tcp::socket& socket) {
    std::vector<char> buffer(1024);
    while (!stopping_) {
        WaitResult wait = dipper::waitForData(socket, kWaitSliceMs);
        if (wait == WaitResult::Failed) {
            return;
        }
        if (wait == WaitResult::Ready) {
            asio::error_code error;
            socket.read_some(asio::buffer(buffer), error);
            if (error) {
                return; // closed by the proxy
            }
        }
    }
}
