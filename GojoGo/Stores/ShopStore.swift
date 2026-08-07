import Foundation

/// The merchant-catalog half of `economy` (Phase 5 M1 + M2): the buyer's
/// browse/checkout/orders, the seller console, digital entitlements and the
/// ownership-transfer workflow.
///
/// Deliberately separate from `EconomyStore`, which owns the C2C listing shelf
/// on the same module's other surface. They share a backend module and almost
/// nothing else: a listing has no variant, no stock and no order behind it.
///
/// Every path here is caller-scoped server-side — `/mine` resolves the shop
/// from the JWT and never from an id in the path — so there is no ownership
/// check for this client to get wrong.
@MainActor
final class ShopStore {

    static let shared = ShopStore()

    // MARK: Buyer — catalog

    func browse(category: String? = nil, sellerId: UUID? = nil,
                before: String? = nil, limit: Int = 24) async throws -> ShopProductPageDTO {
        var path = "/v1/economy/products?limit=\(limit)"
        if let category, category != "All", let enc = Self.query(category) {
            path += "&category=\(enc)"
        }
        if let sellerId { path += "&sellerId=\(sellerId.uuidString)" }
        if let before, let enc = Self.query(before) { path += "&before=\(enc)" }
        return try await APIClient.shared.get(path)
    }

    func product(_ productId: UUID) async throws -> ShopProductDTO {
        try await APIClient.shared.get("/v1/economy/products/\(productId)")
    }

    func reviews(_ productId: UUID, limit: Int = 50) async throws -> [ShopReviewDTO] {
        try await APIClient.shared.get("/v1/economy/products/\(productId)/reviews?limit=\(limit)")
    }

    func review(_ productId: UUID, _ body: ShopReviewBody) async throws -> ShopReviewDTO {
        try await APIClient.shared.post("/v1/economy/products/\(productId)/reviews", body: body)
    }

    // MARK: Buyer — checkout + orders

    func checkout(_ body: ShopCheckoutBody) async throws -> ShopOrderDTO {
        try await APIClient.shared.post("/v1/economy/orders", body: body)
    }

    func myOrders(limit: Int = 50) async throws -> [ShopOrderDTO] {
        try await APIClient.shared.get("/v1/economy/orders?limit=\(limit)")
    }

    func order(_ orderId: UUID) async throws -> ShopOrderDTO {
        try await APIClient.shared.get("/v1/economy/orders/\(orderId)")
    }

    /// "It arrived" — the tap that moves the money out of escrow. There is no
    /// undo behind it, which is why the UI asks first.
    func confirmReceived(_ orderId: UUID) async throws -> ShopOrderDTO {
        try await APIClient.shared.post("/v1/economy/orders/\(orderId)/received")
    }

    func cancelOrder(_ orderId: UUID) async throws -> ShopOrderDTO {
        try await APIClient.shared.post("/v1/economy/orders/\(orderId)/cancel")
    }

    // MARK: Buyer — digital shelf

    func entitlements(limit: Int = 50) async throws -> [ShopEntitlementDTO] {
        try await APIClient.shared.get("/v1/economy/entitlements?limit=\(limit)")
    }

    /// A fresh signed GET, minted for this ask and never stored. Re-issuable
    /// for as long as the entitlement lives, so an expired link is a re-tap
    /// rather than a lost purchase.
    func downloadURL(_ entitlementId: UUID) async throws -> String {
        let response: ShopDownloadDTO = try await APIClient.shared
            .post("/v1/economy/entitlements/\(entitlementId)/download")
        return response.url
    }

    // MARK: Seller console

    func mySeller() async throws -> ShopSellerDTO {
        try await APIClient.shared.get("/v1/economy/sellers/mine")
    }

    func updateSeller(_ body: ShopSellerBody) async throws -> ShopSellerDTO {
        try await APIClient.shared.put("/v1/economy/sellers/mine", body: body)
    }

