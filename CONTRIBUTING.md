# Contributing

Thanks for helping! Issues and pull requests are welcome.

- **Bugs:** include your macOS version, the Cliché version (Settings › About) and steps to reproduce.
- **Code:** logic that doesn't need AppKit goes in `Sources/ClicheCore` with tests in `Tests/ClicheCoreTests` (Swift Testing). Run `scripts/test.sh` before opening a PR.
- **Style:** match the surrounding code; comments explain *why*, in the language of the file.
- **Security:** anything that parses outside input (URLs, files, pasteboard) needs a test in `SecurityTests.swift`. Report vulnerabilities privately (see [SECURITY.md](SECURITY.md)).
