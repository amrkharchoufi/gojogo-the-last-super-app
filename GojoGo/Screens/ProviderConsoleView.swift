import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Your work (Phase 5 · M3)
//
// The provider's console: the booking queue, the service catalog, the weekly
// calendar, the money and the profile customers read before they book.
//
// The queue leads, and inside it the requests lead, because a request is
// somebody waiting — and the clock is real: an unanswered booking auto-declines
// at 24 hours and releases whatever was held. The row says which of the six
// verbs applies rather than offering all of them, since "complete" on a job
// that hasn't started and "no-show" on one nobody confirmed are refusals
// waiting to happen.

struct ProviderConsoleView: View {
    @EnvironmentObject var app: AppState

    @State private var tab: Tab = .queue
    @State private var quoting: BookingDTO?
    @State private var confirming: (booking: BookingDTO, action: ProviderBookingAction)?
    @State private var editing: EditingService?

    private enum Tab: String, CaseIterable, Identifiable {
        case queue, services, hours, money, profile
        var id: String { rawValue }
        var label: String {
            switch self {
            case .queue: return "Bookings"
            case .services: return "Services"
            case .hours: return "Hours"
            case .money: return "Money"
            case .profile: return "Profile"
            }
        }
    }

    struct EditingService: Identifiable {
        let id: UUID
        let service: ServiceDTO?
        init(_ service: ServiceDTO?) {
            self.id = service?.id ?? UUID()
            self.service = service
        }
    }

    private var requests: [BookingDTO] { app.providerBookings.filter { $0.state == .requested } }
    private var upcoming: [BookingDTO] { app.providerBookings.filter { $0.state == .confirmed } }
    private var done: [BookingDTO] { app.providerBookings.filter { !$0.state.isOpen } }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let notice = app.economyNotice {
                EconomyNoticeBanner(message: notice) { app.dismissEconomyNotice() }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            tabs
                .padding(.horizontal, 18)
                .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    switch tab {
                    case .queue: queue
                    case .services: catalog
                    case .hours: hours
                    case .money:
                        PayeeWalletCard(wallet: app.providerWallet,
                                        emptyLine: "Nothing settled yet. A job pays out 48 hours after you mark it done.")
                    case .profile: profile
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .refreshable { await app.refreshProviderConsole() }
        }
        .background(GGColor.sheetBG.ignoresSafeArea())
        .animation(.ggOverlay, value: app.economyNotice)
        .task { await app.refreshProviderConsole() }
        .sheet(item: $quoting) { booking in
            QuoteSheet(booking: booking)
                .environmentObject(app)
                .presentationDetents([.height(280)])
                .presentationBackground(GGColor.sheetBG)
        }
        .sheet(item: $editing) { target in
            ServiceEditor(service: target.service)
                .environmentObject(app)
                .presentationDetents([.large])
                .presentationBackground(GGColor.sheetBG)
        }
        .alert(confirming?.action.label ?? "", isPresented: Binding(
            get: { confirming != nil },
            set: { if !$0 { confirming = nil } }
        )) {
            Button("Back", role: .cancel) { confirming = nil }
            Button(confirming?.action.label ?? "", role: .destructive) {
                if let pending = confirming {
                    app.providerBookingAction(pending.booking, pending.action)
                }
                confirming = nil
            }
        } message: {
            Text(confirmationMessage)
        }
    }