    func sellerWallet(limit: Int = 50) async throws -> PayeeWalletDTO {
        try await APIClient.shared.get("/v1/economy/sellers/mine/wallet?limit=\(limit)")
    }

    /// A fresh Stripe onboarding link — single-use, so this is a POST meant to
    /// be called again rather than a URL to cache. The bank details it asks for
    /// go to Stripe, never through this app.
    func sellerPayoutOnboardingLink() async throws -> String {
        struct LinkResponse: Decodable { let url: String }
        let response: LinkResponse = try await APIClient.shared
            .post("/v1/economy/sellers/mine/payouts/onboarding-link")
        return response.url
    }

    func sellerPayOut(amountMinor: Int64) async throws -> PayeePayoutDTO {
        try await APIClient.shared.post("/v1/economy/sellers/mine/payouts",
                                        body: PayeePayoutBody(amountMinor: amountMinor))
    }

    /// The seller's own catalog — inactive products included, since this is the
    /// only place they still show up.
    func myProducts(limit: Int = 100) async throws -> [ShopProductDTO] {
        try await APIClient.shared.get("/v1/economy/sellers/mine/products?limit=\(limit)")
    }

    func createProduct(_ body: ShopProductBody) async throws -> ShopProductDTO {
        try await APIClient.shared.post("/v1/economy/sellers/mine/products", body: body)
    }

    func updateProduct(_ productId: UUID, _ body: ShopProductBody) async throws -> ShopProductDTO {
        try await APIClient.shared.put("/v1/economy/sellers/mine/products/\(productId)", body: body)
    }

    func setProductActive(_ productId: UUID, _ active: Bool) async throws -> ShopProductDTO {
        try await APIClient.shared.put(
            "/v1/economy/sellers/mine/products/\(productId)/active?active=\(active)",
            body: NoBody())
    }

    func sellerOrders(status: ShopOrderStatus? = nil, limit: Int = 50) async throws -> [ShopOrderDTO] {
        var path = "/v1/economy/sellers/mine/orders?limit=\(limit)"
        if let status { path += "&status=\(status.rawValue)" }
        return try await APIClient.shared.get(path)
    }

    func ship(_ orderId: UUID, trackingNote: String) async throws -> ShopOrderDTO {
        try await APIClient.shared.post("/v1/economy/sellers/mine/orders/\(orderId)/ship",
                                        body: ShopShipBody(trackingNote: trackingNote))
    }

    func cancelAsSeller(_ orderId: UUID) async throws -> ShopOrderDTO {
        try await APIClient.shared.post("/v1/economy/sellers/mine/orders/\(orderId)/cancel")
    }

    func promotions() async throws -> [ShopPromotionDTO] {
        try await APIClient.shared.get("/v1/economy/sellers/mine/promotions")
    }

    func createPromotion(_ body: ShopPromotionBody) async throws -> ShopPromotionDTO {
        try await APIClient.shared.post("/v1/economy/sellers/mine/promotions", body: body)
    }

    /// Deactivation, not deletion — redemptions reference it forever.
    func deactivatePromotion(_ promotionId: UUID) async throws {
        try await APIClient.shared.delete("/v1/economy/sellers/mine/promotions/\(promotionId)")
    }

    func replyToReview(_ reviewId: UUID, body: String) async throws -> ShopReviewDTO {
        try await APIClient.shared.post("/v1/economy/sellers/mine/reviews/\(reviewId)/reply",
                                        body: ShopReplyBody(body: body))
    }

    // MARK: Seller — digital assets

    /// Presign, PUT the bytes straight to S3, then attach the key. The file
    /// never passes through the backend and the app never holds a readable URL.
    func uploadDigitalAsset(_ data: Data, fileName: String, contentType: String,
                            to productId: UUID, entitlementKind: String = "DOWNLOAD") async throws {
        guard let enc = Self.query(contentType) else {
            throw APIClient.APIError.http(status: -1, message: "Bad content type")
        }
        let upload: ShopUploadDTO = try await APIClient.shared
            .post("/v1/economy/sellers/mine/digital-uploads?contentType=\(enc)")
        try await APIClient.shared.upload(to: upload.uploadUrl, data: data, contentType: contentType)
        try await APIClient.shared.putNoContent(
            "/v1/economy/sellers/mine/products/\(productId)/digital-asset",
            body: ShopDigitalAssetBody(objectKey: upload.objectKey, fileName: fileName,
                                       contentType: contentType, entitlementKind: entitlementKind))
    }

