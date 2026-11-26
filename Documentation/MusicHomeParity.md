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

The test fixtures used synthetic data. A live pixel comparison with the Windows app remains open.

## Header, mood animation and featured player

The earlier main-branch revision compared Apple base `f7082622cefd6cf7f1c11396383c978c25003479` against Windows `ac0ea2c525a7d5e6cd1213c8364322466330aff9`. It introduced the native Mac toolbar, the responsive iPhone header, and search through the existing streaming operation. The playback artwork follows the 430 ms Windows reveal. Artwork colors drive the edge light, and the spotlight and press ripple follow pointer or touch input.

The current client uses bundled Selawik for English and IRANSans for Persian. The mood control uses Lottie 4.6.1 with bounded TGS decoding, cached media, and a one-shot click effect. Reduce Motion and view visibility govern playback.

The earlier media path was verified with Swift SDK `6b6279cff54d35e747934cf168d38331cd24c1bd` and server `8e832f4114f397c0d43b99bc95bd134f52d9a408`. The current SDK pin adds verified nearby pieces to the existing authenticated media downloads. The earlier iOS 27.1 simulator exercised search, media loading and navigation with synthetic data. The connected iPhone 16 Pro Max reached Windows over HTTP/3. The feed bounds composite SwiftUI layout types to avoid a previously observed metadata decoding stack overflow on iOS 27.0.1.

## Artist model delivery

Codex repaired artist-model loading from Apple base `53c471a0d4d2e25560b685ca246ba6dfc3b7f2f6`. The Music Home spotlight and artist profile share the same authenticated GLB download and transparent SceneKit renderer. The renderer preserves the existing GLB size and geometry limits. The profile uses its own yaw or the matching Spotlight pose when available.

The registered-media endpoint needs Mizon.Server.API `9832f13d7b1cc17a11f08f200848acec4e1e9092` or later and the existing Mizon.API.Swift pin `9c7f4621e276f07d48fb960ae44a202dc3b018a0`. The server serves `App_Data/PersonProfileFixtures` by default. For existing featured artists registered against files elsewhere, configure the exact artist-model directory in `Media:LocalContentRoots` on the server.

Validation covered authenticated GLB ranges in the server diagnostics, one shared content request for two Swift artist previews, and reference GLB decoding on macOS and iPhone simulator. The display fixture used local copies of reference models and synthetic sessions.

## System shortcuts and the Mac toolbar

