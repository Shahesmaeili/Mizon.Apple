#if os(macOS) || os(iOS)
import GameController
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import MizonAPIClient
import MizonAppleCore
import SwiftUI

extension MusicHomePage {
    func windowsEditorialRail(width: CGFloat) -> some View {
        VStack(spacing: 18) {
            windowsLibrary(width: width)
            windowsRhythm(width: width)
            windowsNews(width: width)
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    func windowsCommunityRail(width: CGFloat) -> some View {
        VStack(spacing: 18) {
            windowsTrending(width: width)
            windowsFollowing(width: width)
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private func windowsLibrary(width: CGFloat) -> some View {
        let accent = MusicWidgetTint.library
        return railSurface(tint: accent, showsPointerGlow: !model.loading.contains(.library) || model.library != nil) {
            railHeader("LibraryTitle", subtitle: "LibrarySubtitle", symbol: .music, tint: accent)
            if model.loading.contains(.library), model.library == nil {
                railSkeleton(height: 360, label: text("LoadingLibrary"))
            } else {
                let summary = librarySummary(model.library)
                if width >= 560 {
                    HStack(alignment: .top, spacing: 14) {
                        libraryList
                            .frame(width: max(0, (width - 38) * 1.35 / 2.35))
                        summary
                    }
                } else {
                    VStack(spacing: 11) {
                        summary
                        libraryList
                    }
                }
                VStack(spacing: 10) {
                    #if os(macOS)
                    if let status = playlistStatusKey { railCaption(widget(status)) }
                    #endif
                    railFooterButton(.recent, widget("LibraryRecent"), symbol: .clock, tint: accent)
                        .accessibilityHint(widget("LibraryRecentHelp"))
                    railFootnote("LibraryFooter")
                    if let library = model.library, library.totalPlaylistsCount > 0 {
                        railFooterButton(.library, railFormat("LibraryMore", number(library.totalPlaylistsCount)),
                                         symbol: forwardSymbol, tint: accent)
                    }
                }
                .padding(.horizontal, 3)
            }
        }
    }

    private func librarySummary(_ library: MusicLibraryResponse?) -> some View {
        let accent = MusicWidgetTint.library
        return VStack(spacing: 4) {
            HStack(spacing: 7) {
                VStack(alignment: .leading, spacing: 4) {
                    Capsule().fill(accent.ink).frame(width: 25, height: 2)
                    Capsule().fill(accent.color.opacity(0.44)).frame(width: 18, height: 2)
                    Capsule().fill(accent.color.opacity(0.21)).frame(width: 11, height: 2)
                }
                .accessibilityHidden(true)
                Spacer(minLength: 0)
                Text(library.map { number($0.totalPlaylistsCount) } ?? "—")
                    .font(localization.font(35, weight: .light))
                    .tracking(-1.4)
                    .foregroundStyle(accent.ink)
                    .accessibilityLabel(library.map { railFormat("LibraryCount", number($0.totalPlaylistsCount)) }
                                        ?? widget("LibraryCountPending"))
            }
            railCaption(widget("LibraryPersonal"))
            railCaption(library.map { item in
                item.totalPlaylistsCount == 0 ? widget("LibrarySummaryEmpty")
                    : railFormat("LibrarySummary", number(item.totalMusicsCount))
            } ?? widget("LibrarySummaryPending"))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            LinearGradient(stops: [.init(color: accent.color.opacity(0.082), location: 0),
                                   .init(color: accent.color.opacity(0.012), location: 0.65),
                                   .init(color: .clear, location: 1)], startPoint: .topTrailing, endPoint: .bottomLeading),
            in: .rect(cornerRadius: 11)
        )
    }

    private var libraryList: some View {
        let accent = MusicWidgetTint.library
        return VStack(spacing: 8) {
            railCaption(widget("LibraryUpdates"))
            if model.failures.contains(.library) {
                railCaption(widget("LibraryError"), tint: MusicWidgetTint.trending.ink)
                railFooterButton(.refresh(.library), widget("Retry"), tint: accent)
                    .accessibilityLabel(widget("LibraryRetry"))
            } else if let library = model.library {
                if library.playlists.isEmpty {
                    VStack(spacing: 8) {
                        MusicWidgetGlyph(.music, size: 24).foregroundStyle(accent.ink.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        railCaption(widget("LibraryEmpty"), size: 11)
                        railCaption(widget("LibraryCreateHint"))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 13)
                    .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(accent.color.opacity(0.094)) }
                } else {
                    VStack(spacing: 6) {
                        ForEach(library.playlists, id: \.publicId) { playlist in
                            control(.playlist(playlist.publicId)) { libraryRow(playlist) }
                                .buttonStyle(MusicWidgetButtonStyle(tint: accent, radius: 11))
                                #if os(macOS)
                                .contextMenu { libraryPlaylistMenu(playlist) }
                                .accessibilityHint(widget("LibraryPlaylistHelp"))
                                .accessibilityActions { libraryPlaylistMenu(playlist) }
                                #endif
                        }
                    }
                }
            }
        }
    }

    #if os(macOS)
    @ViewBuilder private func libraryPlaylistMenu(_ playlist: MusicLibraryPlaylistItemResponse) -> some View {
        Button { activate(.playPlaylist(playlist.publicId)) } label: {
            Label(widget("PlaylistPlay"), systemImage: "play")
        }
        .disabled(playlist.musicsCount <= 0 || model.playlistPlaybackStatus == .preparing)
        Button { activate(.playlist(playlist.publicId)) } label: {
            Label(widget("PlaylistOpen"), systemImage: "music.note")
        }
        Divider()
        Button { activate(.copyPlaylistLink(playlist.publicId)) } label: {
            Label(widget("PlaylistCopy"), systemImage: "link")
        }
    }
    #endif

    private func libraryRow(_ playlist: MusicLibraryPlaylistItemResponse) -> some View {
        let accent = MusicWidgetTint.library
        return HStack(spacing: 9) {
            VStack(spacing: 5) {
                railCaption(playlist.title, size: 12, weight: .semibold, tint: .primary).lineLimit(1)
                HStack(spacing: 4) {
                    railCaption(railFormat("TracksCount", number(playlist.musicsCount))).lineLimit(1)
                    MusicWidgetGlyph(.music, size: 10).foregroundStyle(accent.ink.opacity(0.7))
                }
            }
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 7).fill(accent.color.opacity(0.13))
                    .frame(width: 39, height: 43).offset(y: -3)
                MusicArtwork(mediaID: playlist.lastMusicCoverMediaPublicId, model: model, symbol: "music.note")
                    .frame(width: 48, height: 48).clipShape(.rect(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(accent.color.opacity(0.14)) }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(minHeight: 68)
        .musicWidgetInset()
    }

    private static let rhythmDays = [(38, 10), (54, 18), (46, 10), (66, 26), (52, 16), (72, 32), (62, 20)]

    private func windowsRhythm(width: CGFloat) -> some View {
        let accent = MusicWidgetTint.rhythm
        return railSurface(tint: accent) {
            railHeader("RhythmTitle", subtitle: "RhythmSubtitle", symbol: .trendingArrow, tint: accent)
            if width >= 560 {
                HStack(alignment: .top, spacing: 20) {
                    rhythmChart.frame(width: max(0, (width - 44) * 1.6 / 2.6))
                    rhythmSummary
                }
            } else {
                VStack(spacing: 8) {
                    rhythmSummary
                    rhythmChart
                }
            }
            railFootnote("RhythmDemo").padding(.horizontal, 3)
        }
    }

    private var rhythmSummary: some View {
        let accent = MusicWidgetTint.rhythm
        let music = Self.rhythmDays.reduce(0) { $0 + $1.0 }
        let video = Self.rhythmDays.reduce(0) { $0 + $1.1 }
        let total = music + video
        let percent = Int((Double(total - 442) / 442 * 100).rounded())
        return VStack(spacing: 6) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(rhythmTime(total, padHours: true))
                    .font(localization.font(32, weight: .light)).tracking(-1.6)
                    .accessibilityLabel(railFormat("RhythmTotal", number(total / 60), number(total % 60)))
                Text(widget("RhythmHours")).font(localization.font(10)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            HStack(spacing: 7) {
                Text(railFormat("RhythmPercent", number(percent)))
                    .font(localization.font(11, weight: .semibold))
                    .foregroundStyle(accent.ink)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(accent.color.opacity(0.074), in: .rect(cornerRadius: 7))
                    .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(accent.color.opacity(0.14)) }
                railCaption(widget("RhythmComparison"), size: 8)
            }
            HStack(spacing: 7) {
                rhythmLegend("MusicVideo", time: video, tint: .video)
                rhythmLegend("Music", time: music, tint: accent)
            }
        }
    }

    private func rhythmLegend(_ key: String, time: Int, tint: MusicWidgetTint) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 4) {
                railCaption(widget(key), size: 8)
                Circle().fill(tint.ink).frame(width: 4, height: 4)
            }
            Text(rhythmTime(time)).font(localization.font(12)).foregroundStyle(tint.ink)
        }
        .padding(.horizontal, 2)
    }

    private var rhythmChart: some View {
        let accent = MusicWidgetTint.rhythm
        let day = Self.rhythmDays.indices.contains(selectedRhythmDay) ? selectedRhythmDay : 5
        let selected = Self.rhythmDays[day]
        return VStack(spacing: 6) {
            HStack(spacing: 3) {
                ForEach(Self.rhythmDays.indices, id: \.self) { index in
                    rhythmDay(index, selected: day == index)
                }
            }
            .environment(\.layoutDirection, localization.isPersian ? .rightToLeft : .leftToRight)
            .background(alignment: .top) {
                VStack(spacing: 0) {
                    ForEach(0..<3) { line in
                        Rectangle().fill(MusicWidgetTint.stroke.opacity(line == 2 ? 1 : 0.46))
                            .frame(height: 1).frame(height: 30, alignment: .bottom)
                    }
                }
                .accessibilityHidden(true)
            }
            HStack(spacing: 6) {
                Text(rhythmTime(selected.0 + selected.1))
                    .font(localization.font(12, weight: .semibold)).foregroundStyle(accent.ink)
                    .accessibilityLabel(rhythmDayLabel(day))
                railCaption(widget("Day\(day)")).accessibilityHidden(true)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(accent.color.opacity(0.027), in: .rect(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(accent.color.opacity(0.086)) }
        }
    }

    private func rhythmDay(_ index: Int, selected: Bool) -> some View {
        let accent = MusicWidgetTint.rhythm
        let (music, video) = Self.rhythmDays[index]
        return control(.rhythmDay(index)) {
            VStack(spacing: 6) {
                VStack(spacing: 2) {
                    UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 1,
                                           bottomTrailingRadius: 1, topTrailingRadius: 4)
                        .fill(MusicWidgetTint.video.ink.opacity(0.85))
                        .frame(height: Double(video) * 84 / 104)
                    UnevenRoundedRectangle(topLeadingRadius: 1, bottomLeadingRadius: 4,
                                           bottomTrailingRadius: 4, topTrailingRadius: 1)
                        .fill(.linearGradient(colors: [musicColor("ABEDD9"), musicColor("6DBBA6")],
                                              startPoint: .top, endPoint: .bottom))
                        .frame(height: Double(music) * 84 / 104)
                }
                .frame(width: 12)
                .padding(.bottom, 1)
                .frame(height: 90, alignment: .bottom)
                Text(widget("Day\(index)Short")).font(localization.font(9)).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 1).padding(.bottom, 7)
            .frame(maxWidth: .infinity)
            .background(accent.color.opacity(selected ? 0.05 : 0), in: .rect(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(accent.ink.opacity(selected ? 0.28 : 0)) }
        }
        .buttonStyle(MusicWidgetButtonStyle(tint: accent, radius: 7))
        .accessibilityLabel(rhythmDayLabel(index))
        .accessibilityHint(widget("RhythmDayHelp"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(rhythmDayLabel(index))
    }

    private func rhythmDayLabel(_ index: Int) -> String {
        let (music, video) = Self.rhythmDays[index]
        return railFormat("RhythmDayTooltip", widget("Day\(index)"), rhythmTime(music + video),
                          rhythmTime(music), rhythmTime(video))
    }

    private func rhythmTime(_ minutes: Int, padHours: Bool = false) -> String {
        String(format: padHours ? "%02d:%02d" : "%d:%02d", minutes / 60, minutes % 60)
    }

    private func windowsNews(width: CGFloat) -> some View {
        let accent = MusicWidgetTint.news
        let slideDistance = min(48, max(20, (width - 24) * 0.14))
        let artwork = ["slow-motion", "artist-stage-02", "city-lights", "quiet-room"]
        return railSurface(tint: accent) {
            railHeader("NewsTitle", subtitle: "NewsSubtitle", symbol: .news, tint: accent, badge: widget("Demo"))
            MusicNewsAutoAdvance(index: $newsIndex, paused: newsPaused || newsWidgetHasFocus,
                                 count: artwork.count, isPersian: localization.isPersian) { index, direction in
                newsSlide(index, artwork: artwork[index], width: max(0, width - 24))
                    .id(index)
                    .transition(.asymmetric(
                        insertion: .offset(x: direction * slideDistance).combined(with: .opacity),
                        removal: .offset(x: -direction * slideDistance).combined(with: .opacity)
                    ))
            }
            .clipShape(.rect(cornerRadius: 11))
            VStack(spacing: 10) {
                HStack(spacing: 5) {
                    ForEach(artwork.indices, id: \.self) { index in
                        control(.selectNews(index)) {
                            Capsule().fill(accent.color.opacity(index == newsIndex ? 1 : 0.24))
                                .frame(height: 3).padding(.horizontal, 3).frame(height: 18)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(MusicWidgetButtonStyle(tint: accent, radius: 7))
                        .accessibilityLabel(railFormat("NewsIndicator", number(index + 1), widget("News\(index)Title")))
                        .accessibilityAddTraits(index == newsIndex ? .isSelected : [])
                    }
                }
                .environment(\.layoutDirection, localization.isPersian ? .rightToLeft : .leftToRight)
                HStack(spacing: 6) {
                    newsControl(.nextNews, symbol: localization.isPersian ? .chevronLeft : .chevronRight, description: "NewsNext")
                    HStack(spacing: 8) {
                        Text(String(format: "%02d / %02d", newsIndex + 1, artwork.count))
                            .font(localization.font(10)).foregroundStyle(accent.ink).lineLimit(1)
                            .accessibilityLabel(railFormat("NewsCounter", number(newsIndex + 1), number(artwork.count)))
                        newsRotationControl()
                    }
                    .frame(maxWidth: .infinity)
                    newsControl(.previousNews, symbol: localization.isPersian ? .chevronRight : .chevronLeft,
                                description: "NewsPrevious")
                }
                railFooterButton(.news(newsIndex), widget("NewsRead"), symbol: forwardSymbol, tint: accent)
                    .accessibilityHint(widget("NewsReadDemo"))
                railCaption(widget("NewsFooter"), size: 9)
            }
            .padding(.horizontal, 3)
        }
    }

    private func newsRotationControl() -> some View {
        MusicNewsRotationControl(paused: newsPaused) { symbol, description, enabled in
            newsControl(.toggleNews, symbol: symbol, description: description).disabled(!enabled)
        }
    }

    private func newsControl(_ action: Action, symbol: MusicWidgetSymbol, description: String) -> some View {
        control(action) {
            MusicWidgetGlyph(symbol, size: action == .toggleNews ? 12 : 14)
                .foregroundStyle(MusicWidgetTint.news.ink)
                .frame(width: 32, height: 32)
                .background(MusicWidgetTint.news.color.opacity(0.027), in: .rect(cornerRadius: 10))
        }
        .buttonStyle(MusicWidgetButtonStyle(tint: .news, radius: 10))
        .accessibilityLabel(widget(description))
        .help(widget(description))
    }

    private func newsSlide(_ index: Int, artwork: String, width: CGFloat) -> some View {
        let wide = width >= 500
        let artworkHeight = wide ? 220 : min(174, max(112, width * 0.58))
        let accent = MusicWidgetTint.news
        let art = ZStack(alignment: .topTrailing) {
            assetImage(artwork)
            LinearGradient(stops: [.init(color: musicColor("17243A").opacity(0.078), location: 0),
                                   .init(color: musicColor("17243A").opacity(0.063), location: 0.45),
                                   .init(color: musicColor("101A2B").opacity(0.8), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            Text(widget("News\(index)Category"))
                .font(localization.font(9)).foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(musicColor("192638").opacity(0.90), in: .rect(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.19)) }
                .padding(10)
            HStack(spacing: 6) {
                MusicWidgetGlyph(.news, size: 14)
                railCaption(railFormat("NewsEdition", String(format: "%02d", index + 1)), size: 9, tint: .white)
            }
            .foregroundStyle(.white).padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(height: artworkHeight)
        .background(musicColor("121C2B"))
        .clipped()
        let copy = VStack(spacing: 8) {
            railCaption(widget("News\(index)Title"), size: 13, weight: .semibold, tint: .primary)
                .lineLimit(2).frame(minHeight: 46, alignment: .top)
                .accessibilityAddTraits(.isHeader)
            railCaption(widget("News\(index)Summary")).lineLimit(2).frame(minHeight: 38, alignment: .top)
            HStack(spacing: 6) {
                railCaption(railFormat("NewsMinutes", number(index == 1 ? 3 : 2)), size: 9, tint: accent.ink)
                MusicWidgetGlyph(.clock, size: 11).foregroundStyle(accent.ink)
            }
            .padding(.top, 2)
        }
        .padding(12)
        return Group {
            if wide {
                HStack(spacing: 0) { art.frame(width: width / 2.2); copy }
            } else {
                VStack(spacing: 0) { art; copy }
            }
        }
        .musicWidgetInset()
    }

    private func windowsTrending(width: CGFloat) -> some View {
        let accent = MusicWidgetTint.trending
        let samples = Array(discovery.sorted { $0.likes > $1.likes }.prefix(6))
        return railSurface(tint: accent) {
            railHeader("TrendingTitle", subtitle: "TrendingSubtitle", symbol: .fire, tint: accent,
                       badge: String(format: "%02d", samples.count))
            if let leading = samples.first {
                let wide = width >= 560 && samples.count > 1
                let rows = VStack(spacing: 5) {
                    ForEach(Array(samples.dropFirst().enumerated()), id: \.element.id) { index, sample in
                        trendRow(sample, rank: index + 2)
                    }
                }
                if wide {
                    HStack(alignment: .top, spacing: 12) {
                        trendLeading(leading, height: max(190, CGFloat(samples.count - 1) * 67 - 5))
                            .frame(width: max(0, (width - 36) * 0.45))
                        rows
                    }
                } else {
                    VStack(spacing: 8) {
                        trendLeading(leading, height: 190)
                        rows
                    }
                }
            }
            railFootnote("TrendingFooter").padding(.horizontal, 3)
        }
    }

    // The Windows chart's sample tiles have no MusicPublicId until supplied by the catalog.
    private func trendLeading(_ sample: MusicDiscoverySample, height: CGFloat) -> some View {
        let accent = MusicWidgetTint.trending
        return ZStack {
            assetImage(sample.image)
            LinearGradient(stops: [.init(color: musicColor("090D14").opacity(0.094), location: 0),
                                   .init(color: musicColor("090D14").opacity(0.149), location: 0.3),
                                   .init(color: musicColor("101720").opacity(0.804), location: 0.72),
                                   .init(color: musicColor("101720").opacity(0.949), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 7) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("01").font(localization.font(32, weight: .semibold)).tracking(-1.92)
                            .foregroundStyle(.white.opacity(0.92))
                        Capsule().fill(accent.ink).frame(width: 20, height: 2)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        MusicWidgetGlyph(.fire, size: 10).foregroundStyle(accent.color)
                        Text(widget("TrendingTop")).font(localization.font(8)).foregroundStyle(musicColor("F3DECB"))
                    }
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(musicColor("1B2029").opacity(0.88), in: .rect(cornerRadius: 7))
                    .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(accent.color.opacity(0.26)) }
                }
                Spacer(minLength: 0)
                VStack(spacing: 3) {
                    railCaption(localized(sample.title, sample.persianTitle), size: 16, weight: .bold, tint: .white).lineLimit(2)
                    railCaption(sample.artist, tint: .white)
                }
                HStack(spacing: 8) {
                    MusicWidgetGlyph(.arrowUpRight, size: 11).foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(.white.opacity(0.094), in: .rect(cornerRadius: 8))
                        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.14)) }
                    railCaption(rhythmTime(sample.duration), size: 9, tint: .white)
                    HStack(spacing: 5) {
                        Text(compactLikes(sample.likes)).font(localization.font(11, weight: .semibold))
                            .foregroundStyle(musicColor("F3DECB"))
                        MusicWidgetGlyph(.heart, size: 11).foregroundStyle(accent.color)
                    }
                }
                .padding(.top, 2)
            }
            .padding(12)
        }
        .frame(height: height)
        .background(musicColor("18212A"))
        .clipShape(.rect(cornerRadius: 13))
        .accessibilityElement(children: .combine)
    }

    private func trendRow(_ sample: MusicDiscoverySample, rank: Int) -> some View {
        let accent = MusicWidgetTint.trending
        return HStack(spacing: 8) {
            VStack(spacing: 5) {
                Text(String(format: "%02d", rank)).font(localization.font(15, weight: .semibold)).foregroundStyle(.secondary)
                Capsule().fill(accent.ink.opacity(0.4)).frame(width: 9, height: 2)
            }
            .frame(width: 22)
            VStack(spacing: 2) {
                railCaption(localized(sample.title, sample.persianTitle), size: 11, weight: .semibold, tint: .primary)
                    .lineLimit(1)
                railCaption(sample.artist, size: 8).lineLimit(1)
                HStack(spacing: 5) {
                    railCaption(rhythmTime(sample.duration), size: 8)
                    Text(compactLikes(sample.likes)).font(localization.font(8)).foregroundStyle(accent.ink)
                    MusicWidgetGlyph(.heart, size: 8).foregroundStyle(accent.ink.opacity(0.8))
                }
            }
            assetImage(sample.image, maximumPixelSize: 144).frame(width: 42, height: 42).clipShape(.rect(cornerRadius: 8))
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .frame(minHeight: 62)
        .musicWidgetInset()
        .accessibilityElement(children: .combine)
    }

    private func windowsFollowing(width: CGFloat) -> some View {
        let accent = MusicWidgetTint.friends
        let activity = model.activity
        let items = Array((activity?.activities ?? []).prefix(4))
        return railSurface(tint: accent, showsPointerGlow: !model.loading.contains(.activity) || activity != nil) {
            railHeader("FollowingTitle", subtitle: "FollowingSubtitle", symbol: .people, tint: accent,
                       badge: String(format: "%02d", items.count))
            if model.loading.contains(.activity), activity == nil {
                railSkeleton(height: 320, label: text("LoadingFriends"))
            } else {
                if model.failures.contains(.activity) {
                    VStack(spacing: 12) {
                        railCaption(widget("FollowingError"), size: 11)
                        railFooterButton(.refresh(.activity), widget("Retry"), tint: accent)
                            .accessibilityLabel(widget("FollowingRetry"))
                    }
                    .padding(10)
                } else if items.isEmpty, let activity {
                    followingEmpty(hasFollowings: activity.hasFollowings)
                } else {
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 10),
                                        count: width >= 560 && items.count > 1 ? 2 : 1)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                        ForEach(items, id: \.activityId) { item in
                            control(.activity(item.activityId)) { MusicActivityWidgetCard(item: item, model: model) }
                                .buttonStyle(MusicWidgetButtonStyle(tint: accent, radius: 11))
                                .disabled(activityDestination(item) == nil)
                        }
                    }
                }
                VStack(spacing: 10) {
                    railFootnote("FollowingFooter")
                    if let activity, activity.hasMore || activity.activities.count > 4 {
                        railFooterButton(.moreActivity, widget("FollowingMore"), symbol: forwardSymbol, tint: accent)
                            .accessibilityHint(widget("FollowingMoreHelp"))
                    }
                }
                .padding(.horizontal, 3)
            }
        }
    }

    private func followingEmpty(hasFollowings: Bool) -> some View {
        VStack(spacing: 10) {
            MusicWidgetGlyph(.people, size: 28)
                .foregroundStyle(MusicWidgetTint.friends.ink.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .trailing)
            railCaption(widget(hasFollowings ? "FollowingEmptyTitle" : "FollowingNoFriendsTitle"),
                        size: 12, weight: .semibold)
            railCaption(widget(hasFollowings ? "FollowingEmptyMusicDescription" : "FollowingNoFriendsDescription"), size: 11)
        }
        .padding(.horizontal, 12).padding(.vertical, 18)
        .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(MusicWidgetTint.friends.color.opacity(0.094)) }
    }

    private func railSurface<Content: View>(tint: MusicWidgetTint, showsPointerGlow: Bool = true,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 12, content: content)
            .frame(maxWidth: .infinity)
            .padding(12)
            .musicPanel(cornerRadius: 16)
            .overlay { MusicWidgetPointerGlow(accent: tint.color, enabled: showsPointerGlow) }
    }

