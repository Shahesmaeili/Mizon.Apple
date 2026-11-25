# Nearby devices on Apple platforms

Discovery starts as soon as the public account is loaded for a signed-in user. It stays active with the music header panel closed. The Nearby control shows other Mizon devices on the local network and offers a stop setting that persists on that installation. Signing out, disabling discovery or sending the iPhone app to the background ends the discovery session. Returning to the active iPhone app starts it again when enabled. Each discovery session has a fresh random ID. Apple supplies the Local Network permission.

With the panel open, Mizon looks up each distinct announced account by its exact username in global search, verifies the returned public client profile, and obtains its registered profile image through the existing artwork downloader. The app loads at most three avatars concurrently, cancels work when the list closes or the iPhone goes to the background, and uses the platform icon when no photo is available. Bonjour records carry public device and account text. Photo data, media addresses, profile identifiers and authentication remain in the Mizon API workflow.

## Windows interoperability

This work started from Apple commit `5b0c476cb95a20f6b42c6bf3d0d46ae0a7cf7e82` and the shared contract from the Windows development chat. The service is `_mizon-peer._tcp` in `local.`. The instance name is `Mizon-` followed by the lower-case hyphenated session UUID.

| TXT key | Value |
| --- | --- |
| `v` | Contract version `1` |
| `id` | The instance's lower-case hyphenated UUID |
| `platform` | `windows`, `macos`, `ios`, `android`, `watchos` or `wearos` |
| `app` | App version, up to 32 UTF-8 bytes |
| `device` | Friendly device name, up to 96 UTF-8 bytes |
| `account` | Optional public Mizon username, up to 64 UTF-8 bytes |
| `display` | Optional public Mizon display name, up to 96 UTF-8 bytes |

The app browses only this service type. The TCP listener exists for Bonjour registration and cancels incoming connections. Records describe nearby presence and carry no authentication credentials or private device identifiers. The service rejects malformed, oversized, conflicting and self advertisements. Incoming records are local network announcements and do not verify a device or the identity it claims.

macOS uses its computer name. iOS uses the device name available to standard apps, such as iPhone. Both use the system's Local Network permission. [Apple local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy) · [iPhone device naming](https://developer.apple.com/documentation/uikit/uidevice/name)

## Verification

On macOS, two Network.framework service instances with synthetic Mac and Windows metadata discovered one another without returning their own advertisement. The Swift suite passed 40 tests, including the Windows wire fixture, validation limits, opt-in and permission state. The optimized macOS and iOS builds declare the same service. The iPhone simulator verified that the header opens the disclosure with visibility off and that the panel closes from its own button.

Build 16 was installed and launched on the physical iPhone 16 Pro Max. The signed-in Music Home and its header remained visible. The Swift Network.framework transport on macOS discovered the physical iPhone's live iOS announcement. The native Windows DNS-SD probe found the actual Mac and iPhone and the separate synthetic Mac advertisement. On November 21, 2026, the same Swift transport found the Windows NativeAOT probe on the live LAN. macOS Bonjour reported the probe's withdrawal at 19:00:45 Tehran time. The Apple app has no live MCP host or Nearby consent scope.

The profile and session update uses the pinned Swift SDK revision `6b6279cff54d35e747934cf168d38331cd24c1bd`. The macOS suite covers exact username and public profile validation, reuse of cached thumbnails, cancellation of a live media request without affecting unrelated artwork, session readiness before the welcome avatar fetch, and persistent discovery preference. Windows-local avatar files are subject to the same registered media roots as other local media on the backend.
