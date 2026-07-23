import SwiftUI

// MARK: - Economy live wiring (Phase 2b · Milestone 1)
//
// Bridges the marketplace UI (EconomyView / SellListingSheet) onto the deployed
// `economy` module. On connect, live listings replace the SampleData catalog;
// sell + save sync to the backend for server-backed listings. Offline keeps the
// sample catalog (matching how the other verticals degrade).

extension AppState {

    /// Replaces the marketplace catalog with live listings. The newest listing
    /// becomes the featured hero; the rest fill the grid. Falls back to whatever
    /// is cached on failure (empty backend keeps the sample catalog).
    func refreshEconomy() async {
        guard backendConnected else { return }
        do {
            let page = try await EconomyStore.shared.browse()
            guard !page.products.isEmpty else { return }  // empty prod: keep samples
            economyNextBefore = page.nextBefore
            withAnimation(.easeOut(duration: 0.25)) {
                featuredProduct = page.products.first ?? featuredProduct
                products = Array(page.products.dropFirst())
            }
            schedulePersist()
        } catch {
            #if DEBUG
            print("Economy refresh failed: \(error.localizedDescription)")
            #endif
        }
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

    /// Publishes a listing. When connected it hits the backend (uploading any
    /// picked photo first) and prepends the server-backed product; offline it
    /// prepends the local draft. Returns immediately with an optimistic product.
    func createListing(title: String, price: String, category: String, notes: String,
                       imageData: Data? = nil) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        guard backendConnected else {
            products.insert(localListing(title: trimmed, price: price, category: category,
                                         notes: notes), at: 0)
            schedulePersist()
            return
        }

        Task {
            do {
                var imageUrls: [String] = []
                if let imageData {
                    let payload = UIImage(data: imageData)?.jpegData(compressionQuality: 0.9) ?? imageData
                    let url = try await APIClient.shared.uploadMedia(payload, contentType: "image/jpeg")
                    imageUrls = [url]
                }
                let body = CreateListingBody(
                    title: trimmed,
                    priceCents: EconomyStore.parseCents(price),
                    currency: "USD",
                    category: category,
                    condition: "Good",
                    locationLabel: "nearby",
                    description: notes,
                    imageUrls: imageUrls)
                let product = try await EconomyStore.shared.create(body)
                withAnimation { products.insert(product, at: 0) }
                schedulePersist()
            } catch {
                #if DEBUG
                print("Create listing failed: \(error.localizedDescription)")
                #endif
                // Optimistic local fallback so the user still sees their listing.
                products.insert(localListing(title: trimmed, price: price, category: category,
                                             notes: notes), at: 0)
                schedulePersist()
            }
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

    /// Opens a thread parked while the caller finished My World setup.
    func resumePendingSellerConversation() {
        guard let pending = pendingSellerConversation, !needsWorldSetup else { return }
        pendingSellerConversation = nil
        openWorldConversation(pending.id)
        worldDraft = pending.draft
    }

    private func localListing(title: String, price: String, category: String, notes: String) -> Product {
        Product(
            name: title,
            price: price.isEmpty ? "$—" : (price.hasPrefix("$") ? price : "$\(price)"),
            meta: "you · just now",
            gradient: user.avatarGradient,
            category: category,
            seller: user.handle,
            condition: "Like new",
            distance: "0 km",
            description: notes.isEmpty ? "Listed by you on GojoGo Economy." : notes)
    }
}
