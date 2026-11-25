#include "dipper/http_transaction.hpp"

#include <cctype>

namespace dipper {

bool equalsIgnoreCase(const std::string& a, const std::string& b) {
    if (a.size() != b.size()) {
        return false;
    }
    for (std::size_t i = 0; i < a.size(); ++i) {
        // std::tolower needs an unsigned char, otherwise bytes above 127 are undefined behaviour.
        const int left = std::tolower(static_cast<unsigned char>(a[i]));
        const int right = std::tolower(static_cast<unsigned char>(b[i]));
        if (left != right) {
            return false;
        }
    }
    return true;
}

std::optional<std::string> findHeader(const Headers& headers, const std::string& name) {
    for (const Header& header : headers) {
        if (equalsIgnoreCase(header.name, name)) {
            return header.value;
        }
    }
    return std::nullopt;
}

// Checks the timing values on their own. Returns "" if they are fine.
static std::string findTimingProblem(const Timings& timings) {
    // A measured time can never be negative; only kNotMeasured (-1) is allowed below 0.
    const double values[] = {timings.dnsMs, timings.connectMs, timings.tlsMs, timings.ttfbMs,
                             timings.totalMs};
    for (const double value : values) {
        if (value < 0.0 && value != kNotMeasured) {
            return "a timing value is negative";
        }
    }

    // The first response byte cannot arrive after the whole response has finished.
    const bool bothMeasured = timings.ttfbMs != kNotMeasured && timings.totalMs != kNotMeasured;
    if (bothMeasured && timings.ttfbMs > timings.totalMs) {
        return "time to first byte is longer than the total time";
    }
    return "";
}

std::string findProblem(const HttpTransaction& transaction) {
    const bool failed = transaction.error != TransactionError::None;

    // A transaction either finished with a response or failed with an error, never both
    // and never neither.
    if (failed && transaction.hasResponse) {
        return "transaction has an error but also a response";
    }
    if (!failed && !transaction.hasResponse) {
        return "transaction has no response and no error";
    }

    // HTTP status codes are three digits from 100 to 599.
    if (transaction.hasResponse) {
        const int status = transaction.response.statusCode;
        if (status < 100 || status > 599) {
            return "response status code " + std::to_string(status) + " is not between 100 and 599";
        }
    }

    if (transaction.request.bodySize < 0 || transaction.response.bodySize < 0) {
        return "a body size is negative";
    }

    return findTimingProblem(transaction.timings);
}

} // namespace dipper
