#if os(macOS) || os(iOS)
import MizonAPIClient
import MizonAppleCore
import SwiftUI

/// The center-column rails use the dimensions and templates of the WinUI discovery page.
/// The parent supplies live actions so focus and navigation stay with Music Home.
@MainActor
struct MusicHomeRails {
    let model: MusicHomeViewModel
    let localization: AuthLocalization

    func stories<Add: View, Story: View, Retry: View>(
        @ViewBuilder add: @escaping () -> Add,
        @ViewBuilder story: @escaping (StoryListItemResponse) -> Story,
        @ViewBuilder retry: @escaping () -> Retry
    ) -> some View {
        Group {
            if model.loading.contains(.stories), model.stories.isEmpty {
                skeleton("LoadingStories", minimumHeight: 230)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    if model.failures.contains(.stories) { retry() }
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 10) {
                            add()
                            ForEach(model.stories, id: \.publicId, content: story)
                            if model.stories.isEmpty {
                                Text(text(model.failures.contains(.stories) ? "StoriesFailed" : "NoStories"))
                                    .font(localization.font(10)).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(width: 200, alignment: .leading)
                            }
                        }
                        .frame(height: 230)
                    }
                    .scrollIndicators(.hidden)
                    .accessibilityLabel(text("Stories"))
                    .accessibilityHint(text("StoriesScrollHelp"))
                }
            }
        }
    }

    var addStoryCard: some View {
        ZStack {
            LinearGradient(stops: [
                .init(color: Color.accentColor.opacity(0.24), location: 0),
                .init(color: Color.accentColor.opacity(0), location: 0.75)
            ], startPoint: .topTrailing, endPoint: UnitPoint(x: 0, y: 0.7))
            accentTopLine(.accentColor)
            Text(text("YourStory"))
                .font(localization.font(9))
                .foregroundStyle(.secondary)
                .padding(.top, 14)
                .frame(maxHeight: .infinity, alignment: .top)
            VStack(spacing: 12) {
                FluentIcon(symbol: .agentsAdd, size: 20)
                    .frame(width: 38, height: 38)
                    .background(Color.accentColor.opacity(0.1), in: .rect(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 0.5) }
                Text(text("AddStory")).font(localization.font(11))
            }
            FluentIcon(symbol: .add, size: 12)
                .opacity(0.6)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(width: 112, height: 216)
        .modifier(MusicReferenceRailSurface(radius: 8, outline: .accentColor))
    }

    func storyCard(_ story: StoryListItemResponse) -> some View {
        let name = fullName(story.creatorFirstName, story.creatorLastName)
        let initials = initials(story.creatorFirstName, story.creatorLastName)
        let state = text(story.viewedByMe ? "Viewed" : "New")
        let ringOpacity = story.viewedByMe ? 0.3 : 1.0
        return VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                MusicReferenceRailArtwork(mediaID: story.previewMediaPublicId, model: model, mode: nil) {
                    FluentIcon(symbol: .image, size: 24).opacity(0.15)
                }
                .modifier(MusicReferenceStoryZoom())
                LinearGradient(stops: [
                    .init(color: musicColor("141B24").opacity(112.0 / 255), location: 0),
                    .init(color: musicColor("141B24").opacity(72.0 / 255), location: 0.28),
                    .init(color: musicColor("141B24").opacity(56.0 / 255), location: 0.5),
                    .init(color: musicColor("10161E").opacity(120.0 / 255), location: 0.78),
                    .init(color: musicColor("090C0F").opacity(176.0 / 255), location: 1)
                ], startPoint: .top, endPoint: .bottom)
                HStack(spacing: 4) {
                    Circle().fill(musicColor("86E1C6")).frame(width: 4, height: 4).opacity(ringOpacity)
                    Text(state).font(localization.font(8)).foregroundStyle(.white)
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(musicColor("0D1624").opacity(220.0 / 255), in: .rect(cornerRadius: 5))
                .padding(8)
                if let title = story.title, !title.isEmpty {
                    Text(title)
                        .font(localization.font(9)).lineLimit(1).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(musicColor("0D1624").opacity(220.0 / 255), in: .rect(cornerRadius: 5))
                        .padding(.horizontal, 8).padding(.bottom, 24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
            .frame(height: 162)
            .clipped()
            ZStack(alignment: .top) {
                Text(name)
                    .font(localization.font(9)).lineLimit(1)
                    .padding(.horizontal, 7).padding(.top, 25)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.accentColor).opacity(ringOpacity)
                    .frame(width: 18, height: 2)
                    .padding(.bottom, 5)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                MusicReferenceRailArtwork(mediaID: story.creatorProfileMediaPublicId, model: model, mode: .fill) {
                    Text(initials).font(localization.font(10))
                }
                .frame(width: 34, height: 34)
                .clipShape(.rect(cornerRadius: 9))
                .padding(3)
                .modifier(MusicReferenceRailSurface(radius: 13, outline: .accentColor, isInset: true))
                .offset(y: -20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 132, height: 216)
        .modifier(MusicReferenceRailSurface(radius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([text("Story"), name, story.title ?? "", state]
            .filter { !$0.isEmpty }.joined(separator: localization.isPersian ? "، " : ", "))
    }

    func genres<Clear: View, Genre: View, Retry: View>(
        @ViewBuilder clear: @escaping () -> Clear,
        @ViewBuilder genre: @escaping (MusicGenreTypeItemResponse) -> Genre,
        @ViewBuilder retry: @escaping () -> Retry
    ) -> some View {
        Group {
            if model.loading.contains(.genres), model.genres.isEmpty {
                skeleton("LoadingGenres", minimumHeight: 180)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    toolbar(title: text("GenreHeading"), symbol: .musicNote1, accent: "F0A4BE", actions: clear)
                    if model.genres.isEmpty || model.failures.contains(.genres) {
                        HStack(spacing: 8) {
                            Text(text(model.failures.contains(.genres) ? "GenresFailed" : "NoGenres"))
                                .font(localization.font(10)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if model.failures.contains(.genres) { retry() }
                        }
                    }
                    if !model.genres.isEmpty {
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 10) {
                                ForEach(model.genres, id: \.publicId, content: genre)
                            }
                            .padding(.top, 12).padding(.bottom, 8)
                        }
                        .scrollIndicators(.hidden)
                        .accessibilityLabel(text("MusicGenres"))
                        .accessibilityHint(text("GenresScrollHelp"))
                    }
                }
            }
        }
    }

    var clearGenresLabel: some View {
        HStack(spacing: 7) {
            FluentIcon(symbol: .arrowLeft, size: 12, rightToLeft: localization.isPersian)
            Text(text("AllGenres")).font(localization.font(10))
        }
    }

    func genreCard(_ genre: MusicGenreTypeItemResponse, isSelected: Bool) -> some View {
        let accent = musicColor(genre.accentColorHex, fallback: musicColor("EC4899"))
        let title = genre.title.isEmpty ? genre.persianTitle ?? "" : genre.title
        return ZStack(alignment: .bottomTrailing) {
            LinearGradient(stops: [
                .init(color: accent.opacity(0.24), location: 0),
                .init(color: accent.opacity(0), location: 0.75)
            ], startPoint: .topTrailing, endPoint: UnitPoint(x: 0, y: 0.7))
            MusicReferenceGenreWaveform()
                .stroke(accent.opacity(0.12), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 80, height: 56)
                .offset(x: localization.isPersian ? -5 : 5, y: 4)
                .accessibilityHidden(true)
            accentTopLine(accent)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title).font(localization.font(19, weight: .semibold)).lineLimit(1)
                        if let persian = genre.persianTitle, !persian.isEmpty {
                            Text(persian).font(localization.font(11)).lineLimit(1).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    FluentIcon(symbol: genreGlyph(genre.iconSymbol), size: 20)
                        .foregroundStyle(.secondary)
                        .frame(width: 38, height: 38)
                        .background(accent.opacity(0.1), in: .rect(cornerRadius: 8))
                        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(accent, lineWidth: 0.5) }
                }
                Spacer(minLength: 6)
                HStack(spacing: 5) {
                    HStack(spacing: 5) {
                        Text(genre.musicsCount.formatted(.number.locale(locale)))
                            .font(localization.font(12, weight: .semibold))
                        Text(text("Track")).font(localization.font(10)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .modifier(MusicReferenceRailSurface(radius: 6, showsStroke: false))
                    Spacer()
                    FluentIcon(symbol: .arrowUpRight, size: 13).foregroundStyle(.secondary).opacity(0.8)
                }
            }
            .padding(14)
        }
        .frame(width: 194, height: 138)
        .modifier(MusicReferenceRailSurface(radius: 8, outline: isSelected ? accent.opacity(0.85) : nil))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(formatted("GenreName", localized(genre.title, genre.persianTitle),
                                      genre.musicsCount.formatted(.number.locale(locale))))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    func artists<Actions: View, Profile: View, Follow: View, Retry: View>(
        position: Binding<UUID?>,
        @ViewBuilder actions: @escaping () -> Actions,
        @ViewBuilder profile: @escaping (FeaturedPersonItem) -> Profile,
        @ViewBuilder follow: @escaping (FeaturedPersonItem) -> Follow,
        @ViewBuilder retry: @escaping () -> Retry
    ) -> some View {
        Group {
            if model.loading.contains(.artists), model.artists.isEmpty {
                skeleton("LoadingArtists", minimumHeight: 410)
            } else if !model.artists.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    toolbar(title: text("TopArtists"), symbol: .headphones, accent: "F1C27D", actions: actions)
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(model.artists, id: \.personPublicId) { artist in
                                VStack(spacing: 10) {
                                    profile(artist)
                                        .padding(.horizontal, 8).padding(.top, 8)
                                    follow(artist)
                                        .padding(.horizontal, 12).padding(.bottom, 12)
                                }
                                .frame(width: 224)
                                .modifier(MusicReferenceRailSurface(radius: 16))
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.vertical, 6)
                    }
                    .scrollPosition(id: position)
                    .scrollIndicators(.hidden)
                }
            } else if model.failures.contains(.artists) {
                HStack(spacing: 8) {
                    Text(text("FeaturedArtistsError")).font(localization.font(10)).foregroundStyle(.secondary)
                    retry()
                }
            }
        }
    }

    func artistProfile(_ artist: FeaturedPersonItem) -> some View {
        let accent = musicColor(artist.accentColor, fallback: musicColor("12A6ED"))
        let name = fullName(artist.firstName, artist.lastName)
        let initials = initials(artist.firstName, artist.lastName)
        let avatar = artist.profileMediaPublicId
        let cover = artist.coverMediaPublicId ?? artist.latestMusics.first?.coverMediaPublicId
        return VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                MusicReferenceRailArtwork(mediaID: cover, model: model, mode: .fill) {
                    Color.clear
                }
                LinearGradient(stops: [
                    .init(color: musicColor("141B24").opacity(24.0 / 255), location: 0),
                    .init(color: musicColor("141B24").opacity(8.0 / 255), location: 0.4),
                    .init(color: musicColor("101720").opacity(128.0 / 255), location: 1)
                ], startPoint: .top, endPoint: .bottom)
                FluentIcon(symbol: .arrowUpRight, size: 12)
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(musicColor("0D1420").opacity(219.0 / 255), in: .rect(cornerRadius: 7))
                    .padding(8)
            }
            .frame(height: 92)
            .modifier(MusicReferenceRailSurface(radius: 10, showsStroke: false, isInset: true))
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(localization.font(15, weight: .semibold)).lineLimit(1)
                Text(localized(artist.genreTitle ?? "", artist.persianGenreTitle))
                    .font(localization.font(9)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            .padding(.trailing, 64)
            .padding(.horizontal, 6).padding(.top, 8)
            .overlay(alignment: .topTrailing) {
                MusicReferenceRailArtwork(mediaID: avatar, model: model, mode: .fill) {
                    Text(initials).font(localization.font(16))
                }
                .frame(width: 47, height: 47).clipShape(.circle)
                .frame(width: 56, height: 56)
                .modifier(MusicReferenceRailSurface(radius: 28, outline: accent, lineWidth: 1.5, isInset: true))
                .padding(.trailing, 6).offset(y: -20)
            }
            HStack(spacing: 9) {
                artistStat(artist.monthlyListenersCount, title: "MonthlyListeners", symbol: .headphones)
                Rectangle().fill(.primary.opacity(0.12)).frame(width: 1).padding(.vertical, 2)
                artistStat(artist.followersCount, title: "Followers", symbol: .people)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6).padding(.top, 12)
            Group {
                if artist.dailyPlays.count >= 2, let peak = artist.dailyPlays.max(), peak > 0 {
                    MusicReferenceArtistTrend(days: artist.dailyPlays, peak: peak)
                        .stroke(accent.opacity(0.24), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                        .padding(.horizontal, 6).padding(.top, 9)
                } else {
                    Color.clear
                }
            }
            .frame(height: 32)
            .accessibilityHidden(true)
        }
        .contentShape(.rect(cornerRadius: 11))
        .authHandPointer(enabled: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([
            formatted("ArtistProfileName", name),
            formatted("FollowersCount", artist.followersCount.formatted(.number.locale(locale))),
            formatted("ListenersCount", artist.monthlyListenersCount.formatted(.number.locale(locale)))
        ].joined(separator: " · "))
        .accessibilityHint(text("ArtistProfileHelp"))
    }

    func artistFollow(_ artist: FeaturedPersonItem) -> some View {
        let title = text(artist.isFollowing ? "Following" : "Follow")
        return HStack(spacing: 7) {
            Text(title).font(localization.font(11))
            FluentIcon(symbol: artist.isFollowing ? .checkmark : .personAdd, size: 13)
        }
        .frame(maxWidth: .infinity, minHeight: 24)
        .accessibilityLabel("\(title) · \(fullName(artist.firstName, artist.lastName))")
    }

    func discovery(title: String, subtitle: String, samples: [MusicDiscoverySample], compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            MusicReferenceRailHeading(
                title: title, symbol: compact ? .history : .sparkle,
                accent: compact ? "8BCBE2" : "A9B8FF", localization: localization
            )
            Text(subtitle).font(localization.font(10)).foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(samples) { sample in
                        MusicReferenceDemoTrackCard(sample: sample, compact: compact, localization: localization)
                            .containerRelativeFrame(.horizontal) { width, _ in min(width, compact ? 300 : 224) }
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
            .accessibilityLabel(title)
        }
    }

    private func toolbar<Actions: View>(
        title: String, symbol: FluentSymbol, accent: String, @ViewBuilder actions: @escaping () -> Actions
    ) -> some View {
        let titleView = MusicReferenceRailHeading(title: title, symbol: symbol, accent: accent, localization: localization)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                titleView
                actions()
            }
            .frame(minWidth: 520)
            VStack(alignment: .leading, spacing: 8) {
                titleView
                actions().frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func artistStat(_ value: Int, title: String, symbol: FluentSymbol) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text(MusicReferenceRailFormat.compactNumber(value, locale: locale))
                    .font(localization.font(14, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                FluentIcon(symbol: symbol, size: 12).opacity(0.55)
            }
            Text(text(title)).font(localization.font(9)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func accentTopLine(_ accent: Color) -> some View {
        RoundedRectangle(cornerRadius: 0.5)
            .fill(LinearGradient(colors: [accent.opacity(0), accent.opacity(0.6), accent.opacity(0)],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(height: 1)
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity, alignment: .top)
            .accessibilityHidden(true)
    }

    private func skeleton(_ key: String, minimumHeight: CGFloat) -> some View {
        MusicReferenceRailSkeleton(title: text(key), minimumHeight: minimumHeight, localization: localization)
    }

    private func genreGlyph(_ name: String) -> FluentSymbol {
        switch name.lowercased() {
        case "headphones": .headphones
        case "musicnote2": .musicNote2
        case "guitar": .guitar
        case "soundwavecircle": .soundWaveCircle
        case "mic": .mic
        case "pulse": .pulse
        case "record": .record
        case "speaker2": .speaker2
        case "sparkle": .sparkle
        case "fire": .fire
        case "leafone": .leafOne
        case "album": .album
        default: .musicNote1
        }
    }

    private var locale: Locale { Locale(identifier: localization.isPersian ? "fa-IR" : "en-US") }

    private func localized(_ main: String, _ alternate: String?) -> String {
        if localization.isPersian, let alternate, !alternate.isEmpty { return alternate }
        return main.isEmpty ? alternate ?? "" : main
    }

    private func fullName(_ first: String, _ last: String) -> String {
        [first, last].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: " ")
    }

    private func initials(_ first: String, _ last: String) -> String {
        String([first, last].compactMap { $0.trimmingCharacters(in: .whitespaces).first })
    }

    private func text(_ key: String) -> String { localization.string(key, table: "MusicHome") }

    private func formatted(_ key: String, _ values: String...) -> String {
        MusicReferenceRailFormat.substitute(text(key), with: values)
    }
}

// DiscoverySectionHeader.xaml uses a 38-point icon plate and a two-point rule.
struct MusicReferenceRailHeading: View {
    let title: String
    let symbol: FluentSymbol
    let accent: String
    let localization: AuthLocalization
    var compact = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let color = musicColor(accent)
        let ink = colorScheme == .light ? MusicReferenceRailFormat.lightInk(accent) : color
        HStack(spacing: 10) {
            FluentIcon(symbol: symbol, size: compact ? 15 : 18)
                .foregroundStyle(ink)
                .frame(width: compact ? 30 : 38, height: compact ? 30 : 38)
                .background {
                    LinearGradient(colors: [color.opacity(0.14), color.opacity(0)],
                                   startPoint: .topTrailing, endPoint: .bottomLeading)
                }
                .modifier(MusicReferenceRailSurface(radius: compact ? 10 : 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(localization.font(compact ? 14 : 20, weight: compact ? .semibold : .bold))
                    .foregroundStyle(LinearGradient(colors: [ink, Color.primary], startPoint: .leading, endPoint: .trailing))
                    .frame(maxWidth: .infinity, minHeight: compact ? 24 : 32, alignment: .leading)
                    .padding(.bottom, 2)
                    .accessibilityAddTraits(.isHeader)
                ZStack(alignment: .leading) {
                    Capsule().fill(LinearGradient(colors: [color.opacity(0.25), color.opacity(0)],
                                                  startPoint: .leading, endPoint: .trailing))
                    Capsule().fill(color.opacity(0.8)).frame(width: 22)
                }
                .frame(height: 2)
                .accessibilityHidden(true)
            }
        }
    }
}

struct MusicReferenceRailSkeleton: View {
    let title: String
    let minimumHeight: CGFloat
    let localization: AuthLocalization
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let blocks = colorScheme == .dark ? Color.white.opacity(22.0 / 255) : musicColor("202943").opacity(23.0 / 255)
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(localization.font(11)).foregroundStyle(.secondary)
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 8).fill(blocks).frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 7) {
                        RoundedRectangle(cornerRadius: 4).fill(blocks).frame(height: 9)
                        RoundedRectangle(cornerRadius: 3).fill(blocks).frame(width: 68, height: 6)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .center)
        .modifier(MusicReferenceRailSurface(radius: 16, showsStroke: false, isInset: true))
        .overlay(alignment: .topLeading) {
            GeometryReader { proxy in
                Rectangle().fill(Color.accentColor)
                    .frame(width: proxy.size.width * 0.35, height: 2)
            }
            .frame(height: 2)
            .accessibilityHidden(true)
        }
    }
}

private struct MusicReferenceRailSurface: ViewModifier {
    let radius: CGFloat
    var outline: Color?
    var lineWidth: CGFloat = 1
    var showsStroke = true
    var isInset = false
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        let fill = MusicReferenceRailFormat.surface(colorScheme, inset: isInset)
        content
            .background(fill)
            .clipShape(shape)
            .overlay {
                if showsStroke {
                    shape.strokeBorder(outline ?? MusicReferenceRailFormat.stroke(colorScheme), lineWidth: lineWidth)
                        .allowsHitTesting(false)
                }
            }
    }
}