    private func railHeader(_ title: String, subtitle: String, symbol: MusicWidgetSymbol,
                            tint: MusicWidgetTint, badge: String? = nil) -> some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                VStack(spacing: 5) {
                    Text(widget(title))
                        .font(localization.font(14, weight: .semibold))
                        .foregroundStyle(.linearGradient(colors: [.primary, tint.ink],
                                                         startPoint: .topLeading, endPoint: .topTrailing))
                        .frame(minHeight: 24, alignment: .center)
                        .frame(maxWidth: .infinity, alignment: localization.isPersian ? .trailing : .leading)
                        .multilineTextAlignment(localization.isPersian ? .trailing : .leading)
                        .environment(\.layoutDirection, .leftToRight)
                        .accessibilityAddTraits(.isHeader)
                    Capsule().fill(.linearGradient(colors: [.clear, tint.color.opacity(0.25)],
                                                   startPoint: .topLeading, endPoint: .topTrailing))
                        .frame(height: 2)
                        .overlay(alignment: localization.isPersian ? .trailing : .leading) {
                            Capsule().fill(tint.color.opacity(0.8)).frame(width: 22)
                        }
                }
                MusicWidgetGlyph(symbol, size: 15)
                    .foregroundStyle(tint.ink)
                    .frame(width: 30, height: 30)
                    .background(.linearGradient(colors: [tint.color.opacity(0.14), .clear],
                                                startPoint: .topTrailing, endPoint: .bottomLeading),
                                in: .rect(cornerRadius: 10))
                    .musicPanel(cornerRadius: 10)
            }
            .environment(\.layoutDirection, localization.isPersian ? .leftToRight : .rightToLeft)
            HStack(spacing: 8) {
                if let badge {
                    Text(badge).font(localization.font(9)).foregroundStyle(tint.ink)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(tint.color.opacity(0.055), in: .rect(cornerRadius: 5))
                        .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(tint.color.opacity(0.082)) }
                }
                railCaption(widget(subtitle))
            }
        }
        .padding(.horizontal, 3).padding(.top, 2)
    }

    private func railFootnote(_ key: String) -> some View {
        HStack(spacing: 7) {
            Rectangle().fill(MusicWidgetTint.stroke).frame(height: 1)
                .frame(maxWidth: .infinity)
            Text(widget(key)).font(localization.font(9)).foregroundStyle(.secondary)
                .multilineTextAlignment(localization.isPersian ? .trailing : .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func railCaption(_ value: String, size: CGFloat = 10, weight: Font.Weight = .regular,
                             tint: Color = .secondary) -> some View {
        Text(value).font(localization.font(size, weight: weight)).foregroundStyle(tint)
            .multilineTextAlignment(localization.isPersian ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: localization.isPersian ? .trailing : .leading)
    }

    private func railFooterButton(_ action: Action, _ title: String, symbol: MusicWidgetSymbol? = nil,
                                  tint: MusicWidgetTint) -> some View {
        control(action) {
            HStack(spacing: 8) {
                if let symbol {
                    MusicWidgetGlyph(symbol, size: 13).foregroundStyle(tint.ink)
                }
                railCaption(title, size: 11, tint: tint.ink)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 38)
            .background(tint.color.opacity(0.027), in: .rect(cornerRadius: 11))
        }
        .buttonStyle(MusicWidgetButtonStyle(tint: tint, radius: 11))
    }

    private func railSkeleton(height: CGFloat, label: String) -> some View {
        VStack(spacing: 10) {
            ForEach(0..<3) { _ in
                VStack(alignment: .leading, spacing: 9) {
                    RoundedRectangle(cornerRadius: 4).fill(MusicWidgetTint.stroke).frame(width: 72, height: 9)
                    RoundedRectangle(cornerRadius: 4).fill(MusicWidgetTint.stroke.opacity(0.58)).frame(width: 119, height: 7)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(12)
                .background(MusicWidgetTint.inset, in: .rect(cornerRadius: 10))
            }
        }
        .frame(height: height - 72)
        .accessibilityElement()
        .accessibilityLabel(label)
    }

    private func assetImage(_ name: String, maximumPixelSize: Int = 960) -> some View {
        GeometryReader { proxy in
            MusicLocalArtwork(name, maximumPixelSize: maximumPixelSize).scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height).clipped()
        }
        .accessibilityHidden(true)
    }

    private func number<T: BinaryInteger>(_ value: T) -> String {
        value.formatted(IntegerFormatStyle<T>(locale: Locale(identifier: localization.isPersian ? "fa-IR" : "en-US")))
    }

    private func compactLikes(_ count: Int) -> String {
        let style = FloatingPointFormatStyle<Double>(locale: Locale(identifier: "en-US"))
            .precision(.fractionLength(0...1))
        if count >= 1_000_000 { return (Double(count) / 1_000_000).formatted(style) + "M" }
        if count >= 1000 { return (Double(count) / 1000).formatted(style) + "K" }
        return number(count)
    }

    private func railFormat(_ key: String, _ arguments: String...) -> String {
        formatMusicWidget(widget(key), arguments)
    }

    private var forwardSymbol: MusicWidgetSymbol { localization.isPersian ? .arrowLeft : .arrowRight }
}

struct MusicHomeAllActivityPage: View {
    private enum Target: Hashable { case activity(String), more, retry, close }

    let model: MusicHomeViewModel
    let deepLink: MizonDeepLinkRouter.AuthorizedLink?
    let open: (FollowingActivityItemResponse) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var paginationRequest = 0
    @State private var response: FollowingActivitiesResponse?
    @State private var loading = true
    @State private var failed = false
    @State private var linkResolved = false
    @FocusState private var focus: Target?
    private var localization = AuthLocalization()

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(response?.activities ?? [], id: \.activityId) { item in
                            if canOpen(item) {
                                Button { open(item) } label: { MusicActivityWidgetCard(item: item, model: model) }
                                    .buttonStyle(MusicWidgetButtonStyle(tint: .friends, radius: 11))
                                    .focusable().focused($focus, equals: .activity(item.activityId))
                                    .id(Target.activity(item.activityId))
                            } else {
                                MusicActivityWidgetCard(item: item, model: model)
                            }
                        }
                        if loading {
                            ProgressView().padding(12)
                        } else if failed {
                            Text(widget("FollowingError")).foregroundStyle(.secondary)
                            Button(widget("FollowingRetry")) { paginationRequest += 1 }
                                .buttonStyle(.glass)
                                .focusable().focused($focus, equals: .retry).id(Target.retry)
                        } else if response?.hasMore == true, response?.nextCursor != nil {
                            Button(widget("FollowingMore")) { paginationRequest += 1 }
                                .buttonStyle(.glass)
                                .focusable().focused($focus, equals: .more).id(Target.more)
                        } else if response?.activities.isEmpty == true {
                            ContentUnavailableView(widget("FollowingEmptyTitle"), systemImage: "person.2",
                                                   description: Text(widget("FollowingEmptyDescription")))
                        }
                    }
                    .padding(16)
                }
                .onChange(of: focus) { _, value in
                    if let value, value != .close { scroll.scrollTo(value, anchor: .center) }
                }
            }
            .navigationTitle(widget("FollowingMore"))
            .toolbar {
                Button(widget("Close")) { dismiss() }.keyboardShortcut(.cancelAction)
                    .focusable().focused($focus, equals: .close)
            }
        }
        .task(id: paginationRequest) { await loadPage() }
        .task(id: scenePhase) {
            if scenePhase == .active { await observeController() }
        }
        .onDisappear {
            if let deepLink, !linkResolved {
                linkResolved = true
                MizonDeepLinkRouter.shared.fail(deepLink, code: "page_changed",
                                               message: "The active page changed before navigation completed.")
            }
        }
    }

    private var targets: [Target] {
        let items = (response?.activities ?? []).filter(canOpen).map { Target.activity($0.activityId) }
        var controls: [Target] = [.close] + items
        if !loading {
            if failed { controls.append(.retry) }
            else if response?.hasMore == true, response?.nextCursor != nil { controls.append(.more) }
        }
        return controls
    }

    private func loadPage() async {
        loading = true
        failed = false
        defer { if !Task.isCancelled { loading = false } }
        let cursor = response?.nextCursor
        do {
            var next = try await model.service.allFollowingActivity(after: cursor, session: model.session)
            try Task.checkCancellation()
            if let response {
                var identifiers = Set(response.activities.map(\.activityId))
                next.activities = response.activities + next.activities.filter { identifiers.insert($0.activityId).inserted }
            }
            if next.nextCursor == cursor {
                next.hasMore = false
                next.nextCursor = nil
            }
            response = next
            if let deepLink, !linkResolved {
                linkResolved = true
                MizonDeepLinkRouter.shared.complete(deepLink, stage: .completed)
            }
        } catch {
            if !Task.isCancelled {
                failed = true
                if let deepLink, !linkResolved {
                    linkResolved = true
                    MizonDeepLinkRouter.shared.fail(deepLink, code: "page_unavailable",
                                                   message: "The following activities could not be loaded.")
                }
            }
        }
    }

    private func canOpen(_ item: FollowingActivityItemResponse) -> Bool {
        item.storyPublicId != nil || item.musicPlaylistPublicId != nil || item.musicPublicId != nil
    }

    private func widget(_ key: String) -> String { localization.string(key, table: "MusicWidgets") }

    private func observeController() async {
        var previous: GCExtendedGamepad?
        var armed = false
        var held = 0
        while !Task.isCancelled {
            let current = GCController.controllers().first(where: { $0.extendedGamepad != nil })?.extendedGamepad
            if current !== previous {
                previous = current
                armed = false
                held = 0
            }
            if let pad = current {
                let up = max(pad.dpad.yAxis.value, pad.leftThumbstick.yAxis.value)
                let down = min(pad.dpad.yAxis.value, pad.leftThumbstick.yAxis.value)
                let input = pad.buttonB.isPressed ? 1 : pad.buttonA.isPressed ? 2 : up > 0.65 ? 3 : down < -0.65 ? 4 : 0
                if input == 0 { armed = true; held = 0 }
                if armed, held == 0, input != 0 {
                    held = input
                    let controls = targets
                    switch input {
                    case 1: dismiss(); return
                    case 2:
                        switch focus {
                        case .close: dismiss(); return
                        case .more where controls.contains(.more), .retry where controls.contains(.retry):
                            paginationRequest += 1
                        case .activity(let id):
                            if let item = response?.activities.first(where: { $0.activityId == id }), canOpen(item) {
                                open(item)
                                return
                            }
                        default: focus = controls.first
                        }
                    default:
                        let next = focus.flatMap { controls.firstIndex(of: $0) }.map {
                            min(controls.count - 1, max(0, $0 + (input == 3 ? -1 : 1)))
                        } ?? 0
                        focus = controls[next]
                    }
                }
            }
            do { try await Task.sleep(for: .milliseconds(32)) } catch { break }
        }
    }
}

