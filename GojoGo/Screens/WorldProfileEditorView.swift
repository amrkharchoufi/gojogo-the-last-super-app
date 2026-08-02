import SwiftUI

/// The rich GojoMessages profile.
///
/// This hangs off the **phone-verified identity**, not the public account. That
/// is the whole reason it exists here: the face you show forty people who have
/// your number is not the face you show the internet, and GojoGo deliberately
/// keeps the two accounts apart (ARCHITECTURE §2b decision 4).
///
/// Education is a plain text field. A worldwide schools database is a vendor and
/// a licence fee; an autocomplete can be layered onto this same field later
/// without migrating anything, and nobody has typed a school name yet.
struct WorldProfileEditorView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var draft = WorldRichProfile()
    @State private var busy = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("A line about you", text: $draft.bio, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("Bio")
                } footer: {
                    Text("Only people who have your number see this.")
                }

                Section("Basics") {
                    TextField("Gender", text: $draft.gender)
                    TextField("Current city", text: $draft.city)
                    TextField("Occupation", text: $draft.occupation)
                    TextField("Education", text: $draft.education)
                }

                listSection("Languages", placeholder: "English, Darija, French",
                            values: $draft.languages)
                listSection("Interests & hobbies", placeholder: "Climbing, cooking, chess",
                            values: $draft.interests)
                listSection("Favourite books", placeholder: "Add a book", values: $draft.favouriteBooks)
                listSection("Favourite films", placeholder: "Add a film", values: $draft.favouriteFilms)
                listSection("Favourite TV", placeholder: "Add a show", values: $draft.favouriteTv)
                listSection("Sport", placeholder: "Add a sport", values: $draft.favouriteSport)
                listSection("Games", placeholder: "Add a game", values: $draft.favouriteGames)
            }
            .navigationTitle("Your profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "Saving…" : "Save") { save() }
                        .disabled(busy)
                        .fontWeight(.semibold)
                }
            }
            .task {
                guard !loaded else { return }
                await app.loadWorldGraph()
                draft = app.worldRichProfile
                loaded = true
            }
        }
    }

    /// A comma-separated editor over a list — cheaper than a chip editor and
    /// exactly as expressive for fields nobody queries on.
    private func listSection(_ title: String, placeholder: String,
                             values: Binding<[String]>) -> some View {
        Section(title) {
            TextField(placeholder, text: Binding(
                get: { values.wrappedValue.joined(separator: ", ") },
                set: { raw in
                    values.wrappedValue = raw
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                }), axis: .vertical)
                .lineLimit(1...3)
        }
    }

    private func save() {
        busy = true
        Task {
            let ok = await app.saveWorldRichProfile(draft)
            busy = false
            if ok { dismiss() }
        }
    }
}

// MARK: - Read-only rendering (contact page)

/// Somebody else's rich profile, shown on their contact page. Only ever rendered
/// when the server said the viewer is actually a contact — knowing a number is
/// how you reach someone, not a licence to read where they went to school.
struct WorldRichProfileCard: View {
    let profile: WorldRichProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !profile.bio.isEmpty {
                Text(profile.bio)
                    .font(.system(size: 15))
                    .foregroundStyle(IMColor.label)
            }
            row("Lives in", profile.city)
            row("Works as", profile.occupation)
            row("Studied", profile.education)
            row("Speaks", profile.languages.joined(separator: ", "))
            row("Into", profile.interests.joined(separator: ", "))
            row("Books", profile.favouriteBooks.joined(separator: ", "))
            row("Films", profile.favouriteFilms.joined(separator: ", "))
            row("TV", profile.favouriteTv.joined(separator: ", "))
            row("Sport", profile.favouriteSport.joined(separator: ", "))
            row("Games", profile.favouriteGames.joined(separator: ", "))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(IMColor.chrome.opacity(0.55)))
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(IMColor.secondary)
                    .frame(width: 68, alignment: .leading)
                Text(value)
                    .font(.system(size: 14))
                    .foregroundStyle(IMColor.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
