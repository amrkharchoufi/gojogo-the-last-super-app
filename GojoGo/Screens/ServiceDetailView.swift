import SwiftUI

// MARK: - A service page, and the slot picker (Phase 5 · M3)
//
// The picker is the interesting half. Slots come from the server — the weekly
// template minus exception days minus live bookings minus the buffer between
// jobs — and they are re-asked every time this page opens, never cached with
// the service, because somebody else booking Tuesday at four is exactly the
// event a cached list cannot see.
//
// Days are grouped from the flat list the server sends rather than requested
// per day: one round trip, and the gaps in it are the truth about which days
// this person works.

struct ServiceDetailView: View {
    @EnvironmentObject var app: AppState

    let service: ServiceDTO

    @State private var selectedSlot: String?
    @State private var note: String = ""
    @State private var booking = false
    @State private var error: String?

    private var live: ServiceDTO { app.browsingService ?? service }

    /// The slot list, grouped by local day and kept in the server's order.
    private var slotsByDay: [(day: Date, slots: [String])] {
        let calendar = Calendar.current
        var buckets: [Date: [String]] = [:]
        for raw in app.serviceSlots?.slots ?? [] {
            guard let date = BackendDate.parse(raw) else { continue }
            let day = calendar.startOfDay(for: date)
            buckets[day, default: []].append(raw)
        }
        return buckets.keys.sorted().map { ($0, buckets[$0] ?? []) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            GGColor.sheetBG.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    facts
                    // Same guard as the product page: a field the server
                    // stores as JSON comes back as "{}" rather than as empty.
                    if let description = ShopProductDetailView.readable(live.description) {
                        block(title: "What's included", body: description)
                    }
                    if let requirements = ShopProductDetailView.readable(live.requirements) {
                        block(title: "What they need from you", body: requirements)
                    }
                    slotPicker
                    noteField
                    if let error {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(GGColor.textPrimary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glass(cornerRadius: 14, tint: GGColor.ink(0.08))
                    }
                    reviews
                    Color.clear.frame(height: 120)
                }
                .padding(.horizontal, 18)
                .padding(.top, 66)
            }

            closeBar
        }
        .safeAreaInset(edge: .bottom) { bookBar }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                MediaImage(url: live.providerLogoUrl, cornerRadius: 12)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(live.providerName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                    if let rating = live.averageRating, live.ratingCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                            Text(String(format: "%.1f", rating))
                                .font(.ggMono(11, .semibold))
                            Text("(\(live.ratingCount))")
                                .font(.system(size: 11))
                                .foregroundStyle(GGColor.textTertiary)
                        }
                        .foregroundStyle(GGColor.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            Text(live.name)
                .font(.system(size: 23, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)
        }
    }

    private var facts: some View {
        HStack(spacing: 10) {
            fact(icon: "clock", label: live.durationLabel)
            fact(icon: live.location.icon, label: live.location.label)
            fact(icon: live.priceOnQuote ? "text.bubble" : "creditcard",
                 label: live.priceLabel)
        }
    }