private struct MusicActivityWidgetCard: View {
    let item: FollowingActivityItemResponse
    let model: MusicHomeViewModel
    private var localization = AuthLocalization()

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 9) {
                VStack(spacing: 2) {
                    caption(displayName, size: 12, primary: true).lineLimit(1)
                    caption(widget(action.key), size: 9).lineLimit(2)
                }
                MusicArtwork(mediaID: item.profileMediaPublicId, model: model, symbol: "person")
                    .frame(width: 30, height: 30).clipShape(.circle)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.063), in: .rect(cornerRadius: 13))
                    .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(action.accent.opacity(0.65)) }
            }
            HStack(spacing: 5) {
                Rectangle().fill(MusicWidgetTint.stroke.opacity(0.7)).frame(height: 1)
                Capsule().fill(action.accent.opacity(0.65)).frame(width: 16, height: 1)
            }
            HStack(spacing: 10) {
                VStack(spacing: 4) {
                    caption(content, size: 12, primary: true).lineLimit(1)
                    caption(subtitle, size: 9).lineLimit(1)
                    HStack(spacing: 5) {
                        Text(widget(kind)).font(localization.font(8))
                        MusicWidgetGlyph(action.symbol, size: 10)
                    }
                    .foregroundStyle(MusicWidgetTint.friends.ink)
                    .padding(.top, 2)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                MusicArtwork(mediaID: item.coverMediaPublicId, model: model, symbol: "music.note")
                    .frame(width: 64, height: 64)
                    .overlay(alignment: .bottom) {
                        LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 28)
                    }
                    .overlay(alignment: .bottomLeading) {
                        MusicWidgetGlyph(.arrowUpRight, size: 8).foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(musicColor("16212A").opacity(0.68), in: .rect(cornerRadius: 6))
                            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.19)) }
                            .padding(4)
                    }
                    .clipShape(.rect(cornerRadius: 10))
            }
            caption(relativeTime, size: 9)
        }
        .padding(11)
        .background(.linearGradient(colors: [action.accent.opacity(0.08), .clear],
                                    startPoint: .topTrailing, endPoint: .bottomLeading),
                    in: .rect(cornerRadius: 11))
        .musicWidgetInset()
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .combine)
    }

    private var displayName: String {
        let name = [item.firstName, item.lastName].compactMap { $0 }.joined(separator: " ")
        return [item.nickName, name, item.username].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? widget("MizonUser")
    }

    private var content: String {
        let titles = localization.isPersian ? [item.persianTitle, item.title] : [item.title, item.persianTitle]
        return titles.compactMap { $0 }.first { !$0.isEmpty } ?? (kind == "Story" ? widget("StoryNew") : "")
    }

    private var kind: String {
        if item.storyPublicId != nil { return "Story" }
        if item.musicPlaylistPublicId != nil { return "Playlist" }
        return item.domain == "music-video" ? "MusicVideo" : "Track"
    }

    private var action: (key: String, symbol: MusicWidgetSymbol, accent: Color) {
        switch item.activityType {
        case "comment": ("ActivityComment", .comment, musicColor("8DBEF2"))
        case "like": ("ActivityLike", .heart, musicColor("EEA6BE"))
        case "reaction": ("ActivityReaction", .emoji, musicColor("F1CD86"))
        case "play": (item.domain == "music-video" ? "ActivityWatch" : "ActivityPlay", .headphones, musicColor("9DCEC4"))
        case "playlist-created": ("ActivityPlaylist", .music2, musicColor("C3A9EF"))
        case "story-posted": ("ActivityStory", .image, musicColor("AEB9F6"))
        default: ("ActivityNew", .people, musicColor("9DCEC4"))
        }
    }

    private var subtitle: String {
        switch item.activityType {
        case "comment": item.commentText ?? ""
        case "reaction": item.reactionEmoji ?? widget("ActivityReactionFallback")
        case "playlist-created": formatMusicWidget(widget("TracksCount"), [number(item.playlistMusicsCount ?? 0)])
        case "story-posted":
            if let count = item.taggedMusicsCount, count > 0 {
                formatMusicWidget(widget("ActivityStorySummary"), [number(count), widget(item.storyViewedByMe ? "Viewed" : "New")])
            } else {
                widget("StoryNew")
            }
        default: localization.isPersian && !(item.persianTitle ?? "").isEmpty ? item.title : widget(kind)
        }
    }

    private var relativeTime: String {
        let age = Date().timeIntervalSince(item.createDateTime)
        if age < 60 { return widget("JustNow") }
        if age < 3600 { return formatMusicWidget(widget("MinutesAgo"), [number(Int(age / 60))]) }
        if age < 86400 { return formatMusicWidget(widget("HoursAgo"), [number(Int(age / 3600))]) }
        if age < 604800 { return formatMusicWidget(widget("DaysAgo"), [number(Int(age / 86400))]) }
        return item.createDateTime.formatted(Date.FormatStyle(date: .numeric, time: .omitted).locale(locale))
    }

    private var locale: Locale { Locale(identifier: localization.isPersian ? "fa-IR" : "en-US") }
    private func number(_ n: Int) -> String { n.formatted(.number.locale(locale)) }
    private func widget(_ key: String) -> String { localization.string(key, table: "MusicWidgets") }
    private func caption(_ value: String, size: CGFloat, primary: Bool = false) -> some View {
        Text(value).font(localization.font(size, weight: primary ? .semibold : .regular))
            .foregroundStyle(primary ? Color.primary : Color.secondary)
            .multilineTextAlignment(localization.isPersian ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: localization.isPersian ? .trailing : .leading)
    }
}

