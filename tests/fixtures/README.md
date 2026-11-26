# Test fixtures

Synthetic HTTP messages, HAR and pcap samples. Never add captures of real users' traffic.

`http/`: raw HTTP/1.1 messages for the parser tests. They use CRLF line endings, so Git and
editors must not change them (see `.gitattributes` and `.editorconfig`).
