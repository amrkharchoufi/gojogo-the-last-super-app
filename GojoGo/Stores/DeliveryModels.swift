import Foundation

// MARK: - Delivery module DTOs (Phase 2b · Milestone 4)
//
// Mirror the backend `delivery` records. Money is integer cents; the store maps
// it to the `Double` the SwiftUI delivery models were written against.

struct MenuItemDTO: Decodable {
    let id: UUID
    let name: String
    let detail: String
    let priceCents: Int
    let imageUrl: String?
    let popular: Bool
}

struct MenuSectionDTO: Decodable {
    let id: UUID
    let name: String
    let items: [MenuItemDTO]
}

struct MerchantDTO: Decodable {
    let id: UUID
    let name: String
    let cuisine: String
    let rating: Double
    let reviewCount: Int
    let etaMinutes: Int
    let deliveryFeeCents: Int
    let imageUrl: String?
    let promo: String?
    let tags: [String]
    let categories: [String]
    let latitude: Double
    let longitude: Double
    /// Empty in browse results; filled by the detail endpoint.
    let menu: [MenuSectionDTO]
}

struct OrderMerchantDTO: Decodable {
    let id: UUID
    let name: String
    let imageUrl: String?
    let latitude: Double
    let longitude: Double
}

struct CourierDTO: Decodable {
    let name: String
    let vehicle: String
    let rating: Double
    let deliveries: Int
}

struct OrderLineDTO: Decodable {
    let menuItemId: UUID
    let name: String
    let unitPriceCents: Int
    let qty: Int
}

struct DeliveryAddressDTO: Decodable {
    let id: UUID
    let label: String
    let line1: String
    let note: String
    let latitude: Double?
    let longitude: Double?
    let isDefault: Bool
}

/// Where an order went — a copy taken at order time, so editing the saved
/// address later doesn't rewrite the receipt.
struct OrderAddressDTO: Decodable {
    let id: UUID?
    let label: String
    let line1: String
    let note: String
    let latitude: Double?
    let longitude: Double?
}

struct SaveAddressBody: Encodable {
    let label: String
    let line1: String
    let note: String
    let latitude: Double?
    let longitude: Double?
    let makeDefault: Bool
}

/// A placed order. `status`, `etaMinutes` and `courierProgress` are the
/// server's view of fulfilment — the app renders them rather than running its
/// own timer, so two devices (or a reinstall) agree on the same delivery.
struct OrderDTO: Decodable {
    let id: UUID
    let merchant: OrderMerchantDTO
    let status: String
    let etaMinutes: Int
    let courierProgress: Double
    let courier: CourierDTO?
    let lines: [OrderLineDTO]
    let subtotalCents: Int
    let deliveryFeeCents: Int
    let serviceFeeCents: Int
    let totalCents: Int
    let currency: String
    let addressLabel: String
    let address: OrderAddressDTO?
    let note: String
    let rating: Int?
    let placedAt: String
    let statusChangedAt: String
    let etaAt: String
}

/// "Nothing in flight" is a 200 with a null order, not a 404.
struct ActiveOrderDTO: Decodable {
    let order: OrderDTO?
}

struct PlaceOrderLineBody: Encodable {
    let menuItemId: UUID
    let qty: Int
}

struct PlaceOrderBody: Encodable {
    let merchantId: UUID
    let lines: [PlaceOrderLineBody]
    /// A saved address of the caller's. Nil falls back to their default one.
    let addressId: UUID?
    let note: String
}

struct RateOrderBody: Encodable {
    let rating: Int
}