    private var confirmationMessage: String {
        switch confirming?.action {
        case .cancel:
            return "The customer is refunded in full and pays nothing — a provider cancellation is always free to them."
        case .noShow:
            return "This settles the whole payment to you now. Only use it if they didn't turn up."
        case .decline:
            return "Anything held goes back to them straight away."
        default:
            return ""
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("YOUR WORK")
                    .font(.ggMono(10, .semibold))
                    .tracking(0.8)
                    .foregroundStyle(GGColor.textTertiary)
                Text(app.myProvider?.displayName ?? "Loading…")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
            }
            Spacer(minLength: 0)
            Button {
                app.closeProviderConsole()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
                    .frame(width: 44, height: 44)
                    .glassCapsule(interactive: false)
                    // See ShopProductDetailView.closeBar: an Image in a frame
                    // hit-tests to the glyph unless it is given a shape.
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Tab.allCases) { option in
                    let active = tab == option
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.ggSnappy) { tab = option }
                    } label: {
                        HStack(spacing: 6) {
                            Text(option.label)
                                .font(.system(size: 13, weight: .semibold))
                            if option == .queue, !requests.isEmpty {
                                Text("\(requests.count)")
                                    .font(.ggMono(11, .semibold))
                                    .opacity(0.75)
                            }
                        }
                        .foregroundStyle(active ? GGColor.onAccent : GGColor.textPrimary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(active ? GGColor.white : GGColor.ink(0.08)))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Queue

    @ViewBuilder
    private var queue: some View {
        if app.providerBookings.isEmpty {
            GGEmptyState(icon: "calendar",
                         title: "Nothing booked yet",
                         message: "Requests land here. You have 24 hours to answer one before it auto-declines.")
                .padding(.top, 30)
        } else {
            if !requests.isEmpty {
                label("NEEDS AN ANSWER")
                ForEach(requests) { booking in bookingRow(booking) }
            }
            if !upcoming.isEmpty {
                label("CONFIRMED").padding(.top, 8)
                ForEach(upcoming) { booking in bookingRow(booking) }
            }
            if !done.isEmpty {
                label("PAST").padding(.top, 8)
                ForEach(done) { booking in bookingRow(booking) }
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.ggMono(9, .semibold))
            .tracking(0.8)
            .foregroundStyle(GGColor.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bookingRow(_ booking: BookingDTO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: booking.state.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GGColor.textSecondary)
                Text(booking.state.providerLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                Spacer(minLength: 0)
                Text(booking.priceLabel)
                    .font(.ggMono(13, .semibold))
                    .foregroundStyle(GGColor.textPrimary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(booking.serviceName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                if let start = booking.startDate {
                    Text(BookingsView.when(start) + " · "
                         + ServiceDTO.duration(booking.durationMinutes))
                        .font(.system(size: 12))
                        .foregroundStyle(GGColor.textSecondary)
                }
                if let note = booking.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(GGColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            actions(booking)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 18,
               tint: booking.state == .requested ? GGColor.ink(0.1) : GGColor.ink(0.04))
    }

    @ViewBuilder
    private func actions(_ booking: BookingDTO) -> some View {
        HStack(spacing: 10) {
            if booking.conversationId != nil {
                Button {
                    app.closeProviderConsole()
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
                .accessibilityLabel("Message the customer")
            }
            Spacer(minLength: 0)

            switch booking.state {
            case .requested:
                secondary("Decline") { confirming = (booking, .decline) }
                // A job with no price yet is a quote job: naming the number is
                // the answer, and the customer's acceptance both pays and
                // confirms. Confirming it here instead would confirm a booking
                // nobody has agreed a price for.
                if booking.priceCents == nil {
                    primary("Send a quote") { quoting = booking }
                } else {
                    primary("Confirm") { app.providerBookingAction(booking, .confirm) }
                }
            case .confirmed:
                secondary("Cancel") { confirming = (booking, .cancel) }
                secondary("No-show") { confirming = (booking, .noShow) }
                primary("Mark done") { app.providerBookingAction(booking, .complete) }
            default:
                EmptyView()
            }
        }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(GGColor.onAccent)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(GGColor.white))
        }
        .buttonStyle(PressableStyle())
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(GGColor.textSecondary)
            .buttonStyle(.plain)
    }

    // MARK: Catalog

    @ViewBuilder
    private var catalog: some View {
        Button {
            editing = EditingService(nil)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                Text("Add a service")
                    .font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(GGColor.textPrimary)
            .padding(14)
            .glass(cornerRadius: 18, tint: GGColor.ink(0.04))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())

        if app.myServices.isEmpty {
            Text("Nothing listed yet. Nobody can book you until something is.")
                .font(.system(size: 13))
                .foregroundStyle(GGColor.textTertiary)
                .padding(.vertical, 20)
        } else {
            ForEach(app.myServices) { service in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(service.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(GGColor.textPrimary)
                        Text("\(service.durationLabel) · \(service.priceLabel) · \(service.location.formLabel)")
                            .font(.system(size: 12))
                            .foregroundStyle(GGColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 8) {
                        Button {
                            app.setServiceActive(service.id, !service.active)
                        } label: {
                            Text(service.active ? "Live" : "Hidden")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(service.active ? GGColor.onAccent
                                                 : GGColor.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(service.active ? GGColor.white
                                                           : GGColor.ink(0.08)))
                        }
                        .buttonStyle(.plain)
                        Button("Edit") { editing = EditingService(service) }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(GGColor.textSecondary)
                            .buttonStyle(.plain)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass(cornerRadius: 18, tint: GGColor.ink(0.04))
            }
        }
    }

    // MARK: Hours

    private var hours: some View {
        AvailabilityEditor()
            .environmentObject(app)
    }

    // MARK: Profile

    @ViewBuilder
    private var profile: some View {
        if let provider = app.myProvider {
            ProviderProfileForm(provider: provider)
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(GGColor.ink(0.06))
                .frame(height: 220)
                .shimmering()
        }
    }
}

// MARK: - The weekly calendar

/// Seven rows, each a window. Edited as a whole week and saved in one PUT — a
/// day that has been switched off is simply absent from what gets sent, which
/// is the same discipline the listing editor uses and for the same reason: two
/// ends that can disagree about which days exist will eventually disagree.
struct AvailabilityEditor: View {
    @EnvironmentObject var app: AppState

    @State private var days: [DayWindow] = DayWindow.week
    @State private var saving = false
    @State private var error: String?
    @State private var loaded = false
    @State private var pickingDayOff = false
    @State private var dayOff = Date()

    struct DayWindow: Identifiable, Equatable {
        let id: Int          // 1 = Monday, matching java.time.DayOfWeek
        var open: Bool
        var start: Int       // minutes from midnight
        var end: Int

        static var week: [DayWindow] {
            (1...7).map { DayWindow(id: $0, open: false, start: 9 * 60, end: 17 * 60) }
        }

        var name: String {
            ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][id - 1]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach($days) { $day in
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.ggSnappy) { day.open.toggle() }
                    } label: {
                        Text(day.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(day.open ? GGColor.onAccent : GGColor.textSecondary)
                            .frame(width: 46)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(day.open ? GGColor.white : GGColor.ink(0.08)))
                    }
                    .buttonStyle(.plain)

                    if day.open {
                        timeField(minutes: $day.start)
                        Text("→")
                            .font(.system(size: 12))
                            .foregroundStyle(GGColor.textTertiary)
                        timeField(minutes: $day.end)
                    } else {
                        Text("Closed")
                            .font(.system(size: 12))
                            .foregroundStyle(GGColor.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
            }

            Divider().overlay(GGColor.hairline)

            VStack(alignment: .leading, spacing: 8) {
                Text("DAYS OFF")
                    .font(.ggMono(9, .semibold))
                    .tracking(0.8)
                    .foregroundStyle(GGColor.textTertiary)
                if app.providerExceptions.isEmpty {
                    Text("None. A day off blocks every slot on it, whatever the week says.")
                        .font(.system(size: 12))
                        .foregroundStyle(GGColor.textTertiary)
                } else {
                    ForEach(app.providerExceptions, id: \.self) { day in
                        HStack {
                            Text(day)
                                .font(.ggMono(12))
                                .foregroundStyle(GGColor.textPrimary)
                            Spacer(minLength: 0)
                            Button("Undo") { app.removeDayOff(day) }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(GGColor.textSecondary)
                                .buttonStyle(.plain)
                        }
                    }
                }
                Button {
                    withAnimation(.ggSnappy) { pickingDayOff.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Book a day off")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(GGColor.textSecondary)
                }
                .buttonStyle(.plain)

                if pickingDayOff {
                    DatePicker("", selection: $dayOff, in: Date()..., displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(GGColor.white)
                    Button("Block that day") {
                        app.addDayOff(dayOff)
                        withAnimation(.ggSnappy) { pickingDayOff = false }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                    .buttonStyle(.plain)
                }
            }

            if let error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textSecondary)
            }

            Button { save() } label: {
                Text(saving ? "Saving…" : "Save the week")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(GGColor.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(GGColor.white))
            }
            .buttonStyle(PressableStyle())
            .disabled(saving)
        }
        .padding(16)
        .glass(cornerRadius: 20, tint: GGColor.ink(0.04))
        .onAppear {
            guard !loaded else { return }
            loaded = true
            for rule in app.providerAvailability {
                guard let index = days.firstIndex(where: { $0.id == rule.dayOfWeek }) else { continue }
                days[index].open = true
                days[index].start = rule.startMinute
                days[index].end = rule.endMinute
            }
        }
    }

    /// A minutes-from-midnight value edited as a time. Backed by a `DatePicker`
    /// so the keyboard never has to parse "9.30" or "half nine".
    private func timeField(minutes: Binding<Int>) -> some View {
        DatePicker("", selection: Binding(
            get: {
                Calendar.current.date(bySettingHour: minutes.wrappedValue / 60,
                                      minute: minutes.wrappedValue % 60,
                                      second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        ), displayedComponents: .hourAndMinute)
        .labelsHidden()
        .datePickerStyle(.compact)
        .tint(GGColor.white)
    }

    private func save() {
        saving = true
        error = nil
        Task {
            let failure = await app.saveAvailability(days.filter { $0.open && $0.end > $0.start }
                .map { AvailabilityRuleBody(dayOfWeek: $0.id,
                                            startMinute: $0.start,
                                            endMinute: $0.end) })
            saving = false
            withAnimation(.ggSnappy) { error = failure }
        }
    }
}

// MARK: - Forms

struct QuoteSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let booking: BookingDTO
    @State private var price = ""
    @State private var sending = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 3) {
                Text("Name your price")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
                Text(booking.serviceName)
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textSecondary)
            }
            .padding(.top, 20)

            TextField("0.00", text: $price)
                .keyboardType(.decimalPad)
                .font(.ggMono(26, .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(GGColor.textPrimary)
                .tint(GGColor.white)
                .padding(14)
                .glass(cornerRadius: 16, tint: GGColor.ink(0.06))
                .padding(.horizontal, 18)

            Text("Sending this doesn't confirm anything. They pay and it confirms in one act when they accept — so quote the number you'd take.")
                .font(.system(size: 11))
                .foregroundStyle(GGColor.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if let error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textSecondary)
            }

            Button {
                guard let cents = EconomyStore.parseCents(price), cents > 0 else {
                    withAnimation(.ggSnappy) { error = "Put a number in." }
                    return
                }
                sending = true
                error = nil
                Task {
                    let failure = await app.quoteBooking(booking.id, priceCents: cents)
                    sending = false
                    if failure == nil { dismiss() } else {
                        withAnimation(.ggSnappy) { error = failure }
                    }
                }
            } label: {
                Text(sending ? "Sending…" : "Send quote")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(GGColor.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(GGColor.white))
            }
            .buttonStyle(PressableStyle())
            .disabled(sending)
            .padding(.horizontal, 18)

            Spacer(minLength: 0)
        }
        .background(GGColor.sheetBG.ignoresSafeArea())
    }
}

struct ServiceEditor: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let service: ServiceDTO?

    @State private var name = ""
    @State private var description = ""
    @State private var category = ""
    @State private var requirements = ""
    @State private var duration = "60"
    @State private var price = ""
    @State private var onQuote = false
    @State private var location: ServiceLocationKind = .atProvider
    @State private var saving = false
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text(service == nil ? "New service" : "Edit service")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)

                field("Name", text: $name)
                field("Category", text: $category)
                multiline("What's included", text: $description)
                multiline("What you need from them", text: $requirements)
                field("Minutes", text: $duration, numeric: true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("PRICE")
                        .font(.ggMono(9, .semibold))
                        .tracking(0.8)
                        .foregroundStyle(GGColor.textTertiary)
                    HStack(spacing: 8) {
                        ForEach([false, true], id: \.self) { quote in
                            let active = onQuote == quote
                            Button {
                                withAnimation(.ggSnappy) { onQuote = quote }
                            } label: {
                                Text(quote ? "On quote" : "Fixed")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(active ? GGColor.onAccent : GGColor.textPrimary)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 9)
                                    .background(Capsule().fill(active ? GGColor.white
                                                               : GGColor.ink(0.08)))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }
                    if onQuote {
                        Text("They describe the job, you name a number, and accepting it pays and confirms together.")
                            .font(.system(size: 11))
                            .foregroundStyle(GGColor.textTertiary)
                    } else {
                        TextField("0.00", text: $price)
                            .keyboardType(.decimalPad)
                            .font(.ggMono(14))
                            .foregroundStyle(GGColor.textPrimary)
                            .tint(GGColor.white)
                            .padding(11)
                            .glass(cornerRadius: 12, tint: GGColor.ink(0.06))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("WHERE")
                        .font(.ggMono(9, .semibold))
                        .tracking(0.8)
                        .foregroundStyle(GGColor.textTertiary)
                    HStack(spacing: 8) {
                        ForEach(ServiceLocationKind.allCases) { kind in
                            let active = location == kind
                            Button {
                                withAnimation(.ggSnappy) { location = kind }
                            } label: {
                                Text(kind.formLabel)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(active ? GGColor.onAccent : GGColor.textPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .background(Capsule().fill(active ? GGColor.white
                                                               : GGColor.ink(0.08)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let error {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(GGColor.textSecondary)
                }

                Button { save() } label: {
                    Text(saving ? "Saving…" : (service == nil ? "Add service" : "Save changes"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(GGColor.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(GGColor.white))
                }
                .buttonStyle(PressableStyle())
                .disabled(saving)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .background(GGColor.sheetBG.ignoresSafeArea())
        .onAppear {
            guard !loaded else { return }
            loaded = true
            guard let service else { return }
            name = service.name
            description = service.description ?? ""
            category = service.category ?? ""
            requirements = service.requirements ?? ""
            duration = "\(service.durationMinutes)"
            onQuote = service.priceOnQuote || service.priceCents == nil
            price = service.priceCents.map { String(format: "%.2f", Double($0) / 100) } ?? ""
            location = service.location
        }
    }

    private func field(_ label: String, text: Binding<String>, numeric: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.ggMono(9, .semibold))
                .tracking(0.8)
                .foregroundStyle(GGColor.textTertiary)
            TextField("", text: text)
                .font(.system(size: 14))
                .foregroundStyle(GGColor.textPrimary)
                .tint(GGColor.white)
                .keyboardType(numeric ? .numberPad : .default)
                .padding(11)
                .glass(cornerRadius: 12, tint: GGColor.ink(0.06))
        }
    }

    private func multiline(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.ggMono(9, .semibold))
                .tracking(0.8)
                .foregroundStyle(GGColor.textTertiary)
            TextField("", text: text, axis: .vertical)
                .font(.system(size: 14))
                .foregroundStyle(GGColor.textPrimary)
                .tint(GGColor.white)
                .lineLimit(2...6)
                .padding(11)
                .glass(cornerRadius: 12, tint: GGColor.ink(0.06))
        }
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            withAnimation(.ggSnappy) { error = "Give the service a name." }
            return
        }
        saving = true
        error = nil
        Task {
            let failure = await app.saveService(service?.id, ServiceBody(
                name: name.trimmingCharacters(in: .whitespaces),
                description: description,
                category: category.trimmingCharacters(in: .whitespaces),
                durationMinutes: Int(duration) ?? 60,
                priceCents: onQuote ? nil : (EconomyStore.parseCents(price) ?? 0),
                locationKind: location.rawValue,
                requirements: requirements))
            saving = false
            if failure == nil { dismiss() } else { withAnimation(.ggSnappy) { error = failure } }
        }
    }
}

struct ProviderProfileForm: View {
    @EnvironmentObject var app: AppState

    let provider: ProviderDTO

    @State private var name = ""
    @State private var bio = ""
    @State private var qualifications = ""
    @State private var areas = ""
    @State private var languages = ""
    @State private var timezone = TimeZone.current.identifier
    @State private var logoURL: String?
    @State private var pick: PhotosPickerItem?
    @State private var uploading = false
    @State private var saving = false
    @State private var error: String?
    @State private var loaded = false
    @State private var showFileImporter = false
    @State private var uploadingDoc = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PhotosPicker(selection: $pick, matching: .images, photoLibrary: .shared()) {
                HStack(spacing: 12) {
                    MediaImage(url: logoURL, cornerRadius: 14)
                        .frame(width: 56, height: 56)
                        .overlay {
                            if uploading { ProgressView().tint(GGColor.textPrimary) }
                            else if logoURL == nil {
                                Image(systemName: "person.crop.square")
                                    .font(.system(size: 16, weight: .light))
                                    .foregroundStyle(GGColor.textTertiary)
                            }
                        }
                    Text(logoURL == nil ? "Add a photo" : "Change photo")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .onChange(of: pick) { _, item in
                guard let item else { return }
                Task {
                    defer { pick = nil }
                    uploading = true
                    defer { uploading = false }
                    guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                    logoURL = try? await APIClient.shared.uploadMedia(
                        data, contentType: APIClient.imageContentType(for: data))
                }
            }

            field("Name customers see", text: $name)
            multiline("About you", text: $bio)
            multiline("Qualifications", text: $qualifications)
            field("Areas you cover", text: $areas)
            field("Languages", text: $languages)
            field("Timezone", text: $timezone)

            Text("Your timezone is what your hours mean. Get it wrong and every slot you offer is wrong by the difference.")
                .font(.system(size: 11))
                .foregroundStyle(GGColor.textTertiary)

            Divider().overlay(GGColor.hairline)

            VStack(alignment: .leading, spacing: 8) {
                Text("QUALIFICATION PAPERS")
                    .font(.ggMono(9, .semibold))
                    .tracking(0.8)
                    .foregroundStyle(GGColor.textTertiary)
                ForEach(app.providerDocuments) { document in
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11))
                            .foregroundStyle(GGColor.textTertiary)
                        Text(document.label)
                            .font(.system(size: 13))
                            .foregroundStyle(GGColor.textPrimary)
                        Spacer(minLength: 0)
                        Text(BackendDate.relative(document.uploadedAt))
                            .font(.system(size: 11))
                            .foregroundStyle(GGColor.textTertiary)
                    }
                }
                Button {
                    showFileImporter = true
                } label: {
                    HStack(spacing: 6) {
                        if uploadingDoc { ProgressView().tint(GGColor.textPrimary) }
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Upload a certificate")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(GGColor.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(uploadingDoc)
                Text("Private. Only a reviewer sees these, through a link minted when they open it.")
                    .font(.system(size: 11))
                    .foregroundStyle(GGColor.textTertiary)
            }

            if let error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textSecondary)
            }

            Button { save() } label: {
                Text(saving ? "Saving…" : "Save")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(GGColor.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(GGColor.white))
            }
            .buttonStyle(PressableStyle())
            .disabled(saving)
        }
        .padding(16)
        .glass(cornerRadius: 20, tint: GGColor.ink(0.04))
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.pdf, .image, .data],
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            uploadingDoc = true
            Task {
                defer { uploadingDoc = false }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { return }
                let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                    ?? "application/octet-stream"
                let failure = await app.uploadProviderDocument(
                    data, label: url.lastPathComponent, contentType: type)
                withAnimation(.ggSnappy) { error = failure }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            name = provider.displayName
            bio = provider.bio ?? ""
            qualifications = provider.qualifications ?? ""
            areas = provider.serviceAreas ?? ""
            languages = provider.languages ?? ""
            timezone = provider.timezone ?? TimeZone.current.identifier
            logoURL = provider.logoUrl
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.ggMono(9, .semibold))
                .tracking(0.8)
                .foregroundStyle(GGColor.textTertiary)
            TextField("", text: text)
                .font(.system(size: 14))
                .foregroundStyle(GGColor.textPrimary)
                .tint(GGColor.white)
                .autocorrectionDisabled()
                .padding(11)
                .glass(cornerRadius: 12, tint: GGColor.ink(0.06))
        }
    }

    private func multiline(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.ggMono(9, .semibold))
                .tracking(0.8)
                .foregroundStyle(GGColor.textTertiary)
            TextField("", text: text, axis: .vertical)
                .font(.system(size: 14))
                .foregroundStyle(GGColor.textPrimary)
                .tint(GGColor.white)
                .lineLimit(2...6)
                .padding(11)
                .glass(cornerRadius: 12, tint: GGColor.ink(0.06))
        }
    }

    private func save() {
        saving = true
        error = nil
        Task {
            let failure = await app.saveProviderProfile(ProviderBody(
                displayName: name.trimmingCharacters(in: .whitespaces),
                logoUrl: logoURL,
                bio: bio,
                qualifications: qualifications,
                serviceAreas: areas,
                languages: languages,
                timezone: timezone.trimmingCharacters(in: .whitespaces),
                portfolioUrls: provider.portfolioUrls ?? []))
            saving = false
            withAnimation(.ggSnappy) { error = failure }
        }
    }
}