struct MusicReferenceRailActionStyle: ButtonStyle {
    var square = false

    func makeBody(configuration: Configuration) -> some View {
        MusicReferenceRailAction(label: configuration.label, pressed: configuration.isPressed, square: square)
    }

    private struct MusicReferenceRailAction<Label: View>: View {
        let label: Label
        let pressed: Bool
        let square: Bool
        @State private var hovered = false
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            label
                .foregroundStyle(.secondary)
                .padding(.horizontal, square ? 0 : 10)
                .padding(.vertical, square ? 0 : 6)
                .frame(width: square ? 32 : nil)
                .frame(minHeight: 32)
                .background(.primary.opacity(enabled && (hovered || pressed) ? 0.06 : 0))
                .modifier(MusicReferenceRailSurface(radius: 9))
                .opacity(!enabled ? 0.45 : pressed ? 0.78 : 1)
                .contentShape(.rect)
                .animation(reduceMotion ? nil : .linear(duration: 0.14), value: hovered)
                .animation(reduceMotion ? nil : .linear(duration: 0.10), value: pressed)
                .authHandPointer(enabled: enabled)
                .onHover { hovered = $0 }
        }
    }
}

struct MusicReferenceStoryStyle: ButtonStyle {
    var restingOpacity: Double = 1

    func makeBody(configuration: Configuration) -> some View {
        StoryAction(label: configuration.label, pressed: configuration.isPressed, restingOpacity: restingOpacity)
    }

