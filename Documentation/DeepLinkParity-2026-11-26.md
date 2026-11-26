# Apple deep-link v1 parity

- Owner: Codex
- Date: 2026-11-26
- Branch: codex/align-deep-link-contract
- Apple base: 26cbd2a50e69500b89eab4a4f8716e46bb98e292
- Reference and fixture revision: Mizon.Windows a7010d7a0e67e8f31e68712d5fb2314a599b53aa
- Owned files: Swift route and result rules, App Intent metadata, router result guard, contract tests, CI and deep-link documentation

The shared macOS and iOS parser uses the Windows whitespace set and handles surrounding input whitespace in the same order. App Intent validates metadata before routing and preserves unsupported-version precedence. The router rejects a premature opened receipt for a destination that requires completed. Apple tests consume the exact fixture published by Windows and run separately from the UI and SDK dependency builds.

The Apple entry points continue using existing native scene routing, session handling, page loading, cancellation, Xbox input and VoiceOver labels. watchOS and Apple MCP navigation do not yet provide these entry points. The VPN availability page is an Apple platform gap. Device-level verification remains separate from CI.
