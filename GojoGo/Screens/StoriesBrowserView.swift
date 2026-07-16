import SwiftUI
import PhotosUI

/// Full stories directory — 3-column circle grid (Messages Favorites style).
struct StoriesBrowserView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var storyPicker: PhotosPickerItem?

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

                        PhotosPicker(selection: $storyPicker, matching: .images) {
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
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Stories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(GGColor.blue)
                }
            }
            .preferredColorScheme(.dark)
        }
        .onChange(of: storyPicker) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self) {
                    app.addStory(imageData: data)
                    storyPicker = nil
                }
            }
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
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)

            Text(story.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(GGColor.textSecondary)
                .lineLimit(1)
        }

        if story.isYou && !story.hasMedia {
            PhotosPicker(selection: $storyPicker, matching: .images) { circle }
        } else if story.hasMedia {
            Button {
                app.openStory(story)
            } label: {
                circle
            }
            .buttonStyle(.plain)
        } else {
            circle
        }
    }
}