    private struct StoryAction<Label: View>: View {
        let label: Label
        let pressed: Bool
        let restingOpacity: Double
        @State private var hovered = false
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let opacity = !enabled ? 0.4 : pressed && restingOpacity < 1 ? 0.7 : hovered ? 1 : restingOpacity
            label
                .environment(\.musicReferenceStoryZoom, hovered && !pressed && enabled && !reduceMotion ? 1.035 : 1)
                .scaleEffect(pressed && enabled && !reduceMotion ? 0.98 : 1)
                .opacity(opacity)
                .animation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 1, 1, duration: 0.16), value: pressed)
                .animation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 1, 1, duration: 0.16), value: opacity)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .authHandPointer(enabled: enabled)
                .onHover { hovered = $0 }
        }
    }
}

private extension EnvironmentValues {
    @Entry var musicReferenceStoryZoom: CGFloat = 1
}

private struct MusicReferenceStoryZoom: ViewModifier {
    @Environment(\.musicReferenceStoryZoom) private var zoom

    func body(content: Content) -> some View {
        content.scaleEffect(zoom)
            .animation(.timingCurve(0.2, 0.8, 1, 1, duration: 0.22), value: zoom)
            .clipped()
    }
}

struct MusicReferenceGenreStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        GenreAction(label: configuration.label, pressed: configuration.isPressed, accent: accent)
    }

    private struct GenreAction<Label: View>: View {
        let label: Label
        let pressed: Bool
        let accent: Color
        @State private var hovered = false
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            ZStack {
                label
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(accent.opacity(pressed ? 1 : hovered && enabled ? 0.5 : 0))
                    }
                    .scaleEffect(pressed && enabled && !reduceMotion ? 0.98 : 1)
                    .animation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 1, 1, duration: 0.16), value: pressed)
                    .offset(y: hovered && !pressed && enabled && !reduceMotion ? -4 : 0)
                    .animation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 1, 1, duration: 0.24), value: hovered)
                    .opacity(enabled ? 1 : 0.4)
            }
            .contentShape(.rect)
            .authHandPointer(enabled: enabled)
            .onHover { hovered = $0 }
        }
    }
}

