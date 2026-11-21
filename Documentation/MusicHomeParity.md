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
