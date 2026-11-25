# Presence across Mizon devices

The Windows reference uses `SetWindowPresence` when its signed-in window gains or loses focus. The Apple app reports the same local window state from macOS window activity and the active iPhone scene. The Android phone publishes from its resumed signed-in activity. Backgrounding a mobile app or signing out stops its presence connection.

The [server revision](https://github.com/Shahesmaeili/Mizon.Server.API/commit/fd64e0f0032964be74551626a79fcbe94b343a0a) combines active windows for each authenticated account. `WatchAccountPresence()` reads and subscribes to that account only. The macOS menu bar keeps its subscription while Mizon runs, including when its own window is inactive or closed. The badge turns offline after the final active window deactivates or disconnects. Reconnecting refreshes the snapshot, and the latest server revision wins.

The [Swift SDK revision](https://github.com/Shahesmaeili/Mizon.API.Swift/commit/a074da5452d5c6843b3ffd8d4b0f2eb7eed4b4a8) decodes both the per-window acknowledgment and account events. The [Kotlin SDK revision](https://github.com/Shahesmaeili/Mizon.API.Kotlin/commit/e920fe698ae16afa6bc3427920c592f382c20020) publishes Android focus through the same contract. Older servers still report local focus through the existing contract. Windows continues publishing with its existing client. This change adds no MCP permission or public presence lookup.

The server and Swift SDK were exercised together over a real authenticated loopback connection with two instances of one account and an unrelated account. Coverage includes inactive observers, overlapping active windows, the last window disconnecting, account isolation, and reconnect.
