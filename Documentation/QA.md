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

## Manual macOS checks

The real app bundle was launched, observed through accessibility and captured visually.

- The empty form disables the sign-in button.
- Entering synthetic `preview@example.com` / `preview-only` enables submission.
- The reveal-password control switches between secure and plain entry.
- Submitting against unavailable localhost displays a Persian network error and restores controls.
- Dismissing the error returns to the editable form.
- Connection settings open as a native sheet; an HTTP URL is rejected without saving.
- The registration link opens an honest availability message rather than simulating account creation.
- Synthetic form values were cleared after testing.
- Native window controls and the app's Settings menu are present.

Screenshots are in `Documentation/Screenshots`. Error screenshots contain synthetic test data only. No live production service was used. A physical iPhone/Watch, successful live backend login, production signing, notarization and App Store distribution remain outside this login-only phase.

## Backend version contract

The login metadata currently retains Windows' reference backend version UUID `0195dd3c-9a3e-7c4a-8c6f-2e9c0f6b1a72`, because no Apple-specific registered backend version ID was provided. Before production rollout, register the Apple app version in the backend and replace that UUID in `AuthenticationService.swift`. Device identity is a random per-install UUID persisted in UserDefaults; local operating-system usernames and personal device names are not sent.

## SDK audit and CI

The consumed SDK was audited against all 99 .NET source files, 78 DTOs, 246 typed fields and 30 operations. Its 24 tests and Apple cross-builds passed in [GitHub Actions run 40393410498](https://github.com/Shahesmaeili/Mizon.API.Swift/actions/runs/40393410498) for SDK commit `92998d7`. Runner allocation and an obsolete Swift installer were fixed before that successful run.
