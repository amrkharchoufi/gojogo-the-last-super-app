import SwiftUI

struct MadeleineHomeView: View {
    @EnvironmentObject var app: AppState
    @State private var appear = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            GGColor.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                if app.chatMessages.isEmpty {
                    emptyState
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(app.chatMessages) { msg in
                                    chatBubble(msg).id(msg.id)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 70)
                            .padding(.bottom, 20)
                        }
                        .onChange(of: app.chatMessages.count) { _, _ in
                            if let last = app.chatMessages.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }
                }

                inputBar
                    .padding(.bottom, tabBarInset - 20)
            }

            HStack {
                Text("MADELEINE")
                    .font(.ggMono(13, .semibold)).tracking(0.4)
                    .foregroundStyle(GGColor.textSecondary)
                Spacer()
                if !app.chatMessages.isEmpty {
                    Button("Clear") {
                        withAnimation { app.chatMessages.removeAll() }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GGColor.textTertiary)
                }
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.7)) { appear = true } }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            MadeleineOrb(size: 120)
                .padding(.top, 150)
                .opacity(appear ? 1 : 0)

            Text("Hey, \(app.user.name)")
                .font(.system(size: 36, weight: .bold)).tracking(-1)
                .foregroundStyle(GGColor.textPrimary)
                .padding(.top, 36)
            Text("How can we help?")
                .explanatory(18).foregroundStyle(GGColor.textSecondary)
                .padding(.top, 6)

            VStack(spacing: 10) {
                let items = SampleData.madeleineSuggestions
                ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { i in
                    HStack(spacing: 10) {
                        suggestion(items[i])
                        if i + 1 < items.count {
                            suggestion(items[i + 1])
                        }
                    }
                }
            }
            .padding(.top, 44)
            .opacity(appear ? 1 : 0)

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask Madeleine…", text: $draft, axis: .vertical)
                .font(.system(size: 14))
                .foregroundStyle(GGColor.textPrimary.opacity(0.9))
                .lineLimit(1...4)
                .focused($focused)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassCapsule(fillOpacity: 0.07, borderOpacity: 0.13)

            Button {
                let t = draft
                draft = ""
                focused = false
                app.sendMadeleine(t)
            } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(GGColor.onAccent)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(GGColor.blue))
            }
            .buttonStyle(PressableStyle())
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 20)
    }

    private func suggestion(_ text: String) -> some View {
        Button {
            app.sendMadeleine(text)
        } label: {
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(GGColor.textPrimary.opacity(0.85))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .glassCapsule(fillOpacity: 0.06, borderOpacity: 0.11)
        }
        .buttonStyle(.plain)
    }

    private func chatBubble(_ msg: ChatMessage) -> some View {
        HStack {
            if msg.fromUser { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 8) {
                if !msg.text.isEmpty {
                    Text(msg.text)
                        .font(msg.fromUser ? .system(size: 15) : .ny(15))
                        .foregroundStyle(GGColor.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(
                            UnevenRoundedRectangle(
                                cornerRadii: .init(
                                    topLeading: msg.fromUser ? 18 : 4,
                                    bottomLeading: 18,
                                    bottomTrailing: 18,
                                    topTrailing: msg.fromUser ? 4 : 18),
                                style: .continuous
                            ).fill(msg.fromUser ? GGColor.blue.opacity(0.22) : GGColor.surface)
                        )
                }
                if let chip = msg.fileChip {
                    FileChipView(chip: chip)
                }
            }
            if !msg.fromUser { Spacer(minLength: 40) }
        }
    }
}

struct FileChipView: View {
    let chip: FileChip
    var showClose: Bool = false
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 12))
                .foregroundStyle(chip.tint)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 8).fill(chip.tint.opacity(0.18)))
            VStack(alignment: .leading, spacing: 1) {
                Text(chip.name).font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                if !chip.sub.isEmpty {
                    Text(chip.sub).font(.system(size: 10)).foregroundStyle(GGColor.textTertiary)
                }
            }
            if showClose {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary.opacity(0.5))
                    .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14).fill(GGColor.ink(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(GGColor.ink(0.12), lineWidth: 1))
    }
}
