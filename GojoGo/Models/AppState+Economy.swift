import SwiftUI

// MARK: - Economy live wiring (Phase 2b · Milestone 1)
//
// Bridges the marketplace UI (EconomyView / SellListingSheet) onto the deployed
// `economy` module. On connect, live listings replace the SampleData catalog;
// sell + save sync to the backend for server-backed listings. Offline keeps the
// sample catalog (matching how the other verticals degrade).

extension AppState {

    /// Replaces the marketplace catalog with live listings. The newest listing
    /// becomes the featured hero; the rest fill the grid. A failed call keeps
    /// whatever is cached — a request that didn't come back says nothing about
    /// what's for sale — but a call that *did* come back is adopted whole.
    func refreshEconomy() async {
        guard backendConnected else { return }
        do {
            let page = try await EconomyStore.shared.browse()
            economyNextBefore = page.nextBefore
            adoptBrowsePage(page.products)
        } catch {
            #if DEBUG
            print("Economy refresh failed: \(error.localizedDescription)")
            #endif
        }
        // Browse can't see the seller's paused or sold items, so the shelf is
        // fetched separately — and it's what puts the count on the chrome chip.
        await refreshSellerListings()
        // A transfer moves when the other party acts, so the gesture that means
        // "show me what changed" has to cover them too. Leaving them out meant
        // pulling to refresh on a stale enquiry redrew everything except it.
        await refreshTransfers()
    }

    /// Settles the catalog on what browse just served, and drops what it didn't.
    ///
    /// This used to run only when the page came back non-empty ("empty prod:
    /// keep samples", from when there was a sample catalog to keep — there
    /// isn't any more, `SampleData.products` is empty and the screen has a real
    /// empty state). What that guard actually did was make an empty marketplace
    /// the one case where nothing could ever leave the cached catalog: the last
    /// listing being deleted froze the previous page on screen for good, and no
    /// refresh, relaunch, or reinstall of the account's data could clear it.
    /// That's how a deleted listing kept its detail page — hero card, price,
    /// "Message" button and all — on one device and no other.
    ///
    /// So: an answer of "nothing for sale" is an answer, and it replaces the
    /// catalog like any other. Cards browse can't be expected to return are
    /// kept explicitly (`isKeptFromBrowse`) rather than by leaving stale cards
    /// in place and hoping. This also subsumes the narrower sweep that cleared
    /// the seller's own unpublished drafts: a card the server has never vouched
    /// for isn't the user's to keep, whoever it claims to be selling.
    private func adoptBrowsePage(_ served: [Product]) {
        let servedIDs = Set(served.map(\.id))
        let kept = products.filter { isKeptFromBrowse($0, servedIDs: servedIDs) }
        withAnimation(.easeOut(duration: 0.25)) {
            featuredProduct = served.first ?? SampleData.featuredProduct
            products = Array(served.dropFirst()) + kept
        }
        // A seeded card that browse now serves is part of the catalog proper,
        // and belongs in the cache with the rest of it.
        economySeededListingIDs.subtract(servedIDs)
        economySeededListingIDs.formIntersection(Set(products.map(\.id)))
        schedulePersist()
        // The dropped card can be the one on screen right now — deleted by its
        // seller while a buyer reads it. Saying so beats leaving them on a
        // detail page offering to message about it.
        if let open = browsingProduct, liveProduct(id: open.id) == nil {
            closeProduct()
            showEconomyNotice("That listing isn't available any more.")
        }
    }

    /// Whether a catalog card survives a browse page that didn't include it.
    /// Only two do, and both are listings the server vouched for this session:
    /// a paused or sold item seeded from the seller's own shelf (browse filters
    /// those out by design), and whatever detail sheet is open right now, so a
    /// refresh landing mid-read doesn't empty the screen under the reader.
    private func isKeptFromBrowse(_ product: Product, servedIDs: Set<UUID>) -> Bool {
        guard !servedIDs.contains(product.id),
              EconomyStore.shared.isRemote(product.id) else { return false }
        return product.status != .active || browsingProduct?.id == product.id
    }

