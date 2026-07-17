import SwiftUI

struct GojoTVView: View {
    @EnvironmentObject var app: AppState
    @State private var hideChrome = false
    @State private var filter: String = "Home"

    private let filters = ["Home", "My List", "Series", "Docs", "Kids", "Live"]

    private var continueShows: [TVShow] {
        ([app.tvHero] + app.tvShows).filter { $0.progress > 0.05 }
    }

    private var myList: [TVShow] {
        ([app.tvHero] + app.tvShows).filter(\.onWatchlist)
    }

    var body: some View {
        ZStack(alignment: .top) {
            GGColor.bgTV.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    heroCard.padding(.horizontal, 16)

                    filterRow.padding(.horizontal, 16)

                    if filter == "My List" {
                        myListSection
                    } else {
                        if !continueShows.isEmpty {
                            rail(title: "Continue watching", shows: continueShows, style: .landscape)
                        }
                        rail(title: "Top this month",
                             shows: Array(app.tvShows.prefix(4)),
                             style: .poster,
                             ranked: true)
                        rail(title: "Documentaries",
                             shows: app.tvShows.filter { $0.badge.contains("DOC") },
                             style: .landscape)
                        rail(title: "Family time",
                             shows: app.tvShows.filter { ["KIDS", "LIFESTYLE"].contains($0.badge) || $0.title.contains("Kitchen") || $0.title.contains("Cartoon") },
                             style: .landscape)
                        rail(title: "Live & nights",
                             shows: app.tvShows.filter { $0.badge == "LIVE" || $0.title.contains("Night") },
                             style: .landscape)
                        rail(title: "All originals",
                             shows: app.tvShows,
                             style: .poster)
                    }

                    Color.clear.frame(height: tabBarInset)
                }
                .padding(.top, 100)
            }
            .trackScrollChrome(hidden: $hideChrome)

            HStack {
                Wordmark(size: 19, trailing: "tv")
                Spacer()
                WatchSegments(selection: $app.watchSubFeed)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .zIndex(20)
            .autoHideChrome(hideChrome)
        }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters, id: \.self) { item in
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { filter = item }
                    } label: {
                        Text(item)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(filter == item ? GGColor.onAccent : GGColor.textSecondary)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(filter == item ? GGColor.white : GGColor.ink(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var myListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("My List")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)
                .padding(.horizontal, 16)
            if myList.isEmpty {
                Text("Save shows from any title page to build your list.")
                    .font(.system(size: 14))
                    .foregroundStyle(GGColor.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 24)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible(), spacing: 10)], spacing: 12) {
                    ForEach(myList) { show in
                        Button { app.openTVShow(show.id) } label: {
                            MediaImage(url: show.imageURL, cornerRadius: 12)
                                .aspectRatio(2/3, contentMode: .fill)
                                .clipped()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private enum RailStyle { case poster, landscape }

    private func rail(title: String, shows: [TVShow], style: RailStyle, ranked: Bool = false) -> some View {
        Group {
            if !shows.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(GGColor.textPrimary)
                        .padding(.horizontal, 16)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(shows.enumerated()), id: \.element.id) { i, show in
                                Button { app.openTVShow(show.id) } label: {
                                    switch style {
                                    case .poster:
                                        posterCard(show, rank: ranked ? i + 1 : nil)
                                    case .landscape:
                                        landscapeCard(show)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    private func posterCard(_ show: TVShow, rank: Int?) -> some View {
        ZStack(alignment: .bottomLeading) {
            MediaImage(url: show.imageURL, cornerRadius: 16)
                .frame(width: 112, height: 160)
            if let rank {
                Text("\(rank)")
                    .font(.system(size: 64, weight: .heavy))
                    .tracking(-4)
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.8), radius: 12, y: 4)
                    .offset(x: 6, y: 20)
            }
            if show.progress > 0 {
                progressBar(show.progress)
                    .padding(8)
            }
        }
        .frame(width: 112, height: 160)
        .clipped()
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(GGColor.hairline, lineWidth: 1))
    }

    private func landscapeCard(_ show: TVShow) -> some View {
        ZStack(alignment: .bottomLeading) {
            MediaImage(url: show.imageURL, cornerRadius: 16)
                .frame(width: 170, height: 100)
            LinearGradient(colors: [.clear, .black.opacity(0.75)],
                           startPoint: .top, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text(show.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if show.progress > 0 {
                    progressBar(show.progress)
                }
            }
            .padding(10)
        }
        .frame(width: 170, height: 100)
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(GGColor.hairline, lineWidth: 1))
    }

    private func progressBar(_ value: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.28))
                Capsule().fill(Color.white)
                    .frame(width: max(4, geo.size.width * value))
            }
        }
        .frame(height: 3)
    }

    private var heroCard: some View {
        let show = app.tvHero
        return ZStack(alignment: .bottomLeading) {
            MediaImage(url: show.imageURL, cornerRadius: 26)
            VStack { Spacer(); Color.black.opacity(0.6).frame(height: 170) }

            VStack(alignment: .leading, spacing: 10) {
                Text(show.badge)
                    .font(.ggMono(10, .regular)).tracking(2)
                    .foregroundStyle(GGColor.accent)
                Text(show.title)
                    .font(.system(size: 26, weight: .bold)).tracking(-0.6)
                    .foregroundStyle(.white)
                Text(show.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.75))
                HStack(spacing: 10) {
                    Button { app.playTVShow(show) } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "play.fill").font(.system(size: 11))
                            Text(show.progress > 0 ? "Resume" : "Play")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 18).padding(.vertical, 9)
                        .background(Capsule().fill(Color.white.opacity(0.95)))
                    }
                    .buttonStyle(PressableStyle())

                    Button { app.toggleTVWatchlist(show.id) } label: {
                        HStack(spacing: 7) {
                            Image(systemName: show.onWatchlist ? "checkmark" : "plus")
                                .font(.system(size: 11, weight: .semibold))
                            Text(show.onWatchlist ? "Listed" : "My List")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Capsule().fill(Color.white.opacity(0.16)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
                    }
                    .buttonStyle(PressableStyle())

                    Button { app.openTVShow(show.id) } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Color.white.opacity(0.16)))
                    }
                    .buttonStyle(PressableStyle())
                }
                if show.progress > 0 {
                    progressBar(show.progress)
                        .padding(.top, 4)
                }
            }
            .padding(18)
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(GGColor.hairline, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 26))
        .onTapGesture { app.openTVShow(show.id) }
    }
}

