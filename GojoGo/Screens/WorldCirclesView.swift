import SwiftUI

/// Circles management — the audience primitive, now server-side.
///
/// Circles were a phone-local UI convenience until Phase 2f. They could not stay
/// that way: an audience that exists only on one handset can't decide who reads
/// a post. A circle may only contain people you actually have as contacts, which
/// the server enforces — publishing to a circle can never reach outside your graph.
struct WorldCirclesView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var editing: WorldCircle?
    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            Group {
                if app.worldCircles.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(IMColor.sheetBG.ignoresSafeArea())
            .navigationTitle("Circles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        editing = nil
                        showEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showEditor) {
                WorldCircleEditor(circle: editing)
            }
            .task { await app.loadWorldGraph() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "circle.grid.2x2")
                .font(.system(size: 34))
                .foregroundStyle(IMColor.secondary)
            Text("No circles yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(IMColor.label)
            Text("A circle is a group of your contacts you can post to — family, work, the five-a-side team. One person can be in as many as you like.")
                .font(.system(size: 14))
                .foregroundStyle(IMColor.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Button("Create a circle") {
                editing = nil
                showEditor = true
            }
            .font(.system(size: 15, weight: .semibold))
            .padding(.top, 4)
        }
    }

    private var list: some View {
        List {
            ForEach(app.worldCircles) { circle in
                Button {
                    editing = circle
                    showEditor = true
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(hex: circle.colorHex))
                            .frame(width: 14, height: 14)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(circle.name)
                                .font(.system(size: 16))
                                .foregroundStyle(IMColor.label)
                            Text(memberSummary(circle))
                                .font(.system(size: 13))
                                .foregroundStyle(IMColor.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(IMColor.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                for i in offsets { app.deleteWorldCircle(app.worldCircles[i].id) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func memberSummary(_ circle: WorldCircle) -> String {
        if circle.memberIDs.isEmpty { return "No members yet" }
        let names = circle.memberIDs.compactMap { id in
            app.worldContactsForPicker.first { $0.id == id }?.effectiveName
        }
        let shown = names.prefix(3).joined(separator: ", ")
        return names.count > 3 ? "\(shown) +\(names.count - 3)" : shown
    }
}

// MARK: - Create / edit one circle

struct WorldCircleEditor: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let circle: WorldCircle?

    @State private var name = ""
    @State private var colorHex = "3A3A3C"
    @State private var members: Set<UUID> = []
    @State private var busy = false

    private static let palette = ["3A3A3C", "0A84FF", "30D158", "FF9F0A", "AF52DE", "FF375F"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Family, work, five-a-side…", text: $name)
                }
                Section("Colour") {
                    HStack(spacing: 12) {
                        ForEach(Self.palette, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle().strokeBorder(
                                        colorHex == hex ? IMColor.label : .clear, lineWidth: 2))
                                .onTapGesture { colorHex = hex }
                        }
                    }
                }
                Section {
                    if app.worldContactsForPicker.isEmpty {
                        Text("Add somebody by phone number first — a circle can only contain your contacts.")
                            .font(.system(size: 13))
                            .foregroundStyle(IMColor.secondary)
                    }
                    ForEach(app.worldContactsForPicker) { contact in
                        Button {
                            if members.contains(contact.id) {
                                members.remove(contact.id)
                            } else {
                                members.insert(contact.id)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                MediaImage(url: contact.avatarURL, cornerRadius: 16)
                                    .frame(width: 32, height: 32)
                                    .clipShape(Circle())
                                Text(contact.effectiveName)
                                    .foregroundStyle(IMColor.label)
                                Spacer()
                                Image(systemName: members.contains(contact.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(members.contains(contact.id)
                                                     ? IMColor.blue : IMColor.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Members")
                } footer: {
                    Text("Only your contacts can be in a circle, so a post to this circle can never reach somebody outside your graph.")
                }
            }
            .navigationTitle(circle == nil ? "New circle" : "Edit circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "Saving…" : "Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                if let circle {
                    name = circle.name
                    colorHex = circle.colorHex
                    members = Set(circle.memberIDs)
                }
            }
        }
    }

    private func save() {
        busy = true
        Task {
            let ok = await app.saveWorldCircle(
                id: circle?.id,
                name: name.trimmingCharacters(in: .whitespaces),
                colorHex: colorHex,
                members: Array(members))
            busy = false
            if ok { dismiss() }
        }
    }
}
