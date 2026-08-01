import SwiftUI

// MARK: - Report (Phase 2e · Milestone 5)
//
// A reason list and an optional note, then one Submit. Deliberately not a
// one-tap menu item: a report that fires the instant you touch it is a report
// nobody means, and a moderator working a queue of accidents is a moderator who
// stops reading them.
//
// **It promises nothing.** The confirmation says somebody will look — not that
// the thing was removed, not that the person was warned. A product that says "we
// removed it" teaches people to report things in order to find out whether they
// can, which is how a queue fills with weaponised reports.

/// The report sheet and the block confirmation, as one modifier.
///
/// They travel together because every screen that offers one offers the other,
/// and they are bundled into a modifier rather than written inline for a duller
/// reason: `RootView`'s body is already a long modifier chain, and two more
/// closures on it tips SwiftUI's type-checker over its budget.
///
/// `active` is the one-owner gate this codebase pays attention to. A sheet
/// cannot present over a sheet, so `RootView`, `ProfileView` and `CommentsSheet`
/// each declare a copy and stand down when one of the others is up; two live
/// owners of the same flag silently no-op instead of presenting.
struct SafetyPresentations: ViewModifier {
    @EnvironmentObject var app: AppState

    let active: Bool

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(
                get: { active && app.reportTarget != nil },
                set: { if !$0 { app.closeReport() } }
            )) {
                if let target = app.reportTarget {
                    ReportSheet(target: target).environmentObject(app)
                }
            }
            .confirmationDialog(
                app.pendingBlock.map { "Block @\($0.handle)?" } ?? "",
                isPresented: Binding(
                    get: { active && app.pendingBlock != nil },
                    set: { if !$0 { app.pendingBlock = nil } }),
                titleVisibility: .visible
            ) {
                if let candidate = app.pendingBlock {
                    Button("Block", role: .destructive) {
                        Task { await app.block(profileId: candidate.id, handle: candidate.handle) }
                    }
                }
                Button("Cancel", role: .cancel) { app.pendingBlock = nil }
            } message: {
                Text("You won't see each other anywhere in the app, and you'll both stop following each other. They won't be told.")
            }
            // "@x is blocked." has to land somewhere, and blocking is offered
            // from the feed, a profile and a thread — so the banner rides with
            // the controls rather than being declared once per screen.
            .overlay(alignment: .top) { notice }
            .animation(.ggOverlay, value: app.safetyNotice)
    }

    @ViewBuilder
    private var notice: some View {
        if active, let text = app.safetyNotice {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .glassCapsule(tint: Color.black.opacity(0.55))
                .padding(.horizontal, 24)
                .padding(.top, 66)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { app.safetyNotice = nil }
                .task(id: text) {
                    try? await Task.sleep(nanoseconds: 3_200_000_000)
                    guard !Task.isCancelled else { return }
                    app.safetyNotice = nil
                }
        }
    }
}

extension View {
    /// See `SafetyPresentations`. `active` is the one-owner gate.
    func safetyPresentations(active: Bool) -> some View {
        modifier(SafetyPresentations(active: active))
    }
}

struct ReportSheet: View {
    @EnvironmentObject var app: AppState

    let target: ReportTarget

    @State private var reason: String?
    @State private var note: String = ""
    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if app.reportSubmitted {
                thanks
            } else {
                form
            }
        }
        .background(GGColor.sheetBG.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Chrome

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("REPORT")
                    .font(.ggMono(11, .semibold))
                    .tracking(0.6)
                    .foregroundStyle(GGColor.textSecondary)
                Text(target.label)
                    .font(.gg(22, .bold))
                    .foregroundStyle(GGColor.textPrimary)
                    .lineLimit(1)
            }
            Spacer()
            Button { app.closeReport() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GGColor.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(GGColor.surface))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var form: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("What's wrong with it?")
                        .font(.gg(15))
                        .foregroundStyle(GGColor.textSecondary)
                        .padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        ForEach(Array(app.reportReasons.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Divider().overlay(GGColor.hairline) }
                            reasonRow(item)
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(GGColor.surface))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(GGColor.hairline, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Anything else? (optional)")
                            .font(.ggMono(10, .semibold))
                            .tracking(0.8)
                            .foregroundStyle(GGColor.textTertiary)
                            .padding(.leading, 4)
                        TextEditor(text: $note)
                            .font(.gg(15))
                            .foregroundStyle(GGColor.textPrimary)
                            .scrollContentBackground(.hidden)
                            .frame(height: 100)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(GGColor.surface))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(GGColor.hairline, lineWidth: 1))
                            .focused($noteFocused)
                            .onChange(of: note) { _, value in
                                // Matches the column, so the server never has to
                                // refuse something the app already accepted.
                                if value.count > 1000 { note = String(value.prefix(1000)) }
                            }
                    }

                    if let notice = app.reportNotice {
                        Text(notice)
                            .font(.gg(13))
                            .foregroundStyle(GGColor.textSecondary)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            submit
        }
    }

    private func reasonRow(_ item: ReportReason) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            reason = item.raw
            noteFocused = false
        } label: {
            HStack(spacing: 12) {
                Text(item.label)
                    .font(.gg(15))
                    .foregroundStyle(GGColor.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: reason == item.raw ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(reason == item.raw ? GGColor.textPrimary : GGColor.textTertiary)
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var submit: some View {
        Button {
            guard let reason else { return }
            Task { await app.submitReport(reason: reason, note: note) }
        } label: {
            HStack(spacing: 8) {
                if app.reportBusy { ProgressView().tint(GGColor.sheetBG) }
                Text(app.reportBusy ? "Sending…" : "Submit report")
                    .font(.gg(15, .semibold))
            }
            .foregroundStyle(GGColor.sheetBG)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(GGColor.textPrimary.opacity(reason == nil ? 0.35 : 1)))
        }
        .buttonStyle(PressableStyle())
        .disabled(reason == nil || app.reportBusy)
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    /// What a person is owed after reporting: confirmation that it arrived, and
    /// the two things they can still do themselves. Not a promise about outcome.
    private var thanks: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(GGColor.textPrimary)
            Text(app.reportNotice ?? "Thanks — someone will review this.")
                .font(.gg(16))
                .multilineTextAlignment(.center)
                .foregroundStyle(GGColor.textPrimary)
                .padding(.horizontal, 32)
            Text("We won't tell them who reported it.")
                .font(.gg(13))
                .foregroundStyle(GGColor.textSecondary)
            Spacer()
            Button { app.closeReport() } label: {
                Text("Done")
                    .font(.gg(15, .semibold))
                    .foregroundStyle(GGColor.sheetBG)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(GGColor.textPrimary))
            }
            .buttonStyle(PressableStyle())
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }
}