private struct MusicNewsAutoAdvance<Slide: View>: View {
    @Binding var index: Int
    let paused: Bool
    let count: Int
    let isPersian: Bool
    @ViewBuilder let slide: (Int, CGFloat) -> Slide
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var hovered = false
    @State private var visible = false
    @State private var presentedIndex: Int?
    @State private var direction: CGFloat = 1
    private var shouldRotate: Bool { !paused && !hovered && visible && !reduceMotion && scenePhase == .active }

    var body: some View {
        ZStack {
            slide(presentedIndex ?? index, direction)
        }
        .clipped()
        .onChange(of: index, initial: true) { previous, next in
            let animation: Animation? = reduceMotion || !visible ? nil
                : .timingCurve(0.215, 0.61, 0.355, 1, duration: 0.36)
            withAnimation(animation) {
                let forward = (next - previous + count) % count <= count / 2
                direction = (forward ? 1 : -1) * (isPersian ? -1 : 1)
                presentedIndex = next
            }
        }
        .onHover { hovered = $0 }
        .onScrollVisibilityChange(threshold: 0.05) { visible = $0 }
        .task(id: shouldRotate ? index : -1) {
            guard shouldRotate else { return }
            do {
                try await Task.sleep(for: .seconds(8))
                index = (index + 1) % count
            } catch is CancellationError { }
            catch { }
        }
    }
}

