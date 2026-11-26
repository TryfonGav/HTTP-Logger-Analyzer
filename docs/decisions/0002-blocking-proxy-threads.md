# ADR-0002: Blocking Asio with one thread per proxy connection

> **Draft written with AI help for the student to review and rewrite in their own words.**

- **Status:** proposed
- **Date:** 2026-11-26
- **Related issue:** #21

## Context

The proxy must serve several browser connections at the same time, forward each request to
its server, and stream responses back without holding them whole in memory. The code must be
simple enough to explain line by line at the viva, and it must build and behave the same on
Windows, Linux and macOS. Expected load is one developer's browser and tools, so tens of
connections at once, not thousands.

## Options considered

| Option | Pros | Cons |
| --- | --- | --- |
| Blocking Asio, one `std::thread` per connection | Code reads top to bottom like the protocol; each connection's state is local variables; easy to debug | One thread per connection (fine for tens, not for thousands); blocking calls have no built-in timeout |
| Asio async (callbacks) on a small thread pool | Scales to many connections with few threads; timers give timeouts | State is split across callbacks and shared objects; lifetime bugs are easy to make and hard to explain |
| Asio with C++20 coroutines | Reads top to bottom and scales | Coroutine machinery is advanced and outside the project's coding style |

## Decision

Use blocking Asio calls with one accept thread and one `std::thread` per client connection.
Timeouts are done by asking the operating system whether data is ready (`poll()` /
`WSAPoll()`) in short waits before each read.

## Consequences

- Each connection is handled by straight-line code that is easy to read and test.
- Memory and thread count grow with the number of open connections; acceptable for a
  developer tool on one machine. Revisit if benchmarks (#60) show a problem.
- A small `#ifdef` is needed for `poll()` versus `WSAPoll()`.
- Connecting to a server relies on the operating system's connect timeout (about 21 s on
  Windows, longer on Linux), which cannot be shortened without async calls or non-blocking
  connects.
- Writes to a client that stops reading can block; `stop()` would then wait for that thread.

## References

[1] C. M. Kohlhoff, "Asio C++ Library," 2025. [Online]. Available: https://think-async.com/Asio/

[2] R. Fielding, M. Nottingham and J. Reschke, "HTTP/1.1," RFC 9112, IETF, Jun. 2022.
