import SwiftUI

/// Reporting a problem with a delivered order (Phase 4 M6).
///
/// The screen behind the only route this system has ever had for money to come
/// back after delivery. Everything on it is shaped by that: the claim is items
/// and quantities rather than an amount (the server prices it off the order's
/// own lines — a claim the client priced is a claim the client can inflate), the
/// photos go to a private prefix under keys the server minted, and the outcome
/// is somebody's decision rather than a rule.
///
/// Once something is reported the sheet stops being a form and becomes the
/// answer, because "what happened to my report" is the question people come
/// back with.
struct DeliveryProblemSheet: View {
    @EnvironmentObject var app: AppState
    let order: OrderDTO

    @State private var reason: DisputeReasonChoice = .missingItems
    @State private var note: String = ""
    @State private var qtyByItem: [UUID: Int] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                if let reported = app.deliveryDispute {
                    resolution(reported)
                } else {
                    form
                }
            }
            if app.deliveryDispute == nil { submit }
        }
        .background(GGColor.sheetBG.ignoresSafeArea())
        .task { await app.loadDeliveryDispute(order.id) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(app.deliveryDispute == nil ? "What went wrong?" : "Your report")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)
            Text(order.merchant.name)
                .font(.system(size: 13))
                .foregroundStyle(GGColor.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    // MARK: Filing one

    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 8) {
                ForEach(DisputeReasonChoice.allCases) { choice in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.ggSnappy) {
                            reason = choice
                            // The items picked for "something was missing" are
                            // not an answer to "it never arrived", so they go
                            // rather than sitting there invisibly.
                            if !choice.wantsItems { qtyByItem = [:] }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: reason == choice
                                  ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 16))
                                .foregroundStyle(reason == choice
                                                 ? GGColor.textPrimary : GGColor.textTertiary)
                            Text(choice.label)
                                .font(.system(size: 14, weight: reason == choice
                                              ? .semibold : .regular))
                                .foregroundStyle(GGColor.textPrimary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .glass(cornerRadius: 14, fillOpacity: reason == choice ? 0.08 : 0.03,
                               borderOpacity: 0.08)
                    }
                    .buttonStyle(PressableStyle())
                }
            }

            // Only for the reasons it is an answer to. Asking which items are
            // missing from a bag that was never delivered is the app not
            // listening.
            if reason.wantsItems && !order.lines.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("WHICH ITEMS")
                        .font(.ggMono(10, .semibold))
                        .tracking(0.8)
                        .foregroundStyle(GGColor.textTertiary)
                    ForEach(order.lines, id: \.menuItemId) { line in
                        itemRow(line)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("WHAT HAPPENED")
                    .font(.ggMono(10, .semibold))
                    .tracking(0.8)
                    .foregroundStyle(GGColor.textTertiary)
                TextField("Tell us in your own words", text: $note, axis: .vertical)
                    .lineLimit(3...6)
                    .font(.system(size: 14))
                    .foregroundStyle(GGColor.textPrimary)
                    .padding(12)
                    .glass(cornerRadius: 14, fillOpacity: 0.04, borderOpacity: 0.08)
            }

            Text("Someone will look at this and decide. If we refund it, the money goes "
                 + "back to your GoJo Wallet.")
                .font(.system(size: 11))
                .foregroundStyle(GGColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private func itemRow(_ line: OrderLineDTO) -> some View {
        let picked = qtyByItem[line.menuItemId] ?? 0
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(GGColor.textPrimary)
                    .lineLimit(1)
                Text("\(line.qty) ordered")
                    .font(.system(size: 11))
                    .foregroundStyle(GGColor.textTertiary)
            }
            Spacer(minLength: 4)
            // Capped at what was actually ordered. The server clamps it too —
            // somebody reporting three missing drinks on an order of two has
            // made a mistake worth correcting rather than a request worth
            // failing — but a stepper that lets you go past it is the app
            // inviting the mistake.
            HStack(spacing: 12) {
                stepper("minus", enabled: picked > 0) {
                    qtyByItem[line.menuItemId] = max(0, picked - 1)
                }
                Text("\(picked)")
                    .font(.ggMono(14, .semibold))
                    .foregroundStyle(picked > 0 ? GGColor.textPrimary : GGColor.textTertiary)
                    .frame(minWidth: 18)
                stepper("plus", enabled: picked < line.qty) {
                    qtyByItem[line.menuItemId] = min(line.qty, picked + 1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glass(cornerRadius: 14, fillOpacity: 0.03, borderOpacity: 0.06)
    }

    private func stepper(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(enabled ? GGColor.textPrimary : GGColor.textTertiary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(GGColor.ink(0.08)))
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
    }

    private var submit: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            app.reportDeliveryProblem(order.id, reason: reason, note: note,
                                      items: qtyByItem,
                                      subOrderID: order.kitchens.count == 1
                                          ? order.kitchens.first?.id : nil)
        } label: {
            Text("Send report")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(GGColor.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Capsule().fill(GGColor.white))
        }
        .buttonStyle(PressableStyle())
        .disabled(app.deliveryDisputeBusy || !canSubmit)
        .opacity(app.deliveryDisputeBusy || !canSubmit ? 0.45 : 1)
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    /// Something has to be said. A report with no note and no items is a report
    /// nobody can act on, and sending it would only produce a rejection.
    private var canSubmit: Bool {
        !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || qtyByItem.values.contains(where: { $0 > 0 })
    }

    // MARK: What came back

    private func resolution(_ reported: DisputeDTO) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: reported.isOpen ? "clock.fill"
                      : (reported.wasRefunded ? "checkmark.circle.fill" : "xmark.circle.fill"))
                    .font(.system(size: 18))
                    .foregroundStyle(GGColor.textPrimary)
                Text(reported.summary)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(cornerRadius: 16, fillOpacity: 0.05, borderOpacity: 0.08)

            if !reported.note.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("YOU SAID")
                        .font(.ggMono(10, .semibold))
                        .tracking(0.8)
                        .foregroundStyle(GGColor.textTertiary)
                    Text(reported.note)
                        .font(.system(size: 13))
                        .foregroundStyle(GGColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !reported.items.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(reported.items) { item in
                        Text("\(item.qty)× \(item.name)")
                            .font(.system(size: 13))
                            .foregroundStyle(GGColor.textSecondary)
                    }
                }
            }

            // A rejection carries its reason, which is the whole of what stops
            // "no" being indistinguishable from nobody looking.
            if !reported.isOpen && !reported.wasRefunded && !reported.resolutionNote.isEmpty {
                Text(reported.resolutionNote)
                    .font(.system(size: 13))
                    .foregroundStyle(GGColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }
}
