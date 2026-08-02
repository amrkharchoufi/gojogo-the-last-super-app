import SwiftUI
import UIKit
import UserNotifications

enum EmailAuthStep {
    case credentials, code
}

// MARK: - Live backend wiring (Milestone 4)
//
// AppState stays the façade the views observe; these methods bridge its
// social/profile/auth surface onto the deployed API via SocialStore /
// ProfileStore / AuthSession. Sample content in other domains is untouched.

extension AppState {

    // MARK: Session bootstrap

    func connectBackend() async {
        do {
            _ = try await ProfileStore.shared.establishSession()
            let profile = try await ProfileStore.shared.fetchMe()
            SocialStore.shared.myProfileId = profile.id
            SocialStore.shared.myHandle = profile.handle
            applyProfile(profile)
            backendConnected = true
            // Before anything that draws a price. One small GET, cached for the
            // launch, and a failure is silent — a screen with no rate shows the
            // platform amount, which is the one that is actually true.
            await ExchangeRates.shared.loadIfNeeded()
            // Messaging fetch is next — start shimmer early so My World never
            // flashes the empty state while connectMessaging is still running.
            if worldConversations.isEmpty {
                worldConversationsLoading = true
            }
            // Before the feed, not after: the mapper needs to know which author
            // ids are also this user (their business profiles) or the first
            // screenful renders a Follow chip on their own shop's posts.
            await refreshBusinessProfiles()
            await refreshSocial()
            await refreshWatch()
            await refreshOwnCounts()
            await refreshEconomy()
            await refreshDelivery()
            await refreshMerchantPartner()
            // Roles and the dispatch registry, so "Become a driver" opens the
            // dashboard for somebody who already is one — and so a suspension
            // decided while they were away takes effect on this launch rather
            // than the next reinstall.
            await refreshRoles()
            await refreshDispatch()
            // A trip survives the app being killed — the server is the one that
            // knows whether a car is on its way, so the screen is restored from
            // it rather than from anything cached here.
            await refreshRide()
            if ride != nil { startRidePolling() }
            await connectMessaging()
            await refreshNotifications()
            enablePushNotifications()
            schedulePersist()
        } catch {
            // Offline or cold backend — stop shimmer so My World can show empty/demo.
            worldConversationsLoading = false
            worldConversationsLoaded = true
            #if DEBUG
            print("Backend connect failed: \(error.localizedDescription)")
            #endif
        }
    }

    func applyProfile(_ profile: ProfileDTO) {
        user.handle = profile.handle
        user.name = profile.displayName ?? profile.handle
        user.bio = profile.bio.isEmpty ? user.bio : profile.bio
        user.category = profile.category
        user.avatarURL = profile.avatarUrl ?? user.avatarURL
        if let year = profile.birthYear { user.birthYear = year }
        if !profile.interests.isEmpty { user.interests = profile.interests.sorted() }
        if let mail = profile.email { email = mail }
    }

