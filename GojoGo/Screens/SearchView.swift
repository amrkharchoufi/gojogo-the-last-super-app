import SwiftUI

private enum SearchScope: String, CaseIterable {
    case all, people, content, shop
}

struct SearchView: View {
    @EnvironmentObject var app: AppState
    @State private var query = ""
    @State private var scope: SearchScope = .all
    @FocusState private var focused: Bool

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isSearching: Bool { !trimmed.isEmpty }

    // MARK: Live results across the whole app

    private var matchedPeople: [PersonSuggestion] {
        app.people.filter { $0.name.lowercased().contains(trimmed) }
    }

    private var matchedPosts: [Post] {
        app.posts.filter {
            $0.author.lowercased().contains(trimmed)
                || ($0.text?.lowercased().contains(trimmed) ?? false)
        }
    }

    private var matchedVideos: [VideoItem] {
        app.videos.filter {
            $0.title.lowercased().contains(trimmed) || $0.channel.lowercased().contains(trimmed)
        }
    }

    private var matchedShorts: [Short] {
        app.shorts.filter {
            $0.caption.lowercased().contains(trimmed) || $0.channel.lowercased().contains(trimmed)
        }
    }

    private var matchedProducts: [Product] {
        ([app.featuredProduct] + app.products).filter {
            $0.name.lowercased().contains(trimmed)
                || $0.category.lowercased().contains(trimmed)
                || $0.seller.lowercased().contains(trimmed)
        }
    }

    private var matchedShows: [TVShow] {
        ([app.tvHero] + app.tvShows).filter {
            $0.title.lowercased().contains(trimmed) || $0.synopsis.lowercased().contains(trimmed)
        }
    }

    private var hasResults: Bool {
        switch scope {
        case .all:
            return !(matchedPeople.isEmpty && matchedPosts.isEmpty && matchedVideos.isEmpty
                     && matchedShorts.isEmpty && matchedProducts.isEmpty && matchedShows.isEmpty)
        case .people: return !matchedPeople.isEmpty
        case .content: return !(matchedPosts.isEmpty && matchedVideos.isEmpty && matchedShorts.isEmpty && matchedShows.isEmpty)
        case .shop: return !matchedProducts.isEmpty
        }
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

            HStack { Wordmark(size: 19); Spacer() }
                .padding(.horizontal, 20).padding(.top, 8)
        }
    }

    // MARK: Search card

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("I'm looking for…", text: $query, axis: .vertical)
                .font(.system(size: 15)).lineSpacing(2)
                .foregroundStyle(GGColor.textPrimary.opacity(0.92))
                .focused($focused)
                .lineLimit(2...4)
            HStack(spacing: 8) {
                ForEach(SearchScope.allCases, id: \.self) { s in
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { scope = s }
                    } label: {
                        MonoChip(text: s.rawValue, active: scope == s)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
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

    // MARK: Results

    @ViewBuilder
    private var resultsSections: some View {
        if scope == .all || scope == .people {
            if !matchedPeople.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "People")
                    ForEach(matchedPeople.prefix(5)) { personRow($0) }
                }
            }
        }

        if scope == .all || scope == .content {
            if !matchedPosts.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Posts")
                    ForEach(matchedPosts.prefix(4)) { postRow($0) }
                }
            }
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

        if scope == .all || scope == .shop {
            if !matchedProducts.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Economy")
                    ForEach(matchedProducts.prefix(5)) { productRow($0) }
                }
            }
        }
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

    private func personRow(_ p: PersonSuggestion) -> some View {
        HStack(spacing: 12) {
            Button {
                app.openUserProfile(handle: p.name, avatarURL: p.avatarURL,
                                    avatarGradient: p.gradient)
            } label: {
                HStack(spacing: 12) {
                    UserAvatar(size: 44, letter: String(p.name.prefix(1)).uppercased(),
                               imageURL: p.avatarURL)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(GGColor.textPrimary)
                        Text("On gojogo")
                            .font(.system(size: 12))
                            .foregroundStyle(GGColor.textTertiary)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeOut(duration: 0.2)) { app.toggleFollowPerson(p.id) }
            } label: {
                Text(p.following ? "Following" : "Follow")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(p.following ? GGColor.textSecondary : .black)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(p.following ? GGColor.ink(0.1) : Color.white))
            }
            .buttonStyle(PressableStyle())
        }
    }

    private func postRow(_ post: Post) -> some View {
        Button {
            app.openPostViewer(post.id)
        } label: {
            HStack(spacing: 12) {
                UserAvatar(size: 40, gradient: post.avatarGradient,
                           letter: String(post.author.prefix(1)).uppercased(),
                           imageURL: post.avatarURL)
                VStack(alignment: .leading, spacing: 3) {
                    Text(post.author)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                    if let text = post.text {
                        Text(text)
                            .font(.system(size: 13))
                            .foregroundStyle(GGColor.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer()
                if post.imageURL != nil || post.imageData != nil {
                    MediaImage(url: post.imageURL, data: post.imageData, cornerRadius: 8)
                        .frame(width: 48, height: 48)
                        .clipped()
                }
            }
            .padding(12)
            .glass(cornerRadius: 16, fillOpacity: 0.04, borderOpacity: 0.08)
        }
        .buttonStyle(.plain)
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
                        withAnimation(.easeOut(duration: 0.25)) {
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
                                withAnimation(.easeOut(duration: 0.2)) { app.toggleFollowPerson(p.id) }
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

        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Trending on Economy")
            ForEach(Array(app.products.prefix(3))) { productRow($0) }
        }
    }
}
