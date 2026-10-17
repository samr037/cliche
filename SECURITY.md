# Security

## Reporting a vulnerability

Use **[Report a vulnerability](../../security/advisories/new)** in the Security tab: the report stays private until it is fixed. Please don't open a public issue. Include the Cliché and macOS versions and, if possible, steps to reproduce. Expect a reply within 7 days.

Only the latest release receives fixes.

## What Cliché does and doesn't do

- Screenshots never leave your Mac. Cliché makes **no network requests**: no update check, no telemetry, no upload.
- It needs **Screen Recording** for captures and, only for scrolling capture, **Accessibility** (to post synthetic scroll events).
- `cliche://` links are **disabled until you allow them**, because any web page can open a URL scheme. Even then, only a fixed list of commands is accepted, without parameters: a link can start a capture, never read or write a file (`ClicheCore/Safety.swift`, covered by `SecurityTests`).
- Files are written only inside your chosen screenshots folder, never overwriting an existing file.

## Automated checks

| Check | When | What |
|---|---|---|
| Unit and security tests | every push and PR | `ClicheCore` (input validation, rendering, stitching…) |
| CodeQL `security-extended` | push, PR, weekly | static analysis of the Swift code |
| gitleaks | push, PR, weekly | secrets in the full git history |
| OpenSSF Scorecard | push, weekly (public repo) | supply chain hygiene |
| Dependabot | weekly | pinned GitHub Actions |

## Verifying a download

Every DMG published by the release workflow carries a signed build-provenance attestation:

```sh
gh attestation verify Cliche-x.y.z.dmg -R samr037/cliche
shasum -a 256 -c Cliche-x.y.z.dmg.sha256
```

The app is ad hoc signed and not notarized (no Apple Developer ID): macOS asks for confirmation the first time you open it.