    /// A licence-key product has no file to upload — the key is generated at
    /// capture, so attaching one is a body with no object behind it.
    ///
    /// The kind is `LICENSE`, which is what `EntitlementKind` actually spells.
    /// This read `LICENSE_KEY` — a name invented on this side of the wire — and
    /// the server refused every attach with "Unknown entitlement kind", so a
    /// licence product could be created and never made deliverable.
    func attachLicenseAsset(to productId: UUID) async throws {
        try await APIClient.shared.putNoContent(
            "/v1/economy/sellers/mine/products/\(productId)/digital-asset",
            body: ShopDigitalAssetBody(objectKey: "generated", fileName: "",
                                       contentType: "", entitlementKind: "LICENSE"))
    }

    // MARK: Ownership transfers

    /// Opens (or reuses) the enquiry on a transfer listing. Free — the escrow
    /// comes later, at `pay`.
    func inquire(listingId: UUID) async throws -> TransferDTO {
        try await APIClient.shared.post("/v1/economy/listings/\(listingId)/transfer")
    }

    func transfers(limit: Int = 50) async throws -> [TransferDTO] {
        try await APIClient.shared.get("/v1/economy/transfers?limit=\(limit)")
    }

    func transfer(_ transferId: UUID) async throws -> TransferDTO {
        try await APIClient.shared.get("/v1/economy/transfers/\(transferId)")
    }

    /// The seller names the number. Only they can.
    func acceptTransfer(_ transferId: UUID, priceCents: Int64) async throws -> TransferDTO {
        try await APIClient.shared.post("/v1/economy/transfers/\(transferId)/accept",
                                        body: TransferAcceptBody(priceCents: priceCents))
    }

    func payTransfer(_ transferId: UUID) async throws -> TransferDTO {
        try await APIClient.shared.post("/v1/economy/transfers/\(transferId)/pay")
    }

    func confirmTransferReceived(_ transferId: UUID) async throws -> TransferDTO {
        try await APIClient.shared.post("/v1/economy/transfers/\(transferId)/received")
    }

    func cancelTransfer(_ transferId: UUID, note: String) async throws -> TransferDTO {
        try await APIClient.shared.post("/v1/economy/transfers/\(transferId)/cancel",
                                        body: TransferCancelBody(note: note))
    }

    func transferDocuments(_ transferId: UUID) async throws -> [TransferDocumentDTO] {
        try await APIClient.shared.get("/v1/economy/transfers/\(transferId)/documents")
    }

    func uploadTransferDocument(_ transferId: UUID, data: Data, label: String,
                                contentType: String) async throws -> TransferDocumentDTO {
        guard let enc = Self.query(contentType) else {
            throw APIClient.APIError.http(status: -1, message: "Bad content type")
        }
        let upload: ShopUploadDTO = try await APIClient.shared
            .post("/v1/economy/transfers/\(transferId)/documents/presign?contentType=\(enc)")
        try await APIClient.shared.upload(to: upload.uploadUrl, data: data, contentType: contentType)
        return try await APIClient.shared.post(
            "/v1/economy/transfers/\(transferId)/documents",
            body: TransferDocumentBody(objectKey: upload.objectKey, label: label))
    }

    // MARK: Helpers

    private static func query(_ value: String) -> String? {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
    }
}

/// For the handful of endpoints whose arguments are all in the query string:
/// `APIClient.put` always writes a body, and `{}` is the one that says nothing.
/// Shared with `ServicesStore`, which has the same two toggles.
struct NoBody: Encodable {}