private struct MusicReferenceGenreWaveform: Shape {
    func path(in rect: CGRect) -> Path {
        let heights: [CGFloat] = [8, 16, 24, 12, 20, 7, 28, 14, 6]
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        for (index, height) in heights.enumerated() {
            let x = rect.minX + CGFloat(index + 1) * rect.width / 10
            path.addLine(to: CGPoint(x: x, y: rect.midY))
            path.addLine(to: CGPoint(x: x, y: rect.midY - height))
            path.addLine(to: CGPoint(x: x, y: rect.midY + height))
            path.addLine(to: CGPoint(x: x, y: rect.midY))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

private struct MusicReferenceArtistTrend: Shape {
    let days: [Int]
    let peak: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (index, plays) in days.enumerated() {
            let x = rect.width * CGFloat(index) / CGFloat(days.count - 1)
            let progress = CGFloat(min(max(plays, 0), peak)) / CGFloat(peak)
            let y = rect.height * (1 - progress * 50 / 56)
            let point = CGPoint(x: rect.minX + x, y: rect.minY + y)
            if index == 0 { path.move(to: point) }
            else { path.addLine(to: point) }
        }
        return path
    }
}

private struct MusicReferenceRailArtwork<Placeholder: View>: View {
    let mediaID: UUID?
    let model: MusicHomeViewModel
    let mode: ContentMode?
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var loaded: CGImage?

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let loaded {
                    let image = Image(decorative: loaded, scale: 1).resizable()
                    if let mode { image.aspectRatio(contentMode: mode) }
                    else { image }
                } else {
                    placeholder()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
        .task(id: mediaID) {
            loaded = nil
            guard let mediaID, mediaID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) else { return }
            let image = try? await model.artwork.image(mediaID, session: model.session)
            guard !Task.isCancelled else { return }
            loaded = image
        }
    }
}

private struct MusicReferenceDemoTrackCard: View {
    let sample: MusicDiscoverySample
    let compact: Bool
    let localization: AuthLocalization
    @State private var trackVisible = false
    @State private var profileVisible = false
    @State private var hovered = false
    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var localizedTitle: String { localization.isPersian ? sample.persianTitle : sample.title }
    private var genre: String { localization.isPersian ? sample.persianGenre : sample.genre }
    private var locale: Locale { Locale(identifier: localization.isPersian ? "fa-IR" : "en-US") }
    private var duration: String { String(format: "%d:%02d", sample.duration / 60, sample.duration % 60) }
    private var avatarName: String { sample.artist.hasPrefix("رها") || sample.artist.hasPrefix("آوا") ? "friend-sara" : "friend-amir" }

