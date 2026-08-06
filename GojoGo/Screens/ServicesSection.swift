import SwiftUI

// MARK: - Services: booking somebody's time (Phase 5 · M3)
//
// The Economy tab's third segment, and the one that is not shopping. Every card
// answers three questions before it is tapped, because they are the three that
// decide whether this is even the right person: how long it takes, where it
// happens, and what it costs — with "price on quote" printed as its own kind of
// answer rather than as a blank, since a provider who needs to see the job
// first is telling you something real.

struct ServicesSection: View {
    @EnvironmentObject var app: AppState
    @Binding var chromeHidden: Bool
    /// Measured by the chrome that floats above this scroll, not assumed.
    var chromeHeight: CGFloat = ChromeMetrics.assumedHeight

    private var categories: [String] {
        let live = Set(app.services.compactMap { $0.category }.filter { !$0.isEmpty })
        return ["All"] + live.sorted()
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if categories.count > 1 {
                    categoryChips
                        .padding(.top, 4)
                }

                if app.servicesLoading && app.services.isEmpty {
                    loadingRows
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                } else if app.services.isEmpty {
                    GGEmptyState(
                        icon: "wrench.and.screwdriver",
                        title: "No services listed yet",
                        message: app.isServiceProvider
                            ? "You're approved — add a service and people can book it."
                            : "Plumbers, tutors, photographers and the rest land here.",
                        actionTitle: app.isServiceProvider ? "Set up your services" : nil,
                        action: app.isServiceProvider ? { app.openProviderConsole() } : nil)
                    .padding(.top, 40)
                } else {
                    VStack(spacing: 12) {
                        ForEach(app.services) { service in
                            ServiceCard(service: service) {
                                app.openService(service)
                            }
                            .onAppear { app.loadMoreServicesIfNeeded(after: service.id) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                }

                Color.clear.frame(height: tabBarInset + (app.shopBasket.isEmpty ? 0 : 60))
            }
            .padding(.top, chromeHeight)
        }
        .refreshable { await app.refreshServices() }
        .trackScrollChrome(hidden: $chromeHidden)
        .task {
            if app.services.isEmpty { await app.refreshServices() }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { category in
                    let active = app.serviceCategory == category
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        app.selectServiceCategory(category)
                    } label: {
                        Text(category)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(active ? GGColor.onAccent : GGColor.textPrimary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(active ? GGColor.white : GGColor.ink(0.08)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var loadingRows: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(GGColor.ink(0.06))
                    .frame(height: 104)
                    .shimmering()
            }
        }
    }
}

struct ServiceCard: View {
    let service: ServiceDTO
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                MediaImage(url: service.providerLogoUrl, cornerRadius: 14)
                    .frame(width: 56, height: 56)
                    .overlay {
                        if service.providerLogoUrl == nil {
                            Image(systemName: "person.crop.square")
                                .font(.system(size: 18, weight: .light))
                                .foregroundStyle(GGColor.textTertiary)
                        }
                    }

                VStack(alignment: .leading, spacing: 5) {
                    Text(service.providerName)
                        .font(.ggMono(9, .semibold))
                        .tracking(0.6)
                        .foregroundStyle(GGColor.textTertiary)
                        .lineLimit(1)
                    Text(service.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 8) {
                        metaChip(icon: "clock", text: service.durationLabel)
                        metaChip(icon: service.location.icon, text: service.location.label)
                        if let rating = service.averageRating, service.ratingCount > 0 {
                            metaChip(icon: "star.fill", text: String(format: "%.1f", rating))
                        }
                    }
                }

                Spacer(minLength: 0)

                Text(service.priceLabel)
                    .font(service.priceOnQuote ? .system(size: 11, weight: .semibold)
                          : .ggMono(14, .semibold))
                    .foregroundStyle(service.priceOnQuote ? GGColor.textSecondary
                                     : GGColor.textPrimary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 84, alignment: .trailing)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(cornerRadius: 18, tint: GGColor.ink(0.04))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private func metaChip(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(text)
                .font(.system(size: 11))
        }
        .foregroundStyle(GGColor.textSecondary)
    }
}
