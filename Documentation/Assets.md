# Asset provenance

- `Animation.gif`, `IRANSANS.TTF`, and headphones app-icon artwork: user-owned reference `Shahesmaeili/Mizon.Windows` at `eb809c142c38c4d6cb88a1d75b83dbd61680c351`. GIF pixels and per-frame delays are preserved; no cropping, tinting or added logo overlay.
- `SeagullFluentIcons.otf`: `davidxuang/FluentIcons`, commit `874f2da40bef0c36a009ca081a5a6bd58ea077c2`. This is the font family used by FluentIcons.WinUI, including its regular and RTL glyph encoding. Icon enum offsets come from that same checkout. See ThirdParty/FluentIcons-LICENSE. The Windows project declares FluentIcons.WinUI 2.2.339.1; the bundled upstream font checkout is 2.1.344, rather than claiming a byte-identical NuGet binary.
- `CircleMask.png` and translated Stars / FlipSide algorithms: `Ghost1372/DevWinUI`, commit `609f3395916cff64fc8c06cd7e46e3fbd8765b61`. See ThirdParty/DevWinUI-LICENSE. The Windows project declares DevWinUI 10.4.1; this port uses the audited upstream source revision above.

No license was present in the user's Windows reference, so no new license is invented for that code, font or artwork. Third-party MIT notices are retained. Swift SDK / official Microsoft SignalR dependencies retain their own upstream licenses.
