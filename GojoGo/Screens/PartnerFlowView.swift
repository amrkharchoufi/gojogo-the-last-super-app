import SwiftUI

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
    }

    private var amountCard: some View {
        VStack(spacing: 10) {
            Text("GOOD-CONDUCT STAKE")
                .font(.ggMono(11, .semibold))
                .tracking(0.8)
                .foregroundStyle(GGColor.textSecondary)
            Text("$\(Int(PartnerRole.stakeAmount))")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)
            Text("Refundable · held securely")
                .font(.system(size: 13))
                .foregroundStyle(GGColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .glass(cornerRadius: 24, tint: Color.black.opacity(0.3), floating: true)
    }

    private var breakdown: some View {
        VStack(spacing: 10) {
            row("Stake deposit", "$\(Int(PartnerRole.stakeAmount)).00")
            row("Processing fee", "Free")
            Divider().background(GGColor.ink(0.1))
            HStack {
                Text("Due today")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
                Spacer()
                Text("$\(Int(PartnerRole.stakeAmount)).00")
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

    private var payMethod: some View {
        HStack(spacing: 12) {
            Image(systemName: "apple.logo")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(GGColor.ink(0.08)))
            VStack(alignment: .leading, spacing: 1) {
                Text("Paying with")
                    .font(.system(size: 11)).foregroundStyle(GGColor.textTertiary)
                Text("Apple Pay")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(GGColor.textPrimary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(GGColor.textTertiary)
        }
        .padding(12)
        .glass(cornerRadius: 16, fillOpacity: 0.05, borderOpacity: 0.08)
    }

    private var reassurance: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(GGColor.textTertiary)
            Text("This is a deposit, not a payment for anything. It stays yours and is returned in full when you stop \(role == .driver ? "driving" : "delivering") in good standing.")
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
                    Text("Pay $\(Int(PartnerRole.stakeAmount)) stake")
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
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Verify your identity")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)
            Text("We need a few documents to keep the community safe. Everything is encrypted.")
                .explanatory(14)
                .foregroundStyle(GGColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // Identity — both roles
    private var identitySection: some View {
        formCard(title: "Identity", icon: "person.text.rectangle.fill") {
            docTypePicker
            fieldRow(title: "Full legal name", placeholder: "As printed on your document",
                     text: $app.partnerApplication.fullName)
            fieldRow(title: "\(app.partnerApplication.idType.rawValue) number",
                     placeholder: app.partnerApplication.idType == .passport ? "e.g. AB1234567" : "Document number",
                     text: $app.partnerApplication.idNumber,
                     autocaps: .characters)
            captureTile(title: "\(app.partnerApplication.idType.rawValue) photo",
                        subtitle: "Front & back, clearly readable",
                        icon: app.partnerApplication.idType.icon,
                        captured: $app.partnerApplication.idPhotoCaptured)
            captureTile(title: "Selfie check",
                        subtitle: "A quick photo to match your ID",
                        icon: "face.smiling",
                        captured: $app.partnerApplication.selfieCaptured)
        }
    }

    private var docTypePicker: some View {
        HStack(spacing: 8) {
            ForEach(IDDocumentType.allCases) { type in
                let active = app.partnerApplication.idType == type
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeOut(duration: 0.18)) {
                        app.partnerApplication.idType = type
                        app.partnerApplication.idPhotoCaptured = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: type.icon).font(.system(size: 12, weight: .semibold))
                        Text(type.rawValue).font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(active ? GGColor.onAccent : GGColor.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(active ? GGColor.white : GGColor.ink(0.08)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
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
                captureTile(title: "Licence photo", subtitle: "Both sides",
                            icon: "creditcard.fill",
                            captured: $app.partnerApplication.licenseCaptured)
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
                captureTile(title: "Vehicle registration",
                            subtitle: "Carte grise — matching the plate above",
                            icon: "doc.text.fill",
                            captured: $app.partnerApplication.registrationCaptured)
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

    private func captureTile(title: String, subtitle: String, icon: String,
                             captured: Binding<Bool>) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: captured.wrappedValue ? .light : .medium).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                captured.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: captured.wrappedValue ? "checkmark" : icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(captured.wrappedValue ? GGColor.onAccent : GGColor.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(captured.wrappedValue ? GGColor.white : GGColor.ink(0.08)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                    Text(captured.wrappedValue ? "Captured" : subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(captured.wrappedValue ? GGColor.textSecondary : GGColor.textTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: captured.wrappedValue ? "arrow.counterclockwise" : "camera.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GGColor.textTertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(GGColor.ink(0.05)))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(captured.wrappedValue ? GGColor.ink(0.2) : GGColor.ink(0.08),
                                  lineWidth: captured.wrappedValue ? 1 : 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var submitButton: some View {
        Button {
            app.submitPartnerKYC()
        } label: {
            Text("Submit for review")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(GGColor.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Capsule().fill(GGColor.white))
        }
        .buttonStyle(PressableStyle())
        .disabled(!app.partnerKYCComplete)
        .opacity(app.partnerKYCComplete ? 1 : 0.4)
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
                    Text("Process complete")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(GGColor.textPrimary)
                    Text("You're now a GojoGo \(role.title.lowercased()). Your \(role.service) partner tools are unlocked — go online whenever you're ready to start earning.")
                        .explanatory(15)
                        .foregroundStyle(GGColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                }

                HStack(spacing: 10) {
                    doneBadge(icon: "checkmark.seal.fill", label: "Verified")
                    doneBadge(icon: "lock.shield.fill", label: "Stake held")
                    doneBadge(icon: role.icon, label: role.title)
                }
            }
            .opacity(appear ? 1 : 0)
            Spacer()

            VStack(spacing: 10) {
                Button {
                    app.finishPartnerOnboarding(openDashboard: true)
                } label: {
                    Text("Go to \(role.title) mode")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(GGColor.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Capsule().fill(GGColor.white))
                }
                .buttonStyle(PressableStyle())

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
