import SwiftUI

// MARK: - Your restaurant (Phase 2b · Milestone 6)
//
// The way into the merchant dashboard, and nothing more.
//
// **There is no apply-from-the-app flow** (2026-07-27). Restaurants are created
// in Gojo Admin: the operator fills in the `partner` application, collects the
// KYC papers, and approves it, which provisions the `delivery.merchant`. By the
// time this screen is reachable the restaurant already exists and this user
// already owns it — so the chip only appears for someone who manages one, and
// the sheet has exactly one destination.
//
// The applicant-facing endpoints still exist on the server (see `PartnerStore`);
// if that decision is reversed, the screens to rebuild are the application form,
// a document checklist, and an "in review" state.

// MARK: - Header entry point

/// The chip in the GojoDelivery header, shown only to a restaurant's owner.
struct MerchantHeaderButton: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        if app.showsMerchantEntry {
            Button {
                app.openMerchantPartner()
            } label: {
                HStack(spacing: 7) {
                    if app.isMerchantPartner, app.merchantStorefront?.isOpen == true {
                        Circle().fill(GGColor.white).frame(width: 7, height: 7)
                    } else {
                        Image(systemName: app.merchantChipIcon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(GGColor.textPrimary)
                    }
                    Text(app.merchantChipLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                }
                .padding(.horizontal, 13)
                .frame(height: 36)
                .glassCapsule(tint: Color.black.opacity(0.4), interactive: false, dense: true)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Open your restaurant")
        }
    }
}

// MARK: - The sheet

struct MerchantPartnerView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            // In the layout, not over it: a banner floating across the menu
            // hides the rows the message is usually about.
            if let notice = app.merchantNotice {
                MerchantNoticeBanner(message: notice) { app.dismissMerchantNotice() }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if app.managesRestaurant {
                MerchantDashboardBody()
            } else {
                // Only reachable if the account is unprovisioned behind our
                // back — a restaurant handed to someone else, say. Says so
                // rather than showing an empty dashboard.
                noRestaurant
            }
        }
        .background(GGColor.sheetBG.ignoresSafeArea())
        .animation(.ggOverlay, value: app.merchantNotice)
        .animation(.ggSnappy, value: app.managesRestaurant)
        .task { await app.refreshMerchantPartner() }
    }

    private var noRestaurant: some View {
        VStack(spacing: 10) {
            Image(systemName: "storefront")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(GGColor.textTertiary)
            Text("No restaurant on this account")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)
            Text("Get in touch and we'll set one up for you.")
                .font(.system(size: 13))
                .foregroundStyle(GGColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MerchantNoticeBanner: View {
    let message: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(GGColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(GGColor.textTertiary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glass(cornerRadius: 18, tint: GGColor.ink(0.10), floating: true)
    }
}
