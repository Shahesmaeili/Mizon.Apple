# Deep links on macOS and iPhone

Reference [Mizon.Windows at 315d795](https://github.com/Shahesmaeili/Mizon.Windows/blob/315d795119102715dd4a5b2440b517ea290a343a/DeepLinks.md). Install a build that registers the `mizon` URL scheme. The Apple client uses the same canonical routes and also accepts the Windows `localhost` and SID aliases. IDs are public UUIDs. Welcome remains an internal account check.

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
