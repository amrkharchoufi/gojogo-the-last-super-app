import SwiftUI
import PhotosUI
import UIKit

struct ComposePostView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var imageData: Data?

    var body: some View {
        NavigationStack {
            ZStack {
                GGColor.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 12) {
                            UserAvatar(size: 40, letter: String(app.user.name.prefix(1)),
                                       imageURL: app.user.avatarURL)
                            TextField("Share something…", text: $text, axis: .vertical)
                                .font(.system(size: 16))
                                .foregroundStyle(GGColor.textPrimary)
                                .lineLimit(4...12)
                        }

                        if let imageData, let ui = UIImage(data: imageData) {
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: ui)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 260)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                Button {
                                    self.imageData = nil
                                    pickerItem = nil
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 28, height: 28)
                                        .background(Circle().fill(Color.black.opacity(0.55)))
                                }
                                .padding(10)
                            }
                        }

                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label(imageData == nil ? "Add photo" : "Change photo",
                                  systemImage: "photo")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(GGColor.accent)
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .glassCapsule()
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("New post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(GGColor.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        app.publishPost(text: text, imageData: imageData)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(canPost ? GGColor.accent : GGColor.textTertiary)
                    .disabled(!canPost)
                }
            }
            .preferredColorScheme(.dark)
        }
        .onChange(of: pickerItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self) {
                    imageData = data
                }
            }
        }
    }

    private var canPost: Bool {
        imageData != nil || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
