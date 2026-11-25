# Presence across Mizon devices

The Windows reference uses `SetWindowPresence` when its signed-in window gains or loses focus. The Apple app reports the same local window state from macOS window activity and active iPhone and Apple Watch scenes. The Android phone publishes from its resumed signed-in activity. Backgrounding a mobile app or signing out stops its presence connection.

The [server revision](https://github.com/Shahesmaeili/Mizon.Server.API/commit/fd64e0f0032964be74551626a79fcbe94b343a0a) combines active windows for each authenticated account. `WatchAccountPresence()` reads and subscribes to that account only. The macOS menu bar keeps its subscription while Mizon runs, including when its own window is inactive or closed. The badge turns offline after the final active window deactivates or disconnects. Reconnecting refreshes the snapshot, and the latest server revision wins.

The [Swift SDK revision](https://github.com/Shahesmaeili/Mizon.API.Swift/commit/a074da5452d5c6843b3ffd8d4b0f2eb7eed4b4a8) decodes both the per-window acknowledgment and account events. The [Windows client revision](https://github.com/Shahesmaeili/Mizon.Windows/commit/c2ec123f172b7b3903d031c48ee7e58f38d17838) watches the same account through its [typed .NET SDK](https://github.com/Shahesmaeili/Mizon.API.DotNet/commit/34d80cd0ffef50765776de6cb44b2552408b4a1b) and publishes the result to the taskbar companion. The [Kotlin SDK revision](https://github.com/Shahesmaeili/Mizon.API.Kotlin/commit/e920fe698ae16afa6bc3427920c592f382c20020) publishes Android focus through the same contract. Older servers still report local focus through the existing contract. This change adds no MCP permission or public presence lookup.

The server and Swift SDK were exercised together over a real authenticated loopback connection with two instances of one account and an unrelated account. Coverage includes inactive observers, overlapping active windows, the last window disconnecting, account isolation, and reconnect.

## Profile status indicators

The Windows reference uses a filled green or gray point with a transparent gap at the lower-right corner of the portrait. The macOS in-app toolbar and system menu, iPhone header and signed-in Apple Watch screen use the same badge geometry and colors. The Mac toolbar uses its trailing placement for the radar, mood and profile group. Narrow windows continue to route secondary tabs through the three-dot menu.

The Mac header shares the menu bar account observation. iPhone and Apple Watch observe account-wide state only while their signed-in surface is foregrounded and release the connection on sign-out or background entry. The badge uses confirmed server state and exposes a localized Online or Offline value.
