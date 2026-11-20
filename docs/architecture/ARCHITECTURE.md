# Architecture overview

> Status: **draft**: complete it in the Phase 1 issue "Write architecture document". Record each
> significant choice as an ADR in [`docs/decisions/`](../decisions/).

## 1. Goals and quality attributes

| Attribute | Target (fill in from the SRS) |
| --- | --- |
| Ease of setup | A first-time user sees their first captured request within _N_ minutes |
| Throughput | Proxy sustains _N_ requests/s on a typical laptop |
| Added latency | Proxy adds less than _N_ ms at p95 |
| Scale | GUI stays responsive with _N_ transactions in a session |
| Portability | Builds and runs on Windows, Linux, macOS |
| Safety | No interception of HTTPS unless the user opts in |

## 2. Context

```mermaid
flowchart LR
    U[Beginner / power user] -->|GUI or CLI| T[HTTP Logger & Analyzer]
    B[Browser / app under test] -->|HTTP via proxy| T
    T -->|forwards request| S[Web server]
    N[Network interface] -.->|passive capture, advanced| T
    T -->|HAR / JSON / CSV| F[Files, DevTools, scripts]
```

## 3. Components

```mermaid
flowchart TB
    subgraph core[libhttplogger_core]
        direction TB
        C1[Proxy capture<br/>Asio] --> P[Parser & normaliser<br/>llhttp + TCP reassembly]
        C2[Passive capture<br/>libpcap/Npcap] --> P
        C3[HAR import] --> P
        P --> Q[(Capture queue)]
        Q --> ST[(Session store<br/>SQLite WAL + FTS5)]
        Q --> LIVE[Live event stream]
        ST --> AN[Analyzer<br/>stats, filter language, rules]
        ST --> EX[Exporters<br/>HAR, JSON, CSV]
        API[[Public C++ API]]
        AN --> API
        EX --> API
        LIVE --> API
    end
    API --> GUI[Qt 6 GUI<br/>beginners]
    API --> CLI[httplog CLI<br/>power users]
    API --> TESTS[Tests]
```

| Component | Responsibility | Key types |
| --- | --- | --- |
| Capture | Accept client connections, forward upstream, emit raw bytes + timings | `ProxyServer`, `PcapSource`, `HarImporter` |
| Parser | Turn byte streams into request/response pairs | `HttpParser`, `TcpReassembler` |
| Model | Immutable record of one exchange | `HttpTransaction`, `Headers`, `Timings` |
| Store | Persist and query transactions | `SessionStore`, `Query` |
| Analyzer | Aggregate stats, evaluate filters and alert rules | `FilterExpr`, `Stats`, `RuleEngine` |
| Export | Serialise sessions | `HarExporter`, `CsvExporter` |

## 4. Request flow (proxy mode)

```mermaid
sequenceDiagram
    participant B as Browser
    participant P as ProxyServer
    participant S as Web server
    participant Q as Capture queue
    participant D as SessionStore
    B->>P: GET http://example.com/ (via proxy)
    P->>S: GET / (forwarded)
    S-->>P: 200 OK + body
    P-->>B: 200 OK + body
    P->>Q: HttpTransaction (request, response, timings)
    Q->>D: batched insert
    Q-->>GUI: live event
```

## 5. Data model (draft)

`HttpTransaction`: id, session id, client address, server host/port, scheme, method, URL,
request headers/body ref, status code, response headers/body ref, sizes, timings
(start, DNS, connect, TLS, TTFB, total), capture mode, error (if any).

## 6. Threading model

_To decide (ADR):_ Asio `io_context` on a small thread pool for network I/O; one writer thread
draining the capture queue into SQLite in batches; the GUI thread receives live events via a
Qt queued signal.

## 7. Storage

One SQLite file per session (`*.httplog`), WAL mode, indexes on time, host, status, method;
FTS5 table over URLs and text bodies; large bodies stored with a size cap.

## 8. Security and ethics

HTTPS interception is opt-in, uses a locally generated CA whose private key never leaves the
user's machine, and is clearly indicated in the UI. Proxy listens on `127.0.0.1` by default.
