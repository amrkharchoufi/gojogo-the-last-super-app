import SwiftUI

// MARK: - Your bookings (Phase 5 · M3)
//
// The customer's side of the seven words. Three of them carry a live action and
// the rest are history, so the row is built around whichever of those it is:
//
//   • a quote waiting to be answered — the loudest row on the screen, because
//     accepting it *pays and confirms in one act* and the number is right there
//   • anything still open — cancellable, with what cancelling costs *right now*
//     printed on the button rather than buried in a policy sentence
//   • done — reviewable, once
//
// The cancellation fee is a live number off the booking rather than a rule the
// app re-derives. A tier the client computed would be wrong on the boundary,
// and the boundary is exactly when somebody is deciding.

struct BookingsView: View {
    @EnvironmentObject var app: AppState

    @State private var cancelling: BookingDTO?
    @State private var reviewing: BookingDTO?

    private var open: [BookingDTO] { app.bookings.filter { $0.state.isOpen } }
    private var past: [BookingDTO] { app.bookings.filter { !$0.state.isOpen } }

    var body: some View {
        VStack(spacing: 0) {
            if let notice = app.economyNotice {
                EconomyNoticeBanner(message: notice) { app.dismissEconomyNotice() }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            header

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    if app.bookings.isEmpty {
                        GGEmptyState(icon: "calendar",
                                     title: "No bookings yet",
                                     message: "Anything you book on Services shows up here.")
                            .padding(.top, 30)
                    } else {
                        if !open.isEmpty {
                            sectionLabel("COMING UP")
                            ForEach(open) { booking in row(booking) }
                        }
                        if !past.isEmpty {
                            sectionLabel("PAST")
                                .padding(.top, 8)
                            ForEach(past) { booking in row(booking) }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .refreshable { await app.refreshBookings() }
        }
        .background(GGColor.sheetBG.ignoresSafeArea())
        .animation(.ggOverlay, value: app.economyNotice)
        .task { await app.refreshBookings() }
        .alert("Cancel this booking?", isPresented: Binding(
            get: { cancelling != nil },
            set: { if !$0 { cancelling = nil } }
        )) {
            Button("Keep it", role: .cancel) { cancelling = nil }
            Button("Cancel booking", role: .destructive) {
                if let booking = cancelling { app.cancelBooking(booking.id) }
                cancelling = nil
            }
        } message: {
            Text(cancelling.map { booking in
                booking.cancellationFeeCents > 0
                    ? "You'll be charged \(booking.cancellationFeeLabel) — this is close enough to the time that they've turned other work away."
                    : "Nothing will be charged. Anything held goes back to your balance."
            } ?? "")
        }
        .sheet(item: $reviewing) { booking in
            ServiceReviewSheet(booking: booking)
                .environmentObject(app)
                .presentationDetents([.medium])
                .presentationBackground(GGColor.sheetBG)
        }
    }

    private var header: some View {
        VStack(spacing: 3) {
            Text("Your bookings")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)
            Text("Services you've asked for or booked")
                .font(.system(size: 12))
                .foregroundStyle(GGColor.textSecondary)
        }
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.ggMono(9, .semibold))
            .tracking(0.8)
            .foregroundStyle(GGColor.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ booking: BookingDTO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: booking.state.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(booking.awaitingQuoteAcceptance ? "Quote ready" : booking.state.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                Spacer(minLength: 0)
                Text(booking.priceLabel)
                    .font(.ggMono(13, .semibold))
                    .foregroundStyle(GGColor.textPrimary)
            }
            .foregroundStyle(GGColor.textSecondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(booking.serviceName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                Text(booking.providerName)
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textSecondary)
                if let start = booking.startDate {
                    Text(Self.when(start) + " · " + ServiceDTO.duration(booking.durationMinutes))
                        .font(.system(size: 12))
                        .foregroundStyle(GGColor.textSecondary)
                }
            }

            actions(booking)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 18,
               tint: booking.awaitingQuoteAcceptance ? GGColor.ink(0.1) : GGColor.ink(0.04))
    }

    @ViewBuilder
    private func actions(_ booking: BookingDTO) -> some View {
        HStack(spacing: 10) {
            if booking.conversationId != nil {
                Button {
                    app.openBookingThread(booking)
                } label: {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .glassCapsule(interactive: false)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Message them")
            }

            Spacer(minLength: 0)

            if booking.state.isOpen {
                Button {
                    cancelling = booking
                } label: {
                    Text(booking.cancellationFeeCents > 0
                         ? "Cancel · \(booking.cancellationFeeLabel)"
                         : "Cancel")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GGColor.textSecondary)
                }
                .buttonStyle(.plain)
            }

            if booking.awaitingQuoteAcceptance {
                Button {
                    app.acceptBookingQuote(booking.id)
                } label: {
                    Text("Accept \(booking.priceLabel)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(GGColor.onAccent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(GGColor.white))
                }
                .buttonStyle(PressableStyle())
            } else if booking.state == .completed {
                Button {
                    reviewing = booking
                } label: {
                    Text("Review")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .glassCapsule(interactive: false)
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    static func when(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDateInToday(date)
            || Calendar.current.isDateInTomorrow(date) ? "'at' HH:mm" : "EEE d MMM 'at' HH:mm"
        let prefix = Calendar.current.isDateInToday(date) ? "Today "
            : (Calendar.current.isDateInTomorrow(date) ? "Tomorrow " : "")
        return prefix + formatter.string(from: date)
    }
}

/// A review that names the booking it rides on — the same verified-purchase
/// shape as a product review, and for the same reason.
struct ServiceReviewSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let booking: BookingDTO

    @State private var rating = 5
    @State private var text: String = ""
    @State private var posting = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 3) {
                Text("How did it go?")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
                Text(booking.serviceName)
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textSecondary)
            }
            .padding(.top, 20)

            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.ggSnappy) { rating = star }
                    } label: {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.system(size: 24))
                            .foregroundStyle(star <= rating ? GGColor.white : GGColor.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            TextField("What should others know?", text: $text, axis: .vertical)
                .font(.system(size: 14))
                .foregroundStyle(GGColor.textPrimary)
                .tint(GGColor.white)
                .lineLimit(3...6)
                .padding(12)
                .glass(cornerRadius: 14, tint: GGColor.ink(0.05))
                .padding(.horizontal, 18)

            if let error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textSecondary)
                    .padding(.horizontal, 18)
            }

            Button {
                posting = true
                error = nil
                Task {
                    let failure = await app.reviewService(bookingId: booking.id,
                                                          serviceId: booking.serviceId,
                                                          rating: rating, body: text)
                    posting = false
                    if failure == nil { dismiss() } else {
                        withAnimation(.ggSnappy) { error = failure }
                    }
                }
            } label: {
                Text(posting ? "Posting…" : "Post review")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(GGColor.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(GGColor.white))
            }
            .buttonStyle(PressableStyle())
            .disabled(posting)
            .padding(.horizontal, 18)

            Spacer(minLength: 0)
        }
        .background(GGColor.sheetBG.ignoresSafeArea())
    }
}