    /// Loads the next page of listings when the given product nears the bottom.
    func loadMoreEconomyIfNeeded(after productID: UUID) {
        guard backendConnected,
              !economyLoadingMore,
              let cursor = economyNextBefore,
              let index = products.firstIndex(where: { $0.id == productID }),
              index >= products.count - 3 else { return }
        economyLoadingMore = true
        Task {
            defer { economyLoadingMore = false }
            do {
                let page = try await EconomyStore.shared.browse(before: cursor)
                economyNextBefore = page.nextBefore
                let existing = Set(products.map(\.id)) .union([featuredProduct.id])
                products.append(contentsOf: page.products.filter { !existing.contains($0.id) })
            } catch {
                #if DEBUG
                print("Economy page load failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    /// Publishes a listing: uploads any picked photo, then creates it on the
    /// backend and prepends the server-backed product. Returns `nil` once the
    /// listing exists, or the sentence to show the seller when it doesn't.
    ///
    /// Nothing is prepended on failure. This used to fall back to a local draft
    /// "so the user still sees their listing" — but a listing only this device
    /// knows about is one no buyer can see, that the seller's own shelf doesn't
    /// list, and that no amount of refreshing explains. It is the same class of
    /// lie as the stand-in listing `openListingContext` stopped building: the
    /// seller asked to publish, and a card that looks published is a worse
    /// answer than being told it didn't go up.
    func createListing(title: String, price: String, category: String, notes: String,
                       imageData: Data? = nil,
                       transfer: Bool = false, vinSerial: String = "") async -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "Give the listing a title." }

        // Also false for the length of the first connect, so this is "not yet"
        // as often as it is "offline" — either way there's nowhere to publish to.
        guard backendConnected else {
            return "You're not connected — reconnect and publish again."
        }

        do {
            var imageUrls: [String] = []
            if let imageData {
                let payload = UIImage(data: imageData)?.jpegData(compressionQuality: 0.9) ?? imageData
                let url = try await APIClient.shared.uploadMedia(payload, contentType: "image/jpeg")
                imageUrls = [url]
            }
            let body = ListingBody(
                title: trimmed,
                priceCents: EconomyStore.parseCents(price),
                currency: "USD",
                category: category,
                condition: "Good",
                locationLabel: "nearby",
                description: notes,
                imageUrls: imageUrls,
                // What a listing *is* is decided here and never again: an
                // escrow points at it, and a kind that could be edited later
                // would be a live deal changing shape underneath itself.
                kind: transfer ? "OWNERSHIP_TRANSFER" : "SALE",
                vinSerial: transfer ? vinSerial.trimmingCharacters(in: .whitespaces) : "")
            let product = try await EconomyStore.shared.create(body)
            withAnimation { products.insert(product, at: 0) }
            schedulePersist()
            // Keep "Your listings" honest if it's the next thing they open.
            await refreshSellerListings()
            return nil
        } catch {
            return Self.listingMessage(from: error, fallback: "Couldn't publish that listing.")
        }
    }

    /// Syncs a save/unsave to the backend for server-backed listings.
    func syncListingSave(_ id: UUID, saved: Bool) {
        guard EconomyStore.shared.remoteListingIds.contains(id) else { return }
        Task {
            do {
                if saved { try await EconomyStore.shared.save(id) }
                else { try await EconomyStore.shared.unsave(id) }
            } catch {
                #if DEBUG
                print("Listing save sync failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    // MARK: The seller's own shelf (Phase 2b · M5)
    //
    // Selling used to be one-way: publish and hope. "Your listings" is where a
    // seller edits what they posted, takes it down, marks it sold, or deletes
    // it — and sees what the marketplace did with it (saves, views).

    /// True when the seller hub has anything to manage. Offline listings are
    /// on-device drafts with no server id, so there's nothing to manage there.
    var canManageListings: Bool { backendConnected }

    /// The hub refreshes itself on appear, so this only presents it.
    func openSellerHub() {
        showSellerHub = true
    }

    func closeSellerHub() {
        showSellerHub = false
        editingListing = nil
    }

    /// "Manage listing" from the seller's own detail view: closes the detail and
    /// opens the shelf on that listing's edit form. The shelf may not be loaded
    /// yet (deep-linked from a chat card), so it falls back to the plain shelf
    /// and lets `refreshSellerListings` fill it in.
    func manageListing(_ listingID: UUID) {
        closeProduct()
        editingListing = sellerListings.first(where: { $0.id == listingID })
        showSellerHub = true
    }

    /// "View in marketplace" from the shelf. The listing may be paused or sold —
    /// browse can't see those, so seed the catalog from the shelf copy rather
    /// than hoping `liveProduct` finds it.
    func openListingFromShelf(_ listing: SellerListing) {
        closeSellerHub()
        if let existing = liveProduct(id: listing.id) {
            openProduct(existing)
            return
        }
        let product = Product(
            id: listing.id,
            name: listing.title,
            price: listing.priceLabel,
            meta: "\(user.handle) · \(listing.ageLabel)",
            gradient: user.avatarGradient,
            imageURL: listing.imageURL,
            category: listing.category,
            seller: user.handle,
            condition: listing.condition,
            distance: listing.locationLabel,
            description: listing.description,
            status: listing.status)
        // ProductDetailView resolves through `liveProduct(id:)`, so the catalog
        // has to know about it. Browse filters on status, so a paused or sold
        // listing seeded here doesn't reappear in the grid.
        seedCatalog(product)
        openProduct(product)
    }

    /// Pulls the shelf and the totals together — a status change moves both, and
    /// two half-updated numbers on screen look like a bug.
    func refreshSellerListings() async {
        guard backendConnected else { return }
        sellerListingsLoading = sellerListings.isEmpty
        defer { sellerListingsLoading = false }
        do {
            let listings = try await EconomyStore.shared.mine()
            // Totals are a nicety on top of the shelf, so a failure there must
            // not cost the shelf — the tiles fall back to counting what loaded.
            let totals = try? await EconomyStore.shared.stats()
            withAnimation(.easeOut(duration: 0.2)) {
                sellerListings = listings
                if let totals { sellerStats = totals }
            }
        } catch {
            #if DEBUG
            print("Seller listings refresh failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Saves the seller's edits, then reconciles every surface the listing shows
    /// on: the shelf, the browse catalog, and an open detail sheet.
    func saveListingEdits(_ listingID: UUID, _ body: ListingBody) {
        Task {
            do {
                let dto = try await EconomyStore.shared.update(listingID, body)
                applyListingUpdate(dto)
                editingListing = nil
            } catch {
                showEconomyNotice(Self.listingMessage(
                    from: error, fallback: "Couldn't save those changes."))
                // The form just proved itself stale (deleted from another
                // device, say) — reconcile rather than leave it editing a ghost.
                await refreshSellerListings()
            }
        }
    }

    /// Pause, relist, or mark sold. Moves optimistically — the segment the row
    /// lives in is the whole point of the tap — and reverts on failure.
    func setListingStatus(_ listingID: UUID, _ status: ListingStatus) {
        guard let index = sellerListings.firstIndex(where: { $0.id == listingID }) else { return }
        let previous = sellerListings[index].status
        guard previous != status else { return }
        withAnimation(.ggSnappy) { sellerListings[index].status = status }
        applyCatalogStatus(listingID, status)
        Task {
            do {
                let dto = try await EconomyStore.shared.setStatus(listingID, status)
                applyListingUpdate(dto)
                sellerStats = try? await EconomyStore.shared.stats()
            } catch {
                if let index = sellerListings.firstIndex(where: { $0.id == listingID }) {
                    withAnimation(.ggSnappy) { sellerListings[index].status = previous }
                }
                applyCatalogStatus(listingID, previous)
                showEconomyNotice(Self.listingMessage(
                    from: error, fallback: "Couldn't update that listing."))
                await refreshSellerListings()
            }
        }
    }

    /// Deletes a listing for good. Unlike "sold", this leaves no trace — so the
    /// UI asks first (`SellerListingsView` owns the confirmation).
    func deleteListing(_ listingID: UUID) {
        withAnimation(.ggSnappy) {
            sellerListings.removeAll { $0.id == listingID }
            products.removeAll { $0.id == listingID }
            // The hero is a catalog card like any other, and a deleted listing
            // that keeps the front page is the loudest place to leave one.
            if featuredProduct.id == listingID { featuredProduct = SampleData.featuredProduct }
        }
        economySeededListingIDs.remove(listingID)
        if browsingProduct?.id == listingID { browsingProduct = nil }
        if editingListing?.id == listingID { editingListing = nil }
        Task {
            do {
                try await EconomyStore.shared.delete(listingID)
            } catch {
                showEconomyNotice(Self.listingMessage(
                    from: error, fallback: "Couldn't delete that listing."))
            }
            await refreshSellerListings()
            await refreshEconomy()
        }
    }

    /// Folds the server's version of a listing into the shelf, the catalog and
    /// any open detail sheet, so no surface keeps showing the pre-edit copy.
    private func applyListingUpdate(_ dto: ListingDTO) {
        let listing = EconomyStore.sellerListing(dto)
        let product = EconomyStore.shared.map(dto)
        withAnimation(.easeOut(duration: 0.2)) {
            if let index = sellerListings.firstIndex(where: { $0.id == dto.id }) {
                sellerListings[index] = listing
            } else {
                sellerListings.insert(listing, at: 0)
            }
            // A listing that's no longer live has to leave browse; one that came
            // back has to return, and browse order is by recency.
            if listing.status == .active {
                if featuredProduct.id == dto.id {
                    featuredProduct = product
                } else if let index = products.firstIndex(where: { $0.id == dto.id }) {
                    products[index] = product
                } else {
                    products.insert(product, at: 0)
                }
            } else {
                products.removeAll { $0.id == dto.id }
                if featuredProduct.id == dto.id { featuredProduct = product }
            }
            if browsingProduct?.id == dto.id { browsingProduct = product }
        }
        schedulePersist()
    }

    /// The optimistic half of a status change: keep browse in step before the
    /// server confirms, so a paused listing doesn't linger in the grid.
    private func applyCatalogStatus(_ listingID: UUID, _ status: ListingStatus) {
        if featuredProduct.id == listingID { featuredProduct.status = status }
        if let index = products.firstIndex(where: { $0.id == listingID }) {
            if status == .active {
                products[index].status = status
            } else {
                products.remove(at: index)
            }
        }
        if browsingProduct?.id == listingID { browsingProduct?.status = status }
    }

    // MARK: Notices

    /// Surfaces a short message over Economy — the marketplace screens have no
    /// other way to admit that an edit or a relist didn't take.
    func showEconomyNotice(_ message: String) {
        economyNoticeTask?.cancel()
        withAnimation(.ggSnappy) { economyNotice = message }
        economyNoticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.ggSnappy) { self?.economyNotice = nil }
        }
    }

    func dismissEconomyNotice() {
        economyNoticeTask?.cancel()
        withAnimation(.ggSnappy) { economyNotice = nil }
    }

    /// Like `AppState.message(from:fallback:)`, but never echoes a 404 body. A
    /// missing route or a deleted listing produces framework text ("No static
    /// resource v1/economy/…") that means nothing to a seller — the caller's
    /// own sentence is the better thing to show.
    static func listingMessage(from error: Error, fallback: String) -> String {
        if case APIClient.APIError.http(404, _) = error { return fallback }
        return message(from: error, fallback: fallback)
    }

    // MARK: Seller chat (Phase 2b · M2)

    /// True when "Message seller" can open a real thread — a server-backed
    /// listing that isn't the caller's own, with a live session behind it.
    func canMessageSeller(_ product: Product) -> Bool {
        backendConnected
            && EconomyStore.shared.isRemote(product.id)
            && !EconomyStore.shared.isOwn(product.id)
    }

    /// Asks the backend for the buyer↔seller thread, then hands the user over to
    /// My World with the opener prefilled. Nothing is sent on their behalf: the
    /// message is a draft they can edit or discard, so browsing a listing never
    /// leaves the seller an empty thread. Falls back to the local demo chat if
    /// the call fails, so the button is never dead.
    func openLiveSellerChat(for product: Product) {
        Task {
            do {
                let chat = try await EconomyStore.shared.startChat(product.id)
                // The thread may be brand new — pull it before opening it.
                await refreshWorldConversations()
                enterSellerConversation(chat.conversationId, draft: chat.suggestedMessage)
            } catch {
                #if DEBUG
                print("Seller chat failed: \(error.localizedDescription)")
                #endif
                openLocalSellerChat(for: product)
            }
        }
    }

    /// Leaves the marketplace and lands in the thread. When My World hasn't been
    /// set up yet the id is parked: the setup gate takes over, and the thread
    /// opens by itself once the phone is verified.
    private func enterSellerConversation(_ id: UUID, draft: String) {
        browsingProduct = nil
        messagingProduct = nil
        enterMyWorld()
        guard !needsWorldSetup else {
            pendingSellerConversation = (id, draft)
            return
        }
        openWorldConversation(id)
        worldDraft = draft
    }

    /// Opens the listing a thread's context card points at. The listing may not
    /// be in the loaded catalog page (the seller's own item, or a rotated browse
    /// page), so fetch it and seed the catalog before presenting the detail —
    /// `ProductDetailView` resolves through `liveProduct(id:)`.
    ///
    /// A failure says so. It used to build a stand-in `Product` out of the card
    /// and open *that*, on the theory that a dead tap is worse than a thin one —
    /// but the card is a snapshot the seller can delete out from under, so what
    /// that actually rendered was a deleted item, at its old price, on a detail
    /// screen offering to buy it. An invented listing is the same class of lie
    /// as the invented contacts this app stopped fabricating in Phase 2f.
    func openListingContext(_ context: WorldListingContext) {
        guard context.kind == "listing", let id = context.listingID else { return }
        if let existing = liveProduct(id: id) {
            openProduct(existing)
            return
        }
        Task {
            do {
                let product = try await EconomyStore.shared.get(id)
                seedCatalog(product)
                openProduct(product)
            } catch {
                showWorldNotice("This listing isn't available any more.")
            }
        }
    }

    /// Opens a listing by id — the route a search hit takes, where the catalog
    /// page in memory has probably never contained it. Same shape as
    /// `openListingContext`: fetch, seed, open, and say so when it has gone.
    func openListing(id: UUID) {
        if let existing = liveProduct(id: id) {
            openProduct(existing)
            return
        }
        Task {
            do {
                let product = try await EconomyStore.shared.get(id)
                seedCatalog(product)
                openProduct(product)
            } catch {
                showEconomyNotice("That listing isn't available any more.")
            }
        }
    }

    /// Inserts a fetched listing into the catalog (idempotent) so `liveProduct`
    /// can resolve it for the detail sheet without disturbing browse order.
    ///
    /// Marked as seeded, which keeps it out of the cached catalog on disk: what
    /// arrives here was fetched to be opened once, and a card that outlives the
    /// session it was opened in outlives the listing behind it.
    private func seedCatalog(_ product: Product) {
        guard featuredProduct.id != product.id,
              !products.contains(where: { $0.id == product.id }) else { return }
        products.append(product)
        economySeededListingIDs.insert(product.id)
    }

    /// Opens a thread parked while the caller finished My World setup.
    func resumePendingSellerConversation() {
        guard let pending = pendingSellerConversation, !needsWorldSetup else { return }
        pendingSellerConversation = nil
        openWorldConversation(pending.id)
        worldDraft = pending.draft
    }

}
