import SwiftUI

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
            await refreshSocial()
            await refreshOwnCounts()
            schedulePersist()
        } catch {
            // Offline or cold backend — keep cached UI; next launch retries.
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
        do {
            let feed = try await SocialStore.shared.fetchFeed()
            var rings = try await SocialStore.shared.fetchStories()
            if !rings.contains(where: \.isYou) {
                rings.insert(Story(name: "You", letter: String((user.name.first ?? "g").uppercased()),
                                   gradient: user.avatarGradient, frames: [], isYou: true), at: 0)
            }
            withAnimation(.easeOut(duration: 0.3)) {
                posts = feed
                stories = rings
                savedPostIDs = Set(feed.filter(\.bookmarked).map(\.id))
            }
            commentsByPost = commentsByPost.filter { !SocialStore.shared.remotePostIds.contains($0.key) }
        } catch {
            #if DEBUG
            print("Feed refresh failed: \(error.localizedDescription)")
            #endif
        }
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
        await AuthSession.shared.store(tokens, email: mail)
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
                commentsByPost[postID] = live.reversed()
                if let i = posts.firstIndex(where: { $0.id == postID }) {
                    posts[i].commentCount = live.count
                }
            }
        }
    }

    func syncNewComment(text: String, postID: UUID, optimisticID: UUID) {
        guard SocialStore.shared.remotePostIds.contains(postID) else { return }
        Task {
            do {
                let real = try await SocialStore.shared.addComment(text, to: postID)
                if var list = commentsByPost[postID],
                   let i = list.firstIndex(where: { $0.id == optimisticID }) {
                    list[i] = real
                    commentsByPost[postID] = list
                }
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
                        if index < slides.count { item.imageData = slides[index].imageData }
                        return item
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

    private func uploadSlide(imageData: Data?, videoURL: String?) async throws
        -> (imageUrl: String?, videoUrl: String?)? {
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
            let url = try await APIClient.shared.uploadMedia(payload, contentType: finalType)
            return (imageUrl: url, videoUrl: nil)
        }
        if let ref = videoURL, !ref.isEmpty {
            if ref.hasPrefix("https://") || ref.hasPrefix("http://") {
                return (imageUrl: nil, videoUrl: ref)
            }
            if let resolved = VideoLibrary.resolve(ref),
               let fileURL = URL(string: resolved), fileURL.isFileURL,
               let data = try? Data(contentsOf: fileURL) {
                let type = fileURL.pathExtension.lowercased() == "mov" ? "video/quicktime" : "video/mp4"
                let url = try await APIClient.shared.uploadMedia(data, contentType: type)
                return (imageUrl: nil, videoUrl: url)
            }
            return nil
        }
        return nil
    }

    func syncNewStory(imageData: Data, localFrameID: UUID) {
        Task {
            do {
                let payload = UIImage(data: imageData)?.jpegData(compressionQuality: 0.9) ?? imageData
                let url = try await APIClient.shared.uploadMedia(payload, contentType: "image/jpeg")
                let frames = try await SocialStore.shared.createStory(frameUrls: [url])
                guard let server = frames.first,
                      let si = stories.firstIndex(where: \.isYou),
                      let fi = stories[si].frames.firstIndex(where: { $0.id == localFrameID })
                else { return }
                stories[si].frames[fi] = StoryFrame(
                    id: server.id, imageURL: server.imageUrl,
                    imageData: imageData, seen: false)
                schedulePersist()
            } catch {
                #if DEBUG
                print("Story sync failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    func syncFrameSeen(frameID: UUID) {
        guard SocialStore.shared.remoteFrameIds.contains(frameID) else { return }
        Task {
            try? await SocialStore.shared.markFrameSeen(frameID)
        }
    }

    // MARK: Profiles

    /// Upgrades an opened profile sheet with live data when the author is real.
    func refreshRemoteProfile(handle: String) {
        guard backendConnected,
              let profileId = SocialStore.shared.profileId(forHandle: handle) else { return }
        Task {
            do {
                let view = try await ProfileStore.shared.view(profileId)
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
                    following: view.following)
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
