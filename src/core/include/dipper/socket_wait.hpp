#pragma once

#include <asio/ip/tcp.hpp>

namespace dipper {

/// What happened while waiting for a socket.
enum class WaitResult {
    Ready,  // there is something to read (data, a new connection, or the other side closed)
    NotYet, // the time ran out and nothing arrived
    Failed  // the socket cannot be waited on (for example it was closed)
};

/// Waits up to `timeoutMs` milliseconds until `socket` has something to read.
///
/// Why this exists: Asio's blocking read_some() and accept() wait forever, and blocking Asio
/// has no timeout setting. So before each read we ask the operating system (poll() on
/// Linux/macOS, WSAPoll() on Windows) whether data is there, waiting only a limited time.
WaitResult waitForData(asio::ip::tcp::socket& socket, int timeoutMs);

/// The same for a listening socket: Ready means a new connection is waiting to be accepted.
WaitResult waitForConnection(asio::ip::tcp::acceptor& acceptor, int timeoutMs);

} // namespace dipper
