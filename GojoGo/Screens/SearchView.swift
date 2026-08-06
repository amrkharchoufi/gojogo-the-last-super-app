import SwiftUI

// MARK: - Search, live against the index (Phase 5 · M4)
//
// This screen used to filter whatever the app happened to have in memory, which
// meant it could only ever find things you had already scrolled past. It now
// asks `GET /v1/search` — one query across posts, marketplace listings, shop
// products and services, ranked server-side by relevance × popularity.
//
// What stays local is what the index does not carry: videos, shorts and GojoTV
// have no upsert signal into `search` yet, and people are answered by the
// profile search that has always existed. Those sections are kept rather than
// dropped, and they are kept *below* the live ones, because a result the server
// ranked is a better answer than a substring match on a cached title.
//
// The query text lives in this view and never in AppState. A keystroke that
// republished the whole app would re-render every screen behind this one.

private enum SearchScope: String, CaseIterable {
    case all, people, posts, market, shops, services

    /// What the server is asked for. `nil` means "not a server scope" — people
    /// are answered by `SocialStore`, and `all` asks for everything.
    var kind: SearchKind? {
        switch self {
        case .posts: return .post
        case .market: return .listing
        case .shops: return .product
        case .services: return .service
        case .all, .people: return nil
        }
    }

    var label: String { self == .market ? "market" : rawValue }
}

struct SearchView: View {
    @EnvironmentObject var app: AppState
    @State private var query = ""
    @State private var scope: SearchScope = .all
    @FocusState private var focused: Bool

    /// Live results, held here rather than in AppState — see the note above.
    @State private var hits: [SearchHitDTO] = []
    @State private var trending: [SearchHitDTO] = []
    @State private var people: [MentionCandidate] = []
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isSearching: Bool { !trimmed.isEmpty }

    // MARK: Live results across the whole app

    private var matchedVideos: [VideoItem] {
        app.videos.filter {
            $0.title.lowercased().contains(trimmed)
                || $0.channel.lowercased().contains(trimmed)
                || $0.details.lowercased().contains(trimmed)
        }
    }

    private var matchedShorts: [Short] {
        app.shorts.filter {
            $0.caption.lowercased().contains(trimmed) || $0.channel.lowercased().contains(trimmed)
        }
    }

    private var matchedShows: [TVShow] {
        ([app.tvHero] + app.tvShows).filter {
            !$0.title.isEmpty
                && ($0.title.lowercased().contains(trimmed)
                    || $0.synopsis.lowercased().contains(trimmed))
        }
    }

    /// The server's answer for the scope in hand. `all` shows everything it
    /// returned; a kind scope was already filtered server-side.
    private var visibleHits: [SearchHitDTO] { hits }

    /// Local Watch matches only make sense while the whole app is in scope —
    /// they are not in the index, so a "services" scope must never quietly
    /// return a short.
    private var showsLocalContent: Bool { scope == .all }

    private var hasResults: Bool {
        if !visibleHits.isEmpty { return true }
        if scope == .all || scope == .people { if !people.isEmpty { return true } }
        guard showsLocalContent else { return false }
        return !(matchedVideos.isEmpty && matchedShorts.isEmpty && matchedShows.isEmpty)
    }

