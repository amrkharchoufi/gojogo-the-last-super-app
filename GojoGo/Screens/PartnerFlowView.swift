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
            base.insert(Rule(icon: "car.fill", title: "Valid car & papers",
                             detail: "A roadworthy vehicle, a valid licence, and up-to-date registration (carte grise)."),
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

    private var stakeNote: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(GGColor.onAccent)
                .frame(width: 40, height: 40)
                .background(Circle().fill(GGColor.white))
            VStack(alignment: .leading, spacing: 3) {
                Text("A $\(Int(PartnerRole.stakeAmount)) refundable stake")
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
                Text("I've read and agree to the Partner Terms, the community rules, and the $\(Int(PartnerRole.stakeAmount)) stake policy.")
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

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    intro
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
                Text("Trottinettes don't need a driver's licence or vehicle registration — just your verified ID.")
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
                // Hangs off the application rather than off the car: the licence
                // is the driver's, and it outlives the Yaris.
                // "Both sides" is gone with the placeholder that promised it:
                // one upload is one image, and telling somebody to photograph
                // two would be asking for something this can't keep.
                uploadTile(kind: PartnerDocumentKind.driverLicense,
                           title: "Licence photo", subtitle: "The front, clearly readable",
                           icon: "creditcard.fill",
                           uploaded: app.driverLicenseUploaded)
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
                fieldRow(title: "Licence plate", placeholder: "12345 - أ - 6",
                         text: $app.partnerApplication.plate, autocaps: .characters)
                // Plates are unique per *region*, never globally — the same
                // string is a different car in another country, which is why
                // the server refuses a duplicate only within one.
                fieldRow(title: "Registered in", placeholder: "Casablanca",
                         text: $app.partnerApplication.vehicleRegion)
                HStack(spacing: 10) {
                    fieldRow(title: "Registration expires", placeholder: "2027-04-30",
                             text: $app.partnerApplication.registrationExpiresOn)
                    fieldRow(title: "Insurance expires", placeholder: "2027-01-15",
                             text: $app.partnerApplication.insuranceExpiresOn)
                }
                // These two are real uploads into the private prefix — the same
                // place an ID card goes, and never a public URL. A driver has to
                // have saved the vehicle first, because a document belongs to a
                // car rather than to an application.
                documentTile(kind: VehicleDocumentKind.registration,
                             title: "Vehicle registration",
                             subtitle: "Carte grise — matching the plate above",
                             icon: "doc.text.fill")
                documentTile(kind: VehicleDocumentKind.insurance,
                             title: "Insurance certificate",
                             subtitle: "Current, and expiring after today",
                             icon: "shield.lefthalf.filled")
            }
        }
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
    @ViewBuilder
    private func uploadTile(kind: String, title: String, subtitle: String,
                            icon: String, uploaded: Bool) -> some View {
        PhotosPicker(selection: binding(for: kind), matching: .images) {
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
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(GGColor.ink(0.05)))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(uploaded ? GGColor.ink(0.2) : GGColor.ink(0.08),
                                  lineWidth: uploaded ? 1 : 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func binding(for kind: String) -> Binding<PhotosPickerItem?> {
        Binding(get: { nil }, set: { item in
            guard let item else { return }
            Task { await upload(item, kind: kind) }
        })
    }

    private func upload(_ item: PhotosPickerItem, kind: String) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        uploadingDocument = kind
        defer { uploadingDocument = nil }
        guard kind != PartnerDocumentKind.driverLicense else {
            // The licence belongs to the applicant, so it needs no vehicle —
            // and asking for one first would be a car standing between somebody
            // and photographing their own licence.
            await app.uploadDriverLicense(image: data)
            return
        }
        // A car's papers do: the vehicle has to exist before they can hang off it.
        if app.driverApplication?.activeVehicle == nil,
           !(await app.saveDriverVehicle()) { return }
        await app.uploadVehicleDocument(kind: kind, image: data)
    }

    private var submitButton: some View {
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
                    Text(app.partnerSubmitting ? "Submitting…" : "Submit for review")
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

// MARK: - Page 4 · Process complete

private struct PartnerDonePage: View {
    @EnvironmentObject var app: AppState
    let role: PartnerRole
    @State private var appear = false

    /// True only once a reviewer has actually said yes — which is the dispatch
    /// registry existing, not this app deciding.
    private var approved: Bool { app.partnerRoles.contains(role) }

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
                            Image(systemName: "checkmark")
                                .font(.system(size: 38, weight: .bold))
                                .foregroundStyle(GGColor.onAccent))
                        .scaleEffect(appear ? 1 : 0.6)
                }

                VStack(spacing: 10) {
                    // Submitting is not being approved, and the screen says so.
                    // A person reviews this — the same queue a restaurant waits
                    // in — and telling somebody they are a driver before anybody
                    // has read their application would be the app lying on its
                    // own behalf.
                    Text(approved ? "You're on the road" : "Sent for review")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(GGColor.textPrimary)
                    Text(approved
                         ? "You're a GojoGo \(role.title.lowercased()). Go online whenever you're ready."
                         : "A person checks every \(role.title.lowercased()) application, including your papers and your vehicle. We'll let you know as soon as it's decided — your stake stays yours either way.")
                        .explanatory(15)
                        .foregroundStyle(GGColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                }

                HStack(spacing: 10) {
                    doneBadge(icon: "checkmark.seal.fill", label: "ID verified")
                    doneBadge(icon: "lock.shield.fill", label: "Stake held")
                    doneBadge(icon: approved ? role.icon : "clock.fill",
                              label: approved ? role.title : "In review")
                }
            }
            .opacity(appear ? 1 : 0)
            Spacer()

            VStack(spacing: 10) {
                Button {
                    app.finishPartnerOnboarding(openDashboard: approved)
                } label: {
                    Text(approved ? "Go to \(role.title) mode" : "Done")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(GGColor.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Capsule().fill(GGColor.white))
                }
                .buttonStyle(PressableStyle())

                if approved {
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