The reference is [Windows JumpListService](https://github.com/Shahesmaeili/Mizon.Windows/blob/e1dc09e7db05d7227bbdaf0d40ee5525c121f3c1/Services/JumpListService.cs). Mizon publishes Sign in and Create an account while signed out, and Music, Movies and TV, Apps, and VPN while signed in. Menus follow the app language. The latest section request waits for Welcome to validate the session. A request received during sign-out is discarded. Opening an account form preserves the current session until an explicit account action succeeds.

macOS provides these commands through the running app’s Dock menu. iPhone provides dynamic Home Screen quick actions after the first launch and accepts them on warm and cold launches. Movies and TV and Apps open section landings. Apple VPN opens its availability page. The Apple app has no live MCP host or shortcut consent scope. The existing Mac application remains single-instance.

Music Home draws its 52-point macOS header within the app content. AppKit window controls are vertically centered in the header when windowed and return to the native title bar in full screen. The 44-point navigation tabs start to the right of the window controls in a window and move to the left edge in full screen, including in Persian. The 38-point search and account controls stay on the right, and secondary tabs move to the overflow menu in narrow windows. The header and feed share one window backdrop. Music Home restores the previous title bar configuration when it is removed. The Swift tests cover compact overflow, AppKit control alignment and window chrome restoration, shortcut ordering and localization, authentication gates, and replacement of pending requests.

## Profile and mood in the macOS menu bar

The [Windows taskbar companion](https://github.com/Shahesmaeili/Mizon.Windows/tree/315d795/Taskbar/Mizon.Windows.Taskbar) supplies the reference layout and actions. The Mac shows the confirmed mood to the left of the signed-in avatar in native status items. macOS sizes the menu bar and manages item placement. The avatar opens the authenticated profile and shows a loading ring until the profile resolves. The mood loops only while visible and plays its 208-point effect only on click. The effect appears below the top bar and respects Reduce Motion.

Mac status items remain available when the main window closes. While the signed-in menu bar controls are enabled, Command-Q hides Mizon and leaves its profile, mood and authenticated presence subscription running. Command-Option-Q quits the process. The profile item reopens Mizon. Settings can hide the items. The artwork uses the native button height, with enough space for the profile badge, and scales to the current display. The badge represents [account presence](AccountPresence.md) across active devices. The loop and click effect share Music Home’s authenticated artwork cache. This feature has no Apple MCP transport or grant.

In the active Mizon window, the Xbox controller opens the focused account profile with A and plays the menu bar effect with X when the mood control is focused. The status items themselves use macOS keyboard and accessibility navigation.

## Story collage motion

Apple base `da2cb75` uses the Windows `StoryOrbitMotion` pointer normalization and ease curve for the decorative three-image collage. The Mac uses one stationary pointer surface for the whole collage. Each artwork and label keeps its existing travel, and the panel eases from its current pose when the pointer enters or leaves. Scroll updates pause the animation without resetting the pointer pose.

iPhone uses the fused device attitude through Core Motion for the same layer travel. One 30 Hz source runs while the collage is in the active viewport and Reduce Motion is off. The first sample establishes a neutral pose after activation or interface rotation. A 15-degree tilt covers the full range with a 120 ms smoothing constant. The interface axes follow the attached window scene in portrait and both landscape directions. The app keeps samples in memory and uses them only for drawing. iPad retains pointer input.

### Profile image recovery on macOS and iPhone

The Apple integration for chat `01a1f8c4-a871-7fd0-9b52-1159ac1caef1` started at `a7c26bf` and owns `WelcomeService`, the profile image fixtures, and the two Swift SDK lockfiles. The [Swift SDK change](https://github.com/Shahesmaeili/Mizon.API.Swift/commit/8c84513fafa3e0f8ec4f5b69d5db28a682ca8ea9) owns cache invalidation and download cleanup. Server file media still uses the authenticated content endpoint. Direct HTTPS image storage can return a complete response without range support. A failed decode invalidates the affected cache entry and its partial file and allows one fresh download. Metadata, rejected downloads, and decode failures log stages without account or storage identifiers.

The fixtures verify signed-in file media, a Welcome timeout followed by Home recovery, replacement of a same-size corrupt cached image, and HTTPS origins with and without a pending partial download. The deployed profile image requires its own check in a signed-in app.

## Playlist context menu and navigation

Windows reference `221b82d` uses `MusicPlaylistMenu` in `MusicLibraryPanel` and
starts playback through `MusicPlaylistPlaybackService`. The macOS widget offers
Play, View tracks and Copy playlist link through the native context menu. Play
starts at the beginning, follows the server's track order through later pages,
and opens each next track if the current track page is still visible. The link
uses the shared canonical route. VoiceOver exposes the same actions, and Xbox X
and Y can play or copy the focused playlist.

Music Home and nested destinations on Mac and iPhone use the SwiftUI navigation
stack. macOS uses a native Core Animation push for forward and backward
navigation and honors Reduce Motion. iPhone uses SwiftUI's automatic transition,
system Back button and edge gesture. The Welcome profile handoff and sign-in
card flip remain part of their respective screens.

## Playlist details

The Apple screen follows the Windows reference at `221b82d068e7a9230c3158a9d12843901edeaa4d`,
including `MusicPlaylistPage.xaml`, `MusicLibraryBrowser.xaml`, and
`MusicPlaylistDetailsViewModel.cs`. It uses the same hero artwork rule,
right-aligned track metadata, pager, responsive header breakpoints, and
loading, empty, and error states. The screen requests 20 entries per page and
keeps the first page's artwork when paging. Refresh returns to page one.
The playlist CTA opens the selected track while audio is preparing and shares
the existing ordered playlist playback coordinator on both Apple platforms.
Copy uses the canonical deep-link URI. The library and track links keep the
detail page on the navigation stack so Back restores its page and scroll
position. iPhone uses its native cover zoom. macOS uses its existing
Core Animation navigation and the reference pointer timing for track rows.