    var body: some View {
        ZStack(alignment: .top) {
            GGBackground(glow: GGColor.accent.opacity(0.12))

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Search").font(.system(size: 34, weight: .bold)).tracking(-1)
                            .foregroundStyle(GGColor.textPrimary)
                        Text("People, content, products — or just say what you want. Madeleine finds it.")
                            .explanatory(15).lineSpacing(2)
                            .foregroundStyle(GGColor.textSecondary)
                            .frame(maxWidth: 300, alignment: .leading)
                    }

                    searchCard

                    if isSearching {
                        if hasResults {
                            resultsSections
                        } else if searching {
                            searchingRows
                        } else {
                            noResults
                        }
                    } else {
                        defaultSections
                    }

                    Color.clear.frame(height: tabBarInset)
                }
                .padding(.horizontal, 20)
                .padding(.top, 130)
            }
            .scrollDismissesKeyboard(.immediately)
            // Debounced rather than per-keystroke: the index is a round trip,
            // and a query fired on every letter is five requests to answer one
            // question. The task is cancelled and replaced, so the answer on
            // screen is always the one for the text on screen.
            .onChange(of: query) { _, _ in scheduleSearch() }
            .onChange(of: scope) { _, _ in scheduleSearch(immediate: true) }
            .task { await loadTrending() }

            HStack { Wordmark(size: 19); Spacer() }
                .padding(.horizontal, 20).padding(.top, 8)

            // A result that has been deleted since it was indexed fails on the
            // tap, and this screen is the only place that can say so — the
            // banner otherwise only exists on the Economy surfaces, which is
            // where a search failure would have gone to die.
            if let notice = app.economyNotice {
                EconomyNoticeBanner(message: notice) { app.dismissEconomyNotice() }
                    .padding(.horizontal, 20)
                    .padding(.top, 44)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(3)
            }
        }
        .animation(.ggOverlay, value: app.economyNotice)
    }

    // MARK: Search card

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("I'm looking for…", text: $query, axis: .vertical)
                .font(.system(size: 15)).lineSpacing(2)
                .foregroundStyle(GGColor.textPrimary.opacity(0.92))
                .focused($focused)
                .lineLimit(2...4)
            // Scopes and the ask-Madeleine arrow share one row, as they always
            // have. Phase 5 split them onto two — six scopes don't fit where
            // four did — which pushed the arrow onto a line of its own and left
            // the last chip guillotined mid-word. They still don't fit, so the
            // strip scrolls; the fade is what says so, rather than a hard cut.
            HStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(SearchScope.allCases, id: \.self) { s in
                            Button {
                                withAnimation(.ggSnappy) { scope = s }
                            } label: {
                                MonoChip(text: s.label, active: scope == s)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.trailing, 4)
                }
                .mask(scopeFade)

                // A fixed slot: the spinner comes and goes on every keystroke,
                // and the arrow must not move when it does.
                ZStack {
                    if searching {
                        ProgressView()
                            .controlSize(.small)
                            .tint(GGColor.textTertiary)
                    }
                }
                .frame(width: 14)

                Button {
                    focused = false
                    if !query.isEmpty { app.sendMadeleine(query); app.activeTab = .madeleine }
                } label: {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(GGColor.onAccent)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(GGColor.blue))
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(18)
        .glass(cornerRadius: 22, fillOpacity: 0.06, borderOpacity: 0.12)
    }

    /// Opaque until the last few points, so a chip running past the edge
    /// dissolves into the card instead of being cut through the middle of a
    /// letter. Leading stays hard — nothing is ever hidden on that side.
    private var scopeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: 0.9),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading, endPoint: .trailing
        )
    }

    // MARK: Results

    @ViewBuilder
    private var resultsSections: some View {
        // The indexed kinds first, in the order the server ranked them within
        // each kind. Grouped rather than interleaved: a listing and a service
        // are answers to different questions, and a mixed list makes the reader
        // sort them by eye.
        ForEach(SearchKind.allCases) { kind in
            let group = visibleHits.filter { $0.searchKind == kind }
            if !group.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: kind.label)
                    ForEach(group) { hit in hitRow(hit) }
                }
            }
        }

        if scope == .all || scope == .people {
            if !people.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "People")
                    ForEach(people.prefix(6)) { candidate in candidateRow(candidate) }
                }
            }
        }

        if showsLocalContent {
            if !matchedVideos.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Videos")
                    ForEach(matchedVideos.prefix(4)) { videoRow($0) }
                }
            }
            if !matchedShorts.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Shorts")
                    shortsRail
                }
            }
            if !matchedShows.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "On GojoTV")
                    showsRail
                }
            }
        }

    }

    /// Rows that stand in for an answer that hasn't landed. Deliberately not a
    /// spinner over the whole screen: the previous answer stays readable until
    /// the new one replaces it.
    private var searchingRows: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(GGColor.ink(0.06))
                    .frame(height: 62)
                    .shimmering()
            }
        }
    }

    /// One indexed result. The snippet is the server's, trimmed there rather
    /// than here, so what is shown is what was matched.
    private func hitRow(_ hit: SearchHitDTO) -> some View {
        Button {
            focused = false
            app.openSearchHit(hit)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: hit.searchKind?.icon ?? "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GGColor.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(GGColor.ink(0.08)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(hit.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                    if let snippet = hit.snippet, !snippet.isEmpty {
                        Text(snippet)
                            .font(.system(size: 12))
                            .foregroundStyle(GGColor.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                if let category = hit.category, !category.isEmpty {
                    Text(category)
                        .font(.ggMono(9, .semibold))
                        .tracking(0.6)
                        .foregroundStyle(GGColor.textTertiary)
                }
            }
            .padding(12)
            .glass(cornerRadius: 16, fillOpacity: 0.04, borderOpacity: 0.08)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A person, from the profile search that has always existed — the index
    /// does not carry accounts.
    private func candidateRow(_ candidate: MentionCandidate) -> some View {
        Button {
            focused = false
            app.openUserProfile(handle: candidate.handle, avatarURL: candidate.avatarURL,
                                avatarGradient: SocialStore.gradient(for: candidate.handle))
        } label: {
            HStack(spacing: 12) {
                UserAvatar(size: 44, letter: String(candidate.handle.prefix(1)).uppercased(),
                           imageURL: candidate.avatarURL)
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                    Text("@\(candidate.handle)")
                        .font(.system(size: 12))
                        .foregroundStyle(GGColor.textTertiary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Running the query

    private func scheduleSearch(immediate: Bool = false) {
        searchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            hits = []
            people = []
            searching = false
            return
        }
        searching = true
        searchTask = Task {
            if !immediate {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            guard !Task.isCancelled else { return }
            async let indexed = try? await SearchStore.shared.search(text, kind: scope.kind)
            async let profiles = (scope == .all || scope == .people)
                ? try? await SocialStore.shared.searchProfiles(text)
                : []
            let (foundHits, foundPeople) = await (indexed, profiles)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                hits = foundHits ?? []
                people = foundPeople ?? []
                searching = false
            }
        }
    }

    private func loadTrending() async {
        guard trending.isEmpty else { return }
        let rail = (try? await SearchStore.shared.trending()) ?? []
        withAnimation(.easeOut(duration: 0.2)) { trending = rail }
    }

    private var noResults: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(GGColor.textTertiary)
            Text("Nothing for “\(query)” yet.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GGColor.textSecondary)
            Text("Try another spelling — or ask Madeleine with the arrow above.")
                .font(.system(size: 13))
                .foregroundStyle(GGColor.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    private func videoRow(_ v: VideoItem) -> some View {
        Button {
            app.playVideo(v.id)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    MediaImage(url: v.thumbURL, data: v.thumbData, cornerRadius: 10)
                        .frame(width: 92, height: 54)
                        .clipped()
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(v.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(v.meta)
                        .font(.system(size: 11))
                        .foregroundStyle(GGColor.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(10)
            .glass(cornerRadius: 16, fillOpacity: 0.04, borderOpacity: 0.08)
        }
        .buttonStyle(.plain)
    }

    private var shortsRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(matchedShorts.prefix(6)) { short in
                    Button {
                        app.focusedShortID = short.id
                        withAnimation(.ggTab) {
                            app.activeTab = .watch
                            app.watchSubFeed = .shorts
                        }
                    } label: {
                        ZStack(alignment: .bottomLeading) {
                            MediaImage(url: short.imageURL, data: short.imageData, cornerRadius: 14)
                                .frame(width: 104, height: 185) // 9:16 Reels thumb
                                .clipped()
                            LinearGradient(colors: [.clear, .black.opacity(0.7)],
                                           startPoint: .center, endPoint: .bottom)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            Text(short.channel)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .padding(8)
                        }
                        .frame(width: 104, height: 185)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var showsRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(matchedShows.prefix(6)) { show in
                    Button { app.openTVShow(show.id) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            MediaImage(url: show.imageURL, cornerRadius: 14)
                                .frame(width: 104, height: 148)
                                .clipped()
                            Text(show.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(GGColor.textPrimary)
                                .lineLimit(1)
                        }
                        .frame(width: 104, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func productRow(_ p: Product) -> some View {
        Button {
            app.openProduct(p)
        } label: {
            HStack(spacing: 12) {
                MediaImage(url: p.imageURL, cornerRadius: 10)
                    .frame(width: 52, height: 52)
                    .clipped()
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                        .lineLimit(1)
                    Text("\(p.condition) · \(p.distance) · \(p.seller)")
                        .font(.system(size: 11))
                        .foregroundStyle(GGColor.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                Text(p.price)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(GGColor.accent)
            }
            .padding(12)
            .glass(cornerRadius: 16, fillOpacity: 0.04, borderOpacity: 0.08)
        }
        .buttonStyle(.plain)
    }

    // MARK: Default (no query)

    @ViewBuilder
    private var defaultSections: some View {
        // Trending is an aggregate on a 15-minute server cache, so it is asked
        // once per appearance and not per keystroke.
        if !trending.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Trending now")
                ForEach(trending.prefix(6)) { hit in hitRow(hit) }
            }
        }

        let hasDiscover = !app.people.isEmpty
            || !SampleData.searchContent.isEmpty
            || !app.products.isEmpty

        if !hasDiscover && trending.isEmpty {
            GGEmptyState(
                icon: "magnifyingglass",
                title: "Nothing to discover yet",
                message: "Search will surface people, posts, and products as they appear."
            )
            .padding(.top, 24)
        } else {
            if !app.people.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "People you might know")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(app.people) { p in
                                VStack(spacing: 6) {
                                    Button {
                                        app.openUserProfile(handle: p.name, avatarURL: p.avatarURL,
                                                            avatarGradient: p.gradient)
                                    } label: {
                                        UserAvatar(size: 56, letter: String(p.name.prefix(1)).uppercased(),
                                                   imageURL: p.avatarURL)
                                            .overlay(Circle().strokeBorder(
                                                p.following ? GGColor.blue : GGColor.ink(0.1),
                                                lineWidth: p.following ? 2 : 1))
                                    }
                                    .buttonStyle(.plain)

                                    Text(p.name).font(.system(size: 11))
                                        .foregroundStyle(GGColor.textSecondary)

                                    Button {
                                        withAnimation(.ggSnappy) { app.toggleFollowPerson(p.id) }
                                    } label: {
                                        Text(p.following ? "Following" : "Follow")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(p.following ? GGColor.textTertiary : GGColor.blue)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }

            if !SampleData.searchContent.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Content to interest you")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                        GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(SampleData.searchContent) { tile in
                            Button { app.activeTab = .watch } label: {
                                ZStack(alignment: .bottomLeading) {
                                    MediaImage(url: tile.imageURL, cornerRadius: 18)
                                    LinearGradient(colors: [.clear, .black.opacity(0.65)],
                                                   startPoint: .center, endPoint: .bottom)
                                        .clipShape(RoundedRectangle(cornerRadius: 18))
                                    Text(tile.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.9))
                                        .padding(10)
                                }
                                .frame(height: 96)
                                .overlay(RoundedRectangle(cornerRadius: 18)
                                    .strokeBorder(GGColor.ink(0.09), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if !app.products.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Trending on Economy")
                    ForEach(Array(app.products.prefix(3))) { productRow($0) }
                }
            }
        }
    }
}
