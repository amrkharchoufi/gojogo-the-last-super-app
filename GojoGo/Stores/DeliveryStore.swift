import SwiftUI

/// Delivery-module API surface (restaurant catalog, orders, fulfilment state)
/// plus DTO→UI mapping. Server UUIDs are reused as the `DeliveryRestaurant` /
/// `DeliveryMenuItem` ids, so a cart line can be sent back by id as-is.
@MainActor
final class DeliveryStore {

    static let shared = DeliveryStore()

    /// Restaurants that came from the server — AppState uses this to decide
    /// whether checkout places a real order or runs the local demo.
    private(set) var remoteMerchantIds: Set<UUID> = []
    /// Menus already fetched (browse returns restaurants without them).
    private var menuCache: [UUID: [DeliveryMenuSection]] = [:]

    func reset() {
        remoteMerchantIds = []
        menuCache = [:]
    }

    func isRemote(_ merchantId: UUID) -> Bool { remoteMerchantIds.contains(merchantId) }

    // MARK: Catalog

    func merchants(category: String? = nil, query: String? = nil, limit: Int = 30) async throws
        -> [DeliveryRestaurant] {
        var path = "/v1/delivery/merchants?limit=\(limit)"
        if let category, category != "All",
           let enc = category.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&category=\(enc)"
        }
        if let query, !query.isEmpty,
           let enc = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&q=\(enc)"
        }
        let dtos: [MerchantDTO] = try await APIClient.shared.get(path)
        for dto in dtos { remoteMerchantIds.insert(dto.id) }
        return dtos.map(map)
    }

    /// Restaurant detail — the only response that carries the menu.
    func merchant(_ merchantId: UUID) async throws -> DeliveryRestaurant {
        let dto: MerchantDTO = try await APIClient.shared.get("/v1/delivery/merchants/\(merchantId)")
        remoteMerchantIds.insert(dto.id)
        let restaurant = map(dto)
        menuCache[dto.id] = restaurant.menu
        return restaurant
    }

    func cachedMenu(_ merchantId: UUID) -> [DeliveryMenuSection]? { menuCache[merchantId] }

    // MARK: Orders

    /// Prices a basket without placing it. The app never adds an order up
    /// itself — fees, discounts and what the wallet can cover are all the
    /// server's answer, and this is how the checkout screen learns them.
    func quote(merchantId: UUID, lines: [DeliveryCartLine],
               promotionCode: String?, tipCents: Int) async throws -> QuoteDTO {
        let body = QuoteBody(
            merchantId: merchantId,
            lines: lines.map { PlaceOrderLineBody(menuItemId: $0.item.id, qty: $0.qty) },
            promotionCode: promotionCode?.isEmpty == false ? promotionCode : nil,
            tipCents: tipCents)
        return try await APIClient.shared.post("/v1/delivery/orders/quote", body: body)
    }

    func placeOrder(merchantId: UUID, lines: [DeliveryCartLine],
                    addressId: UUID?, note: String,
                    promotionCode: String? = nil, tipCents: Int = 0) async throws -> OrderDTO {
        let body = PlaceOrderBody(
            merchantId: merchantId,
            lines: lines.map { PlaceOrderLineBody(menuItemId: $0.item.id, qty: $0.qty) },
            addressId: addressId,
            note: note,
            promotionCode: promotionCode?.isEmpty == false ? promotionCode : nil,
            tipCents: tipCents)
        return try await APIClient.shared.post("/v1/delivery/orders", body: body)
    }

    /// A tip after the food arrived. 100% of it goes to whoever delivered it.
    func tip(_ orderId: UUID, cents: Int) async throws -> OrderDTO {
        try await APIClient.shared.post("/v1/delivery/orders/\(orderId)/tip",
                                        body: TipBody(tipCents: cents))
    }

    func promotions(_ merchantId: UUID) async throws -> [DeliveryPromotionDTO] {
        try await APIClient.shared.get("/v1/delivery/merchants/\(merchantId)/promotions")
    }

    // MARK: The owner's money

    func merchantWallet() async throws -> MerchantWalletDTO {
        try await APIClient.shared.get("/v1/delivery/merchants/mine/wallet")
    }

    func payOut(amountMinor: Int) async throws -> PayoutDTO {
        try await APIClient.shared.post("/v1/delivery/merchants/mine/payouts",
                                        body: PayoutBody(amountMinor: amountMinor))
    }

    /// A fresh Stripe onboarding link — single-use, so this is a POST that is
    /// meant to be called again rather than a URL to cache.
    func payoutOnboardingLink() async throws -> String {
        struct LinkResponse: Decodable { let url: String }
        let response: LinkResponse = try await APIClient.shared
            .post("/v1/delivery/merchants/mine/payouts/onboarding-link")
        return response.url
    }

    // MARK: Saved addresses

    func addresses() async throws -> [DeliveryAddress] {
        let dtos: [DeliveryAddressDTO] = try await APIClient.shared.get("/v1/delivery/addresses")
        return dtos.map(map)
    }

    func createAddress(_ body: SaveAddressBody) async throws -> DeliveryAddress {
        let dto: DeliveryAddressDTO = try await APIClient.shared.post("/v1/delivery/addresses",
                                                                      body: body)
        return map(dto)
    }

    func updateAddress(_ addressId: UUID, _ body: SaveAddressBody) async throws -> DeliveryAddress {
        let dto: DeliveryAddressDTO = try await APIClient.shared
            .put("/v1/delivery/addresses/\(addressId)", body: body)
        return map(dto)
    }

    func makeDefaultAddress(_ addressId: UUID) async throws {
        try await APIClient.shared.post("/v1/delivery/addresses/\(addressId)/default")
    }

    func deleteAddress(_ addressId: UUID) async throws {
        try await APIClient.shared.delete("/v1/delivery/addresses/\(addressId)")
    }

    func map(_ dto: DeliveryAddressDTO) -> DeliveryAddress {
        DeliveryAddress(id: dto.id, label: dto.label, line1: dto.line1, note: dto.note,
                        latitude: dto.latitude, longitude: dto.longitude, isDefault: dto.isDefault)
    }

    func activeOrder() async throws -> OrderDTO? {
        let response: ActiveOrderDTO = try await APIClient.shared.get("/v1/delivery/orders/active")
        return response.order
    }

    /// One order by id — how the tracking screen polls, since `/active` stops
    /// returning an order the moment it's delivered.
    func order(_ orderId: UUID) async throws -> OrderDTO {
        try await APIClient.shared.get("/v1/delivery/orders/\(orderId)")
    }

    func history(limit: Int = 20) async throws -> [OrderDTO] {
        try await APIClient.shared.get("/v1/delivery/orders?limit=\(limit)")
    }

    func cancel(_ orderId: UUID) async throws -> OrderDTO {
        try await APIClient.shared.post("/v1/delivery/orders/\(orderId)/cancel")
    }

    func rate(_ orderId: UUID, stars: Int) async throws -> OrderDTO {
        try await APIClient.shared.post("/v1/delivery/orders/\(orderId)/rate",
                                        body: RateOrderBody(rating: stars))
    }

    // MARK: Mapping

    func map(_ dto: MerchantDTO) -> DeliveryRestaurant {
        DeliveryRestaurant(
            id: dto.id,
            name: dto.name,
            cuisine: dto.cuisine,
            rating: dto.rating,
            reviews: Self.reviewsLabel(dto.reviewCount),
            etaMinutes: dto.etaMinutes,
            feeLabel: Self.feeLabel(cents: dto.deliveryFeeCents),
            feeCents: dto.deliveryFeeCents,
            imageURL: dto.imageUrl,
            tags: dto.tags,
            promo: dto.promo,
            categories: dto.categories,
            menu: dto.menu.map { section in
                DeliveryMenuSection(id: section.id, name: section.name,
                                    items: section.items.map { item in
                                        DeliveryMenuItem(id: item.id,
                                                         name: item.name,
                                                         detail: item.detail,
                                                         price: Double(item.priceCents) / 100,
                                                         imageURL: item.imageUrl,
                                                         popular: item.popular)
                                    })
            },
            storefront: StorefrontBlock.page(dto.storefront),
            latitude: dto.latitude,
            longitude: dto.longitude)
    }

    /// The server's fulfilment state → the enum the tracking screen renders.
    /// A cancelled order has no live state at all, hence nil.
    static func status(_ wire: String) -> DeliveryOrderStatus? {
        switch wire {
        case "CONFIRMED":             return .confirmed
        case "PREPARING":             return .preparing
        case "COURIER_TO_RESTAURANT": return .courierToRestaurant
        case "DELIVERING":            return .delivering
        case "DELIVERED":             return .delivered
        default:                      return nil   // CANCELLED
        }
    }

    static func courier(_ dto: CourierDTO) -> DeliveryCourier {
        DeliveryCourier(name: dto.name, rating: dto.rating,
                        deliveries: dto.deliveries, vehicle: dto.vehicle)
    }

    static func money(cents: Int) -> String {
        String(format: "$%.2f", Double(cents) / 100)
    }

    /// "2× Double Smash, 1× Rosemary Fries"
    static func summary(_ lines: [OrderLineDTO]) -> String {
        lines.map { "\($0.qty)× \($0.name)" }.joined(separator: ", ")
    }

    static func feeLabel(cents: Int) -> String {
        cents == 0 ? "Free" : money(cents: cents)
    }

    private static func reviewsLabel(_ count: Int) -> String {
        count >= 1000 ? String(format: "%.1fk+", Double(count) / 1000) : "\(count)+"
    }
}
