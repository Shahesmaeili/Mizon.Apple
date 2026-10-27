# Login validation

Local toolchain: Apple Swift 6.4 / Xcode 27.1. App minimums: macOS 26, iOS 26, watchOS 26, matching native Liquid Glass availability.

## Automated

- Email-versus-username classification matches the Windows regular expression, including plus-addressed emails and trimmed identifiers.
- Password content, including leading/trailing spaces, is preserved in the API request.
- Empty and whitespace-only identifiers cannot submit.
- Server addresses must be HTTPS and cannot include credentials, query parameters or fragments.
- Login success clears the password; error and cancellation restore controls.
- Duplicate submission is ignored while a request is in progress.
- The real SDK performs POST `/Clients/Login` with gzip and installation metadata, without Bearer auth.
- Returned access/refresh tokens and IDs are handed to the injected session store. Secure-storage failure clears the SDK token.
- Missing success content is rejected, and API error text/close-button text is preserved.
- Tests use an in-memory store and URLProtocol fixtures; no personal credentials are persisted or sent.

## Source-driven presentation validation

Fourteen local tests cover the existing authentication/SDK contracts plus actual CoreText registration of IRANSans and Seagull Fluent Icons, required regular/RTL glyph availability, DevWinUI's five-retry random semantics, star parameter ranges, cumulative Z across successive movement segments, and composition easing endpoints.

The actual Mac bundle is inspected in both card states. Synthetic credentials enable submission and survive a flip; an unavailable localhost produces the expected Persian alert and restores controls. The initial registration face, exact labels and placeholders, 304-point width, 440/500-point heights, original animated GIF, bottom app bar and toggling back and forth are checked. Screenshots are in Documentation/Screenshots. Passwords stay secure. The old custom password-reveal button, registration-information sheet, extra marketing text, system icons and decorative gradients have been removed.

The native glass window uses a clear nonopaque NSWindow and behind-window NSVisualEffectView. System transparency preferences affect the result. Mac has no Windows inclinometer; sensor-based tilt is unavailable on that platform. Rendering uses SwiftUI Canvas rather than Windows Composition, so native antialiasing and material appearance differ. Windows source initializes a random sky; pixel positions are not fixed across launches on either platform.

A physical iPhone/Watch, successful live backend login, production signing, notarization and App Store distribution remain outside this login-only phase. CI is triggered by push; this iteration does not wait for GitHub Actions, as requested.

## Backend version contract

The login metadata currently retains Windows' reference backend version UUID `0195dd3c-9a3e-7c4a-8c6f-2e9c0f6b1a72`, because no Apple-specific registered backend version ID was provided. Before production rollout, register the Apple app version in the backend and replace that UUID in `AuthenticationService.swift`. Device identity is a random per-install UUID persisted in UserDefaults; local operating-system usernames and personal device names are not sent.

## SDK audit and CI

The consumed SDK was audited against all 99 .NET source files, 78 DTOs, 246 typed fields and 30 operations. Its 24 tests and Apple cross-builds passed in [GitHub Actions run 40393410498](https://github.com/Shahesmaeili/Mizon.API.Swift/actions/runs/40393410498) for SDK commit `92998d7`. Runner allocation and an obsolete Swift installer were fixed before that successful run.
