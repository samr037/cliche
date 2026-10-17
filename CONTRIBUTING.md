# Contributing

Thanks for helping! Issues and pull requests are welcome.

- **Bugs:** include your macOS version, the Cliché version (Settings › About) and steps to reproduce.
- **Code:** logic that doesn't need AppKit goes in `Sources/ClicheCore` with tests in `Tests/ClicheCoreTests` (Swift Testing). Run `scripts/test.sh` before opening a PR.
- **Style:** match the surrounding code; comments explain *why*, in the language of the file.
- **Translations:** UI text is written in French in the code (`String(localized:)`, SwiftUI literals). After changing text, run `scripts/l10n.py extract`, then update every `Resources/<lang>.lproj/Localizable.strings` following [the glossary](docs/l10n-glossary.md). `scripts/l10n.py check` (also run in CI) must pass. New languages are welcome: add the code to `LANGS` in `scripts/l10n.py` and to `CFBundleLocalizations` in `Resources/Info.plist`.
- **Security:** anything that parses outside input (URLs, files, pasteboard) needs a test in `SecurityTests.swift`. Report vulnerabilities privately (see [SECURITY.md](SECURITY.md)).
