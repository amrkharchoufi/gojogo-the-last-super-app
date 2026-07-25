import SwiftUI

/// Full stories directory — 3-column circle grid (Messages Favorites style).
struct StoriesBrowserView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 28), count: 3)

    var body: some View {
        NavigationStack {
            ZStack {
                GGColor.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 28) {
                        ForEach(app.storyTray) { story in
                            storyCell(story)
                        }

                        Button {
                            app.showStoryComposer = true
                        } label: {
                            VStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(GGColor.surface)
                                        .frame(width: 88, height: 88)
                                    Image(systemName: "plus")
                                        .font(.system(size: 28, weight: .medium))
                                        .foregroundStyle(GGColor.blue)
                                }
                                .overlay(
                                    Circle().strokeBorder(
                                        GGColor.blue.opacity(0.45),
                                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                )
                                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)

                                Text("Add")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(GGColor.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Stories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { app.showStoryArchive = true } label: {
                            Label("Archive", systemImage: "clock.arrow.circlepath")
                        }
                        Button { app.showCloseFriends = true } label: {
                            Label("Close friends", systemImage: "person.2")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(GGColor.blue)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(GGColor.blue)
                }
            }
            .preferredColorScheme(.dark)
        }
        // Present viewer on top of this sheet — do not dismiss back to Home.
        .fullScreenCover(isPresented: Binding(
            get: { app.showStoriesBrowser && app.viewingStory != nil },
            set: { if !$0 { app.closeStoryViewer() } }
        )) {
            StoryViewer()
                .environmentObject(app)
                .interactiveDismissDisabled()
        }
        // The composer, archive and close-friends list open from this sheet, so
        // they have to present from here — RootView's copies stand down while
        // this browser is up.
        .fullScreenCover(isPresented: $app.showStoryComposer) {
            StoryComposer().environmentObject(app)
        }
        .sheet(isPresented: $app.showStoryArchive) {
            StoryArchiveView().environmentObject(app)
        }
        .sheet(isPresented: $app.showCloseFriends) {
            CloseFriendsView().environmentObject(app)
        }
    }

    @ViewBuilder
    private func storyCell(_ story: Story) -> some View {
        let circle = VStack(spacing: 10) {
            UserAvatar(
                size: 88,
                letter: story.letter,
                ring: !story.seen || story.isYou,
                imageURL: story.isYou && !story.hasMedia ? app.user.avatarURL : story.imageURL,
                imageData: story.imageData
            )
            .opacity(story.muted ? 0.55 : 1)
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)

            Text(story.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(story.muted ? GGColor.textTertiary : GGColor.textSecondary)
                .lineLimit(1)
        }

        if story.isYou && !story.hasMedia {
            Button { app.showStoryComposer = true } label: { circle }
                .buttonStyle(.plain)
        } else if story.hasMedia {
            Button {
                app.openStory(story)
            } label: {
                circle
            }
            .buttonStyle(.plain)
            .contextMenu {
                if !story.isYou {
                    Button { app.toggleStoryMute(authorID: story.id) } label: {
                        Label(story.muted ? "Unmute \(story.name)" : "Mute \(story.name)",
                              systemImage: story.muted ? "bell" : "bell.slash")
                    }
                }
            }
        } else {
            circle
        }
    }
}