private struct MusicNewsRotationControl<Label: View>: View {
    let paused: Bool
    @ViewBuilder let label: (MusicWidgetSymbol, String, Bool) -> Label
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        label(reduceMotion || paused ? .play : .pause,
              reduceMotion ? "NewsMotionOff" : paused ? "NewsResume" : "NewsPause", !reduceMotion)
    }
}

private enum MusicWidgetSymbol: Int {
    case arrowLeft = 18, arrowRight = 21, arrowUpRight = 22
    case chevronLeft = 84, chevronRight = 85, clock = 90, comment = 96, emoji = 127
    case headphones = 152, heart = 154, image = 158, news = 194, pause = 208, people = 209, play = 234
    case trendingArrow = 479, music = 1087, music2 = 1088, fire = 2052
}

private struct MusicWidgetGlyph: View {
    let symbol: MusicWidgetSymbol
    let size: CGFloat

    init(_ symbol: MusicWidgetSymbol, size: CGFloat) {
        self.symbol = symbol
        self.size = size
    }

    var body: some View {
        let _ = WindowsTypography.registered
        let scalar = UnicodeScalar(0xF0000 + 4 * symbol.rawValue)!
        Text(String(scalar)).font(.custom("SeagullFluentIcons", size: size)).accessibilityHidden(true)
    }
}

