import SwiftUI

// MARK: - Business profiles (Phase 2e · Milestone 1)
//
// The vision's universal journey starts here: anyone can create a business
// profile, build an audience with it, and only later turn commerce on. That
// works because a business *is* a profile — same table, same handle space, same
// social graph — so followers, feed, stories and Watch need no business-shaped
// second implementation (ARCHITECTURE §2b decision 1, SPECS §8).
//
// What the app adds on top is one idea: **who you are publishing as**. That
// lives in `ActingIdentity`, is creation-only, and resets to you on relaunch.

/// One business profile the account runs.
struct BusinessIdentity: Identifiable, Equatable {
    let id: UUID
    var handle: String
    var name: String
    var avatarURL: String?
    var category: String
    var bio: String
    /// Earned through a partner (KYC) approval, never bought.
    var verified: Bool
    var phone: String
    var email: String
    var website: String
    var addressLine: String
    var city: String
    var country: String
    /// Free-form for now; the structured hours document lands with the
    /// storefront block contract (Phase 2e M4).
    var openingHours: String

    var addressSummary: String {
        [addressLine, city, country]
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: ", ")
    }

    init(_ dto: BusinessProfileDTO) {
        id = dto.id
        handle = dto.handle
        name = dto.displayName ?? dto.handle
        avatarURL = dto.avatarUrl
        category = dto.category ?? "Business"
        bio = dto.bio ?? ""
        verified = dto.verified
        phone = dto.contactPhone ?? ""
        email = dto.contactEmail ?? ""
        website = dto.websiteUrl ?? ""
        addressLine = dto.addressLine ?? ""
        city = dto.city ?? ""
        country = dto.country ?? ""
        openingHours = dto.openingHours ?? ""
    }
}

extension AppState {

    // MARK: Derived state

    var hasBusinessProfile: Bool { !ownedBusinesses.isEmpty }

    /// The business currently being published as, if any.
    var actingBusiness: BusinessIdentity? {
        guard let actingBusinessID else { return nil }
        return ownedBusinesses.first { $0.id == actingBusinessID }
    }

    /// What the composer and the profile chip read: "you", or the business.
    var publishingAsName: String { actingBusiness?.name ?? user.name }

    var publishingAsHandle: String { actingBusiness?.handle ?? user.handle }

    // MARK: Loading

    /// One GET on connect, and again whenever the sheet opens. Cheap enough to
    /// be the source of truth rather than something the app caches and guesses.
    func refreshBusinessProfiles() async {
        guard backendConnected else { return }
        do {
            let list = try await ProfileStore.shared.myBusinesses()
            ownedBusinesses = list.map(BusinessIdentity.init)
            // A business that's gone (deleted elsewhere) must not stay the
            // identity every new post is published under.
            if let acting = actingBusinessID,
               !ownedBusinesses.contains(where: { $0.id == acting }) {
                stopActingAsBusiness()
            }
        } catch {
            #if DEBUG
            print("Business profiles refresh failed: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: Creating + editing

    /// Creates the business profile and switches to it — creating one and then
    /// posting as yourself is never what was meant.
    @discardableResult
    func createBusinessProfile(name: String, handle: String?, category: String, bio: String,
                               phone: String, email: String, website: String,
                               addressLine: String, city: String, country: String,
                               openingHours: String, avatarData: Data?) async -> Bool {
        guard backendConnected else {
            showBusinessNotice("You're offline — sign in to create a business profile.")
            return false
        }
        businessBusy = true
        defer { businessBusy = false }
        do {
            var avatarURL: String?
            if let avatarData {
                avatarURL = try await APIClient.shared.uploadMedia(avatarData, contentType: "image/jpeg")
            }
            let body = CreateBusinessBody(
                displayName: name.trimmingCharacters(in: .whitespacesAndNewlines),
                handle: blankToNil(handle ?? ""),
                category: blankToNil(category),
                bio: bio,
                avatarUrl: avatarURL,
                contactPhone: phone, contactEmail: email, websiteUrl: blankToNil(website),
                addressLine: addressLine, city: city, country: country,
                latitude: nil, longitude: nil,
                openingHours: blankToNil(openingHours))
            let created = try await ProfileStore.shared.createBusiness(body)
            let identity = BusinessIdentity(created)
            ownedBusinesses.insert(identity, at: 0)
            actAsBusiness(identity.id)
            return true
        } catch {
            showBusinessNotice(message(for: error))
            return false
        }
    }

    @discardableResult
    func updateBusinessProfile(_ id: UUID, name: String, handle: String, category: String,
                               bio: String, phone: String, email: String, website: String,
                               addressLine: String, city: String, country: String,
                               openingHours: String, avatarData: Data?) async -> Bool {
        guard backendConnected else { return false }
        businessBusy = true
        defer { businessBusy = false }
        do {
            var avatarURL: String?
            if let avatarData {
                avatarURL = try await APIClient.shared.uploadMedia(avatarData, contentType: "image/jpeg")
            }
            let body = UpdateBusinessBody(
                displayName: blankToNil(name), handle: blankToNil(handle),
                category: blankToNil(category), bio: bio, avatarUrl: avatarURL,
                contactPhone: phone, contactEmail: email, websiteUrl: website,
                addressLine: addressLine, city: city, country: country,
                latitude: nil, longitude: nil, openingHours: openingHours)
            let updated = try await ProfileStore.shared.updateBusiness(id, body)
            let identity = BusinessIdentity(updated)
            if let i = ownedBusinesses.firstIndex(where: { $0.id == id }) {
                ownedBusinesses[i] = identity
            }
            return true
        } catch {
            showBusinessNotice(message(for: error))
            return false
        }
    }

    // MARK: Acting as

    func actAsBusiness(_ id: UUID) {
        guard ownedBusinesses.contains(where: { $0.id == id }) else { return }
        actingBusinessID = id
        ActingIdentity.shared.businessProfileID = id
    }

    func stopActingAsBusiness() {
        actingBusinessID = nil
        ActingIdentity.shared.businessProfileID = nil
    }

    /// Opens the business page itself — a business is a profile, so this is the
    /// ordinary profile screen, not a business-only one.
    func openBusinessProfile(_ business: BusinessIdentity) {
        showBusinessProfiles = false
        openUserProfile(handle: business.handle, name: business.name,
                        avatarURL: business.avatarURL)
    }

    // MARK: Notices

    func showBusinessNotice(_ text: String) {
        businessNotice = text
        businessNoticeTask?.cancel()
        businessNoticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_600_000_000)
            guard !Task.isCancelled else { return }
            self?.businessNotice = nil
        }
    }

    private func blankToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func message(for error: Error) -> String {
        (error as? APIClient.APIError)?.errorDescription ?? error.localizedDescription
    }
}
