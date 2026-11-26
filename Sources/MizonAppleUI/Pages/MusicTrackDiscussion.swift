#if os(macOS) || os(iOS)
import Foundation
import MizonAPIClient
import MizonAppleCore
import Observation
import SwiftUI

@Observable @MainActor
final class TrackDiscussionDraft: Identifiable {
    let id = UUID()
    let parent: MusicCommentItemResponse?
    let time: Double?
    var attach: Bool
    var value = ""
    var tagType = "music"
    var query = ""
    var tags: [MusicCommentTagItem] = []
    var results: [MusicCommentTagItem] = []
    var tagSearchMessage: String?
    var searching = false
    var searchGeneration = 0

    init(parent: MusicCommentItemResponse?, time: Double?, attachesPosition: Bool) {
        self.parent = parent
        self.time = time
        attach = attachesPosition
    }
}

extension MusicTrackDetailsView {
    var tabs: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(.horizontal) {
                HStack(spacing: 5) {
                    if let album = track.musicAlbum {
                        tab(.album, label: localized(album.title, album.persianTitle), symbol: "magnifyingglass")
                    }
                    tab(.contributors, label: text("ArtistTracks"), symbol: "house")
                    tab(.comments, label: text("Comments"), symbol: "bubble")
                    Label(text("Remixes"), systemImage: "house").font(localization.font(12, weight: .semibold))
                        .foregroundStyle(MizonPalette.secondaryText.opacity(0.55)).padding(.horizontal, 10)
                }
                .padding(4)
                .background(MusicHomeStyle.secondaryCard, in: .rect(cornerRadius: 8))
            }
            .scrollIndicators(.hidden)
            if details.pane == .comments {
                discussion
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else { relatedTracks }
        }
        .accessibilityIdentifier("music.track.tabs")
    }

    private func tab(_ pane: MusicTrackDetailsViewModel.Pane, label: String, symbol: String) -> some View {
        control(.pane(pane), text: label, symbol: symbol, selected: details.pane == pane)
    }

    private var relatedTracks: some View {
        VStack(alignment: .leading) {
            if details.loading.contains(.related) { ProgressView().padding(8) }
            else if details.failures.contains(.related) { control(.retry(.related), text: text("TrackRetry"), symbol: "arrow.clockwise") }
            else if details.related.isEmpty { Text(text("TrackNoRelated")).font(localization.font(12)).foregroundStyle(.secondary) }
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(details.related, id: \.publicId) { track in
                        let target = Target.related(track.publicId)
                        Button { perform(target) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                MusicArtwork(mediaID: track.coverMediaPublicId, model: music, symbol: "music.note")
                                    .frame(width: 112, height: 112).clipShape(.rect(cornerRadius: 6))
                                Text(localized(track.title, track.persianTitle))
                                    .font(localization.font(13, weight: .semibold)).lineLimit(1)
                                Text(track.contributors.map { $0.firstName + " " + $0.lastName }.joined(separator: ", "))
                                    .font(localization.font(11)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(width: 112, alignment: .leading)
                            .padding(8)
                        }
                        .buttonStyle(TrackButtonStyle(focused: focus == target))
                        .id(target)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var discussion: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            Text(text("Comments")).font(localization.font(20, weight: .semibold)).accessibilityAddTraits(.isHeader)
            TrackControlsLayout {
                control(.commentNew, text: text("CommentNew"), symbol: "square.and.pencil")
                Menu {
                    ForEach(MusicTrackDetailsViewModel.CommentSort.allCases, id: \.self) { sort in
                        Button { run { await details.sortDiscussion(sort) } } label: {
                            Label(text(sort.textKey), systemImage: details.sort == sort ? "checkmark" : "arrow.up.arrow.down")
                        }
                    }
                } label: { Label(text(details.sort.textKey), systemImage: "arrow.up.arrow.down").font(localization.font(12)) }
                .id(Target.sort)
                .modifier(TrackFocus(isFocused: focus == .sort))
                .accessibilityLabel(text("CommentSort"))
                if details.parentComment != nil {
                    control(.repliesBack, text: text("ShowAllComments"), symbol: "chevron.backward")
                }
            }
            if let parent = details.parentComment {
                Text(format("CommentReplyTo", displayName(parent))).font(localization.font(13, weight: .semibold))
                    .foregroundStyle(MizonPalette.accent)
                Text(parent.text).font(localization.font(13)).foregroundStyle(.secondary)
            }
            if let notice = details.notice {
                HStack {
                    Text(text(notice)).font(localization.font(12)).accessibilityAddTraits(.updatesFrequently)
                    Spacer()
                    Button { details.notice = nil } label: { Image(systemName: "xmark").font(.system(size: 11)) }
                        .buttonStyle(.plain).accessibilityLabel(text("TrackClose"))
                }.padding(8).background(MizonPalette.accent.opacity(0.12), in: .rect(cornerRadius: 8))
            }
            ForEach(details.comments, id: \.publicId) { comment in commentCell(comment) }
            if details.loading.contains(.discussion) {
                ProgressView().accessibilityLabel(text("Comments"))
            } else if details.failures.contains(.discussion) {
                control(.retry(.discussion), text: text("CommentsRetry"), symbol: "arrow.clockwise")
            } else if details.comments.isEmpty {
                Text(text("CommentEmpty")).font(localization.font(13)).foregroundStyle(.secondary)
            }
            if details.nextComment != nil {
                control(.more, text: text("CommentMore"), disabled: details.loading.contains(.discussion))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(14)
        .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
    }

    private func commentCell(_ comment: MusicCommentItemResponse) -> some View {
        let target = Target.comment(comment.publicId)
        return HStack(alignment: .top, spacing: 9) {
            Button { perform(target) } label: {
                MusicArtwork(mediaID: comment.profileMediaPublicId, model: music, symbol: "person.fill")
                    .frame(width: 34, height: 34).clipShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(displayName(comment))
            VStack(alignment: .leading, spacing: 8) {
                TrackControlsLayout(horizontal: 7, vertical: 4) {
                    Text(displayName(comment)).font(localization.font(13, weight: .semibold))
                    if let username = comment.username { Text("@" + username).font(localization.font(11)).foregroundStyle(MizonPalette.accent) }
                    Text(comment.createDateTime, style: .relative).font(localization.font(11)).foregroundStyle(.secondary)
                    Text(comment.platform ?? text("CommentUnknownPlatform")).font(localization.font(10)).foregroundStyle(.secondary)
                }
                Text(comment.text).font(localization.font(14)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !comment.tags.isEmpty {
                    TrackControlsLayout {
                        ForEach(comment.tags, id: \.publicId) { tag in
                            control(.tag(tag.publicId), text: tag.label, tint: MizonPalette.accent)
                        }
                    }
                }
                TrackControlsLayout(horizontal: 6, vertical: 5) {
                    if let time = comment.timestamp?.totalSeconds {
                        Button {
                            details.seek(to: time, title: title)
                        } label: {
                            Label(Self.time(time), systemImage: "play").font(localization.font(12)).padding(6)
                        }
                        .buttonStyle(TrackButtonStyle()).accessibilityLabel(format("CommentPlayAt", Self.time(time)))
                    }
                    control(.vote(comment.publicId, 1), text: comment.likes.formatted(), symbol: "hand.thumbsup",
                            label: text("CommentLike"), disabled: details.busyIDs.contains(comment.publicId), selected: comment.myVote == 1)
                    control(.vote(comment.publicId, -1), text: comment.dislikes.formatted(), symbol: "hand.thumbsdown",
                            label: text("CommentDislike"), disabled: details.busyIDs.contains(comment.publicId), selected: comment.myVote == -1)
                    control(.reply(comment.publicId), text: text("CommentReply"))
                    if comment.replies > 0 { control(.replies(comment.publicId), text: format("CommentReplies", String(comment.replies))) }
                    Button { details.notice = "CommentTranslationSoon" } label: {
                        Text(text("CommentTranslate")).font(localization.font(12)).padding(6)
                    }.buttonStyle(TrackButtonStyle())
                    Button {
                        copy(MizonDeepLink.musicComment(details.id, comment: comment.publicId).canonicalURI)
                        details.notice = "CommentLinkCopied"
                    } label: {
                        Image(systemName: "document.on.document").font(.system(size: 13)).padding(7)
                    }
                    .buttonStyle(TrackButtonStyle()).accessibilityLabel(text("CopyLink"))
                }
            }
        }
        .padding(12)
        .background(MusicHomeStyle.secondaryCard, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(MizonPalette.accent.opacity(highlightedComment == comment.publicId ? 1 : 0),
                              lineWidth: 1)
                .allowsHitTesting(false)
        }
        .modifier(TrackFocus(isFocused: focus == target))
        .id(target)
        .accessibilityIdentifier("music.track.comment.\(comment.publicId)")
    }

    var storiesRail: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 8) {
                Button { perform(.storyAdd) } label: {
                    VStack(spacing: 4) {
                        FluentIcon(symbol: .agentsAdd, size: 22)
                        Text(text("AddStory")).font(localization.font(12))
                    }
                    .frame(width: 100, height: 180)
                }
                .buttonStyle(TrackButtonStyle(focused: focus == .storyAdd, selected: true))
                .id(Target.storyAdd)
                ForEach(details.stories, id: \.publicId) { story in
                    let target = Target.story(story.publicId)
                    Button { perform(target) } label: {
                        ZStack {
                            MusicArtwork(mediaID: story.previewMediaPublicId, model: music, symbol: "photo")
                            musicColor("0D2238").opacity(61.0 / 255)
                            VStack(alignment: .leading, spacing: 2) {
                                MusicArtwork(mediaID: story.creatorProfileMediaPublicId, model: music, symbol: "person.fill")
                                    .frame(width: 28, height: 28).clipShape(.circle)
                                    .overlay(Circle().strokeBorder(.white))
                                Spacer()
                                Text(story.creatorFirstName + " " + story.creatorLastName)
                                    .font(localization.font(12, weight: .semibold)).lineLimit(1)
                                if let title = story.title { Text(title).font(localization.font(11)).lineLimit(2) }
                            }
                            .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        }
                        .frame(width: 111, height: 180)
                        .clipShape(.rect(cornerRadius: 8))
                    }
                    .buttonStyle(TrackButtonStyle(focused: focus == target))
                    .opacity(story.viewedByMe ? 0.78 : 1)
                    .id(target)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    var trackInsights: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                heartInsight.frame(minWidth: 235)
                audienceInsight.frame(minWidth: 235)
                insightTrend.frame(minWidth: 212)
                aiInsight.frame(minWidth: 220)
            }
            VStack(spacing: 8) {
                heartInsight
                audienceInsight
                insightTrend
                aiInsight
            }
        }
        .accessibilityIdentifier("music.track.insights")
    }

    private var heartInsight: some View {
        HStack(spacing: 12) {
            VStack(spacing: 5) {
                HStack(spacing: 10) {
                    insightRing("HR", value: "67", percent: 0.67, tint: musicColor("FD7283"))
                    insightRing("VR", value: "29", percent: 0.29, tint: musicColor("CAAAF7"))
                    insightRing("SW", value: "11", percent: 0.11, tint: musicColor("89D1EA"))
                }
                Label(text("HeartRateChange"), systemImage: "chart.line.uptrend.xyaxis")
                    .font(localization.font(10)).foregroundStyle(MizonPalette.secondaryText)
            }
            Spacer(minLength: 0)
            Image(systemName: "waveform.path.ecg").foregroundStyle(MizonPalette.accent.opacity(0.7))
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 100)
        .background(MusicHomeStyle.secondaryCard, in: .rect(cornerRadius: 8))
    }

    private func insightRing(_ title: String, value: String, percent: Double, tint: Color) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(tint.opacity(0.13), lineWidth: 3)
                Circle().trim(from: 0, to: percent).stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(value).font(AuthLocalization.englishFont(10)).opacity(0.8)
            }
            .frame(width: 34, height: 34)
            Text(title).font(AuthLocalization.englishFont(12)).opacity(0.8)
        }
    }

    private var audienceInsight: some View {
        VStack(alignment: .leading, spacing: 5) {
            insightValue("InsightViewLabel", "SampleListenerQuote")
            insightValue("InsightSatisfactionLabel", "SampleSatisfaction")
            insightValue("InsightCommentCountLabel", "SampleComments")
        }
        .padding(9).frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .background(MusicHomeStyle.secondaryCard, in: .rect(cornerRadius: 8))
    }

    private func insightValue(_ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(text(label)).font(localization.font(12)).foregroundStyle(MizonPalette.accent)
            Text(text(value)).font(localization.font(10)).foregroundStyle(MizonPalette.secondaryText)
        }
    }

    private var insightTrend: some View {
        VStack(alignment: .leading, spacing: 5) {
            Canvas { context, size in
                let sx = size.width / 156, sy = size.height / 60
                let points: [(CGFloat, CGFloat)] = [(5, 41), (29, 49), (54, 33), (78, 25), (102, 33), (127, 25), (151, 9)]
                let coordinates = points.map { CGPoint(x: $0.0 * sx, y: $0.1 * sy) }
                var floor = Path()
                floor.move(to: CGPoint(x: 5 * sx, y: 53 * sy))
                floor.addLine(to: CGPoint(x: 151 * sx, y: 53 * sy))
                context.stroke(floor, with: .color(.white.opacity(0.16)))
                var line = Path()
                if let initial = coordinates.first { line.move(to: initial) }
                for (from, to) in zip(coordinates, coordinates.dropFirst()) {
                    line.addCurve(to: to, control1: CGPoint(x: (from.x + to.x) / 2 - 2, y: from.y),
                                  control2: CGPoint(x: (from.x + to.x) / 2 + 2, y: to.y))
                }
                context.stroke(line, with: .color(MizonPalette.accent), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                for point in coordinates {
                    context.fill(Path(ellipseIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)),
                                 with: .color(MizonPalette.accent))
                }
            }
            .frame(height: 60).accessibilityHidden(true)
            Label(text("HeartRateChange"), systemImage: "waveform.path.ecg")
                .font(localization.font(10)).foregroundStyle(.secondary)
        }
        .accessibilityLabel(text("PulseTrend"))
        .padding(9).frame(maxWidth: .infinity, minHeight: 100)
        .background(MusicHomeStyle.secondaryCard, in: .rect(cornerRadius: 8))
    }

    private var aiInsight: some View {
        HStack(spacing: 10) {
            FluentIcon(symbol: .agentsAdd, size: 38, usesColor: true).opacity(0.6)
            VStack(alignment: .leading, spacing: 4) {
                insightValue("InsightViewLabel", "SampleListenerQuote")
                insightValue("InsightSatisfactionLabel", "SampleSatisfaction")
                insightValue("InsightCommentCountLabel", "SampleComments")
            }
        }
        .accessibilityLabel(text("AiSummary"))
        .padding(9).frame(maxWidth: .infinity, minHeight: 100)
        .background(MusicHomeStyle.secondaryCard, in: .rect(cornerRadius: 8))
    }

    func startComment(at time: Double? = nil, parent: MusicCommentItemResponse? = nil) {
        if details.pane != .comments { details.select(.comments) }
        let available = time ?? (details.duration > 0 ? position.seconds : nil)
        composer = TrackDiscussionDraft(parent: parent, time: available, attachesPosition: time != nil)
    }

    func locateComment(_ comment: MusicCommentItemResponse) {
        highlight(comment)
        if details.pane != .comments { details.select(.comments) }
        details.showLinkedComment(comment)
        scrollToComment = nil
        run {
            await Task.yield()
            scrollToComment = comment.publicId
        }
    }

    private func highlight(_ comment: MusicCommentItemResponse) {
        withAnimation(animation) { highlightedComment = comment.publicId }
    }

    func displayName(_ comment: MusicCommentItemResponse) -> String {
        let name = [comment.firstName, comment.lastName].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? comment.username ?? text("AudienceListener") : name
    }

    func discussionComposer(_ draft: TrackDiscussionDraft) -> some View {
        @Bindable var draft = draft
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(draft.parent.map { format("CommentReplyTo", displayName($0)) } ?? text("CommentNew"))
                    .font(localization.font(20, weight: .semibold)).accessibilityAddTraits(.isHeader)
                if let controllerKeyboard {
                    AuthGamepadKeyboard(keyboard: controllerKeyboard, value: draft.value, prompt: text("CommentNew")) { key in
                        editDraft(key, draft: draft)
                    }.frame(height: 320)
                } else {
                    TextField(text("CommentPlaceholder"), text: $draft.value, axis: .vertical)
                        .font(localization.font(14))
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(4...8)
                        .modifier(TrackFocus(isFocused: focus == .editComposer))
                        .accessibilityIdentifier("music.track.comment.input")
                        .onChange(of: draft.value) {
                            if draft.value.utf16.count > 2_000 {
                                var length = 0
                                draft.value = String(draft.value.prefix { character in
                                    length += String(character).utf16.count
                                    return length <= 2_000
                                })
                            }
                        }
                }
                if let time = draft.time {
                    Toggle(text("CommentAttachPosition") + " · " + Self.time(time), isOn: $draft.attach)
                        .font(localization.font(12))
                }
                TrackControlsLayout {
                    Picker(text("CommentTagType"), selection: $draft.tagType) {
                        Text(text("CommentTagPerson")).tag("person")
                        Text(text("CommentTagClient")).tag("client")
                        Text(text("CommentTagMusic")).tag("music")
                    }.pickerStyle(.menu)
                    TextField(text("CommentTagSearch"), text: $draft.query).textFieldStyle(.roundedBorder).frame(width: 145)
                    Button(text("CommentTagSearch")) { searchTags(draft) }
                        .buttonStyle(.glass).disabled(draft.searching)
                }
                if let message = draft.tagSearchMessage { Text(text(message)).font(localization.font(11)).foregroundStyle(.secondary) }
                ForEach(draft.results, id: \.publicId) { tag in
                    Button(tag.label) {
                        if draft.tags.count == 8 { draft.tagSearchMessage = "CommentTagLimit"; return }
                        if !draft.tags.contains(where: { $0.type == tag.type && $0.publicId == tag.publicId }) { draft.tags.append(tag) }
                    }
                    .buttonStyle(.glass)
                }
                TrackControlsLayout {
                    ForEach(draft.tags, id: \.publicId) { tag in
                        Button {
                            draft.tags.removeAll { $0.publicId == tag.publicId && $0.type == tag.type }
                        } label: { Label(tag.label, systemImage: "xmark.circle") }.buttonStyle(.glass)
                    }
                }
                HStack {
                    control(.saveComposer, text: text(details.posting ? "CommentPosting" : "PostWaveformComment"),
                            disabled: details.posting || draft.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                            accented: true)
                    control(.cancelComposer, text: text("TrackClose"), disabled: details.posting)
                }
            }
            .padding(20)
            .frame(maxWidth: 550)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .font(localization.font(12))
        .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
        .interactiveDismissDisabled(details.posting)
        #if os(macOS)
        .frame(minWidth: 450, idealWidth: 510, minHeight: 330, idealHeight: 430)
        #endif
        .onDisappear { controllerKeyboard = nil }
    }

    func editDraft(_ key: GamepadKeyboard.Key, draft: TrackDiscussionDraft) {
        guard var keyboard = controllerKeyboard else { return }
        if key == .done || key == .close { controllerKeyboard = nil; return }
        if let value = keyboard.edit(key, value: draft.value, accepts: { $0.utf16.count <= 2_000 }) { draft.value = value }
        controllerKeyboard = keyboard
    }

    private func searchTags(_ draft: TrackDiscussionDraft) {
        let query = String(draft.query.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { draft.tagSearchMessage = "CommentTagShort"; return }
        let kind = draft.tagType
        draft.searchGeneration += 1
        let generation = draft.searchGeneration
        draft.searching = true
        draft.tagSearchMessage = nil
        run {
            defer { if draft.searchGeneration == generation { draft.searching = false } }
            do {
                let found = try await details.tagSearch(type: kind, text: query)
                guard composer?.id == draft.id, draft.searchGeneration == generation else { return }
                draft.results = found
                if found.isEmpty { draft.tagSearchMessage = "CommentTagNone" }
            } catch {
                if composer?.id == draft.id, draft.searchGeneration == generation { draft.tagSearchMessage = "TrackSectionFailed" }
            }
        }
    }
}
#endif