    private func fact(icon: String, label: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GGColor.textSecondary)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glass(cornerRadius: 16, tint: GGColor.ink(0.05))
    }

    private func block(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.ggMono(10, .semibold))
                .tracking(0.8)
                .foregroundStyle(GGColor.textTertiary)
            Text(body)
                .font(.system(size: 14))
                .foregroundStyle(GGColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Slots

    private var slotPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Pick a time")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
                Spacer(minLength: 0)
                if let zone = app.serviceSlots?.timezone, !zone.isEmpty,
                   zone != TimeZone.current.identifier {
                    // Their zone, not yours — a 9am slot in Casablanca is not
                    // 9am in Berlin, and the times below are shown in *yours*.
                    Text("Times shown in your zone")
                        .font(.system(size: 10))
                        .foregroundStyle(GGColor.textTertiary)
                }
            }

            if app.serviceSlotsLoading && app.serviceSlots == nil {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(GGColor.ink(0.06))
                    .frame(height: 70)
                    .shimmering()
            } else if slotsByDay.isEmpty {
                Text("Nothing free in the next fortnight. Message them and ask.")
                    .font(.system(size: 13))
                    .foregroundStyle(GGColor.textTertiary)
            } else {
                ForEach(slotsByDay, id: \.day) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Self.dayLabel(group.day))
                            .font(.ggMono(10, .semibold))
                            .tracking(0.6)
                            .foregroundStyle(GGColor.textTertiary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(group.slots, id: \.self) { slot in
                                    slotChip(slot)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
    }

    private func slotChip(_ slot: String) -> some View {
        let active = selectedSlot == slot
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.ggSnappy) { selectedSlot = slot }
        } label: {
            Text(Self.timeLabel(slot))
                .font(.ggMono(13, .semibold))
                .foregroundStyle(active ? GGColor.onAccent : GGColor.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(active ? GGColor.white : GGColor.ink(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(live.priceOnQuote ? "DESCRIBE THE JOB" : "ANYTHING THEY SHOULD KNOW")
                .font(.ggMono(9, .semibold))
                .tracking(0.8)
                .foregroundStyle(GGColor.textTertiary)
            TextField(live.priceOnQuote
                      ? "The more detail, the better the quote"
                      : "Optional", text: $note, axis: .vertical)
                .font(.system(size: 14))
                .foregroundStyle(GGColor.textPrimary)
                .tint(GGColor.white)
                .lineLimit(2...5)
                .padding(12)
                .glass(cornerRadius: 14, tint: GGColor.ink(0.05))
        }
    }

    // MARK: Reviews

    private var reviews: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reviews")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)
            if app.serviceReviews.isEmpty {
                Text("No reviews yet. Only people who booked can leave one.")
                    .font(.system(size: 13))
                    .foregroundStyle(GGColor.textTertiary)
            } else {
                ForEach(app.serviceReviews) { review in
                    ServiceReviewRow(review: review)
                }
            }
        }
    }

    // MARK: Chrome

    private var closeBar: some View {
        HStack {
            Button {
                app.closeService()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
                    .frame(width: 44, height: 44)
                    .glassCapsule(interactive: false)
                    // See ShopProductDetailView.closeBar: without a shape this
                    // hit-tests to the glyph, not the circle.
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    /// Two different acts behind one button, and the label says which. A priced
    /// service holds the money now; a quote-only one holds nothing and asks a
    /// question — which is why it does not say "book".
    private var bookBar: some View {
        VStack(spacing: 6) {
            Button {
                request()
            } label: {
                Text(bookLabel)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(GGColor.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Capsule().fill(
                        selectedSlot == nil ? GGColor.ink(0.18) : GGColor.white))
            }
            .buttonStyle(PressableStyle())
            .disabled(selectedSlot == nil || booking)

            Text(live.priceOnQuote
                 ? "Nothing is charged until you accept their price."
                 : "Held from your GoJo balance and released if they decline.")
                .font(.system(size: 11))
                .foregroundStyle(GGColor.textTertiary)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    private var bookLabel: String {
        if booking { return "Sending…" }
        guard selectedSlot != nil else { return "Pick a time" }
        return live.priceOnQuote ? "Ask for a quote" : "Request · \(live.priceLabel)"
    }

    private func request() {
        guard let slot = selectedSlot else { return }
        booking = true
        error = nil
        Task {
            let failure = await app.requestBooking(live, at: slot, note: note)
            booking = false
            if failure != nil {
                withAnimation(.ggSnappy) {
                    error = failure
                    // The slots were re-asked by the failure path; the one we
                    // held is provably not ours.
                    selectedSlot = nil
                }
            }
        }
    }

    // MARK: Formatting

    static func dayLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "TODAY" }
        if calendar.isDateInTomorrow(day) { return "TOMORROW" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMM"
        return formatter.string(from: day).uppercased()
    }

    static func timeLabel(_ raw: String) -> String {
        guard let date = BackendDate.parse(raw) else { return raw }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

struct ServiceReviewRow: View {
    let review: ServiceReviewDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(review.authorName ?? "Someone")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                HStack(spacing: 1) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= review.rating ? "star.fill" : "star")
                            .font(.system(size: 8))
                    }
                }
                .foregroundStyle(GGColor.textSecondary)
                Spacer(minLength: 0)
                Text(BackendDate.relative(review.createdAt))
                    .font(.system(size: 11))
                    .foregroundStyle(GGColor.textTertiary)
            }
            if let body = review.body, !body.isEmpty {
                Text(body)
                    .font(.system(size: 13))
                    .foregroundStyle(GGColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let reply = review.replyBody, !reply.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Rectangle()
                        .fill(GGColor.ink(0.18))
                        .frame(width: 2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("They replied")
                            .font(.ggMono(9, .semibold))
                            .tracking(0.6)
                            .foregroundStyle(GGColor.textTertiary)
                        Text(reply)
                            .font(.system(size: 12))
                            .foregroundStyle(GGColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 16, tint: GGColor.ink(0.04))
    }
}
