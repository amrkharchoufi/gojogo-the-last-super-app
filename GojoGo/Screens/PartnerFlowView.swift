import SwiftUI
import PhotosUI

// MARK: - Header entry button (top-right, liquid glass)

/// Top-right pill in GojoTravel / GojoDelivery. Opens the become-a-partner
/// flow, or the working dashboard once the user is onboarded for the role.
struct PartnerHeaderButton: View {
    @EnvironmentObject var app: AppState
    let role: PartnerRole

    private var isPartner: Bool { app.isPartner(role) }

    var body: some View {
        Button {
            app.openPartner(role)
        } label: {
            HStack(spacing: 7) {
                if isPartner && app.partnerOnline {
                    Circle().fill(GGColor.white).frame(width: 7, height: 7)
                } else {
                    Image(systemName: role == .driver ? "steeringwheel" : "bag.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                }
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
            }
            .padding(.horizontal, 13)
            .frame(height: 36)
            .glassCapsule(tint: Color.black.opacity(0.4), interactive: false, dense: true)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(isPartner ? "Open \(role.title) mode" : role.ctaTitle)
    }

    private var label: String {
        if isPartner {
            return app.partnerOnline ? "Online" : role.title
        }
        return role == .driver ? "Drive" : "Deliver"
    }
}

// MARK: - Become-a-partner onboarding (rules → stake → KYC → done)

struct PartnerOnboardingView: View {
    @EnvironmentObject var app: AppState

    private var role: PartnerRole { app.partnerOnboardingRole ?? .driver }

    var body: some View {
        ZStack {
            GGColor.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                // This cover sits above everything, so a message posted to the
                // layer underneath would never be seen — the same lesson as the
                // merchant sheet. One owner: it is rendered here and nowhere
                // else in the flow.
                if let notice = app.partnerNotice {
                    MerchantNoticeBanner(message: notice) { app.dismissPartnerNotice() }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Group {
                    switch app.partnerStep {
                    case .rules: PartnerRulesPage(role: role)
                    case .stake: PartnerStakePage(role: role)
                    case .kyc:   PartnerKYCPage(role: role)
                    case .done:  PartnerDonePage(role: role)
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)))
            }
            .animation(.easeInOut(duration: 0.32), value: app.partnerStep)
            .animation(.ggOverlay, value: app.partnerNotice)
        }
    }

    // MARK: Header — close + step progress

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                if app.partnerStep != .done {
                    Button {
                        app.cancelPartnerOnboarding()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(GGColor.textPrimary)
                            .frame(width: 36, height: 36)
                            .glassCapsule(tint: Color.black.opacity(0.35), interactive: false, dense: true)
                    }
                    .buttonStyle(PressableStyle())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(role.service.uppercased())
                        .font(.ggMono(11, .semibold))
                        .tracking(0.6)
                        .foregroundStyle(GGColor.textSecondary)
                    Wordmark(size: 20, trailing: role.wordmarkTrailing)
                }
            }

            if app.partnerStep != .done {
                stepBar
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var stepBar: some View {
        let steps: [PartnerOnboardingStep] = [.rules, .stake, .kyc]
        let labels = ["Rules", "Stake", "Verify"]
        return HStack(spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.element) { i, step in
                VStack(spacing: 5) {
                    Capsule()
                        .fill(step <= app.partnerStep ? GGColor.white : GGColor.ink(0.14))
                        .frame(height: 4)
                    Text(labels[i])
                        .font(.ggMono(9, .semibold))
                        .foregroundStyle(step <= app.partnerStep ? GGColor.textPrimary : GGColor.textTertiary)
                }
            }
        }
    }
}

// MARK: - Page 1 · Rules / how it works

private struct PartnerRulesPage: View {
    @EnvironmentObject var app: AppState
    let role: PartnerRole

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    VStack(spacing: 12) {
                        ForEach(rules, id: \.title) { rule in
                            ruleRow(rule)
                        }
                    }
                    stakeNote
                    agreementToggle
                    Color.clear.frame(height: 12)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }

            footerCTA
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: role.icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(GGColor.onAccent)
                .frame(width: 60, height: 60)
                .background(Circle().fill(GGColor.white))

