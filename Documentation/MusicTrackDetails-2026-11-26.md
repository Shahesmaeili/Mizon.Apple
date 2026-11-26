# Apple track details

Apple base revision: \`3612feb22b3d4487121ac030ce094fcfa9dbae08\`.
Windows reference: \`55d0f5ee21d255515871cb11b7c09bcd603e362e\`, especially
\`Pages/MusicsPage.xaml\`, its partials, \`ViewModels/MusicPageViewModel.cs\`, the
MusicDetails language tables, and \`UserControls/MusicDetailsShowcase.xaml\`.
The existing typed Swift SDK revision is recorded in \`Package.resolved\`.

The original track and track-comment routes share the production detail page.
The route owner retains download and play receipts and the highlight for linked
comments. Playback, playlist continuation, file integrity and cache still use
the authenticated Music Home services and the shared AVPlayer.

- The player uses the reference artwork size, layout thresholds, waveform
  dimensions, bar colors and bilingual typography. Compact layout wraps actions
  and keeps volume usable at iPhone sizes. Short landscape viewports keep the
  cover and playback controls next to one another. Cover preview supports connected
  geometry, zoom, pan and Reduce Motion.
- Credits, reactions, live listeners, stories, album and contributor tracks,
  timed lyrics, and discussion use typed SDK operations. Discussion supports
  sort, cursors, timestamped comments, replies, votes, tags and links.
- Track repeat and stem mix share the current playback owner. The Mac picker
  uses CoreAudio output UIDs. iPhone uses the system audio route picker. The Mac
  has a floating AppKit player and an exportable web shortcut. iPhone has an
  in-app floating player and the native share sheet.
- Windows insight and vocal-segment samples remain illustrative. Comment
  translation, remix and story composition lack a working source action in
  the reference. The Apple app has no live scoped MCP host for Music Details.
  Device-specific volume and battery telemetry are platform-dependent.
- The Xbox adapter uses the active detail surface, waveform seek by triggers,
  focus feedback, and the existing text-entry keyboard for comment text.

Visual equality requires renders of the same track and state on actual Windows
and Apple displays. Simulated layout widths and unsigned builds do not establish
device rotation, AVAudio device selection, controller hardware, or VoiceOver.
