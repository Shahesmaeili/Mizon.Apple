# Mizon Apple development requirements

Apply these requirements to every relevant change in the macOS and iOS apps. Use the matching Windows page, view model, assets, and shared backend contract as the behavior reference. Preserve the accepted SwiftUI design, native Apple controls, and Liquid Glass where the task uses them. Keep platform-specific behavior native to macOS and iOS.

## Swift, performance, and UI

- Use the latest Swift language mode and Xcode toolchain supported by the project and its dependencies. Follow Swift 6 strict concurrency, use explicit typed `Codable` contracts and dispatch, and keep Release builds compatible with the native compiler without reflection-based fallbacks or broad warning suppression.
- Keep startup, scrolling, interaction, and animation responsive. Bound network, stream buffering, cache, decoding, polling, and background work. Keep expensive work off the main actor, cancel superseded work, and release connections, timers, observers, media, and native resources when their owning surface closes.
- Reuse Mizon's existing backend operations, typed SDK endpoints, playback, caching, authentication, and navigation. Keep business rules in their owning services. Preserve the wire contract and existing callers when porting new Windows behavior.
- Check narrow, wide, short, and tall windows, iPhone layouts, keyboard and pointer or touch, Persian RTL and English LTR, VoiceOver, visible focus, and Reduce Motion as applicable. Preserve the source behavior at breakpoints and feedback during loading, failure, and empty states.

## Xbox controller input

- Every new or changed interactive page must support Xbox controllers through GameController and the same actions, validation, and routing used by the rest of the UI. Include meaningful mappings, visible and restorable focus, directional navigation and scrolling, A for the focused action, B for back or cancel, localized hints, and a usable text-entry path when the page requires it.
- Capture input on the active surface only. Respect system-reserved controls, handle dead zones, press edges, bounded repeats, disconnects and reactivation, and clear held input on ownership changes. Test action eligibility, focus, cancellation, and lifecycle. Record real-controller and rendered behavior separately from synthetic checks.

## MCP

- New or changed user-facing behavior must include meaningful, typed MCP state and actions where applicable, plus integration verification through the real adapter or transport boundary. Reuse the same live model and business services as the UI. For styling-only edits, reuse existing contracts and checks.
- Keep discovery side-effect free and define accurate input/output schemas. Default to denied access. Separate read, control, and consequential submit permissions by feature domain. An authentication grant does not grant music, appearance, settings, or other access. In-app consent, revocation, cancellation, and resource cleanup must apply to the actual calls.
- Exclude credentials, tokens, cookies, and raw authentication payloads from MCP state and logs. Never expose arbitrary shell, SQL, reflection, HTTP, or input injection, or let a tool or test approve its own access. Use synthetic data and verify applicable denied, insufficient-scope, revoked, cancellation, failure, and cleanup cases.
- Report current Apple MCP coverage by feature. Windows coverage and SwiftUI accessibility identifiers alone do not establish Apple MCP support.

## Verification and delivery

- Read the relevant Windows [collaboration rules](https://github.com/Shahesmaeili/Mizon.Windows/blob/main/docs/ai/COLLABORATION.md) and [MCP development guide](https://github.com/Shahesmaeili/Mizon.Windows/blob/main/Mcp/DEVELOPMENT.md) from the reference revision. Apply platform-appropriate equivalents to the Apple code.
- Verify behavior with focused tests and affected Xcode builds. Exercise the actual visible flow, accessibility, controller lifecycle, MCP permissions, and performance when relevant. Report unverified device, live-server, rendering, and Release checks accurately.
- Preserve unrelated work. Use isolated branches or worktrees for concurrent changes. Commit only the completed scope and push it to the intended GitHub branch. Record dependency revisions and known gaps in the handoff. Keep credentials, test data, local network settings, and generated artifacts out of commits.