    var body: some View {
        Group {
            if compact { recentCard }
            else { openCard }
        }
        .modifier(MusicReferenceRailSurface(
            radius: 16, outline: hovered || pressed ? Color.accentColor.opacity(pressed ? 1 : 0.5) : nil
        ))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .overlay {
            Button {
                hovered = false
                trackVisible = true
            } label: {
                Color.clear.contentShape(.rect(cornerRadius: 16))
            }
            .buttonStyle(MusicReferenceDemoHitStyle(pressed: $pressed))
            .accessibilityLabel(formatted("MusicName", [
                localizedTitle, sample.artist, genre, duration,
                sample.likes.formatted(.number.locale(locale))
            ]))
            .accessibilityHint(text("OpenTrackHelp"))
        }
        .overlay(alignment: compact ? .trailing : .bottomTrailing) {
            Button {
                hovered = false
                profileVisible = true
            } label: {
                portrait(diameter: compact ? 20 : 24)
                    .frame(width: compact ? 28 : 32, height: compact ? 28 : 32)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(formatted("ProfileName", [sample.artist]))
            .authHandPointer(enabled: true)
            .padding(.trailing, compact ? 13 + 88 + 12 : 14)
            .padding(.bottom, compact ? 0 : 14)
            .popover(isPresented: $profileVisible) { profilePreview }
        }
        .scaleEffect(pressed && !reduceMotion ? 0.98 : 1)
        .animation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 1, 1, duration: 0.16), value: pressed)
        .offset(y: hovered && !pressed && !reduceMotion ? -4 : 0)
        .animation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 1, 1, duration: 0.24), value: hovered)
        .contentShape(.rect(cornerRadius: 16))
        .onHover { hovered = $0 }
        .sheet(isPresented: $trackVisible) { trackPreview }
    }

    private var openCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Color.clear.aspectRatio(1, contentMode: .fit)
                .overlay { artwork(radius: 10) }
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    FluentIcon(symbol: .arrowUpRight, size: 13).opacity(0.45).padding(.top, 5)
                    titleBlock(titleSize: 16, alternateSize: 10, spacing: 3)
                        .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
                }
                Rectangle().fill(MusicReferenceRailFormat.stroke(colorScheme).opacity(0.65)).frame(height: 1)
                HStack(spacing: 7) {
                    likes(size: 10)
                    Text(sample.artist).font(localization.font(10)).foregroundStyle(.secondary).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal, 5).padding(.bottom, 5)
        }
        .padding(9)
    }

    private var recentCard: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                titleBlock(titleSize: 13, alternateSize: 9, spacing: 2)
                Text(sample.artist).font(localization.font(10)).foregroundStyle(.secondary).lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.trailing, 34)
                HStack(spacing: 8) {
                    likes(size: 9)
                    Text(genre).font(localization.font(9)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            artwork(radius: 9)
                .frame(width: 88, height: 88)
        }
        .frame(height: 88)
        .padding(13)
    }

    private func titleBlock(titleSize: CGFloat, alternateSize: CGFloat, spacing: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text(localizedTitle).font(localization.font(titleSize, weight: .semibold)).lineLimit(1)
            if localization.isPersian {
                Text(sample.title).font(localization.font(alternateSize)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func likes(size: CGFloat) -> some View {
        HStack(spacing: 4) {
            FluentIcon(symbol: .heart, size: size + 1)
                .foregroundStyle(musicColor(colorScheme == .dark ? "E58AA5" : "8F3051"))
            Text(MusicReferenceRailFormat.compactNumber(sample.likes, locale: locale))
                .font(localization.font(size)).foregroundStyle(.secondary)
        }
    }

    private func artwork(radius: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            cover
                .scaleEffect(hovered && !reduceMotion ? 1.035 : 1)
                .animation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 1, 1, duration: 0.33), value: hovered)
            LinearGradient(stops: [
                .init(color: musicColor("141B24").opacity(40.0 / 255), location: 0),
                .init(color: musicColor("141B24").opacity(8.0 / 255), location: 0.48),
                .init(color: musicColor("0D1420").opacity(112.0 / 255), location: 1)
            ], startPoint: .top, endPoint: .bottom)
            if !compact {
                Text(genre).font(localization.font(9)).foregroundStyle(.white).lineLimit(1)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(musicColor("141B24").opacity(221.0 / 255), in: .rect(cornerRadius: 6))
                    .frame(maxWidth: 130, alignment: .trailing)
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            HStack(spacing: 5) {
                if !compact { FluentIcon(symbol: .headphones, size: 10).opacity(0.8) }
                Text(duration).font(localization.font(compact ? 9 : 10))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 5 : 7).padding(.vertical, compact ? 2 : 4)
            .background(musicColor("0D1420").opacity(219.0 / 255), in: .rect(cornerRadius: compact ? 4 : 6))
            .padding(compact ? 5 : 10)
        }
        .clipShape(.rect(cornerRadius: radius))
    }

    private var cover: some View {
        GeometryReader { proxy in
            MusicLocalArtwork(sample.image, maximumPixelSize: 800).scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .accessibilityHidden(true)
    }

    private func portrait(diameter: CGFloat) -> some View {
        MusicLocalArtwork(avatarName, maximumPixelSize: 180)
            .scaledToFill()
            .frame(width: diameter, height: diameter)
            .clipShape(.circle)
            .accessibilityHidden(true)
    }

    private var trackPreview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                cover.frame(height: 240).clipShape(.rect(cornerRadius: 12))
                Text(localizedTitle).font(localization.font(20, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Text(sample.artist).font(localization.font(13)).foregroundStyle(.secondary)
                Text(formatted("PreviewDurationLikes", [duration, sample.likes.formatted(.number.locale(locale))]))
                    .font(localization.font(12)).foregroundStyle(.secondary)
                Text(text("TrackPreviewExplanation")).font(localization.font(11)).foregroundStyle(.secondary)
                Button(text("Close")) { trackVisible = false }
                    .buttonStyle(MusicReferenceRailActionStyle())
                    .keyboardShortcut(.cancelAction)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(maxWidth: 360)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        #if os(macOS)
        .frame(width: 400, height: 440)
        #endif
    }

    private var profilePreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            cover.frame(height: 92)
                .overlay(alignment: .topLeading) {
                    Button { profileVisible = false } label: {
                        FluentIcon(symbol: .dismiss, size: 12)
                            .frame(width: 28, height: 28)
                            .background(.ultraThinMaterial, in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(text("Close"))
                    .keyboardShortcut(.cancelAction)
                    .padding(12)
                }
            HStack(alignment: .bottom, spacing: 12) {
                Text("\(text("Singer")) · \(genre)")
                    .font(localization.font(10)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 6)
                portrait(diameter: 70).padding(4)
                    .modifier(MusicReferenceRailSurface(radius: 39, isInset: true))
            }
            .padding(.horizontal, 16).padding(.top, -30)
            VStack(alignment: .leading, spacing: 12) {
                Text(sample.artist).font(localization.font(18, weight: .semibold))
                Text(formatted("InTrack", [localizedTitle])).font(localization.font(10))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 11).padding(.vertical, 9)
                    .modifier(MusicReferenceRailSurface(radius: 10))
                Text(text("Preview")).font(localization.font(9)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 16)
        }
        .frame(width: 320)
        .presentationCompactAdaptation(.popover)
    }

    private func text(_ key: String) -> String { localization.string(key, table: "MusicHome") }

    private func formatted(_ key: String, _ values: [String]) -> String {
        MusicReferenceRailFormat.substitute(text(key), with: values)
    }
}

private struct MusicReferenceDemoHitStyle: ButtonStyle {
    @Binding var pressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .authHandPointer(enabled: true)
            .onChange(of: configuration.isPressed) { _, value in pressed = value }
    }
}

private enum MusicReferenceRailFormat {
    static func compactNumber(_ value: Int, locale: Locale) -> String {
        let scale = value >= 1_000_000 ? 1_000_000 : value >= 1000 ? 1000 : 1
        guard scale > 1 else { return value.formatted(.number.locale(locale)) }
        return (Double(value) / Double(scale))
            .formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "en_US_POSIX")))
            + (scale == 1_000_000 ? "M" : "K")
    }

    static func substitute(_ message: String, with values: [String]) -> String {
        values.enumerated().reduce(message) { result, entry in
            result.replacingOccurrences(of: "{\(entry.offset)}", with: entry.element)
                .replacingOccurrences(of: "{\(entry.offset):N0}", with: entry.element)
        }
    }

    static func surface(_ scheme: ColorScheme, inset: Bool) -> Color {
        if inset { return scheme == .dark ? MusicHomeStyle.inset : musicColor("202943").opacity(12.0 / 255) }
        return scheme == .dark ? MusicHomeStyle.secondaryCard : .white.opacity(0.58)
    }

    static func stroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? MusicHomeStyle.stroke : .black.opacity(0.095)
    }

    static func lightInk(_ hex: String) -> Color {
        guard let rgb = UInt32(hex, radix: 16) else { return .primary }
        return Color(red: Double((rgb >> 16) & 255) * 0.42 / 255,
                     green: Double((rgb >> 8) & 255) * 0.42 / 255,
                     blue: Double(rgb & 255) * 0.42 / 255)
    }
}
#endif