    /// Replaces the home feed + story rail with live content.
    func refreshSocial() async {
        if posts.isEmpty { feedLoading = true }
        defer { feedLoading = false }
        do {
            let page = try await SocialStore.shared.fetchFeed()
            var rings = try await StoriesStore.shared.fetchRings()
            if !rings.contains(where: \.isYou) {
                rings.insert(Story(name: "You", letter: String((user.name.first ?? "g").uppercased()),
                                   gradient: user.avatarGradient, frames: [], isYou: true), at: 0)
            }
            feedNextBefore = page.nextBefore
            withAnimation(.easeOut(duration: 0.3)) {
                posts = page.posts
                stories = rings
                savedPostIDs = Set(page.posts.filter(\.bookmarked).map(\.id))
            }
            // Decode the first screenful of media up front so the feed is "already
            // there" the instant the user looks — no per-cell spinner on refresh.
            prefetchFeedImages(from: 0, count: 8)
            commentsByPost = commentsByPost.filter { !SocialStore.shared.remotePostIds.contains($0.key) }
        } catch {
            #if DEBUG
            print("Feed refresh failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Pull-to-refresh on Home.
    func pullRefreshFeed() async {
        guard backendConnected else { return }
        await refreshSocial()
        await refreshOwnCounts()
    }

    /// Fetches the next feed page when the given post is near the bottom, and
    /// warms the images just below the current scroll position. Triggers 6 rows
    /// out (not 3) so the next page is in hand before the user reaches it — the
    /// scroll should never hit a "loading more" gap.
    func loadMoreFeedIfNeeded(after postID: UUID) {
        // Look-ahead: decode the next few posts' media before they scroll on.
        prefetchAround(postID: postID)
        guard backendConnected,
              !feedLoadingMore,
              let cursor = feedNextBefore,
              let index = posts.firstIndex(where: { $0.id == postID }),
              index >= posts.count - 6 else { return }
        feedLoadingMore = true
        Task {
            defer { feedLoadingMore = false }
            do {
                let page = try await SocialStore.shared.fetchFeed(before: cursor)
                feedNextBefore = page.nextBefore
                let existing = Set(posts.map(\.id))
                let fresh = page.posts.filter { !existing.contains($0.id) }
                let startIndex = posts.count
                posts.append(contentsOf: fresh)
                // Warm the whole freshly-arrived page immediately.
                prefetchFeedImages(from: startIndex, count: fresh.count)
            } catch {
                #if DEBUG
                print("Feed page load failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    // MARK: Image prefetch

    /// Warms `ImageCache` for a window of posts (post media + author avatar).
    func prefetchFeedImages(from index: Int, count: Int) {
        guard count > 0, index < posts.count else { return }
        let end = min(index + count, posts.count)
        guard index < end else { return }
        let urls: [URL] = posts[index..<end].flatMap { post -> [URL] in
            var out: [URL] = []
            if let s = post.imageURL, let u = URL(string: s) { out.append(u) }
            if let a = post.avatarURL, let u = URL(string: a) { out.append(u) }
            return out
        }
        guard !urls.isEmpty else { return }
        Task { await ImagePrefetcher.shared.prefetch(urls) }
    }

    /// Look-ahead warm for the ~6 posts after the one currently appearing.
    func prefetchAround(postID: UUID) {
        guard let idx = posts.firstIndex(where: { $0.id == postID }) else { return }
        prefetchFeedImages(from: idx + 1, count: 6)
    }

    /// Requests notification permission and registers for APNs. The device
    /// token is sent to the backend once it arrives (see PushRegistrar); an
    /// incoming/tapped push refreshes the activity feed.
    func enablePushNotifications() {
        PushRegistrar.shared.onPushReceived = { [weak self] in
            Task { @MainActor in await self?.refreshNotifications() }
        }
        PushRegistrar.shared.markAuthenticated()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            Task { @MainActor in UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    /// Replaces the activity feed with live notifications (follows / likes /
    /// comments). Falls back to whatever's cached on failure.
    func refreshNotifications() async {
        guard backendConnected else { return }
        do {
            let page = try await NotificationStore.shared.fetch()
            withAnimation(.easeOut(duration: 0.25)) { notifications = page.items }
        } catch {
            #if DEBUG
            print("Notifications refresh failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Uploads a new profile photo and saves it to the backend + local user.
    func syncProfileAvatar(_ data: Data) {
        guard backendConnected else { return }
        Task {
            do {
                let payload = UIImage(data: data)?.jpegData(compressionQuality: 0.9) ?? data
                let url = try await APIClient.shared.uploadMedia(payload, contentType: "image/jpeg")
                user.avatarURL = url
                if profileUser?.isOwn == true { profileUser?.avatarURL = url }
                let body = UpdateProfileBody(displayName: nil, handle: nil, bio: nil,
                                             category: nil, birthYear: nil, avatarUrl: url, interests: nil)
                if let profile = try? await ProfileStore.shared.updateMe(body) { applyProfile(profile) }
                schedulePersist()
            } catch {
                #if DEBUG
                print("Avatar upload failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    /// Changes the username against the backend (2-month cooldown enforced
    /// server-side) and updates local state. Throws the backend message on
    /// failure (429 cooldown / 409 taken) so the caller can surface it.
    func changeUsername(to handle: String) async throws {
        guard backendConnected else {
            // Offline / prototype: apply locally so the UI still reflects the change.
            user.handle = handle
            if profileUser?.isOwn == true { profileUser = .own(from: user, posts: myPosts.count) }
            schedulePersist()
            return
        }
        let profile = try await ProfileStore.shared.changeHandle(handle)
        applyProfile(profile)
        SocialStore.shared.myHandle = profile.handle
        if profileUser?.isOwn == true { profileUser = .own(from: user, posts: myPosts.count) }
        schedulePersist()
    }

    func refreshOwnCounts() async {
        guard let myId = SocialStore.shared.myProfileId,
              let view = try? await ProfileStore.shared.view(myId) else { return }
        user.followerCount = view.followerCount
        user.followingCount = view.followingCount
        user.postCount = view.postCount
    }

    // MARK: Email auth flow (EmailSignUpView)

    func submitEmailCredentials() {
        guard !authBusy else { return }
        let mail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let password = authPassword
        guard mail.contains("@"), password.count >= 8 else {
            authError = "Enter your email and a password of 8+ characters."
            return
        }
        authBusy = true
        authError = nil
        let cognito = CognitoAuthClient()
        Task {
            defer { authBusy = false }
            do {
                try await completeSignIn(email: mail, password: password)
            } catch let error as CognitoAuthClient.AuthError {
                switch error.cognitoType {
                case "UserNotFoundException":
                    await startSignUp(email: mail, password: password)
                case "UserNotConfirmedException":
                    try? await cognito.resendConfirmationCode(email: mail)
                    withAnimation(.easeInOut(duration: 0.3)) { emailAuthStep = .code }
                default:
                    authError = error.localizedDescription
                }
            } catch {
                authError = error.localizedDescription
            }
        }
    }

    private func startSignUp(email mail: String, password: String) async {
        do {
            try await CognitoAuthClient().signUp(email: mail, password: password)
            withAnimation(.easeInOut(duration: 0.3)) { emailAuthStep = .code }
        } catch {
            authError = error.localizedDescription
        }
    }

    func submitConfirmationCode() {
        guard !authBusy else { return }
        let mail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let code = authCode.trimmingCharacters(in: .whitespaces)
        guard code.count >= 4 else {
            authError = "Enter the code from your email."
            return
        }
        authBusy = true
        authError = nil
        Task {
            defer { authBusy = false }
            do {
                try await CognitoAuthClient().confirmSignUp(email: mail, code: code)
                try await completeSignIn(email: mail, password: authPassword)
            } catch {
                authError = error.localizedDescription
            }
        }
    }

    func resendAuthCode() {
        let mail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        Task {
            try? await CognitoAuthClient().resendConfirmationCode(email: mail)
        }
    }

    private func completeSignIn(email mail: String, password: String) async throws {
        let tokens = try await CognitoAuthClient().signIn(email: mail, password: password)
        await applyTokens(tokens, email: mail)
    }

    /// Shared tail for every sign-in path (email, Google, Apple): persist the
    /// Cognito token set, establish the profile session, and route to
    /// onboarding (new account) or the app (returning account).
    func applyTokens(_ tokens: CognitoAuthClient.Tokens, email mail: String) async {
        await AuthSession.shared.store(tokens, email: mail)
        do {
            let session = try await ProfileStore.shared.establishSession()
            authPassword = ""
            authCode = ""
            authError = nil
            let isNewAccount = session.displayName == nil
            if isNewAccount {
                pendingOnboarding = true
                user.handle = session.handle ?? ""
                withAnimation(.easeInOut(duration: 0.4)) {
                    phase = .onboarding
                    onboardingStep = 1
                }
            } else {
                withAnimation(.easeInOut(duration: 0.4)) { phase = .app }
            }
            await connectBackend()
        } catch {
            authError = error.localizedDescription
        }
    }

    // MARK: Social sign-in (WelcomeView)

    /// Google via Cognito Hosted UI (ASWebAuthenticationSession + PKCE).
    func signInWithGoogle() {
        guard !authBusy else { return }
        authBusy = true
        authError = nil
        Task {
            defer { authBusy = false }
            do {
                let tokens = try await GoogleSignInClient().signIn()
                let mail = JWT.email(fromIDToken: tokens.idToken) ?? ""
                await applyTokens(tokens, email: mail)
            } catch SocialAuthError.cancelled {
                // User dismissed the sheet — no error UI.
            } catch {
                authError = error.localizedDescription
                #if DEBUG
                print("Google sign-in failed: \(error)")
                #endif
            }
        }
    }

    /// Native Sign in with Apple → backend token exchange.
    func signInWithApple() {
        guard !authBusy else { return }
        authBusy = true
        authError = nil
        Task {
            defer { authBusy = false }
            do {
                let result = try await AppleSignInClient().signIn()
                guard let tokenData = result.credential.identityToken,
                      let identityToken = String(data: tokenData, encoding: .utf8) else {
                    authError = "Apple sign-in returned no identity token."
                    return
                }
                let name = [result.credential.fullName?.givenName,
                            result.credential.fullName?.familyName]
                    .compactMap { $0 }
                    .joined(separator: " ")
                let tokens = try await BackendAuth.exchangeApple(
                    AppleAuthBody(identityToken: identityToken,
                                  rawNonce: result.rawNonce,
                                  fullName: name.isEmpty ? nil : name))
                let mail = result.credential.email ?? JWT.email(fromIDToken: tokens.idToken) ?? ""
                await applyTokens(tokens, email: mail)
            } catch SocialAuthError.cancelled {
                // User dismissed the sheet — no error UI.
            } catch {
                authError = error.localizedDescription
                #if DEBUG
                print("Apple sign-in failed: \(error)")
                #endif
            }
        }
    }

    /// Pushes the onboarding choices (name, handle, birth year, interests) to the profile.
    func syncOnboardingProfile() {
        guard AuthSession.shared.isAuthenticated else { return }
        let name = user.name
        let handle = user.handle
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9_.]", with: "", options: .regularExpression)
        let year = user.birthYear
        let picked = user.interests
        Task {
            do {
                let body = UpdateProfileBody(
                    displayName: name.isEmpty ? nil : name,
                    handle: handle.count >= 2 ? handle : nil,
                    birthYear: year,
                    interests: picked)
                let profile = try await ProfileStore.shared.updateMe(body)
                applyProfile(profile)
                SocialStore.shared.myHandle = profile.handle
            } catch {
                // Likely a taken handle — adopt whatever the server has.
                if let profile = try? await ProfileStore.shared.fetchMe() {
                    applyProfile(profile)
                    SocialStore.shared.myHandle = profile.handle
                }
            }
            schedulePersist()
        }
    }

    // MARK: Post mutations

    func syncLike(postID: UUID, liked: Bool) {
        guard SocialStore.shared.remotePostIds.contains(postID) else { return }
        Task {
            do {
                if liked { try await SocialStore.shared.like(postID) }
                else { try await SocialStore.shared.unlike(postID) }
            } catch {
                #if DEBUG
                print("Like sync failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    /// Deletes a post server-side. A purely local post (sample content, or one
    /// whose create is still in flight) just stays deleted on the device.
    func syncDeletePost(_ postID: UUID, restoring post: Post, at index: Int) {
        guard SocialStore.shared.remotePostIds.contains(postID) else { return }
        Task {
            do {
                try await SocialStore.shared.deletePost(postID)
                await refreshOwnCounts()
            } catch {
                // Put it back rather than leave the user believing it's gone.
                let insertAt = min(index, posts.count)
                posts.insert(post, at: insertAt)
                user.postCount += 1
                if profileUser?.isOwn == true { profileUser?.postCount += 1 }
                schedulePersist()
                #if DEBUG
                print("Post delete failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    func syncBookmark(postID: UUID, bookmarked: Bool) {
        guard SocialStore.shared.remotePostIds.contains(postID) else { return }
        Task {
            do {
                if bookmarked { try await SocialStore.shared.bookmark(postID) }
                else { try await SocialStore.shared.unbookmark(postID) }
            } catch {
                #if DEBUG
                print("Bookmark sync failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    func syncFollow(postID: UUID, following: Bool) {
        guard let authorId = SocialStore.shared.authorIdByPost[postID] else { return }
        syncFollow(profileId: authorId, following: following)
    }

    func syncProfileFollow(handle: String, following: Bool) {
        guard let profileId = SocialStore.shared.profileId(forHandle: handle) else { return }
        syncFollow(profileId: profileId, following: following)
    }

    private func syncFollow(profileId: UUID, following: Bool) {
        guard backendConnected else { return }
        Task {
            do {
                if following { try await SocialStore.shared.follow(profileId) }
                else { try await SocialStore.shared.unfollow(profileId) }
            } catch {
                #if DEBUG
                print("Follow sync failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    // MARK: Comments

    func refreshComments(for postID: UUID) {
        Task {
            if let live = try? await SocialStore.shared.comments(for: postID) {
                // The server reads a thread top-down; the sheet reads newest
                // first. Only the top level flips — replies stay chronological,
                // which is the only order a conversation makes sense in.
                commentsByPost[postID] = live.reversed()
                applyCommentCount(AppState.totalComments(live), to: postID)
            }
        }
    }

    /// Pulls a thread's full reply list — the "view all N replies" path, for a
    /// thread the comments payload only previewed.
    func refreshReplies(postID: UUID, commentID: UUID) {
        guard SocialStore.shared.remoteCommentIds.contains(commentID) else { return }
        Task {
            guard let live = try? await SocialStore.shared.replies(for: commentID),
                  var list = commentsByPost[postID],
                  let i = list.firstIndex(where: { $0.id == commentID }) else { return }
            list[i].replies = live
            list[i].replyCount = max(list[i].replyCount, live.count)
            commentsByPost[postID] = list
            applyCommentCount(AppState.totalComments(list), to: postID)
        }
    }

    func syncNewComment(text: String, postID: UUID, parentID: UUID?, optimisticID: UUID) {
        guard SocialStore.shared.remotePostIds.contains(postID) else { return }
        // A reply to a comment the server has never heard of (sample content, or
        // one whose own write is still in flight) would be rejected — post it as
        // a top-level comment rather than losing it.
        let parent = parentID.flatMap {
            SocialStore.shared.remoteCommentIds.contains($0) ? $0 : nil
        }
        Task {
            do {
                let real = try await SocialStore.shared.addComment(text, to: postID,
                                                                   parentID: parent)
                guard var list = commentsByPost[postID] else { return }
                if let i = list.firstIndex(where: { $0.id == optimisticID }) {
                    list[i] = real
                } else if let root = real.parentID ?? parent,
                          let i = list.firstIndex(where: { $0.id == root }),
                          let r = list[i].replies.firstIndex(where: { $0.id == optimisticID }) {
                    list[i].replies[r] = real
                } else {
                    return
                }
                commentsByPost[postID] = list
            } catch {
                #if DEBUG
                print("Comment sync failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    func syncCommentLike(commentID: UUID, liked: Bool) {
        guard SocialStore.shared.remoteCommentIds.contains(commentID) else { return }
        Task {
            do {
                if liked { try await SocialStore.shared.likeComment(commentID) }
                else { try await SocialStore.shared.unlikeComment(commentID) }
            } catch {
                #if DEBUG
                print("Comment like sync failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    // MARK: Publishing

    func syncPublishPost(localID: UUID, text: String?, imageData: Data?,
                         videoURL: String?, slides: [PostMediaItem]) {
        Task {
            do {
                var uploaded: [(imageUrl: String?, videoUrl: String?)] = []
                if slides.isEmpty {
                    if let url = try await uploadSlide(imageData: imageData, videoURL: videoURL) {
                        uploaded.append(url)
                    }
                } else {
                    for slide in slides {
                        if let url = try await uploadSlide(imageData: slide.imageData,
                                                          videoURL: slide.videoURL) {
                            uploaded.append(url)
                        }
                    }
                }
                let hasMedia = !uploaded.isEmpty
                let server = try await SocialStore.shared.createPost(
                    text: text, slides: uploaded, imageAspect: hasMedia ? 1.25 : 1.0)
                if let i = posts.firstIndex(where: { $0.id == localID }) {
                    // Keep local image bytes for instant rendering; identity moves to the server post.
                    var merged = server
                    merged.imageData = imageData ?? slides.first?.imageData
                    merged.mediaItems = server.mediaItems.enumerated().map { index, item in
                        var item = item
                        if index < slides.count {
                            item.imageData = slides[index].imageData
                            // Keep the local playable ref if the server omitted video.
                            if (item.videoURL == nil || item.videoURL?.isEmpty == true),
                               let local = slides[index].videoURL, !local.isEmpty {
                                item.videoURL = local
                            }
                        }
                        return item
                    }
                    if (merged.videoURL == nil || merged.videoURL?.isEmpty == true),
                       let local = videoURL ?? slides.first(where: \.isVideo)?.videoURL,
                       !local.isEmpty {
                        merged.videoURL = local
                    }
                    posts[i] = merged
                }
                schedulePersist()
            } catch {
                #if DEBUG
                print("Post publish sync failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    /// Uploads a carousel slide. Video slides carry a poster (`imageData`) plus
    /// the movie (`videoURL`) — both must go up, otherwise the post comes back
    /// looking like a still photo.
    private func uploadSlide(imageData: Data?, videoURL: String?) async throws
        -> (imageUrl: String?, videoUrl: String?)? {
        var imageUrl: String? = nil
        var videoUrl: String? = nil

        if let ref = videoURL, !ref.isEmpty {
            if ref.hasPrefix("https://") || ref.hasPrefix("http://") {
                videoUrl = ref
            } else if let resolved = VideoLibrary.resolve(ref),
                      let fileURL = URL(string: resolved), fileURL.isFileURL,
                      let data = try? Data(contentsOf: fileURL) {
                let type = fileURL.pathExtension.lowercased() == "mov"
                    ? "video/quicktime" : "video/mp4"
                videoUrl = try await APIClient.shared.uploadMedia(data, contentType: type)
            }
        }

        if let data = imageData {
            let type = APIClient.imageContentType(for: data)
            let payload: Data
            if type == "image/jpeg" || type == "image/png" || type == "image/gif" {
                payload = data
            } else if let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.9) {
                payload = jpeg
            } else {
                payload = data
            }
            let finalType = payload == data ? type : "image/jpeg"
            imageUrl = try await APIClient.shared.uploadMedia(payload, contentType: finalType)
        }

        if imageUrl == nil && videoUrl == nil { return nil }
        return (imageUrl: imageUrl, videoUrl: videoUrl)
    }

    func syncFrameSeen(frameID: UUID) {
        guard StoriesStore.shared.isLive(frameID) else { return }
        Task {
            try? await StoriesStore.shared.markSeen(frameID)
        }
    }

    // MARK: Profiles

    /// Upgrades an opened profile sheet with live data when the author is real.
    func refreshRemoteProfile(handle: String) {
        guard backendConnected else { return }
        Task {
            do {
                let view: ProfileViewDTO
                if let profileId = SocialStore.shared.profileId(forHandle: handle) {
                    view = try await ProfileStore.shared.view(profileId)
                } else {
                    // Unknown locally — resolve by handle (404s for sample-data authors).
                    view = try await ProfileStore.shared.view(handle: handle)
                }
                let profileId = view.id
                SocialStore.shared.registerProfile(id: profileId, handle: view.handle)
                // Real follower count — the "subscribers" line on their videos reads this.
                followerCountByHandle[view.handle.lowercased()] = view.followerCount
                guard showProfile, profileUser?.handle.lowercased() == handle.lowercased() else { return }
                profileUser = ProfileUser(
                    name: view.name,
                    handle: view.handle,
                    avatarURL: view.avatarUrl,
                    avatarGradient: SocialStore.gradient(for: view.handle),
                    bio: view.bio,
                    category: view.category,
                    postCount: view.postCount,
                    followerCount: view.followerCount,
                    followingCount: view.followingCount,
                    isOwn: view.isOwn,
                    following: view.following,
                    isBusiness: view.kind == "BUSINESS",
                    verified: view.verified ?? false,
                    isBusinessOwner: view.isOwner ?? false,
                    business: view.business.map {
                        BusinessContact(phone: $0.contactPhone ?? "",
                                        email: $0.contactEmail ?? "",
                                        website: $0.websiteUrl ?? "",
                                        addressLine: $0.addressLine ?? "",
                                        city: $0.city ?? "",
                                        country: $0.country ?? "",
                                        openingHours: $0.openingHours ?? "")
                    })
                let authorPosts = try await ProfileStore.shared.posts(of: profileId)
                let mapped = authorPosts.map { SocialStore.shared.map($0) }
                for post in mapped where !posts.contains(where: { $0.id == post.id }) {
                    posts.append(post)
                }
            } catch {
                #if DEBUG
                print("Profile refresh failed: \(error.localizedDescription)")
                #endif
            }
        }
    }
}
