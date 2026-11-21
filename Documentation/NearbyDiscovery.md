# Nearby devices on Apple platforms

The macOS and iPhone music header contains an opt-in Nearby control. With discovery enabled, Mizon shows other opted-in devices on the same local network. It displays the device name, platform, app version and the available public profile name or username. Signing out, disabling discovery or sending the app to the background ends the discovery session. Each session has a fresh random ID.

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

Build 16 was installed and launched on the physical iPhone 16 Pro Max. The signed-in Music Home and its header remained visible. The Swift Network.framework transport on macOS discovered the physical iPhone's live iOS announcement. The native Windows DNS-SD probe reported the actual Mac and iPhone and passed a check for the separate synthetic Mac advertisement. The Apple-to-Windows browse path still needs a Windows advertisement that remains active for the reverse check. The Apple app has no live MCP host or Nearby consent scope.
