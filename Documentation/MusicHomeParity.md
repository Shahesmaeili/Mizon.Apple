# Music Home for Mac and iPhone

Owner: Codex. Task: 2026-11-21 music landing page after Welcome.

- Windows reference: `ac0ea2c525a7d5e6cd1213c8364322466330aff9` in Mizon.Windows, including `Pages/MusicPage.xaml`, `UserControls/StoryOrbitCard.xaml`, and the Music Home view models and resource tables.
- Apple bases: `8297d23c454cc6066bfcde90fa9585137d28783d` on `main` and `258c9786f93bda2452484dd19db8731416d40cda` on `preview/catppuccin`.
- Shared SDK: Mizon.API.Swift `f295dc53c3bc9e1cc09bf1226c35548cac1429a9`. Music Home uses the existing operation and endpoint types with the authenticated API instance. No server or SDK changes were required.
- GLTFKit2: `0.5.15` at `e69e354c4f31ea07b7816b8cbe2ddb28e897d073`. It is linked on macOS and iOS. The artist preview reads embedded GLB data and rejects external asset references, oversized model files and vertex counts beyond the Windows preview limit before import.

The Apple implementation owns the signed-in landing route, Music Home views, typed Music Home service, view model, and English and Persian resources. Music Home uses Windows' page width breakpoints of 1040 and 1440 points. Features, artists, stories, genres, playlists and following activity load independently. Editorial cards and sample recommendations use the Windows preview data. Add Story opens the Windows preview explanation. Story and artist media are resolved through the API, and likes and follows use the server-confirmed state.

The Windows reference still has a more extensive signed-in shell, Story viewer, track-detail player and discussion workflow. Apple Music Home can navigate to the available track, artist, story, and playlist details. Windows' MCP read, control, and submission scopes still need a live Apple transport and consent integration. The Music Home focus/action mappings support GameController input. Hardware Xbox navigation, full accessibility, live media/export, exact scrolling and animation timing, and pixel comparisons across macOS window sizes still require separate verification.

The iOS simulator smoke test uses a synthetic session and response fixtures, with a Windows Kana model from the reference checkout. The fixture, local developer trust configuration, device logs and build artifacts stay outside the source commits.

Validation completed with Xcode 27.1 and Swift 6.4. The 29 Swift tests passed. The iOS 27.1 UI smoke case loaded the Kana artist model, advanced and reversed the hero, opened a track and returned to Music Home, then scrolled to the Add Story preview. The main macOS Debug and iOS Simulator Release builds passed. The Catppuccin macOS Release build includes arm64 and x86_64 and ran with one application instance. A development-signed build was installed and the app process confirmed on the connected iPhone 16 Pro Max. The device's signed-in Music Home was not exercised with an account.

## Visual parity revision

Windows reference remained `ac0ea2c525a7d5e6cd1213c8364322466330aff9` when checked against the remote branch. Apple revision bases were `b8ef1bb891f0778a729b57a2b7e04f6b45b6ef5e` and `9670bd3e3c15b69653a2ed305afff51c3ff8c064`. The Swift SDK revision above remains pinned.

The signed-in music page uses the Windows top navigation and embedded search, the original featured-player overlay and spotlight proportions, and closer ports of the card rails and sidebar widgets. The search and mood controls use the existing SDK operations. The reference timings drive the hero selection, spotlight entrances, and news transitions. The actual Windows photos are loaded from the SwiftPM bundle with bounded ImageIO decoding. The rendering check covered 320, 390, 1000, 1100, and 1600 point macOS fixtures. The iPhone simulator exercised the search field and selected music tab, feature controls, the Windows Kana model, track navigation, page scrolling, and the story preview. The 30-test Swift suite includes bundled artwork coverage.

The test fixtures used synthetic data. A live pixel comparison with the Windows app remains open. The English typography falls back to the Apple system font when Segoe UI Variable is unavailable. The mood control displays the API emoji and supports selection, with the Windows Lottie effects still pending. The non-music sections still need their own Apple destinations.

## Artist model delivery

Codex repaired artist-model loading from Apple base `53c471a0d4d2e25560b685ca246ba6dfc3b7f2f6`. The Music Home spotlight and artist profile share the same authenticated GLB download and transparent SceneKit renderer. The renderer preserves the existing GLB size and geometry limits. The profile uses its own yaw or the matching Spotlight pose when available.

The registered-media endpoint needs Mizon.Server.API `9832f13d7b1cc17a11f08f200848acec4e1e9092` or later and the existing Mizon.API.Swift pin `9c7f4621e276f07d48fb960ae44a202dc3b018a0`. The server serves `App_Data/PersonProfileFixtures` by default. For existing featured artists registered against files elsewhere, configure the exact artist-model directory in `Media:LocalContentRoots` on the server.

Validation covered authenticated GLB ranges in the server diagnostics, one shared content request for two Swift artist previews, and reference GLB decoding on macOS and iPhone simulator. The display fixture used local copies of reference models and synthetic sessions.