// MARK: - Title detail

struct TVShowDetailView: View {
    @EnvironmentObject var app: AppState
    let showID: UUID

    private var show: TVShow {
        if app.tvHero.id == showID { return app.tvHero }
        return app.tvShows.first(where: { $0.id == showID })
            ?? TVShow(title: "Title", subtitle: "", synopsis: "", gradient: SampleData.g1)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    MediaImage(url: show.imageURL, cornerRadius: 0)
                        .frame(height: 320)
                        .clipped()
                    LinearGradient(colors: [.clear, GGColor.bg], startPoint: .center, endPoint: .bottom)
                    Button { app.closeTVShow() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.black.opacity(0.45)))
                    }
                    .padding(16)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text(show.badge)
                        .font(.ggMono(11, .medium)).tracking(1.2)
                        .foregroundStyle(GGColor.textSecondary)
                    Text(show.title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(GGColor.textPrimary)
                    Text(show.subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(GGColor.textSecondary)

                    HStack(spacing: 10) {
                        Button { app.playTVShow(show) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                Text(show.progress > 0 ? "Resume" : "Play")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(GGColor.onAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(GGColor.white))
                        }
                        .buttonStyle(PressableStyle())

                        Button { app.toggleTVWatchlist(show.id) } label: {
                            Image(systemName: show.onWatchlist ? "checkmark" : "plus")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(GGColor.textPrimary)
                                .frame(width: 52, height: 52)
                                .glassCapsule(interactive: false)
                        }
                        .buttonStyle(PressableStyle())
                    }

                    Text(show.synopsis)
                        .font(.system(size: 15))
                        .foregroundStyle(GGColor.textSecondary)
                        .lineSpacing(4)

                    if !show.episodes.isEmpty {
                        Text("Episodes")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(GGColor.textPrimary)
                            .padding(.top, 8)

                        VStack(spacing: 10) {
                            ForEach(show.episodes) { ep in
                                Button { app.playEpisode(showID: show.id, episodeID: ep.id) } label: {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(GGColor.ink(0.08))
                                                .frame(width: 64, height: 40)
                                            Image(systemName: ep.watched ? "checkmark" : "play.fill")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(GGColor.textPrimary)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(ep.number). \(ep.title)")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(GGColor.textPrimary)
                                            Text(ep.duration)
                                                .font(.system(size: 12))
                                                .foregroundStyle(GGColor.textTertiary)
                                        }
                                        Spacer()
                                    }
                                    .padding(12)
                                    .glass(cornerRadius: 14, fillOpacity: 0.04, borderOpacity: 0.08)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 40)
            }
        }
        .background(GGColor.bg.ignoresSafeArea())
    }
}
