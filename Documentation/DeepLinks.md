# Deep links on macOS and iPhone

Reference [Mizon.Windows at a7010d7](https://github.com/Shahesmaeili/Mizon.Windows/blob/a7010d7a0e67e8f31e68712d5fb2314a599b53aa/DeepLinks.md). Install a build that registers the `mizon` URL scheme. The Apple client uses the same canonical routes and also accepts the Windows `localhost` and SID aliases. IDs are public UUIDs. Welcome remains an internal account check.

| Link | Destination or operation |
| --- | --- |
| `mizon://home`, `mizon://music` | Music home |
| `mizon://login`, `mizon://register` | Sign-in or registration form |
| `mizon://movies`, `mizon://apps`, `mizon://vpn` | Apple section landing or VPN availability |
| `mizon://playlists`, `mizon://playlist/{id}` | Library or a particular playlist |
| `mizon://music/{id}` | Track details without autoplay |
| `mizon://music/{id}?action=play` | Track details and explicit playback |
| `mizon://music/{id}?action=download` | Track details and download to the existing cache |
| `mizon://music/{id}?action=video` | Linked video without autoplay |
| `mizon://music/{id}/comments/{commentId}` | Track details and the requested comment |
| `mizon://client/{id}`, `mizon://person/{id}` | Client or artist profile |
| `mizon://story/{id}` | Story viewer |
| `mizon://activities` | Following activity |
| `mizon://settings`, `mizon://settings/{section}` | Settings or the named section |
| `mizon://search?query={urlEncodedText}` | Search with a query of 1–120 characters |

Settings sections are `account`, `security`, `language`, `appearance`, `notifications`, `storage`, `updates`, `platforms`, and `ai-connections`. The Apple settings sheet exposes existing Apple capabilities and shows informational states for unavailable operations. A link can select a section without changing its preferences or permissions. Authentication links open a form without submitting it or signing out.

## Requests with a result

A regular URL opens Mizon. To receive a result, run the **Open Mizon Link** action in Apple Shortcuts. Supply the URL, an optional nonzero UUID in **Request ID**, and **Response Version** 1. The action returns JSON text with the Windows v1 fields `version`, `requestId`, `success`, `code`, `message`, and optional `data`. The macOS menu-bar avatar uses this same response path within Mizon. Apple provides its own app activation mechanism through [App Intents](https://developer.apple.com/documentation/appintents); Windows callers continue using `LaunchUriForResultsAsync`.

`opened` confirms presentation. `completed` confirms the corresponding load or operation. Request IDs correlate the result with the caller. The timeout is 50 seconds, or five minutes for an explicit download. A newer link supersedes the previous request. Ordinary protected links can wait for sign-in. A result request that requires sign-in returns `requires_sign_in` without queuing work for a later account. The response contains the typed destination and public identifiers when relevant. No credentials or local file paths are accepted or returned. Custom callback URLs are not part of the contract.

Apple MCP navigation transport and its separate approval scope are not yet available.

## Contract checks

The [Windows v1 fixture](https://github.com/Shahesmaeili/Mizon.Windows/blob/a7010d7a0e67e8f31e68712d5fb2314a599b53aa/docs/ai/contracts/deep-links-v1.json)
is mirrored byte for byte in `Tests/Fixtures`. CI compares the copy with the current Windows fixture and exercises the production Swift parser, result DTO and request lifecycle.
Run `bash Scripts/validate-deep-links.sh` on macOS for the focused optimized tests.

This reference covers the shared macOS and iOS scheme and App Intent. The watchOS target currently has no registered Mizon scheme or deep-link dispatcher. The VPN route on macOS and iOS shows the platform's availability page because those targets do not have the Windows VPN implementation. Some Apple settings sections likewise document platform availability.
