import SwiftUI

struct SearchView: View {
    @EnvironmentObject var app: AppState
    @State private var query = ""
    @FocusState private var focused: Bool

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

                    VStack(alignment: .leading, spacing: 14) {
                        TextField("I'm looking for…", text: $query, axis: .vertical)
                            .font(.system(size: 15)).lineSpacing(2)
                            .foregroundStyle(GGColor.textPrimary.opacity(0.92))
                            .focused($focused)
                            .lineLimit(2...4)
                        HStack(spacing: 8) {
                            MonoChip(text: "people", active: true)
                            MonoChip(text: "groups")
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

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "People you might know")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(app.people) { p in
                                    Button {
                                        app.toggleFollowPerson(p.id)
                                    } label: {
                                        VStack(spacing: 6) {
                                            UserAvatar(size: 56, letter: String(p.name.prefix(1)).uppercased(),
                                                       imageURL: p.avatarURL)
                                                .overlay(Circle().strokeBorder(
                                                    p.following ? GGColor.blue : Color.white.opacity(0.1),
                                                    lineWidth: p.following ? 2 : 1))
                                            Text(p.name).font(.system(size: 11))
                                                .foregroundStyle(GGColor.textSecondary)
                                            Text(p.following ? "Following" : "Follow")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(p.following ? GGColor.textTertiary : GGColor.blue)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Content to interest you")
                        HStack(spacing: 10) {
                            ForEach(SampleData.searchContent) { tile in
                                Button { app.activeTab = .watch } label: {
                                    ZStack(alignment: .bottomLeading) {
                                        MediaImage(url: tile.imageURL, cornerRadius: 18)
                                        Text(tile.title)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.9))
                                            .padding(10)
                                    }
                                    .frame(height: 96)
                                    .overlay(RoundedRectangle(cornerRadius: 18)
                                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
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
}
