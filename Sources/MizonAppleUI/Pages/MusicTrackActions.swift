#if os(macOS) || os(iOS)
import MizonAPIClient
import MizonAppleCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension MusicTrackDetailsView {
    private enum Scope: Equatable {
        case page(MusicTrackDetailsViewModel.Pane), cover, panel(Panel), composer(UUID, Bool), export, dialog, floating
    }

    private var controlScope: Scope? {
        guard canUseController else { return nil }
        if exporting { return .export }
        if createsPlaylist || contextNotice != nil { return .dialog }
        if coverOpen { return .cover }
        if let composer { return .composer(composer.id, controllerKeyboard != nil) }
        if let panel { return .panel(panel) }
        if floating { return .floating }
        return .page(details.pane)
    }

    func watchController() async {
        await GamepadControls.observe(scope: { controlScope }, onReset: {
            controllerKeyboard = nil
        }) { input, _ in
            guard let scope = controlScope else { return }
            if case .composer = scope, let composer, var keyboard = controllerKeyboard {
                let key = keyboard.key(for: input)
                controllerKeyboard = keyboard
                if let key { editDraft(key, draft: composer) }
                return
            }
            if input == .back {
                back(scope)
                return
            }
            if case .page = scope {
                if input == .previousField { perform(.rewind); return }
                if input == .nextField { perform(.forward); return }
                if input == .clear && focus == .waveform { perform(.waveform); return }
                if let step = input.scrollStep { scroll.move(by: step); return }
                if input == .previousSection || input == .nextSection {
                    let panes = availablePanes
                    let index = panes.firstIndex(of: details.pane) ?? 0
                    let step = input == .previousSection ? -1 : 1
                    perform(.pane(panes[(index + panes.count + step) % panes.count]))
                    return
                }
            }
            if focus == .volume, input == .move(.left) || input == .move(.right) {
                changeVolume(playerVolume + (input == .move(.left) ? -0.05 : 0.05))
                return
            }
            if focus == .balance, input == .move(.left) || input == .move(.right) {
                details.balance = min(100, max(-100, details.balance + (input == .move(.left) ? -5 : 5)))
                music.updateTrackMixBalance(details.balance, for: details.id)
                return
            }
            if input == .help && scope == .page(details.pane) {
                contextNotice = "WaveformControls"
                return
            }
            if input == .submit && composer != nil { perform(.saveComposer); return }
            let targets = available(scope)
            if input == .primary || input == .reset { focus = targets.first; return }
            if input == .accept {
                if let focus, targets.contains(focus) { perform(focus) }
                else { focus = targets.first }
            } else if let step = input.focusStep {
                focus = targets.gamepadTarget(from: focus, step: step)
            }
        }
    }

    private func back(_ scope: Scope) {
        if createsPlaylist { createsPlaylist = false }
        else if contextNotice != nil { contextNotice = nil }
        else if coverOpen { hideCover() }
        else if composer != nil, !details.posting { composer = nil; controllerKeyboard = nil; focus = .commentNew }
        else if let panel { closePanel(panel) }
        else if floating { floating = false; focus = .floating }
        else if scope == .page(.comments), details.parentComment != nil { perform(.repliesBack) }
        else if case .page = scope { dismiss() }
    }

    private var availablePanes: [MusicTrackDetailsViewModel.Pane] {
        (track.musicAlbum == nil ? [] : [.album]) + [.contributors, .comments]
    }

    private func available(_ scope: Scope) -> [Target] {
        switch scope {
        case .cover: return [.close, .zoomOut, .zoomReset, .zoomIn]
        case .floating: return [.play, .rewind, .forward, .close]
        case .composer: return details.posting ? [] : [.editComposer, .saveComposer, .cancelComposer]
        case .panel(.support): return [.copy, .close]
        case .panel(.playlists):
            return [.createPlaylist] + (details.changingPlaylists ? [] : details.playlists.map { .membership($0.publicId) }) + [.close]
        case .panel(.shortcut): return [.copy, .shortcut, .close]
        case .panel(.output):
            #if os(macOS)
            return [.device(""), .volume] + outputDevices.map { .device($0.id) } + [.close]
            #else
            return [.volume, .close]
            #endif
        case .panel: return [.close]
        case .dialog, .export: return []
        case .page: break
        }

        var list: [Target] = []
        if canOpenCover { list.append(.cover) }
        if track.musicAlbum != nil { list.append(.album) }
        list += [.views, .live]
        if !music.requestingPlayback { list.append(.play) }
        list.append(.repeatTrack)
        if details.duration > 0 { list += [.rewind, .forward] }
        if !downloading { list.append(.download) }
        list += [.shortcut, .floating, .copy]
        if details.duration > 0 { list.append(.waveform) }
        if details.failures.contains(.waveform) { list.append(.retry(.waveform)) }
        list += [.support, .playlists, .output]
        if track.musicVideo != nil { list.append(.video) }
        if !details.liking { list.append(.like) }
        list += details.reactions.filter { !details.busyIDs.contains($0.id) }.map { .reaction($0.id) }
        list += details.credits.map { .artist($0.personPublicId, $0.musicContributorTypePublicId) }
        list += [.volume, .lyrics]
        if details.stemMix?.isAvailable == true && music.playingTrack == details.id && !details.mixLoading {
            list.append(.mix)
            if details.mixActive { list.append(.balance) }
        }
        if lyricsOpen {
            list += details.lyrics.map { .lyric($0.lineOrder) }
            if details.failures.contains(.lyrics) { list.append(.retry(.lyrics)) }
        }
        list.append(.storyAdd)
        list += details.stories.map { .story($0.publicId) }
        list += availablePanes.map(Target.pane)
        if details.pane == .comments {
            list += [.commentNew, .sort]
            if details.parentComment != nil { list.append(.repliesBack) }
            for comment in details.comments {
                list.append(.comment(comment.publicId))
                if !details.busyIDs.contains(comment.publicId) { list += [.vote(comment.publicId, 1), .vote(comment.publicId, -1)] }
                list.append(.reply(comment.publicId))
                if comment.replies > 0 { list.append(.replies(comment.publicId)) }
                list += comment.tags.map { .tag($0.publicId) }
            }
            if details.failures.contains(.discussion) { list.append(.retry(.discussion)) }
            if details.nextComment != nil, !details.loading.contains(.discussion) { list.append(.more) }
        } else {
            if details.failures.contains(.related) { list.append(.retry(.related)) }
            list += details.related.map { .related($0.publicId) }
        }
        return list
    }

    func perform(_ target: Target) {
        switch target {
        case .cover: if canOpenCover { showCover() }
        case .play:
            if !music.requestingPlayback {
                if music.playingTrack == details.id { music.togglePlayback() }
                else { music.play(details.id, title: title) }
            }
        case .waveform: if details.duration > 0 { startComment(at: position.seconds) }
        case .rewind: details.seek(to: position.seconds - 5, startPlayback: false, title: title)
        case .forward: details.seek(to: position.seconds + 5, startPlayback: false, title: title)
        case .download: download()
        case .shortcut:
            if panel == .shortcut {
                #if os(macOS)
                saveShortcut()
                #endif
            } else { panel = .shortcut; focus = .copy }
        case .floating:
            #if os(macOS)
            floatWindow.open(inAppFloatingPlayer, title: title)
            #else
            floating.toggle()
            #endif
        case .copy: copy(link); contextNotice = "CopiedMessage"
        case .support: panel = .support; focus = .copy
        case .playlists: panel = .playlists; focus = .createPlaylist
        case .output:
            #if os(macOS)
            outputDevices = TrackAudioOutput.list()
            #endif
            panel = .output
            focus = .volume
        case .views: panel = .views; focus = .close
        case .live: panel = .live; focus = .close
        case .album: choosePane(.album)
        case .video: open(.musicVideo(details.id))
        case .artist(let id, _): open(.artist(id))
        case .story(let id): open(.story(id))
        case .related(let id): if id != details.id { open(.track(id)) }
        case .like: run { await details.like() }
        case .repeatTrack: music.repeatingTrack = music.repeatingTrack == details.id ? nil : details.id
        case .volume:
            if music.player.volume > 0 { volumeBeforeMute = Double(music.player.volume); changeVolume(0) }
            else { changeVolume(max(0.1, volumeBeforeMute)) }
        case .lyrics: withAnimation(animation) { lyricsOpen.toggle() }
        case .mix: run { await details.toggleMix() }
        case .balance:
            details.balance = details.balance >= 100 ? -100 : details.balance + 50
            music.updateTrackMixBalance(details.balance, for: details.id)
        case .reaction(let id):
            if let reaction = details.reactions.first(where: { $0.id == id }) { run { await details.react(reaction) } }
        case .storyAdd: contextNotice = "StoryPreviewExplanation"
        case .pane(let pane): choosePane(pane)
        case .sort:
            let modes = MusicTrackDetailsViewModel.CommentSort.allCases
            let index = modes.firstIndex(of: details.sort) ?? 0
            run { await details.sortDiscussion(modes[(index + 1) % modes.count]) }
        case .commentNew: startComment()
        case .repliesBack: run { await details.showReplies(nil) }
        case .more: run { await details.moreComments() }
        case .retry(let section): run { await details.load(section, refresh: true) }
        case .lyric(let order):
            if let line = details.lyrics.first(where: { $0.lineOrder == order }) {
                details.seek(to: Double(line.startTimeInMilliseconds) / 1_000, title: title)
            }
        case .comment(let id): if let row = comment(id) { open(.client(row.clientPublicId)) }
        case .vote(let id, let vote): if let row = comment(id) { run { await details.vote(row, vote: vote) } }
        case .reply(let id): if let row = comment(id) { startComment(parent: row) }
        case .replies(let id): if let row = comment(id) { run { await details.showReplies(row) } }
        case .tag(let id):
            if let tag = details.comments.flatMap(\.tags).first(where: { $0.publicId == id }) {
                let destination = tag.navigationPublicId ?? tag.publicId
                switch tag.type.lowercased() {
                case "music": open(.track(destination))
                case "person": open(.artist(destination))
                case "client": open(.client(destination))
                default: break
                }
            }
        case .close:
            if coverOpen { hideCover() }
            else if let panel { closePanel(panel) }
            else {
                floating = false
                #if os(macOS)
                floatWindow.close()
                #endif
            }
        case .device(let uid):
            #if os(macOS)
            music.player.audioOutputDeviceUniqueID = uid.isEmpty ? nil : uid
            focus = target
            #endif
        case .zoomIn: zoom(to: coverZoom * 1.25)
        case .zoomOut: zoom(to: coverZoom * 0.8)
        case .zoomReset: zoom(to: 1)
        case .createPlaylist: if !details.changingPlaylists { createsPlaylist = true }
        case .membership(let id): run { await details.toggleMembership(id) }
        case .editComposer:
            if let composer {
                controllerKeyboard = GamepadKeyboard(allowsPersian: true, masksValue: false,
                                                      persian: rtl, length: composer.value.count)
            }
        case .saveComposer:
            if let draft = composer {
                run {
                    if await details.submit(draft.value, parent: draft.parent?.publicId,
                                            time: draft.attach ? draft.time : nil, tags: draft.tags), composer?.id == draft.id {
                        composer = nil
                        focus = .commentNew
                        if draft.attach { details.notice = "WaveformCommentPosted" }
                    }
                }
            }
        case .cancelComposer:
            if !details.posting { composer = nil; focus = .commentNew }
        }
    }

    private func comment(_ id: UUID) -> MusicCommentItemResponse? { details.comments.first { $0.publicId == id } }

    private func choosePane(_ pane: MusicTrackDetailsViewModel.Pane) {
        guard availablePanes.contains(pane) else { return }
        withAnimation(animation) { details.select(pane) }
        focus = .pane(pane)
    }

    var link: String { MizonDeepLink.track(details.id, action: .details).canonicalURI }

    func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    private func download() {
        guard !downloading else { return }
        downloading = true
        exportTask = Task {
            defer { downloading = false }
            do {
                let url = try await music.artwork.downloadTrack(details.id, session: music.session)
                try Task.checkCancellation()
                exportDocument = MusicFeatureExport(url: url)
                exporting = true
            } catch {
                if !Task.isCancelled { contextNotice = "TrackSectionFailed" }
            }
        }
    }

    private func closePanel(_ panel: Panel) {
        self.panel = nil
        switch panel {
        case .support: focus = .support
        case .playlists: focus = .playlists
        case .output: focus = .output
        case .views: focus = .views
        case .live: focus = .live
        case .shortcut: focus = .shortcut
        }
    }

    func changeVolume(_ value: Double) {
        playerVolume = min(1, max(0, value))
        music.player.volume = Float(playerVolume)
    }

    #if os(macOS)
    private func saveShortcut() {
        let folder = FileManager.default.temporaryDirectory.appending(path: "MizonTrackShortcuts", directoryHint: .isDirectory)
        let file = folder.appending(path: details.id.uuidString + ".webloc")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let payload = try PropertyListSerialization.data(fromPropertyList: ["URL": link], format: .xml, options: 0)
            try payload.write(to: file, options: .atomic)
            closePanel(.shortcut)
            exportDocument = MusicFeatureExport(url: file)
            exporting = true
        } catch { contextNotice = "TrackSectionFailed" }
    }
    #endif

    func showCover() {
        coverZoom = 1
        coverDrag = .zero
        focus = .close
        withAnimation(animation) { coverOpen = true }
    }

    private func hideCover() {
        withAnimation(animation) { coverOpen = false }
        focus = .cover
    }

    private func zoom(to scale: CGFloat) {
        withAnimation(animation) {
            coverZoom = min(4, max(1, scale))
            if coverZoom == 1 { coverDrag = .zero }
        }
    }

    var coverPreview: some View {
        GeometryReader { geometry in
            let imageSize = min(900, min(800, min(geometry.size.width - 24, geometry.size.height - 76)))
            ZStack(alignment: .topTrailing) {
                Color.black.opacity(0.78).ignoresSafeArea().onTapGesture { hideCover() }
                MusicArtwork(mediaID: track.musicCover?.mediaPublicId, model: music, symbol: "music.note")
                    .frame(width: max(1, imageSize), height: max(1, imageSize))
                    .clipShape(.rect(cornerRadius: 12))
                    .matchedGeometryEffect(id: "track-artwork", in: coverNamespace, isSource: true)
                    .scaleEffect(min(4, max(1, coverZoom * pinch)))
                    .offset(x: coverDrag.width + drag.width, y: coverDrag.height + drag.height)
                    .gesture(MagnifyGesture().updating($pinch) { value, state, _ in state = value.magnification }
                        .onEnded { zoom(to: coverZoom * $0.magnification) })
                    .simultaneousGesture(DragGesture().updating($drag) { value, state, _ in
                        if coverZoom > 1 { state = value.translation }
                    }.onEnded {
                        guard coverZoom > 1 else { return }
                        let maximum = CGFloat(max(0, imageSize)) * coverZoom / 2
                        coverDrag = CGSize(width: max(-maximum, min(maximum, coverDrag.width + $0.translation.width)),
                                           height: max(-maximum, min(maximum, coverDrag.height + $0.translation.height)))
                    })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 50)
                HStack(spacing: 6) {
                    control(.zoomOut, symbol: "minus.magnifyingglass", label: text("ZoomOut"), disabled: coverZoom <= 1)
                    control(.zoomReset, text: "\(Int(coverZoom * 100))%", label: text("ResetZoom"))
                    control(.zoomIn, symbol: "plus.magnifyingglass", label: text("ZoomIn"), disabled: coverZoom >= 4)
                    control(.close, symbol: "xmark", label: text("CloseCover")).keyboardShortcut(.cancelAction)
                }
                .padding(12)
            }
            .clipped()
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("music.track.cover.preview")
        .transition(.opacity)
    }

    var inAppFloatingPlayer: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                MusicArtwork(mediaID: track.musicCover?.mediaPublicId, model: music, symbol: "music.note")
                    .frame(width: 44, height: 44).clipShape(.rect(cornerRadius: 6))
                Text(title).font(localization.font(13, weight: .semibold)).lineLimit(1)
                Spacer()
                control(.close, symbol: "xmark", label: text("TrackClose"))
            }
            HStack(spacing: 8) {
                control(.rewind, symbol: "gobackward.5", label: text("TrackSeek"))
                control(.play, symbol: isTrackPlaying ? "pause.fill" : "play.fill", label: text("Play"), accented: true)
                control(.forward, symbol: "goforward.5", label: text("TrackSeek"))
                TrackTimeLabel(position: position, duration: details.duration)
            }
        }
        .padding(12)
        .background(MizonPalette.surface, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(MusicHomeChrome.hairline))
        .padding(8)
        .accessibilityIdentifier("music.track.floating")
    }

    func panelBody(_ panel: Panel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(text(panelTitle(panel))).font(localization.font(17, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    Spacer()
                    control(.close, symbol: "xmark", label: text("TrackClose")).keyboardShortcut(.cancelAction)
                }
                switch panel {
                case .support:
                    Text(text("SupportInfo")).font(localization.font(12))
                    control(.copy, text: text("CopyLink"), symbol: "document.on.document", accented: true)
                case .shortcut:
                    if let url = URL(string: link) { ShareLink(item: url).buttonStyle(.glass) }
                    control(.copy, text: text("CopyLink"), symbol: "document.on.document")
                    #if os(macOS)
                    control(.shortcut, text: text("Shortcut"), symbol: "desktopcomputer", accented: true)
                    #endif
                case .playlists:
                    control(.createPlaylist, text: text("NewPlaylist"), symbol: "plus", disabled: details.changingPlaylists)
                    if details.loading.contains(.playlists) { ProgressView() }
                    if details.failures.contains(.playlists) { control(.retry(.playlists), text: text("TrackRetry")) }
                    ForEach(details.playlists, id: \.publicId) { playlist in
                        let target = Target.membership(playlist.publicId)
                        Button { perform(target) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: playlist.containsCurrentMusic ? "checkmark.square.fill" : "square")
                                MusicArtwork(mediaID: playlist.lastMusicCoverMediaPublicId, model: music, symbol: "music.note.list")
                                    .frame(width: 25, height: 25).clipShape(.rect(cornerRadius: 4))
                                Text(playlist.title).lineLimit(1)
                                Spacer()
                                Text(playlist.musicsCount.formatted()).foregroundStyle(.secondary)
                            }.padding(7)
                        }
                        .buttonStyle(TrackButtonStyle(focused: focus == target, selected: playlist.containsCurrentMusic))
                        .disabled(details.changingPlaylists)
                        .id(target)
                    }
                case .output:
                    #if os(macOS)
                    control(.device(""), text: text("TrackSystemOutput"), symbol: music.player.audioOutputDeviceUniqueID == nil ? "checkmark" : "speaker")
                    ForEach(outputDevices) { device in
                        control(.device(device.id), text: device.name,
                                symbol: device.id == music.player.audioOutputDeviceUniqueID ? "checkmark" : "speaker.wave.2")
                    }
                    #else
                    TrackAudioRoutePicker().frame(width: 44, height: 44)
                    #endif
                    Slider(value: Binding(get: { playerVolume }, set: changeVolume), in: 0...1) {
                        Text(text("Volume"))
                    }.modifier(TrackFocus(isFocused: focus == .volume))
                case .views:
                    Text(track.viewsCount.formatted()).font(localization.font(24, weight: .semibold))
                        .foregroundStyle(MizonPalette.accent)
                    Text(text("AudienceHistorySample")).foregroundStyle(.secondary)
                    audienceSamples(live: false)
                case .live:
                    if details.listeners.isEmpty {
                        Text(text("LiveAudienceEmptySample")).foregroundStyle(.secondary)
                        audienceSamples(live: true)
                    }
                    ForEach(details.listeners, id: \.clientPublicId) { listener in
                        HStack(spacing: 7) {
                            MusicArtwork(mediaID: listener.profileMediaPublicId, model: music, symbol: "person.fill")
                                .frame(width: 26, height: 26).clipShape(.circle)
                            Text(listener.firstName + " " + listener.lastName).lineLimit(1)
                            Spacer()
                            Label(Self.time(Double(listener.positionMilliseconds) / 1_000),
                                  systemImage: listener.isPlaying ? "play.fill" : "pause.fill").font(localization.font(11))
                        }
                    }
                }
            }
            .padding(16).frame(maxWidth: 390).frame(maxWidth: .infinity, alignment: .center)
        }
        .font(localization.font(12))
        .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
        .task(id: panel) { if panel == .playlists { await details.load(.playlists, refresh: true) } }
        #if os(macOS)
        .frame(minWidth: 325, idealWidth: 380, minHeight: 200, idealHeight: 330)
        #endif
    }

    private func audienceSamples(live: Bool) -> some View {
        let names = rtl ? ["آوا", "نیما", "سارا", "آرمان", "دریا"] : ["Ava", "Nima", "Sara", "Arman", "Darya"]
        let ids = withUnsafeBytes(of: details.id.uuid) { bytes in Array(bytes) }
        return ForEach(0..<(live ? 3 : names.count), id: \.self) { index in
            let views = Int(ids[index]) % 16 + 2
            let listens = Int(ids[index + 5]) % views + 1
            let device = ["Windows", "Android", "iOS", "macOS", "Web"][Int(ids[index]) % 5]
            HStack(spacing: 7) {
                Text(String(names[index].prefix(1)))
                    .frame(width: 26, height: 26).background(MizonPalette.accent.opacity(0.18), in: .circle)
                Text(names[index]).font(localization.font(12, weight: .semibold))
                Spacer()
                Text(live ? format("AudienceLiveDetails", device, Self.time(Double(10 + Int(ids[index + 5]) % 140)),
                                   text(ids[index + 10] % 4 == 0 ? "AudiencePaused" : "AudiencePlaying"))
                     : format("AudienceHistoryDetails", views.formatted(), listens.formatted()))
                    .font(localization.font(11)).foregroundStyle(.secondary)
            }
        }
    }

    private func panelTitle(_ panel: Panel) -> String {
        switch panel {
        case .support: "Support"
        case .playlists: "AddToPlaylist"
        case .output: "AudioOutput"
        case .views: "ViewsAudience"
        case .live: "LiveAudience"
        case .shortcut: "Shortcut"
        }
    }
}
#endif