            Text(role == .driver ? "Drive with GojoTravel" : "Deliver with GojoDelivery")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)
            Text("Turn your \(role == .driver ? "car" : "trips") into earnings. Work when you want, get paid per \(role.jobNoun), and build a rating that opens up better \(role.earner).")
                .explanatory(15)
                .foregroundStyle(GGColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct Rule { let icon: String; let title: String; let detail: String }

    private var rules: [Rule] {
        var base = [
            Rule(icon: "checkmark.seal.fill", title: "Be verified",
                 detail: "Complete identity checks (ID or passport) before your first \(role.jobNoun)."),
            Rule(icon: "hand.raised.fill", title: "Treat \(role.earner) with respect",
                 detail: "Be on time, courteous, and professional. Harassment or unsafe conduct means removal."),
            Rule(icon: "star.fill", title: "Keep your rating up",
                 detail: "Stay above 4.6★. Repeated low ratings or cancellations pause your account."),
            Rule(icon: "shield.lefthalf.filled", title: "Safety first",
                 detail: "Never work impaired. Follow all local traffic and safety laws at all times."),
        ]
        if role == .driver {
            // "(carte grise)" used to be in here, which is what the document is
            // called in Morocco and in France and nowhere else. The rule is the
            // same everywhere; the name on the paper is not, so the name is left
            // to the form — where the country is known — and the rule says what
            // it means.
            base.insert(Rule(icon: "car.fill", title: "Valid vehicle & papers",
                             detail: "A roadworthy vehicle, a valid driving licence, and current registration and insurance."),
                        at: 1)
        }
        return base
    }

    private func ruleRow(_ rule: Rule) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: rule.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(GGColor.ink(0.08)))
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                Text(rule.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(GGColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glass(cornerRadius: 18, fillOpacity: 0.05, borderOpacity: 0.08)
    }

    /// The stake in the currency the server actually charges it in.
    ///
    /// This page hardcoded "$30" twice while the page after it read the amount
    /// and the currency off the application — so a driver in a market billed in
    /// dirhams or naira agreed to one number on the rules screen and was asked
    /// for a different one on the next. The constant survives only as the value
    /// to show before the application has loaded.
    private var stakeLabel: String {
        guard let stake = app.driverStake else { return "$\(Int(PartnerRole.stakeAmount))" }
        return WalletStore.money(stake.requiredMinor, currency: stake.currency)
    }

    private var stakeNote: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(GGColor.onAccent)
                .frame(width: 40, height: 40)
                .background(Circle().fill(GGColor.white))
            VStack(alignment: .leading, spacing: 3) {
                Text("A \(stakeLabel) refundable stake")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                Text("Held as a good-conduct deposit. If a \(role.earner.dropLast()) is wronged, it can be released to them as compensation. You get it back when you leave in good standing.")
                    .font(.system(size: 13))
                    .foregroundStyle(GGColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glass(cornerRadius: 18, tint: Color.black.opacity(0.3))
    }

    private var agreementToggle: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeOut(duration: 0.18)) { app.partnerAgreedToTerms.toggle() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: app.partnerAgreedToTerms ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(app.partnerAgreedToTerms ? GGColor.white : GGColor.textTertiary)
                Text("I've read and agree to the Partner Terms, the community rules, and the \(stakeLabel) stake policy.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(GGColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footerCTA: some View {
        Button {
            app.agreePartnerRules()
        } label: {
            Text("I agree")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(GGColor.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Capsule().fill(GGColor.white))
        }
        .buttonStyle(PressableStyle())
        .disabled(!app.partnerAgreedToTerms)
        .opacity(app.partnerAgreedToTerms ? 1 : 0.4)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

// MARK: - Page 2 · Stake payment ($30)

private struct PartnerStakePage: View {
    @EnvironmentObject var app: AppState
    let role: PartnerRole

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    amountCard
                    breakdown
                    payMethod
                    reassurance
                    Color.clear.frame(height: 12)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            payButton
        }
        // The wallet and the stake both come from the server; a page opened
        // after a top-up in another tab should not show the old numbers.
        .task {
            await app.refreshWallet()
            await app.refreshDriverApplication(role)
        }
    }

    private var amountCard: some View {
        VStack(spacing: 10) {
            Text("GOOD-CONDUCT STAKE")
                .font(.ggMono(11, .semibold))
                .tracking(0.8)
                .foregroundStyle(GGColor.textSecondary)
            Text(stakeLabel)
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)
            Text("Refundable · held in your own wallet")
                .font(.system(size: 13))
                .foregroundStyle(GGColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .glass(cornerRadius: 24, tint: Color.black.opacity(0.3), floating: true)
    }

    private var breakdown: some View {
        VStack(spacing: 10) {
            row("Stake deposit", stakeLabel)
            row("Processing fee", "Free")
            row("Your wallet", WalletStore.money(
                app.driverStake?.walletAvailableMinor ?? app.wallet?.availableMinor ?? 0))
            Divider().background(GGColor.ink(0.1))
            HStack {
                Text(shortfall > 0 ? "Still needed" : "Due today")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
                Spacer()
                Text(shortfall > 0 ? WalletStore.money(shortfall) : stakeLabel)
                    .font(.ggMono(15, .semibold))
                    .foregroundStyle(GGColor.textPrimary)
            }
        }
        .padding(16)
        .glass(cornerRadius: 18, fillOpacity: 0.05, borderOpacity: 0.08)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(GGColor.textSecondary)
            Spacer()
            Text(value).font(.ggMono(13, .medium)).foregroundStyle(GGColor.textSecondary)
        }
    }

    /// Where the money comes from — the GoJo Wallet, which is the only place it
    /// ever could. There is no card form in this app and never should be: cards
    /// reach Stripe's hosted page and nothing else.
    private var payMethod: some View {
        HStack(spacing: 12) {
            Image(systemName: "wallet.bifold.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(GGColor.ink(0.08)))
            VStack(alignment: .leading, spacing: 1) {
                Text(shortfall > 0 ? "Not enough in" : "Held from")
                    .font(.system(size: 11)).foregroundStyle(GGColor.textTertiary)
                Text("Your GoJo Wallet")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(GGColor.textPrimary)
            }
            Spacer()
            if shortfall > 0 && app.walletTopUpAvailable {
                Button {
                    app.topUpForStake()
                } label: {
                    Text("Add \(WalletStore.money(shortfall))")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(GGColor.onAccent)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(GGColor.white))
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(12)
        .glass(cornerRadius: 16, fillOpacity: 0.05, borderOpacity: 0.08)
    }

    /// The amount is the server's, not a constant in this app — a stake that
    /// changes should be a config row, not a release.
    private var stakeLabel: String {
        WalletStore.money(app.driverStake?.requiredMinor ?? 3000,
                          currency: app.driverStake?.currency ?? "USD")
    }

    private var shortfall: Int { app.driverStake?.shortfallMinor ?? 0 }

    private var reassurance: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(GGColor.textTertiary)
            Text("This is a deposit, not a payment. It moves into a locked pocket of your own wallet, funds your ID check, and the rest comes back if you're turned down or you withdraw.")
                .font(.system(size: 12))
                .foregroundStyle(GGColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    private var payButton: some View {
        Button {
            app.payPartnerStake()
        } label: {
            HStack(spacing: 8) {
                if app.partnerStakeProcessing {
                    ProgressView().tint(GGColor.onAccent)
                    Text("Processing…")
                } else {
                    Image(systemName: "lock.fill").font(.system(size: 13, weight: .bold))
                    Text(app.driverStake?.isPaid == true
                         ? "Continue" : "Lock \(stakeLabel) stake")
                }
            }
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(GGColor.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Capsule().fill(GGColor.white))
        }
        .buttonStyle(PressableStyle())
        .disabled(app.partnerStakeProcessing)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

// MARK: - Page 3 · KYC / verification

private struct PartnerKYCPage: View {
    @EnvironmentObject var app: AppState
    let role: PartnerRole
    /// Which paper is in flight, so the tile can say so rather than looking dead.
    @State private var uploadingDocument: String?
    /// Which paper the picker on screen is for. One set of pickers serves every
    /// tile — presenting a camera and a library per tile would be six sheets
    /// racing each other for the same screen.
    @State private var pendingDocument: String?
    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var libraryItem: PhotosPickerItem?
    /// Where the vehicle is registered, and which expiry date is being set.
    @State private var choosingCountry = false
    @State private var editingDate: DateField?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    intro
                    if app.driverApplicationWasRejected { rejectionNote }
                    identitySection
                    if role == .driver { driverSection }
                    if role == .courier { courierSection }
                    Color.clear.frame(height: 12)
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
            }
            .scrollDismissesKeyboard(.interactively)
            submitButton
        }
        // The verdict can land while this page is open — a check that was
        // "in review" when they got here may be done by the time they look.
        .task { await app.refreshIdentity() }
        .modifier(DocumentSourcePickers(
            showLibrary: $showLibrary,
            showCamera: $showCamera, libraryItem: $libraryItem,
            onCancel: { pendingDocument = nil },
            onPicked: { data in
                guard let kind = pendingDocument else { return }
                pendingDocument = nil
                Task { await upload(data, kind: kind) }
            }))
        .sheet(isPresented: $choosingCountry) {
            CountryPickerSheet(selected: $app.partnerApplication.vehicleCountry)
        }
        .sheet(item: $editingDate) { field in
            ExpiryDateSheet(title: field.title, iso: binding(for: field))
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Verify your identity")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)
            Text(app.showsIdentityVerification
                 ? "We check your ID with a licensed verification provider. Your documents go to them, not to us."
                 : "We need a few documents to keep the community safe. Everything is encrypted.")
                .explanatory(14)
                .foregroundStyle(GGColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What the reviewer said, when they sent it back.
    ///
    /// A rejected application reopens with everything still on it, so the only
    /// thing separating it from a resubmission is knowing what was wrong — and
    /// the app used to know and not say. Their sentence, not a paraphrase of it:
    /// "the back of your licence is out of focus" is a five-second fix, and
    /// "we couldn't verify this" is a person giving up.
    private var rejectionNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(GGColor.ink(0.08)))
            VStack(alignment: .leading, spacing: 3) {
                Text("Sent back for a fix")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                Text(app.driverReviewNote
                     ?? "A reviewer couldn't accept this as it was. Check your photos are sharp and your details match your papers.")
                    .font(.system(size: 13))
                    .foregroundStyle(GGColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Nothing is lost — fix what's below and send it again. Your stake stays where it is.")
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glass(cornerRadius: 18, tint: GGColor.ink(0.10))
    }

    // MARK: Identity — the vendor's half
    //
    // This card is a *rendering of a verdict*, not a form. Everything the person
    // types or photographs happens inside the Sumsub SDK, which sends it
    // straight to Sumsub — so there is nothing here to bind, validate, or store.
    // What used to be here (a name field, a document-number field, and two tiles
    // you tapped to claim you'd taken a photo) checked nothing at all.

    private var identitySection: some View {
        formCard(title: "Identity", icon: app.identity.status.icon) {
            if app.showsIdentityVerification {
                identityStatusRow
                if let message = identityMessage {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(GGColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                identityActions
            } else {
                // No vendor configured on this backend: identity is proved by
                // document upload and human review, which is the operator's
                // journey in Gojo Admin — so say so rather than offering a
                // button that would fail.
                Text("Identity checks are handled by our team for this account. "
                     + "We'll be in touch about your documents.")
                    .font(.system(size: 13))
                    .foregroundStyle(GGColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var identityStatusRow: some View {
        HStack(spacing: 12) {
            Image(systemName: app.identity.status.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(app.identity.isVerified ? GGColor.onAccent : GGColor.textPrimary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(app.identity.isVerified
                                          ? GGColor.white : GGColor.ink(0.08)))
            VStack(alignment: .leading, spacing: 2) {
                Text(identityHeadline)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                Text(app.identity.status.label)
                    .font(.ggMono(10, .semibold))
                    .tracking(0.4)
                    .foregroundStyle(GGColor.textTertiary)
            }
            Spacer(minLength: 0)
            if app.identityBusy {
                ProgressView().tint(GGColor.textSecondary)
            }
        }
    }

    private var identityHeadline: String {
        switch app.identity.status {
        case .verified: return "Your identity is confirmed"
        case .inReview: return "We're checking your documents"
        case .rejected: return "We couldn't verify this"
        default:        return "Scan your ID and take a selfie"
        }
    }

    /// The vendor's own wording when there is any, so a person is told the same
    /// thing the reviewer saw rather than our paraphrase of it.
    private var identityMessage: String? {
        app.identity.isVerified ? nil : app.identity.message
    }

    @ViewBuilder
    private var identityActions: some View {
        if let title = app.identity.actionTitle {
            Button {
                app.startIdentityVerification()
            } label: {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(GGColor.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(GGColor.white))
            }
            .buttonStyle(PressableStyle())
            .disabled(app.identityBusy)
            .opacity(app.identityBusy ? 0.5 : 1)
        } else if app.identity.status.isPending {
            // Nothing for them to do but wait — and waiting with no way to ask
            // is what makes a pending check feel broken.
            Button {
                app.recheckIdentity()
            } label: {
                Text("Check again")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(GGColor.ink(0.08)))
            }
            .buttonStyle(PressableStyle())
            .disabled(app.identityBusy)
        }
    }

    // Driver — vehicle type, then (car / motorcycle only) licence + papers
    private var driverSection: some View {
        VStack(spacing: 20) {
            vehicleTypeCard

            if app.partnerApplication.driverVehicle.requiresLicense {
                licenceAndVehicleCards
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                trottinetteNote
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: app.partnerApplication.driverVehicle)
    }

    private var vehicleTypeCard: some View {
        formCard(title: "What do you drive?", icon: "car.fill") {
            VStack(spacing: 8) {
                ForEach(DriverVehicle.allCases) { v in
                    let active = app.partnerApplication.driverVehicle == v
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeOut(duration: 0.2)) { app.partnerApplication.driverVehicle = v }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: v.icon)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(active ? GGColor.onAccent : GGColor.textPrimary)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(active ? GGColor.white : GGColor.ink(0.08)))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(v.rawValue)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(GGColor.textPrimary)
                                if !v.requiresLicense {
                                    Text("No licence or papers needed")
                                        .font(.system(size: 11))
                                        .foregroundStyle(GGColor.textTertiary)
                                }
                            }
                            Spacer()
                            Image(systemName: active ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18))
                                .foregroundStyle(active ? GGColor.white : GGColor.textTertiary)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(active ? GGColor.ink(0.1) : Color.clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var trottinetteNote: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(GGColor.onAccent)
                .frame(width: 40, height: 40)
                .background(Circle().fill(GGColor.white))
            VStack(alignment: .leading, spacing: 3) {
                Text("You're all set")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                Text("E-scooters don't need a driving licence or vehicle papers anywhere we operate — just your verified ID.")
                    .font(.system(size: 13))
                    .foregroundStyle(GGColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glass(cornerRadius: 18, tint: Color.black.opacity(0.3))
    }

    private var licenceAndVehicleCards: some View {
        VStack(spacing: 20) {
            formCard(title: "Driver's licence", icon: "creditcard.fill") {
                fieldRow(title: "Licence number", placeholder: "Licence number",
                         text: $app.partnerApplication.licenseNumber, autocaps: .characters)
                // Both hang off the application rather than off the car: the
                // licence is the driver's, and it outlives the Yaris. Two tiles
                // rather than one "both sides" because one upload is one image,
                // and the back is a different document — it carries what you're
                // entitled to drive and when that runs out.
                uploadTile(kind: PartnerDocumentKind.driverLicenseFront,
                           title: "Licence — front", subtitle: "The photo side",
                           icon: "creditcard.fill",
                           uploaded: app.driverLicenseUploaded(
                               PartnerDocumentKind.driverLicenseFront))
                uploadTile(kind: PartnerDocumentKind.driverLicenseBack,
                           title: "Licence — back", subtitle: "Categories and expiry",
                           icon: "creditcard.and.123",
                           uploaded: app.driverLicenseUploaded(
                               PartnerDocumentKind.driverLicenseBack))
            }
            formCard(title: "Your vehicle", icon: "car.fill") {
                HStack(spacing: 10) {
                    fieldRow(title: "Make", placeholder: "Toyota",
                             text: $app.partnerApplication.vehicleMake)
                    fieldRow(title: "Model", placeholder: "Yaris",
                             text: $app.partnerApplication.vehicleModel)
                }
                HStack(spacing: 10) {
                    fieldRow(title: "Year", placeholder: "2021",
                             text: $app.partnerApplication.vehicleYear, keyboard: .numberPad)
                    fieldRow(title: "Colour", placeholder: "White",
                             text: $app.partnerApplication.vehicleColor)
                }
                // Country first, because it decides what the two fields under it
                // are called and whether the second one exists at all.
                countryRow
                fieldRow(title: "Licence plate", placeholder: plateRules.plateExample,
                         text: $app.partnerApplication.plate, autocaps: .characters)
                // Asked only where a plate is issued by a state or a province.
                // Everywhere else plates are national, and a city here would be
                // an address pretending to be part of an identifier — two
                // spellings of one town landing in two uniqueness scopes.
                if let subdivision = plateRules.subdivisionLabel {
                    fieldRow(title: subdivision,
                             placeholder: plateRules.subdivisionExample ?? subdivision,
                             text: $app.partnerApplication.vehicleRegion)
                }
                HStack(spacing: 10) {
                    dateRow(title: "Registration expires", field: .registration)
                    dateRow(title: "Insurance expires", field: .insurance)
                }
                // These two are real uploads into the private prefix — the same
                // place an ID card goes, and never a public URL. A driver has to
                // have saved the vehicle first, because a document belongs to a
                // car rather than to an application.
                documentTile(kind: VehicleDocumentKind.registration,
                             title: "Vehicle registration",
                             subtitle: registrationHint,
                             icon: "doc.text.fill")
                documentTile(kind: VehicleDocumentKind.insurance,
                             title: "Insurance certificate",
                             subtitle: "Current, and expiring after today",
                             icon: "shield.lefthalf.filled")
            }
        }
    }

    private var plateRules: VehicleRegistry.Rules {
        VehicleRegistry.rules(for: app.partnerApplication.vehicleCountry)
    }

    /// "Carte grise — matching the plate above" where that is what the document
    /// is called, and just the plain instruction where the local name for it is
    /// the plain one. Repeating "vehicle registration" under a tile titled
    /// "Vehicle registration" says nothing.
    private var registrationHint: String {
        let local = plateRules.registrationName
        guard local != "vehicle registration" else { return "Matching the plate above" }
        return "\(local.prefix(1).uppercased())\(local.dropFirst()) — matching the plate above"
    }

    private var countryRow: some View {
        let code = app.partnerApplication.vehicleCountry
        return VStack(alignment: .leading, spacing: 5) {
            Text("REGISTERED IN")
                .font(.ggMono(9, .semibold))
                .tracking(0.4)
                .foregroundStyle(GGColor.textTertiary)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                choosingCountry = true
            } label: {
                HStack(spacing: 8) {
                    Text(code.isEmpty ? "Choose a country"
                         : "\(VehicleRegistry.flag(code))  \(VehicleRegistry.name(of: code))")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(code.isEmpty ? GGColor.textTertiary : GGColor.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(GGColor.textTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(GGColor.ink(0.06)))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(GGColor.ink(0.08), lineWidth: 0.5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Courier — vehicle type
    private var courierSection: some View {
        formCard(title: "How you'll deliver", icon: "bag.fill") {
            VStack(spacing: 8) {
                ForEach(CourierVehicle.allCases) { v in
                    let active = app.partnerApplication.vehicleType == v
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeOut(duration: 0.18)) { app.partnerApplication.vehicleType = v }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: v.icon)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(active ? GGColor.onAccent : GGColor.textPrimary)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(active ? GGColor.white : GGColor.ink(0.08)))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(v.rawValue)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(GGColor.textPrimary)
                                if v == .onFeet {
                                    Text("Walk deliveries nearby")
                                        .font(.system(size: 11))
                                        .foregroundStyle(GGColor.textTertiary)
                                }
                            }
                            Spacer()
                            Image(systemName: active ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18))
                                .foregroundStyle(active ? GGColor.white : GGColor.textTertiary)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(active ? GGColor.ink(0.1) : Color.clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: form building blocks

    private func formCard<Content: View>(title: String, icon: String,
                                          @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glass(cornerRadius: 20, fillOpacity: 0.05, borderOpacity: 0.08)
    }

    private func fieldRow(title: String, placeholder: String, text: Binding<String>,
                          keyboard: UIKeyboardType = .default,
                          autocaps: TextInputAutocapitalization = .words) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.ggMono(9, .semibold))
                .tracking(0.4)
                .foregroundStyle(GGColor.textTertiary)
            TextField(placeholder, text: text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(GGColor.textPrimary)
                .tint(GGColor.white)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocaps)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(GGColor.ink(0.06)))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(GGColor.ink(0.08), lineWidth: 0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A date on a document, picked rather than typed.
    ///
    /// These two were text fields asking for `2027-04-30`, which is a format
    /// almost nobody writes by hand: most of the world types 30/04/2027 and much
    /// of the Americas types 04/30/2027. Both were refused, and the refusal
    /// arrived at submit — long after the mistake, with no clue which of the two
    /// fields was wrong.
    ///
    /// A picker cannot produce an invalid date and shows it in the reader's own
    /// calendar and language, while what travels stays the ISO string the API
    /// speaks. It reads "Select a date" until one is actually chosen, because
    /// this whole screen's original sin was controls that looked answered
    /// before anybody had answered them.
    private func dateRow(title: String, field: DateField) -> some View {
        let iso = binding(for: field).wrappedValue
        return VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.ggMono(9, .semibold))
                .tracking(0.4)
                .foregroundStyle(GGColor.textTertiary)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                editingDate = field
            } label: {
                HStack(spacing: 6) {
                    Text(iso.isEmpty ? "Select a date" : Self.readable(iso))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(iso.isEmpty ? GGColor.textTertiary : GGColor.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GGColor.textTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(GGColor.ink(0.06)))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(GGColor.ink(0.08), lineWidth: 0.5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Which of the two expiry dates a sheet is editing. An enum rather than the
    /// binding itself because `sheet(item:)` needs something identifiable, and
    /// two dates is not enough to justify anything cleverer.
    enum DateField: String, Identifiable {
        case registration, insurance
        var id: String { rawValue }
        var title: String {
            self == .registration ? "Registration expires" : "Insurance expires"
        }
    }

    private func binding(for field: DateField) -> Binding<String> {
        switch field {
        case .registration: return $app.partnerApplication.registrationExpiresOn
        case .insurance:    return $app.partnerApplication.insuranceExpiresOn
        }
    }

    /// The stored `yyyy-MM-dd` as the reader would write it — their calendar,
    /// their month names, their order.
    private static func readable(_ iso: String) -> String {
        guard let date = isoFormatter.date(from: iso) else { return iso }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// Fixed POSIX locale, Gregorian, UTC — never the device's. The wire format
    /// is a Gregorian ISO date, and formatting one through a Persian, Buddhist
    /// or Japanese-era calendar would send the server a year it cannot read.
    static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// A vehicle paper — a claim about the car, so whether it has arrived is
    /// read off the car.
    private func documentTile(kind: String, title: String, subtitle: String,
                              icon: String) -> some View {
        uploadTile(kind: kind, title: title, subtitle: subtitle, icon: icon,
                   uploaded: !(app.driverApplication?.activeVehicle?
                       .missingDocuments?.contains(kind) ?? true))
    }

    /// One upload, whatever it hangs off — a car's papers or the driver's own
    /// licence.
    ///
    /// The tiles this replaces toggled a Bool and checked nothing — the same
    /// pattern the identity half lost when Sumsub arrived, for the same reason:
    /// a checkbox that claims a photo was taken is worse than no photo, because
    /// it looks like evidence. So `uploaded` is always somebody else's answer —
    /// the server's `missingDocuments` — and never a flag this screen sets on
    /// itself the moment it is tapped.
    ///
    /// Tapping asks camera or library rather than assuming. Most of these papers
    /// are in somebody's hand while they fill this in, and a tile that only ever
    /// opened the library asked them to go and photograph it somewhere else first.
    ///
    /// The choice is a menu on the tile rather than a dialog on the page, because
    /// a dialog is anchored to the view that presents it: one page-level dialog
    /// serving six tiles opened at the top of the screen no matter which paper
    /// was tapped, beside a card that had nothing to do with it. A menu opens on
    /// its own label, so "front of your licence" is asked over the front of your
    /// licence.
    private func uploadTile(kind: String, title: String, subtitle: String,
                            icon: String, uploaded: Bool) -> some View {
        Menu {
            // The camera is absent in the Simulator and on a device with no
            // usable one, where offering it would present an empty controller.
            if CameraCaptureView.isAvailable {
                Button {
                    beginUpload(kind) { showCamera = true }
                } label: {
                    Label("Take a photo", systemImage: "camera.fill")
                }
            }
            Button {
                beginUpload(kind) { showLibrary = true }
            } label: {
                Label("Choose from library", systemImage: "photo.on.rectangle")
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: uploaded ? "checkmark.circle.fill" : icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(uploaded ? GGColor.onAccent : GGColor.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(uploaded ? GGColor.white : GGColor.ink(0.08)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                    Text(uploaded ? "Uploaded" : subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(uploaded ? GGColor.textSecondary : GGColor.textTertiary)
                }
                Spacer(minLength: 0)
                if uploadingDocument == kind {
                    ProgressView().controlSize(.small).tint(GGColor.textTertiary)
                } else {
                    Image(systemName: uploaded ? "arrow.counterclockwise" : "camera.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GGColor.textTertiary)
                }
            }
            .padding(12)
            // A menu sizes itself to its label, where the button this used to be
            // was handed the card's width — without this the tile shrinks to
            // its text and stops lining up with the fields above it.
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(GGColor.ink(0.05)))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(uploaded ? GGColor.ink(0.2) : GGColor.ink(0.08),
                                  lineWidth: uploaded ? 1 : 0.5))
            .contentShape(Rectangle())
        }
        .menuOrder(.fixed)
        .buttonStyle(.plain)
        // One upload at a time. Two in flight would race each other to replace
        // `driverApplication`, and the loser's tile would go back to un-uploaded.
        // Nothing at all once the application has left the applicant's hands:
        // the server refuses the write, so the tile must not offer it.
        .disabled(uploadingDocument != nil || !app.driverApplicationIsOpen)
    }

    /// Marks which paper the picker about to open is for, then opens it.
    /// Set here rather than when the tile is tapped so a menu somebody dismissed
    /// without choosing leaves nothing behind to attach the next photo to.
    private func beginUpload(_ kind: String, _ open: () -> Void) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        pendingDocument = kind
        open()
    }

    private func upload(_ data: Data, kind: String) async {
        uploadingDocument = kind
        defer { uploadingDocument = nil }
        guard !PartnerDocumentKind.driverLicense.contains(kind) else {
            // The licence belongs to the applicant, so it needs no vehicle —
            // and asking for one first would be a car standing between somebody
            // and photographing their own licence.
            await app.uploadDriverLicense(kind: kind, image: data)
            return
        }
        // A car's papers do: the vehicle has to exist before they can hang off
        // it. The licence number goes with that save — the server wants it
        // before it will call the application complete, and this is the first
        // moment the app has anything to send.
        if app.driverApplication?.activeVehicle == nil {
            await app.saveDriverLicenseNumber()
            guard await app.saveDriverVehicle() else { return }
        }
        await app.uploadVehicleDocument(kind: kind, image: data)
    }

    @ViewBuilder
    private var submitButton: some View {
        // Already handed in. Re-entering the flow lands on the review page, so
        // this is for the submission that lands while the page is open — a
        // refresh, or a second device. Either way there is nothing to submit
        // twice, and a live Submit button would be offering it.
        if app.driverApplicationIsSubmitted {
            reviewNotice
        } else {
            submitCTA
        }
    }

    private var reviewNotice: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(GGColor.ink(0.08)))
            VStack(alignment: .leading, spacing: 2) {
                Text("In review")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                Text("A person is checking your application. Nothing else to do — we'll let you know.")
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .glass(cornerRadius: 16, fillOpacity: 0.05, borderOpacity: 0.08)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var submitCTA: some View {
        VStack(spacing: 8) {
            // A greyed-out button that won't say why is the thing people report
            // as broken, so the server's own sentence goes underneath it.
            if let hint = app.partnerSubmitHint, !app.partnerKYCComplete {
                Text(hint)
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
            Button {
                app.submitDriverApplication()
            } label: {
                HStack(spacing: 8) {
                    if app.partnerSubmitting {
                        ProgressView().tint(GGColor.onAccent)
                    }
                    // "Send it again" over a rejection, matching the note at the
                    // top of the page: this is the same application going back
                    // to the same queue, not a second one being started.
                    Text(app.partnerSubmitting ? "Submitting…"
                         : app.driverApplicationWasRejected ? "Send it again"
                         : "Submit for review")
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(GGColor.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Capsule().fill(GGColor.white))
            }
            .buttonStyle(PressableStyle())
            .disabled(!app.partnerKYCComplete || app.partnerSubmitting)
            .opacity(app.partnerKYCComplete && !app.partnerSubmitting ? 1 : 0.4)
        }
        .animation(.easeInOut(duration: 0.2), value: app.partnerSubmitHint)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

// MARK: - Where the car is registered

/// Every country, searchable, in the reader's own language and sort order.
///
/// A full list rather than the handful the platform launched in: a driver whose
/// country isn't on a list can't correct it, and "we only know about these
/// eleven places" is precisely the assumption this screen was carrying.
private struct CountryPickerSheet: View {
    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var matches: [VehicleRegistry.Country] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return VehicleRegistry.countries }
        return VehicleRegistry.countries.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.code.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        NavigationStack {
            List(matches) { country in
                Button {
                    selected = country.code
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Text(VehicleRegistry.flag(country.code))
                        Text(country.name)
                            .foregroundStyle(GGColor.textPrimary)
                        Spacer(minLength: 0)
                        if country.code == selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(GGColor.textPrimary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(GGColor.sheetBG.ignoresSafeArea())
            .searchable(text: $query, prompt: "Search countries")
            .navigationTitle("Registered in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// One expiry date, on a wheel that cannot produce an invalid one.
///
/// The range starts today: a registration that expired last month is not an
/// expiry date somebody is entering on purpose, and the server refuses it
/// anyway — better to make it unreachable than to reject it two screens later.
private struct ExpiryDateSheet: View {
    let title: String
    @Binding var iso: String
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            DatePicker(title, selection: $date, in: Date()...,
                       displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(GGColor.white)
                .labelsHidden()
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(GGColor.sheetBG.ignoresSafeArea())
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            iso = PartnerKYCPage.isoFormatter.string(from: date)
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            // Opens on what's already recorded, or a year out — roughly when
            // papers renewed today would lapse, so the first spin is a short one.
            // Clamped forward, because a date already recorded may have expired
            // since, and starting the wheel outside its own range is undefined.
            let stored = PartnerKYCPage.isoFormatter.date(from: iso)
                ?? Calendar(identifier: .gregorian)
                    .date(byAdding: .year, value: 1, to: Date()) ?? Date()
            date = max(stored, Date())
        }
    }
}

// MARK: - Camera or library, for a paper you're holding

/// The two presentations every document tile shares: the library and the camera.
///
/// One set for the whole page rather than one per tile. SwiftUI presents at most
/// one sheet per view, so six tiles carrying their own pickers would mean six
/// modifiers competing for the same slot — and a photo landing on whichever tile
/// won. The page holds the pickers; the tile only says which paper it is for.
///
/// The *choice* between the two is not here, and that is the point: it is a menu
/// on the tile itself (see `uploadTile`). A dialog presented from this modifier
/// is anchored to the view carrying it — the whole page — so every tile, however
/// far down the scroll, opened one panel pinned near the top of the screen,
/// pointing at whatever card happened to be there.
private struct DocumentSourcePickers: ViewModifier {
    @Binding var showLibrary: Bool
    @Binding var showCamera: Bool
    @Binding var libraryItem: PhotosPickerItem?
    let onCancel: () -> Void
    let onPicked: (Data) -> Void

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $showLibrary, selection: $libraryItem,
                          matching: .images)
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                libraryItem = nil
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self) else {
                        onCancel()
                        return
                    }
                    onPicked(data)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCaptureView(
                    onCapture: { capture in
                        showCamera = false
                        guard case .photo(let data) = capture else {
                            onCancel()
                            return
                        }
                        onPicked(data)
                    },
                    onCancel: {
                        showCamera = false
                        onCancel()
                    },
                    photosOnly: true)
                .ignoresSafeArea()
            }
    }
}

// MARK: - Page 4 · Process complete

private struct PartnerDonePage: View {
    @EnvironmentObject var app: AppState
    let role: PartnerRole
    @State private var appear = false

    /// True only once a reviewer has actually said yes — which is the dispatch
    /// registry existing, not this app deciding.
    private var approved: Bool { app.partnerRoles.contains(role) }

    /// Approved once and switched off since. Kept apart from "in review" on
    /// purpose: this page is now also where somebody lands when they re-open
    /// the flow, and a suspended partner told "we're checking your application"
    /// would be waiting for a verdict that has already been reached.
    private var suspended: Bool { app.driverApplicationIsSuspended }

    /// Whether there is a dashboard worth opening behind the button.
    private var canWork: Bool { approved && !suspended }

    private var headline: String {
        if suspended { return "Your account is on hold" }
        return canWork ? "You're on the road" : "Sent for review"
    }

    /// The reviewer's own sentence for a suspension, because a paused account
    /// with no reason given is a support ticket. Submitting is not being
    /// approved, and the middle case says so: a person reviews this — the same
    /// queue a restaurant waits in — and telling somebody they are a driver
    /// before anybody has read their application would be the app lying on its
    /// own behalf.
    private var explanation: String {
        if suspended {
            return app.driverReviewNote
                ?? "Your \(role.title.lowercased()) account is paused while we look into something. Your stake stays yours."
        }
        if canWork {
            return "You're a GojoGo \(role.title.lowercased()). Go online whenever you're ready."
        }
        return "A person checks every \(role.title.lowercased()) application, including your papers and your vehicle. We'll let you know as soon as it's decided — your stake stays yours either way."
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(GGColor.ink(0.12), lineWidth: 2)
                        .frame(width: 108, height: 108)
                        .scaleEffect(appear ? 1.15 : 0.8)
                        .opacity(appear ? 0 : 0.9)
                    Circle()
                        .fill(GGColor.white)
                        .frame(width: 88, height: 88)
                        .overlay(
                            Image(systemName: suspended ? "pause.fill" : "checkmark")
                                .font(.system(size: 38, weight: .bold))
                                .foregroundStyle(GGColor.onAccent))
                        .scaleEffect(appear ? 1 : 0.6)
                }

                VStack(spacing: 10) {
                    Text(headline)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(GGColor.textPrimary)
                    Text(explanation)
                        .explanatory(15)
                        .foregroundStyle(GGColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                }

                HStack(spacing: 10) {
                    doneBadge(icon: "checkmark.seal.fill", label: "ID verified")
                    doneBadge(icon: "lock.shield.fill", label: "Stake held")
                    if suspended {
                        doneBadge(icon: "pause.circle.fill", label: "On hold")
                    } else {
                        doneBadge(icon: canWork ? role.icon : "clock.fill",
                                  label: canWork ? role.title : "In review")
                    }
                }
            }
            .opacity(appear ? 1 : 0)
            Spacer()

            VStack(spacing: 10) {
                Button {
                    app.finishPartnerOnboarding(openDashboard: canWork)
                } label: {
                    Text(canWork ? "Go to \(role.title) mode" : "Done")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(GGColor.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Capsule().fill(GGColor.white))
                }
                .buttonStyle(PressableStyle())

                if canWork {
                    Button {
                        app.finishPartnerOnboarding(openDashboard: false)
                    } label: {
                        Text("Maybe later")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(GGColor.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 20)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { appear = true }
        }
    }

    private func doneBadge(icon: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(GGColor.ink(0.08)))
            Text(label)
                .font(.ggMono(9, .semibold))
                .foregroundStyle(GGColor.textSecondary)
        }
    }
}
