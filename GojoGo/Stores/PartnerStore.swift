import Foundation

/// The restaurant an approved partner runs: their storefront and its menu, plus
/// the one read of the partner account the dashboard needs (is it live, and why
/// is it suspended).
///
/// **Creating a restaurant is not here.** Onboarding — the application, the KYC
/// papers, the review — happens in Gojo Admin (2026-07-27). The server still
/// exposes the applicant-facing surface; iOS just doesn't call it. If that
/// decision is ever reversed, the endpoints are `POST /v1/partner/applications`,
/// `POST …/{id}/documents/presign`, `PUT …/{id}/documents` and `POST …/{id}/submit`.
@MainActor
final class PartnerStore {

    static let shared = PartnerStore()

    // MARK: The partner account (read-only from the app)

    /// `nil` when this user isn't a partner at all.
    func me() async throws -> MerchantAccount? {
        let response: MyPartnerResponseDTO =
            try await APIClient.shared.get("/v1/partner/me?kind=RESTAURANT")
        return response.account.map(Self.account)
    }

    // MARK: The restaurant

    func storefront() async throws -> MerchantStorefront {
        let dto: MyMerchantDTO = try await APIClient.shared.get("/v1/delivery/merchants/mine")
        return Self.storefront(dto)
    }

    func updateStorefront(_ body: UpdateMerchantBody) async throws -> MerchantStorefront {
        let dto: MyMerchantDTO = try await APIClient.shared.put("/v1/delivery/merchants/mine", body: body)
        return Self.storefront(dto)
    }

    func setOpen(_ open: Bool) async throws -> MerchantStorefront {
        let dto: MyMerchantDTO = try await APIClient.shared
            .put("/v1/delivery/merchants/mine/open", body: SetOpenBody(open: open))
        return Self.storefront(dto)
    }

    // MARK: The menu
    //
    // Every mutation answers with the whole restaurant, so the editor re-renders
    // from one authoritative response instead of patching its own copy.

    func addSection(named name: String) async throws -> MerchantStorefront {
        let dto: MyMerchantDTO = try await APIClient.shared
            .post("/v1/delivery/merchants/mine/sections", body: MenuSectionBody(name: name))
        return Self.storefront(dto)
    }

    func renameSection(_ sectionID: UUID, to name: String) async throws -> MerchantStorefront {
        let dto: MyMerchantDTO = try await APIClient.shared
            .put("/v1/delivery/merchants/mine/sections/\(sectionID)", body: MenuSectionBody(name: name))
        return Self.storefront(dto)
    }

    func deleteSection(_ sectionID: UUID) async throws -> MerchantStorefront {
        let dto: MyMerchantDTO = try await APIClient.shared
            .deleteReturning("/v1/delivery/merchants/mine/sections/\(sectionID)")
        return Self.storefront(dto)
    }

    func addItem(to sectionID: UUID, _ body: MenuItemBody) async throws -> MerchantStorefront {
        let dto: MyMerchantDTO = try await APIClient.shared
            .post("/v1/delivery/merchants/mine/sections/\(sectionID)/items", body: body)
        return Self.storefront(dto)
    }

    func updateItem(_ itemID: UUID, _ body: MenuItemBody) async throws -> MerchantStorefront {
        let dto: MyMerchantDTO = try await APIClient.shared
            .put("/v1/delivery/merchants/mine/items/\(itemID)", body: body)
        return Self.storefront(dto)
    }

    func deleteItem(_ itemID: UUID) async throws -> MerchantStorefront {
        let dto: MyMerchantDTO = try await APIClient.shared
            .deleteReturning("/v1/delivery/merchants/mine/items/\(itemID)")
        return Self.storefront(dto)
    }

    // MARK: Mapping

    private static func account(_ dto: PartnerAccountDTO) -> MerchantAccount {
        MerchantAccount(
            id: dto.id,
            status: MerchantApplicationStatus(wire: dto.status),
            businessName: dto.businessName,
            category: dto.category ?? "",
            reviewNote: dto.reviewNote,
            merchantID: dto.refId)
    }

    private static func storefront(_ dto: MyMerchantDTO) -> MerchantStorefront {
        MerchantStorefront(
            id: dto.id,
            name: dto.name,
            cuisine: dto.cuisine,
            imageURL: dto.imageUrl,
            promo: dto.promo,
            etaMinutes: dto.etaMinutes,
            deliveryFeeCents: dto.deliveryFeeCents,
            rating: dto.rating,
            reviewCount: dto.reviewCount,
            latitude: dto.latitude,
            longitude: dto.longitude,
            categories: dto.categories,
            tags: dto.tags,
            isOpen: dto.open,
            isSuspended: dto.suspended,
            offersPickup: dto.offersPickup,
            pickupPrepMinutes: dto.pickupPrepMinutes,
            pickupAddress: dto.pickupAddress ?? "",
            menu: dto.menu.map { section in
                MerchantMenuSection(id: section.id, name: section.name,
                    items: section.items.map {
                        MerchantMenuItem(id: $0.id, name: $0.name, detail: $0.detail ?? "",
                                         priceCents: $0.priceCents, imageURL: $0.imageUrl,
                                         isPopular: $0.popular, isAvailable: $0.available)
                    })
            })
    }
}
