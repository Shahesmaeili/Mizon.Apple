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

The test fixtures used synthetic data. The non-music sections still need their own Apple destinations.

## Header, mood animation and featured player

Apple base `f7082622cefd6cf7f1c11396383c978c25003479` was compared against Windows `ac0ea2c525a7d5e6cd1213c8364322466330aff9`. This revision covers the music header, mood control, typography and featured player media. macOS places the controls in the window toolbar. iPhone keeps them above the scrolling content and puts secondary sections in the overflow menu at narrow widths. Search opens from the header and preserves keyboard navigation and the existing typed streaming search operation.

The mood control renders the server's animation assets with Lottie 4.6.1. It caches bounded gzip TGS decoding, preloads the selected effect, and displays the one-shot effect over the header button. The player follows the Windows cubic timing, pivot and opacity values for the 430 ms artwork reveal. It holds the outgoing artwork while the incoming image decodes. Artwork colors drive the edge light, and the spotlight and press ripple follow the mouse or touch. The Apple effect uses SwiftUI and respects Reduce Motion, increased contrast, visibility changes and full-window video.

The app uses an installed Segoe UI Variable face where available. It bundles Microsoft Selawik under the SIL Open Font License as its English fallback. IRANSans remains the Persian face. [Microsoft font licensing FAQ](https://learn.microsoft.com/en-us/typography/fonts/font-faq) · [Selawik](https://learn.microsoft.com/en-us/typography/font-list/selawik)

The client consumes Swift SDK `6b6279cff54d35e747934cf168d38331cd24c1bd` and server endpoint source `8e832f4114f397c0d43b99bc95bd134f52d9a408`. Registered Windows `file:` media is retrieved by its media ID from the authenticated server with bounded byte-range downloads. Existing HTTPS media uses its direct HTTPS URL. The feature can fall back to the cover if the registered image or video poster fails. The Windows development server must run the server revision for this path to be available in the live app.

The Swift test suite passes 33 tests and the SDK suite passes 31. The backend Release build and the loopback Kestrel diagnostics passed. The macOS Release build includes arm64 and x86_64, and the window toolbar and search were checked in the running app. The iOS 27.1 simulator exercised the header, type-to-search, artwork download, feature navigation, scrolling and track navigation with synthetic data. The connected iPhone 16 Pro Max reached Windows over HTTP/3. On iOS 27.0.1 the populated feed overflowed SwiftUI's metadata decoding stack. The feed now bounds composite layout types at section boundaries, and the signed build with that fix is installed. Live Windows pixel comparison and physical device visual checks remain open. The Apple app still needs a live Music Home MCP transport and consent integration. Controller hardware and VoiceOver were outside these checks.
