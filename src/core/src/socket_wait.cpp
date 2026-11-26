#include "dipper/socket_wait.hpp"

// poll() lives in a different header on each operating system. On Windows, Asio has already
// included <winsock2.h>, which declares WSAPoll().
#ifndef _WIN32
#include <cerrno>
#include <poll.h>
#endif

namespace dipper {

namespace {

// Asks the operating system whether `handle` becomes readable within `timeoutMs`.
WaitResult waitForReadable(const asio::ip::tcp::socket::native_handle_type& handle, int timeoutMs) {
#ifdef _WIN32
    WSAPOLLFD entry{};
    entry.fd = handle;
    entry.events = POLLRDNORM;
    int result = WSAPoll(&entry, 1, timeoutMs);
#else
    pollfd entry{};
    entry.fd = handle;
    entry.events = POLLIN;
    int result = ::poll(&entry, 1, timeoutMs);
    if (result < 0 && errno == EINTR) {
        return WaitResult::NotYet; // a signal woke us up early; the caller just waits again
    }
#endif
    if (result < 0) {
        return WaitResult::Failed;
    }
    if (result == 0) {
        return WaitResult::NotYet;
    }
    // Readable, or closed, or in error: the next read or accept will tell which.
    return WaitResult::Ready;
}

} // namespace

WaitResult waitForData(asio::ip::tcp::socket& socket, int timeoutMs) {
    if (!socket.is_open()) {
        return WaitResult::Failed;
    }
    return waitForReadable(socket.native_handle(), timeoutMs);
}

WaitResult waitForConnection(asio::ip::tcp::acceptor& acceptor, int timeoutMs) {
    if (!acceptor.is_open()) {
        return WaitResult::Failed;
    }
    return waitForReadable(acceptor.native_handle(), timeoutMs);
}

} // namespace dipper