private enum MusicWidgetTint {
    case library, rhythm, video, news, trending, friends

    var color: Color { musicColor(hex.dark) }
    var ink: Color { Self.adaptive(dark: musicColor(hex.dark), light: musicColor(hex.light)) }

    private var hex: (dark: String, light: String) {
        switch self {
        case .library: ("C7A0F6", "5E3289")
        case .rhythm: ("91DEC5", "12604D")
        case .video: ("B9A3EC", "503485")
        case .news: ("94C9F5", "175280")
        case .trending: ("F2B288", "8B3B1D")
        case .friends: ("9DCEC4", "215E54")
        }
    }

    static let inset = adaptive(dark: .white.opacity(11 / 255), light: musicColor("202943").opacity(12 / 255))
    static let stroke = adaptive(dark: .white.opacity(19 / 255), light: .black.opacity(15 / 255))

    private static func adaptive(dark: Color, light: Color) -> Color {
        #if os(macOS)
        let night = NSColor(dark)
        let day = NSColor(light)
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? night : day
        })
        #else
        let night = UIColor(dark)
        let day = UIColor(light)
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? night : day })
        #endif
    }
}

private struct MusicWidgetButtonStyle: ButtonStyle {
    let tint: MusicWidgetTint
    let radius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        HoverSurface(label: configuration.label, pressed: configuration.isPressed, tint: tint, radius: radius)
    }

    private struct HoverSurface<Label: View>: View {
        let label: Label
        let pressed: Bool
        let tint: MusicWidgetTint
        let radius: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovered = false

        var body: some View {
            label
                .opacity(!isEnabled ? 0.4 : pressed ? 0.7 : 1)
                .overlay {
                    if isEnabled && (hovered || pressed) {
                        let shape = RoundedRectangle(cornerRadius: radius)
                        shape.fill(tint.ink.opacity(0.035))
                            .overlay { shape.strokeBorder(tint.ink.opacity(0.28)) }
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(.rect(cornerRadius: radius))
                .onHover { hovered = $0 }
                .authHandPointer(enabled: isEnabled)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: pressed)
        }
    }
}

private extension View {
    func musicWidgetInset() -> some View {
        background(MusicWidgetTint.inset, in: .rect(cornerRadius: 11))
            .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(MusicWidgetTint.stroke).allowsHitTesting(false) }
    }
}

private func formatMusicWidget(_ source: String, _ arguments: [String]) -> String {
    arguments.enumerated().reduce(source) { result, argument in
        let (index, value) = argument
        return ["{\(index):00}", "{\(index):N0}", "{\(index):0}", "{\(index)}"].reduce(result) {
            $0.replacingOccurrences(of: $1, with: value)
        }
    }
}
#endif
