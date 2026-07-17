import SwiftUI

enum SampleData {

    static let g1 = [Color(hex: "26303F"), Color(hex: "141821")]
    static let g2 = [Color(hex: "3d3546"), Color(hex: "191420")]
    static let g3 = [Color(hex: "2d4038"), Color(hex: "131c17")]
    static let g4 = [Color(hex: "40352c"), Color(hex: "1c1712")]
    static let g5 = [Color(hex: "203040"), Color(hex: "101820")]
    static let gBlue = [Color(hex: "182030"), Color(hex: "0B0E14")]
    static let gViolet = [Color(hex: "20182a"), Color(hex: "100b16")]

    /// Bundled sample photos (Assets.xcassets) — use as `imageURL` asset names.
    static let mediaBatman = "SampleBatman"
    static let mediaLighthouse = "SampleLighthouse"
    static let mediaPorscheDesert = "SamplePorscheDesert"
    static let mediaPorscheDubai = "SamplePorscheDubai"
    static let mediaBMWM4 = "SampleBMWM4"
    static let mediaCosmicFace = "SampleCosmicFace"
    static let mediaSpidey = "SampleSpidey"
    static let mediaPilotCat = "SamplePilotCat"
    static let mediaCockpitCat = "SampleCockpitCat"
    static let mediaCatsDuo = "SampleCatsDuo"

    static let allSampleMedia: [String] = [
        mediaBatman, mediaLighthouse, mediaPorscheDesert, mediaPorscheDubai,
        mediaBMWM4, mediaCosmicFace, mediaSpidey, mediaPilotCat,
        mediaCockpitCat, mediaCatsDuo,
    ]

    // MARK: Stories — several people have multiple frames
    static let stories: [Story] = [
        Story(name: "You", letter: "J", gradient: g1, isYou: true),
        Story(name: "marta", letter: "M", gradient: g2, frames: [
            StoryFrame(imageURL: mediaBatman),
            StoryFrame(imageURL: mediaLighthouse),
            StoryFrame(imageURL: mediaCosmicFace),
        ]),
        Story(name: "kal.eb", letter: "K", gradient: g3, frames: [
            StoryFrame(imageURL: mediaPorscheDesert),
            StoryFrame(imageURL: mediaPorscheDubai),
        ]),
        Story(name: "sena", letter: "S", gradient: g4, frames: [
            StoryFrame(imageURL: mediaBMWM4, seen: true),
        ]),
        Story(name: "dani", letter: "D", gradient: g5, frames: [
            StoryFrame(imageURL: mediaSpidey),
            StoryFrame(imageURL: mediaPilotCat),
            StoryFrame(imageURL: mediaCockpitCat),
            StoryFrame(imageURL: mediaCatsDuo),
        ]),
        Story(name: "omar", letter: "O", gradient: gBlue, frames: [
            StoryFrame(imageURL: mediaLighthouse),
        ]),
        Story(name: "lea", letter: "L", gradient: gViolet, frames: [
            StoryFrame(imageURL: mediaBatman),
            StoryFrame(imageURL: mediaSpidey),
        ]),
        Story(name: "theo", letter: "T", gradient: g3, frames: [
            StoryFrame(imageURL: mediaPorscheDubai, seen: true),
        ]),
        Story(name: "nia", letter: "N", gradient: g2, frames: [
            StoryFrame(imageURL: mediaCosmicFace),
            StoryFrame(imageURL: mediaLighthouse),
        ]),
        Story(name: "rex", letter: "R", gradient: g4, frames: [
            StoryFrame(imageURL: mediaPilotCat),
        ]),
        Story(name: "ava", letter: "A", gradient: g5, frames: [
            StoryFrame(imageURL: mediaCockpitCat, seen: true),
        ]),
        Story(name: "juin", letter: "J", gradient: gBlue, frames: [
            StoryFrame(imageURL: mediaCatsDuo),
            StoryFrame(imageURL: mediaBMWM4),
            StoryFrame(imageURL: mediaPorscheDesert),
        ]),
        Story(name: "mira", letter: "M", gradient: g1, frames: [
            StoryFrame(imageURL: mediaBatman),
            StoryFrame(imageURL: mediaPorscheDubai),
        ]),
        Story(name: "kofi", letter: "K", gradient: g5, frames: [
            StoryFrame(imageURL: mediaSpidey),
        ]),
        Story(name: "elle", letter: "E", gradient: gViolet, frames: [
            StoryFrame(imageURL: mediaLighthouse),
            StoryFrame(imageURL: mediaCosmicFace),
            StoryFrame(imageURL: mediaBMWM4),
        ]),
    ]

    // MARK: Posts
    static let posts: [Post] = [
        Post(author: "marta.st", meta: "channel · 2h",
             avatarGradient: g2,
             avatarURL: mediaPilotCat,
             imageURL: mediaBatman,
             videoURL: clip1,
             imageAspect: 1.25, text: "Morning light in the field — dog insisted on co-starring.",
             likeCount: 248, commentCount: 3),
        Post(author: "kal.eb", meta: "channel · 4h",
             avatarGradient: g3,
             avatarURL: mediaPorscheDesert,
             text: "Shipped the first prototype of the drone mapper today. Three months of weekends. Worth it.",
             likeCount: 512, commentCount: 2),
        Post(author: "sena.films", meta: "channel · 6h",
             avatarGradient: g4,
             avatarURL: mediaBMWM4,
             imageURL: mediaPorscheDesert,
             videoURL: clip2,
             mediaItems: [
                PostMediaItem(imageURL: mediaPorscheDesert, videoURL: clip2),
                PostMediaItem(imageURL: mediaPorscheDubai, videoURL: clip5),
                PostMediaItem(imageURL: mediaBMWM4, videoURL: clip6),
             ],
             imageAspect: 1.25,
             text: "Golden hour on the last day of the shoot.",
             showFollow: true, likeCount: 1840, commentCount: 4),
        Post(author: "nia.studio", meta: "channel · 9h",
             avatarGradient: g5,
             avatarURL: mediaLighthouse,
             imageURL: mediaLighthouse,
             videoURL: clip3,
             imageAspect: 1.25,
             text: "Clay still drying. Patience is the whole craft.",
             showFollow: true, likeCount: 926, commentCount: 2),
        Post(author: "omar.labs", meta: "channel · 12h",
             avatarGradient: gBlue,
             avatarURL: mediaCosmicFace,
             text: "Night market tip: follow the steam, not the neon.",
             likeCount: 301, commentCount: 1),
        Post(author: "lea.style", meta: "channel · 14h",
             avatarGradient: gViolet,
             avatarURL: mediaSpidey,
             imageURL: mediaSpidey,
             videoURL: clip4,
             imageAspect: 1.25,
             text: "Thrifted the whole fit for under $40. Receipts in comments.",
             showFollow: true, likeCount: 2210, commentCount: 5),
        Post(author: "dani.codes", meta: "channel · 18h",
             avatarGradient: g1,
             avatarURL: mediaCockpitCat,
             text: "Hot take: side projects die from scope, not from lack of time. Ship the ugly version this weekend.",
             likeCount: 764, commentCount: 3),
        Post(author: "theo.fit", meta: "channel · 1d",
             avatarGradient: g3,
             avatarURL: mediaPorscheDubai,
             imageURL: mediaPorscheDubai,
             videoURL: clip5,
             imageAspect: 1.25,
             text: "5am run club, week 6. The bridge finally stopped winning.",
             likeCount: 431, commentCount: 2),
        Post(author: "nia.studio", meta: "channel · 1d",
             avatarGradient: g5,
             avatarURL: mediaLighthouse,
             imageURL: mediaCosmicFace,
             videoURL: clip6,
             imageAspect: 1.25,
             text: "Kiln day. Half survive, and that's a good ratio.",
             likeCount: 1108, commentCount: 4),
        Post(author: "juin.eats", meta: "channel · 2d",
             avatarGradient: gBlue,
             avatarURL: mediaCatsDuo,
             imageURL: mediaCatsDuo,
             imageAspect: 1.0,
             text: "Rated every dumpling spot within walking distance so you don't have to. Thread soon.",
             showFollow: true, likeCount: 3320, commentCount: 6),
        Post(author: "rex.audio", meta: "channel · 2d",
             avatarGradient: g4,
             avatarURL: mediaPilotCat,
             imageURL: mediaPilotCat,
             videoURL: clip1,
             imageAspect: 1.1,
             text: "Mixed the whole EP on $30 earbuds first. If it slaps there, it slaps anywhere.",
             likeCount: 587, commentCount: 2),
        Post(author: "ava.maps", meta: "channel · 3d",
             avatarGradient: g2,
             avatarURL: mediaCockpitCat,
             imageURL: mediaCockpitCat,
             videoURL: clip2,
             imageAspect: 1.25,
             text: "Hand-drew the neighborhood as it was in 1962. Overlay coming next week.",
             likeCount: 1892, commentCount: 4),
    ]

    // MARK: Activity / notifications
    static let notifications: [ActivityItem] = [
        ActivityItem(kind: .like, actor: "marta.st",
                     text: "liked your post “First frames on gojogo”.",
                     timeAgo: "2m",
                     avatarURL: "https://picsum.photos/seed/av-marta/200/200",
                     previewURL: "https://picsum.photos/seed/own-post-1-jad/200/200"),
        ActivityItem(kind: .follow, actor: "kal.eb",
                     text: "started following you.",
                     timeAgo: "26m",
                     avatarURL: "https://picsum.photos/seed/av-kaleb/200/200"),
        ActivityItem(kind: .comment, actor: "dani",
                     text: "commented: “Studio looks unreal.”",
                     timeAgo: "1h",
                     avatarURL: "https://picsum.photos/seed/c-dani/120/120",
                     previewURL: "https://picsum.photos/seed/own-post-2-jad/200/200"),
        ActivityItem(kind: .mention, actor: "lea.style",
                     text: "mentioned you in a comment.",
                     timeAgo: "3h",
                     avatarURL: "https://picsum.photos/seed/av-lea/200/200"),
        ActivityItem(kind: .order, actor: "mira.tech",
                     text: "replied about “iPhone 13 · 128GB” — still available.",
                     timeAgo: "5h",
                     avatarURL: "https://picsum.photos/seed/prod-iphone/120/120"),
        ActivityItem(kind: .like, actor: "omar",
                     text: "and 12 others liked your post.",
                     timeAgo: "8h", read: true,
                     avatarURL: "https://picsum.photos/seed/c-omar/120/120"),
        ActivityItem(kind: .system, actor: "Madeleine",
                     text: "Your weekend plan is ready — 3 events pinned.",
                     timeAgo: "1d", read: true),
        ActivityItem(kind: .follow, actor: "nia.studio",
                     text: "started following you.",
                     timeAgo: "1d", read: true,
                     avatarURL: "https://picsum.photos/seed/av-nia/200/200"),
        ActivityItem(kind: .comment, actor: "theo",
                     text: "commented: “What lens was this?”",
                     timeAgo: "2d", read: true,
                     avatarURL: "https://picsum.photos/seed/c-theo/120/120"),
    ]

    /// Posts seeded as the signed-in user (handle remapped in AppState.init).
    static func ownSeedPosts(handle: String, name: String, avatarURL: String?,
                             avatarGradient: [Color]) -> [Post] {
        [
            Post(author: handle, meta: "channel · just now",
                 avatarGradient: avatarGradient, avatarURL: avatarURL,
                 imageURL: mediaBatman,
                 videoURL: clip1,
                 mediaItems: [
                    PostMediaItem(imageURL: mediaBatman, videoURL: clip1),
                    PostMediaItem(imageURL: mediaLighthouse, videoURL: clip3),
                    PostMediaItem(imageURL: mediaSpidey, videoURL: clip4),
                 ],
                 imageAspect: 1.25,
                 text: "First frames on gojogo — more coming.",
                 likeCount: 12, commentCount: 0),
            Post(author: handle, meta: "channel · 1d",
                 avatarGradient: avatarGradient, avatarURL: avatarURL,
                 imageURL: mediaPorscheDesert,
                 videoURL: clip5,
                 imageAspect: 1.25,
                 text: "Studio light tests. Saving the ones that stay.",
                 likeCount: 48, commentCount: 1),
            Post(author: handle, meta: "channel · 3d",
                 avatarGradient: avatarGradient, avatarURL: avatarURL,
                 text: "Building in public. Notes later.",
                 likeCount: 27, commentCount: 0),
        ]
    }

    // Bundled sample clips (GojoGo/SampleVideos).
    static let clip1 = "bundlevideo:SampleClip1"
    static let clip2 = "bundlevideo:SampleClip2"
    static let clip3 = "bundlevideo:SampleClip3"
    static let clip4 = "bundlevideo:SampleClip4"
    static let clip5 = "bundlevideo:SampleClip5"
    static let clip6 = "bundlevideo:SampleClip6"

    static let allSampleClips: [String] = [clip1, clip2, clip3, clip4, clip5, clip6]

    // Legacy remote sample URLs — remapped to bundled clips for old caches.
    private static let videoBigBuck = clip1
    private static let videoElephants = clip2
    private static let videoSintel = clip3
    private static let videoTears = clip4

    /// Remap known-dead CDN URLs (cached sessions may still hold them).
    static func repairedVideoURL(_ url: String?) -> String? {
        guard let url, !url.isEmpty else { return url }
        if url.hasPrefix("bundlevideo:") || url.hasPrefix("SampleClip") { return url }
        if url.contains("gtv-videos-bucket") || url.contains("commondatastorage.googleapis.com")
            || url.contains("w3schools.com") || url.contains("mozilla.net")
            || url.contains("media.w3.org") || url.contains("test-videos.co.uk") {
            let idx = abs(url.hashValue) % allSampleClips.count
            return allSampleClips[idx]
        }
        return url
    }

    // MARK: Long-form videos
    static let videos: [VideoItem] = [
        VideoItem(title: "Why LLMs need tools — a field guide",
                  channel: "signal.lab", meta: "signal.lab · 214K views · 2d",
                  duration: "0:18", thumbGradient: gBlue,
                  thumbURL: mediaBatman,
                  videoURL: clip1, likes: 4200),
        VideoItem(title: "The quiet economics of night markets",
                  channel: "marta.st", meta: "marta.st · 88K views · 5d",
                  duration: "0:14", thumbGradient: gViolet,
                  thumbURL: mediaLighthouse,
                  videoURL: clip2, likes: 2100),
        VideoItem(title: "Building a camera from spare parts",
                  channel: "kal.eb", meta: "kal.eb · 41K views · 1w",
                  duration: "0:08", thumbGradient: g3,
                  thumbURL: mediaPorscheDesert,
                  videoURL: clip3, likes: 980),
        VideoItem(title: "Frame rates that feel like film",
                  channel: "sena.films", meta: "sena.films · 62K views · 3d",
                  duration: "0:10", thumbGradient: g4,
                  thumbURL: mediaPorscheDubai,
                  videoURL: clip4, likes: 1560),
        VideoItem(title: "I biked every bridge in the bay (in one day)",
                  channel: "ava.maps", meta: "ava.maps · 156K views · 4d",
                  duration: "0:16", thumbGradient: g2,
                  thumbURL: mediaBMWM4,
                  videoURL: clip5, likes: 5400),
        VideoItem(title: "Sound design from kitchen junk — full breakdown",
                  channel: "rex.audio", meta: "rex.audio · 33K views · 6d",
                  duration: "0:12", thumbGradient: gViolet,
                  thumbURL: mediaCosmicFace,
                  videoURL: clip6, likes: 1210),
        VideoItem(title: "Dumpling tier list: 14 spots, zero mercy",
                  channel: "juin.eats", meta: "juin.eats · 402K views · 1w",
                  duration: "0:18", thumbGradient: g4,
                  thumbURL: mediaSpidey,
                  videoURL: clip1, likes: 9800),
        VideoItem(title: "Thrift flip: $12 jacket → runway",
                  channel: "lea.style", meta: "lea.style · 77K views · 1w",
                  duration: "0:14", thumbGradient: gViolet,
                  thumbURL: mediaPilotCat,
                  videoURL: clip2, likes: 2650),
        VideoItem(title: "Training for my first marathon, week 1 vs week 12",
                  channel: "theo.fit", meta: "theo.fit · 91K views · 2w",
                  duration: "0:08", thumbGradient: g3,
                  thumbURL: mediaCockpitCat,
                  videoURL: clip5, likes: 3100),
    ]

    static let defaultComments: [Comment] = [
        Comment(author: "dani", text: "This hits different at 2am.",
                avatarURL: "https://picsum.photos/seed/c-dani/120/120", likeCount: 12, timeAgo: "1h"),
        Comment(author: "lea", text: "Saving this for later — need that light.",
                avatarURL: "https://picsum.photos/seed/c-lea/120/120", likeCount: 4, timeAgo: "3h"),
    ]

    static func seedComments(for posts: [Post]) -> [UUID: [Comment]] {
        var map: [UUID: [Comment]] = [:]
        for (i, p) in posts.enumerated() {
            var list = defaultComments
            if i == 0 {
                list.insert(Comment(author: "omar", text: "The dog stole the scene 👏",
                                    avatarURL: "https://picsum.photos/seed/c-omar/120/120",
                                    likeCount: 28, timeAgo: "40m"), at: 0)
            }
            if i == 2 {
                list.append(Comment(author: "theo", text: "What lens was this?",
                                    avatarURL: "https://picsum.photos/seed/c-theo/120/120",
                                    likeCount: 9, timeAgo: "5h"))
            }
            map[p.id] = list
        }
        return map
    }

    // MARK: Shorts
    static let shorts: [Short] = [
        Short(channel: "marta.st", subscribers: "channel · 1.2M",
              caption: "Behind the scenes of the rooftop set — one take, no cuts.",
              gradient: [Color(hex: "1a2030"), Color(hex: "07090d")],
              imageURL: mediaBatman,
              videoURL: clip1, likeCount: 84_200),
        Short(channel: "kal.eb", subscribers: "channel · 640K",
              caption: "Drone mapper first flight. It actually works.",
              gradient: [Color(hex: "241a2e"), Color(hex: "090711")],
              imageURL: mediaPorscheDesert,
              videoURL: clip2, likeCount: 31_400),
        Short(channel: "sena.films", subscribers: "channel · 2.4M",
              caption: "Golden hour, no color grade. Straight off the sensor.",
              gradient: [Color(hex: "2a2018"), Color(hex: "0d0906")],
              imageURL: mediaBMWM4,
              videoURL: clip3, likeCount: 120_800),
        Short(channel: "juin.eats", subscribers: "channel · 890K",
              caption: "POV: the dumpling spot with no sign and a 40-minute line. Worth it.",
              gradient: [Color(hex: "2a1e18"), Color(hex: "0d0806")],
              imageURL: mediaCatsDuo,
              videoURL: clip4, likeCount: 210_400),
        Short(channel: "theo.fit", subscribers: "channel · 310K",
              caption: "Day 42 of running before sunrise. The city belongs to you at 5am.",
              gradient: [Color(hex: "18242a"), Color(hex: "060b0d")],
              imageURL: mediaPorscheDubai,
              videoURL: clip5, likeCount: 45_100),
        Short(channel: "lea.style", subscribers: "channel · 1.7M",
              caption: "3 outfits from one thrifted blazer. Save this for later.",
              gradient: [Color(hex: "241a2e"), Color(hex: "0b0711")],
              imageURL: mediaSpidey,
              videoURL: clip6, likeCount: 156_900),
        Short(channel: "rex.audio", subscribers: "channel · 420K",
              caption: "Made this beat with a spoon, a mug, and one synth. Sound on. 🎧",
              gradient: [Color(hex: "1e1a2e"), Color(hex: "090711")],
              imageURL: mediaPilotCat,
              videoURL: clip1, likeCount: 88_700),
        Short(channel: "ava.maps", subscribers: "channel · 260K",
              caption: "Every staircase street in the city, ranked by burn. Part 1.",
              gradient: [Color(hex: "1a2a20"), Color(hex: "060d09")],
              imageURL: mediaCockpitCat,
              videoURL: clip2, likeCount: 32_500),
    ]

    // MARK: Economy
    static let economyCategories = ["All", "Phones", "Cameras", "Fashion", "Home", "Sports"]

    static let featuredProduct = Product(
        name: "iPhone 13 · 128GB", price: "$275",
        meta: "Battery 91% · verified seller · 2.1 km away",
        gradient: [Color(hex: "1c222e"), Color(hex: "0d1016")],
        imageURL: mediaPorscheDubai,
        category: "Phones", seller: "mira.tech", condition: "Excellent",
        distance: "2.1 km",
        description: "Unlocked iPhone 13, battery health 91%. Original box + cable. Small scuff on the frame — happy to FaceTime for a walkthrough.")

    static let products: [Product] = [
        Product(name: "Keycaps · PBT set", price: "$24",
                meta: "Like new · 0.8 km",
                gradient: [Color(hex: "242030"), Color(hex: "100e16")],
                imageURL: mediaCosmicFace,
                category: "Home", seller: "desk.lab", condition: "Like new", distance: "0.8 km"),
        Product(name: "Film cam · Contax", price: "$110",
                meta: "Good · 1.4 km",
                gradient: [Color(hex: "20302a"), Color(hex: "0e1612")],
                imageURL: mediaLighthouse,
                category: "Cameras", seller: "sena.films", condition: "Good", distance: "1.4 km",
                description: "Contax T2 body. Light seals replaced. Comes with strap and half a roll of Portra."),
        Product(name: "Chelsea boots", price: "$68",
                meta: "Size 42 · 3.2 km",
                gradient: [Color(hex: "302420"), Color(hex: "160f0d")],
                imageURL: mediaBMWM4,
                category: "Fashion", seller: "lea.style", condition: "Good", distance: "3.2 km"),
        Product(name: "Desk lamp", price: "$39",
                meta: "Warm LED · 1.1 km",
                gradient: [Color(hex: "1e2836"), Color(hex: "0d1218")],
                imageURL: mediaBatman,
                category: "Home", seller: "kal.eb", condition: "Like new", distance: "1.1 km"),
        Product(name: "Pixel 7a", price: "$220",
                meta: "128GB · unlocked · 4 km",
                gradient: [Color(hex: "1a2430"), Color(hex: "0c1016")],
                imageURL: mediaPorscheDesert,
                category: "Phones", seller: "omar.gears", condition: "Excellent", distance: "4.0 km"),
        Product(name: "Yoga mat · cork", price: "$32",
                meta: "Barely used · 2.6 km",
                gradient: [Color(hex: "203028"), Color(hex: "0e1612")],
                imageURL: mediaSpidey,
                category: "Sports", seller: "nia.move", condition: "Like new", distance: "2.6 km"),
        Product(name: "Vintage denim", price: "$45",
                meta: "M · soft wash · 1.9 km",
                gradient: [Color(hex: "242830"), Color(hex: "101418")],
                imageURL: mediaPilotCat,
                category: "Fashion", seller: "theo.fit", condition: "Good", distance: "1.9 km"),
        Product(name: "Sony a6400 body", price: "$480",
                meta: "Shutter 12k · 5.1 km",
                gradient: [Color(hex: "2a2030"), Color(hex: "120e18")],
                imageURL: mediaCockpitCat,
                category: "Cameras", seller: "marta.st", condition: "Excellent", distance: "5.1 km",
                description: "Body only. Two batteries + charger. No dents. Receipt available."),
        Product(name: "AirPods Pro 2", price: "$120",
                meta: "USB-C · sealed tips · 1.6 km",
                gradient: [Color(hex: "222a30"), Color(hex: "0e1216")],
                imageURL: mediaCatsDuo,
                category: "Phones", seller: "dani.codes", condition: "Excellent", distance: "1.6 km",
                description: "Barely used, all sizes of sealed ear tips included. Case has a small scratch."),
        Product(name: "Road bike · 54cm", price: "$310",
                meta: "New chain · 2.9 km",
                gradient: [Color(hex: "20302a"), Color(hex: "0c1610")],
                imageURL: mediaBatman,
                category: "Sports", seller: "ava.maps", condition: "Good", distance: "2.9 km",
                description: "Aluminum frame, carbon fork. New chain and bar tape last month. Test rides welcome."),
        Product(name: "Mid-century armchair", price: "$95",
                meta: "Walnut legs · 3.8 km",
                gradient: [Color(hex: "30281c"), Color(hex: "16110b")],
                imageURL: mediaLighthouse,
                category: "Home", seller: "nia.move", condition: "Good", distance: "3.8 km"),
        Product(name: "Fuji X100V", price: "$720",
                meta: "Boxed · 6.2 km",
                gradient: [Color(hex: "2c2230"), Color(hex: "130e16")],
                imageURL: mediaPorscheDesert,
                category: "Cameras", seller: "sena.films", condition: "Excellent", distance: "6.2 km",
                description: "The one everyone wants. Boxed with two batteries, thumb grip, and half-case."),
        Product(name: "Running shoes · 44", price: "$55",
                meta: "80 km on them · 1.2 km",
                gradient: [Color(hex: "1c2a24"), Color(hex: "0b1410")],
                imageURL: mediaBMWM4,
                category: "Sports", seller: "theo.fit", condition: "Good", distance: "1.2 km"),
        Product(name: "Wool overcoat · M", price: "$88",
                meta: "Dry cleaned · 2.4 km",
                gradient: [Color(hex: "2a2420"), Color(hex: "120f0d")],
                imageURL: mediaSpidey,
                category: "Fashion", seller: "lea.style", condition: "Like new", distance: "2.4 km"),
        Product(name: "Studio monitors · pair", price: "$260",
                meta: "5\" · with stands · 4.5 km",
                gradient: [Color(hex: "241e30"), Color(hex: "0f0c16")],
                imageURL: mediaCosmicFace,
                category: "Home", seller: "rex.audio", condition: "Excellent", distance: "4.5 km",
                description: "Flat response, perfect for a small room. Includes isolation pads and cables."),
    ]

    // MARK: Search
    static let people: [PersonSuggestion] = [
        PersonSuggestion(name: "dani", gradient: g1, avatarURL: "https://picsum.photos/seed/p-dani/120/120"),
        PersonSuggestion(name: "omar", gradient: g2, avatarURL: "https://picsum.photos/seed/p-omar/120/120"),
        PersonSuggestion(name: "lea", gradient: g3, avatarURL: "https://picsum.photos/seed/p-lea/120/120"),
        PersonSuggestion(name: "theo", gradient: g4, avatarURL: "https://picsum.photos/seed/p-theo/120/120"),
        PersonSuggestion(name: "nia", gradient: g5, avatarURL: "https://picsum.photos/seed/p-nia/120/120"),
        PersonSuggestion(name: "juin", gradient: gBlue, avatarURL: "https://picsum.photos/seed/p-juin/120/120"),
        PersonSuggestion(name: "rex", gradient: g4, avatarURL: "https://picsum.photos/seed/p-rex/120/120"),
        PersonSuggestion(name: "ava", gradient: g2, avatarURL: "https://picsum.photos/seed/p-ava/120/120"),
        PersonSuggestion(name: "marta", gradient: gViolet, avatarURL: "https://picsum.photos/seed/p-marta/120/120"),
        PersonSuggestion(name: "sena", gradient: g3, avatarURL: "https://picsum.photos/seed/p-sena/120/120"),
    ]

    static let searchContent: [TVTile] = [
        TVTile(title: "Sunday league", gradient: gBlue,
               imageURL: "https://picsum.photos/seed/search-league/600/400"),
        TVTile(title: "5-a-side near you", gradient: gViolet,
               imageURL: "https://picsum.photos/seed/search-5aside/600/400"),
        TVTile(title: "Night market food crawl", gradient: g4,
               imageURL: "https://picsum.photos/seed/search-market/600/400"),
        TVTile(title: "Film photography walks", gradient: g3,
               imageURL: "https://picsum.photos/seed/search-film/600/400"),
    ]

    // MARK: GojoTV
    static let tvHero = TVShow(
        title: "LLMs Need Tools",
        subtitle: "6 episodes · Docuseries",
        synopsis: "Field notes on agents, tools, and the engineers shipping the next interface. Shot across three labs — no voiceover fluff.",
        badge: "GOJOTV ORIGINAL · SERIES",
        gradient: gBlue,
        imageURL: "https://picsum.photos/seed/gojotv-hero/1200/800",
        progress: 0.42,
        episodes: [
            TVEpisode(number: 1, title: "Why chat isn’t enough", duration: "18m", watched: true),
            TVEpisode(number: 2, title: "Toolformer in the wild", duration: "22m", watched: true),
            TVEpisode(number: 3, title: "Memory that sticks", duration: "19m"),
            TVEpisode(number: 4, title: "Eval is product", duration: "24m"),
            TVEpisode(number: 5, title: "Human in the loop", duration: "21m"),
            TVEpisode(number: 6, title: "What ships next", duration: "26m"),
        ]
    )

    static let tvShows: [TVShow] = {
        let night = TVShow(
            title: "Night Signal", subtitle: "8 episodes · Thriller",
            synopsis: "A radio engineer picks up a broadcast that shouldn’t exist — and a city that starts answering back.",
            badge: "SERIES", gradient: [Color(hex: "2a1e30"), Color(hex: "120b16")],
            imageURL: "https://picsum.photos/seed/tv1/800/1200", progress: 0.18,
            episodes: [
                TVEpisode(number: 1, title: "Static", duration: "44m", watched: true),
                TVEpisode(number: 2, title: "Caller ID", duration: "41m"),
                TVEpisode(number: 3, title: "Relay", duration: "46m"),
            ])
        let circuit = TVShow(
            title: "Open Circuit", subtitle: "10 episodes · Drama",
            synopsis: "Hardware founders, one failed chip, and a year that rewrites who they are.",
            badge: "SERIES", gradient: [Color(hex: "1e2a30"), Color(hex: "0b1216")],
            imageURL: "https://picsum.photos/seed/tv2/800/1200",
            episodes: [
                TVEpisode(number: 1, title: "Fab Zero", duration: "48m"),
                TVEpisode(number: 2, title: "Yield", duration: "45m"),
            ])
        let amber = TVShow(
            title: "Amber Hour", subtitle: "Film · 1h 42m",
            synopsis: "One golden hour shot across five cities. No cuts that feel like cuts.",
            badge: "FILM", gradient: [Color(hex: "30281e"), Color(hex: "16100b")],
            imageURL: "https://picsum.photos/seed/tv3/800/1200", progress: 0.67,
            episodes: [TVEpisode(number: 1, title: "Feature", duration: "1h 42m", watched: true)])
        let field = TVShow(
            title: "Field Notes", subtitle: "12 episodes · Doc",
            synopsis: "Short essays from makers who still touch their work.",
            badge: "DOC", gradient: [Color(hex: "1e3028"), Color(hex: "0b1610")],
            imageURL: "https://picsum.photos/seed/tv4/800/1200",
            episodes: [
                TVEpisode(number: 1, title: "Hands", duration: "28m"),
                TVEpisode(number: 2, title: "Maps", duration: "31m"),
            ],
            onWatchlist: true)
        let cartoons = TVShow(
            title: "Saturday Cartoons", subtitle: "Kids · Season 3",
            synopsis: "Soft chaos for the morning couch. New episodes drop weekly.",
            badge: "KIDS", gradient: [Color(hex: "233040"), Color(hex: "0e141c")],
            imageURL: "https://picsum.photos/seed/tv-cartoons/800/450",
            episodes: [TVEpisode(number: 1, title: "Balloon day", duration: "12m")])
        let nature = TVShow(
            title: "Nature, Up Close", subtitle: "Doc · 8 parts",
            synopsis: "Macro wildlife without the narration that talks down to you.",
            badge: "DOC", gradient: [Color(hex: "302336"), Color(hex: "140e18")],
            imageURL: "https://picsum.photos/seed/tv-nature/800/450", progress: 0.31,
            episodes: [TVEpisode(number: 1, title: "Dew", duration: "34m", watched: true)])
        let kitchen = TVShow(
            title: "Kitchen Lab", subtitle: "Cooking · Season 1",
            synopsis: "Recipes treated like prototypes. Failures stay in the cut.",
            badge: "LIFESTYLE", gradient: [Color(hex: "2c3623"), Color(hex: "12160e")],
            imageURL: "https://picsum.photos/seed/tv-kitchen/800/450",
            episodes: [TVEpisode(number: 1, title: "Salt first", duration: "26m")])
        let live = TVShow(
            title: "City Night Live", subtitle: "Live · Fridays 9pm",
            synopsis: "Street sets, guest DJs, and a chat that actually stays on-topic.",
            badge: "LIVE", gradient: [Color(hex: "301e28"), Color(hex: "160b12")],
            imageURL: "https://picsum.photos/seed/tv-live/800/450",
            episodes: [TVEpisode(number: 1, title: "Tonight", duration: "Live")])
        return [night, circuit, amber, field, cartoons, nature, kitchen, live]
    }()

    static var tvTop10: [TVPoster] {
        Array(tvShows.prefix(4).enumerated()).map { i, show in
            TVPoster(rank: i + 1, title: show.title, gradient: show.gradient,
                     imageURL: show.imageURL, showID: show.id)
        }
    }

    static var tvFamily: [TVTile] {
        tvShows.filter { ["Saturday Cartoons", "Nature, Up Close", "Kitchen Lab"].contains($0.title) }
            .map { TVTile(title: $0.title, gradient: $0.gradient, imageURL: $0.imageURL, showID: $0.id) }
    }

    static var tvDocs: [TVTile] {
        tvShows.filter { $0.badge == "DOC" || $0.badge.contains("DOC") }
            .map { TVTile(title: $0.title, gradient: $0.gradient, imageURL: $0.imageURL, showID: $0.id) }
    }

    static var tvContinue: [TVShow] {
        tvShows.filter { $0.progress > 0 } + (tvHero.progress > 0 ? [tvHero] : [])
    }

    // MARK: Profile grid (image URLs)
    static let profileGridURLs: [String] = [
        mediaBatman,
        mediaLighthouse,
        mediaPorscheDesert,
        mediaPorscheDubai,
        mediaBMWM4,
        mediaCosmicFace,
    ]

    // Kept for source compat
    static let profileGrid: [[Color]] = [
        gBlue, gViolet, [Color(hex: "1e3028"), Color(hex: "0b1610")],
        [Color(hex: "30281e"), Color(hex: "16100b")],
        [Color(hex: "233040"), Color(hex: "0e141c")],
        [Color(hex: "302336"), Color(hex: "140e18")],
    ]

    // MARK: Madeleine
    static let madeleineSuggestions = [
        "Summarize my feed", "Plan my weekend",
        "Find me a football group", "Help with homework",
        "What should I watch tonight?", "Find me a camera deal",
    ]

    static let watchingChat: [ChatMessage] = [
        ChatMessage(text: "Pull the papers this video references and summarize them.", fromUser: true),
        ChatMessage(text: "This is your research, sir. Three papers cited so far — the 2024 toolformer study is the backbone of his argument.", fromUser: false),
        ChatMessage(text: "", fromUser: false,
                    fileChip: FileChip(name: "research-summary.pdf", sub: "3 sources · 2 min read")),
    ]

    // MARK: Interests
    static let interests: [Interest] = [
        Interest(title: "Football", selected: true, x: 0.20, y: 0.14, size: 118,
                 accent: [GGColor.accent, GGColor.auroraDeep]),
        Interest(title: "Music", x: 0.80, y: 0.09, size: 92),
        Interest(title: "AI & tech", selected: true, x: 0.48, y: 0.34, size: 104,
                 accent: [GGColor.auroraViolet, GGColor.auroraDeep]),
        Interest(title: "Anime", x: 0.84, y: 0.36, size: 84),
        Interest(title: "Cooking", x: 0.18, y: 0.44, size: 96),
        Interest(title: "Gaming", selected: true, x: 0.50, y: 0.62, size: 122,
                 accent: [GGColor.accent, GGColor.auroraTeal]),
        Interest(title: "Fashion", x: 0.82, y: 0.60, size: 88),
        Interest(title: "Travel", x: 0.20, y: 0.74, size: 80),
        Interest(title: "Fitness", x: 0.44, y: 0.86, size: 90),
        Interest(title: "Night markets", x: 0.80, y: 0.85, size: 96),
    ]

    static let usernameSuggestions = ["go", "its"]

    // MARK: GojoTravel — SF Bay demo anchors

    static let travelDefaultCenter = TravelPlace(
        name: "Current location",
        subtitle: "Near you",
        latitude: 37.7749,
        longitude: -122.4194,
        icon: "location.fill"
    )

    static let travelRecentPlaces: [TravelPlace] = [
        TravelPlace(name: "SFO Airport", subtitle: "San Francisco International",
                    latitude: 37.6213, longitude: -122.3790, icon: "airplane"),
        TravelPlace(name: "Ferry Building", subtitle: "1 Ferry Building, San Francisco",
                    latitude: 37.7955, longitude: -122.3937, icon: "building.2"),
        TravelPlace(name: "Golden Gate Bridge", subtitle: "Golden Gate Brg, San Francisco",
                    latitude: 37.8199, longitude: -122.4783, icon: "road.lanes"),
        TravelPlace(name: "Mission Dolores Park", subtitle: "Dolores St & 19th St",
                    latitude: 37.7596, longitude: -122.4269, icon: "leaf"),
        TravelPlace(name: "Chase Center", subtitle: "1 Warriors Way",
                    latitude: 37.7680, longitude: -122.3877, icon: "sportscourt"),
    ]

    static let travelSuggestions: [TravelPlace] = [
        TravelPlace(name: "Union Square", subtitle: "Geary St & Powell St",
                    latitude: 37.7879, longitude: -122.4075, icon: "bag"),
        TravelPlace(name: "Oracle Park", subtitle: "24 Willie Mays Plaza",
                    latitude: 37.7786, longitude: -122.3893, icon: "flag"),
        TravelPlace(name: "Twin Peaks", subtitle: "501 Twin Peaks Blvd",
                    latitude: 37.7544, longitude: -122.4477, icon: "mountain.2"),
        TravelPlace(name: "Palace of Fine Arts", subtitle: "3601 Lyon St",
                    latitude: 37.8021, longitude: -122.4488, icon: "building.columns"),
        TravelPlace(name: "Castro Theatre", subtitle: "429 Castro St",
                    latitude: 37.7620, longitude: -122.4350, icon: "theatermasks"),
        TravelPlace(name: "Ocean Beach", subtitle: "Great Hwy, Outer Sunset",
                    latitude: 37.7594, longitude: -122.5107, icon: "water.waves"),
        TravelPlace(name: "Coit Tower", subtitle: "1 Telegraph Hill Blvd",
                    latitude: 37.8024, longitude: -122.4058, icon: "building.columns"),
        TravelPlace(name: "Presidio Tunnel Tops", subtitle: "210 Lincoln Blvd",
                    latitude: 37.8016, longitude: -122.4551, icon: "leaf"),
        TravelPlace(name: "SF MOMA", subtitle: "151 3rd St",
                    latitude: 37.7857, longitude: -122.4011, icon: "paintpalette"),
        TravelPlace(name: "Caltrain Station", subtitle: "700 4th St",
                    latitude: 37.7766, longitude: -122.3946, icon: "tram"),
    ]

    static func rideOptions(to dropoff: TravelPlace) -> [RideOption] {
        let dist = hypot(dropoff.latitude - travelDefaultCenter.latitude,
                         dropoff.longitude - travelDefaultCenter.longitude)
        let base = max(8, Int(dist * 120))
        return [
            RideOption(name: "GojoGo", tagline: "Everyday rides",
                       etaMinutes: max(2, base / 4),
                       price: String(format: "$%.0f", Double(base) * 0.85),
                       capacity: 4, icon: "car.fill"),
            RideOption(name: "Comfort", tagline: "Newer cars · extra space",
                       etaMinutes: max(3, base / 3),
                       price: String(format: "$%.0f", Double(base) * 1.15),
                       capacity: 4, icon: "car.side.fill"),
            RideOption(name: "XL", tagline: "Up to 6 seats",
                       etaMinutes: max(4, base / 2),
                       price: String(format: "$%.0f", Double(base) * 1.45),
                       capacity: 6, icon: "bus.fill"),
            RideOption(name: "Black", tagline: "Premium · quiet cabin",
                       etaMinutes: max(5, base / 2 + 2),
                       price: String(format: "$%.0f", Double(base) * 1.9),
                       capacity: 4, icon: "car.rear.fill"),
        ]
    }

    static func sampleDriver(near pickup: TravelPlace, eta: Int) -> TravelDriver {
        TravelDriver(
            name: ["Maya R.", "Leo K.", "Sofia N.", "Amir T."].randomElement()!,
            rating: [4.92, 4.97, 4.88, 4.95].randomElement()!,
            trips: Int.random(in: 420...4200),
            vehicle: ["Tesla Model 3", "Toyota Camry", "BMW 5", "Mercedes E-Class"].randomElement()!,
            plate: ["8GZK442", "7HXM119", "9PRL220", "6WQT881"].randomElement()!,
            etaMinutes: eta,
            avatarURL: "https://picsum.photos/seed/gojo-driver-\(Int.random(in: 1...40))/200/200",
            latitude: pickup.latitude + Double.random(in: -0.012...0.012),
            longitude: pickup.longitude + Double.random(in: -0.012...0.012)
        )
    }

    // MARK: - My World

    static let worldContacts: [WorldContact] = [
        WorldContact(name: "Marta Chen", username: "marta", phone: "+1 415 555 0142",
                     avatarURL: "https://picsum.photos/seed/mw-marta/200/200",
                     avatarGradient: g2, bio: "Design + cold brew", city: "San Francisco",
                     latitude: 37.7749, longitude: -122.4194, distanceLabel: "2 km", etaLabel: "8 min"),
        WorldContact(name: "Kaleb Okonkwo", username: "kal.eb", phone: "+1 646 555 0198",
                     avatarURL: "https://picsum.photos/seed/mw-kaleb/200/200",
                     avatarGradient: g3, bio: "Making things", city: "Brooklyn",
                     latitude: 40.6782, longitude: -73.9442, distanceLabel: "14 km", etaLabel: "28 min"),
        WorldContact(name: "Sena Park", username: "sena", phone: "+82 10 5555 2211",
                     avatarURL: "https://picsum.photos/seed/mw-sena/200/200",
                     avatarGradient: g4, bio: "Film & weekends", city: "Seoul",
                     latitude: 37.5665, longitude: 126.9780, distanceLabel: "5 km", etaLabel: "18 min"),
        WorldContact(name: "Dani Ruiz", username: "dani", phone: "+34 612 555 033",
                     avatarURL: "https://picsum.photos/seed/mw-dani/200/200",
                     avatarGradient: g5, bio: "Always cooking", city: "Barcelona",
                     latitude: 41.3874, longitude: 2.1686, distanceLabel: "3 km", etaLabel: "12 min"),
        WorldContact(name: "Omar Hassan", username: "omar", phone: "+971 50 555 7744",
                     avatarURL: "https://picsum.photos/seed/mw-omar/200/200",
                     avatarGradient: gBlue, bio: "Travel light", city: "Dubai",
                     latitude: 25.2048, longitude: 55.2708, distanceLabel: "11 km", etaLabel: "22 min"),
        WorldContact(name: "Lea Moreau", username: "lea", phone: "+33 6 55 55 01 22",
                     avatarURL: "https://picsum.photos/seed/mw-lea/200/200",
                     avatarGradient: gViolet, bio: "Books & bikes", city: "Paris",
                     latitude: 48.8566, longitude: 2.3522, distanceLabel: "4 km", etaLabel: "15 min"),
        WorldContact(name: "Wifey ❤️💍🐣", username: "wifey", phone: "+212 6 05 27 91 09",
                     avatarURL: "https://picsum.photos/seed/mw-wifey/200/200",
                     avatarGradient: g2, bio: "My person", city: "Sale",
                     latitude: 34.0531, longitude: -6.7985, distanceLabel: "23 km", etaLabel: "36 min"),
    ]

    static let worldCircles: [WorldCircle] = {
        let c = worldContacts
        guard c.count >= 6 else { return [] }
        return [
            WorldCircle(name: "Close Friends",
                        memberIDs: [c[0].id, c[1].id, c[6].id],
                        colorHex: "5AC8FA"),
            WorldCircle(name: "Family",
                        memberIDs: [c[3].id, c[4].id, c[6].id],
                        colorHex: "FF9F0A"),
            WorldCircle(name: "College",
                        memberIDs: [c[0].id, c[2].id, c[5].id],
                        colorHex: "BF5AF2"),
            WorldCircle(name: "City crew",
                        memberIDs: [c[1].id, c[3].id, c[5].id],
                        colorHex: "30D158"),
        ]
    }()

    static let worldConversations: [WorldConversation] = {
        let c = worldContacts
        guard c.count >= 7 else { return [] }
        let circles = worldCircles
        let wifey = c[6]
        let now = Date()
        return [
            WorldConversation(
                contactID: wifey.id, title: wifey.name,
                preview: "See you soon 😘", timeAgo: "22:55", unread: 2, pinned: true,
                avatarURL: wifey.avatarURL, avatarGradient: wifey.avatarGradient,
                messages: [
                    WorldMessage(kind: .timestamp, text: "Mon, 8 Jun at 12:31"),
                    WorldMessage(kind: .system, text: "Text Message · SMS"),
                    WorldMessage(kind: .system, text: "Not Encrypted"),
                    WorldMessage(text: "Did you get the attestation?", fromUser: false),
                    WorldMessage(kind: .file, text: "", fromUser: false,
                                 fileName: "Attestation_master.pdf",
                                 fileMeta: "PDF Document · 399 KB"),
                    WorldMessage(text: "Got it — thank you ❤️", fromUser: true,
                                 readLabel: "Read 3/6/2026"),
                    WorldMessage(kind: .emoji, text: "😘", fromUser: false),
                    WorldMessage(kind: .timestamp, text: "Today 22:48"),
                    WorldMessage(text: "On my way home", fromUser: false),
                    WorldMessage(text: "See you soon 😘", fromUser: true,
                                 readLabel: "Read 22:55"),
                ],
                lastActivityAt: now.addingTimeInterval(-60 * 5)),
            WorldConversation(
                contactID: c[0].id, title: c[0].name,
                preview: "See you at the gallery tonight?", timeAgo: "Yesterday", unread: 1,
                pinned: true,
                avatarURL: c[0].avatarURL, avatarGradient: c[0].avatarGradient,
                messages: [
                    WorldMessage(kind: .timestamp, text: "Yesterday 19:12"),
                    WorldMessage(text: "Are you free later?", fromUser: false),
                    WorldMessage(text: "Yeah — after 7 works", fromUser: true),
                    WorldMessage(text: "See you at the gallery tonight?", fromUser: false),
                ],
                lastActivityAt: now.addingTimeInterval(-60 * 60 * 20)),
            WorldConversation(
                contactID: c[1].id, title: c[1].name,
                preview: "Sent a photo", timeAgo: "Monday", unread: 0,
                avatarURL: c[1].avatarURL, avatarGradient: c[1].avatarGradient,
                messages: [
                    WorldMessage(text: "Check this out", fromUser: false),
                    WorldMessage(text: "Love it 🔥", fromUser: true, readLabel: "Read Monday"),
                ],
                filterBadge: "P",
                lastActivityAt: now.addingTimeInterval(-60 * 60 * 48)),
            WorldConversation(
                circleID: circles.first?.id, title: "Close Friends",
                preview: "Marta: who's hosting Friday?", timeAgo: "Sunday", unread: 5,
                isGroup: true, avatarGradient: g2,
                messages: [
                    WorldMessage(kind: .timestamp, text: "Sun, 14 Jun at 16:02"),
                    WorldMessage(text: "who's hosting Friday?", fromUser: false, senderName: "Marta"),
                    WorldMessage(text: "I can do my place", fromUser: true),
                ],
                lastActivityAt: now.addingTimeInterval(-60 * 60 * 72)),
            WorldConversation(
                contactID: c[2].id, title: c[2].name,
                preview: "That film was perfect", timeAgo: "9/7/2026", unread: 0,
                avatarURL: c[2].avatarURL, avatarGradient: c[2].avatarGradient,
                messages: [
                    WorldMessage(text: "That film was perfect", fromUser: false),
                    WorldMessage(text: "Right?? We should go again", fromUser: true,
                                 readLabel: "Delivered"),
                ],
                filterBadge: "S",
                lastActivityAt: now.addingTimeInterval(-60 * 60 * 96)),
            WorldConversation(
                contactID: c[5].id, title: c[5].name,
                preview: "You: let's bike Sunday", timeAgo: "9/7/2026", unread: 0,
                avatarURL: c[5].avatarURL, avatarGradient: c[5].avatarGradient,
                messages: [
                    WorldMessage(text: "let's bike Sunday", fromUser: true),
                    WorldMessage(text: "Deal — Bois de Boulogne?", fromUser: false),
                ],
                lastActivityAt: now.addingTimeInterval(-60 * 60 * 120)),
            WorldConversation(
                circleID: circles.count > 1 ? circles[1].id : nil, title: "Family",
                preview: "Omar: landing tomorrow ✈️", timeAgo: "8/7/2026", unread: 1,
                isGroup: true, avatarGradient: g4,
                messages: [
                    WorldMessage(text: "landing tomorrow ✈️", fromUser: false, senderName: "Omar"),
                    WorldMessage(text: "Can't wait!!", fromUser: true),
                ],
                lastActivityAt: now.addingTimeInterval(-60 * 60 * 144)),
        ]
    }()

    // MARK: - GojoDelivery

    /// Real food photography (Unsplash) for restaurants & menu items.
    private static let food = (
        burgerHero: "https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=900&q=80",
        burger1: "https://images.unsplash.com/photo-1550547660-d9450f859349?w=500&q=80",
        burger2: "https://images.unsplash.com/photo-1572802419224-296b0aeee0d9?w=500&q=80",
        fries: "https://images.unsplash.com/photo-1573080496219-bb080dd4f907?w=500&q=80",
        shake: "https://images.unsplash.com/photo-1572490122747-3968b75cc699?w=500&q=80",
        pizzaHero: "https://images.unsplash.com/photo-1513104890138-7c749659a591?w=900&q=80",
        pizza1: "https://images.unsplash.com/photo-1574071318508-1cdbab80d264?w=500&q=80",
        pizza2: "https://images.unsplash.com/photo-1628840042765-356cda07504e?w=500&q=80",
        pizza3: "https://images.unsplash.com/photo-1604382354936-07c5d9983bd3?w=500&q=80",
        tiramisu: "https://images.unsplash.com/photo-1571877227200-a0d98ea607e9?w=500&q=80",
        sushiHero: "https://images.unsplash.com/photo-1579871494447-9811cf80d66c?w=900&q=80",
        sushi1: "https://images.unsplash.com/photo-1617196034796-73dfa7b1fd56?w=500&q=80",
        sushi2: "https://images.unsplash.com/photo-1611143669185-af224c5e3252?w=500&q=80",
        ramen: "https://images.unsplash.com/photo-1569718212165-3a8278d5f624?w=500&q=80",
        tacosHero: "https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=900&q=80",
        tacos1: "https://images.unsplash.com/photo-1551504734-5ee1c4a1479b?w=500&q=80",
        tacos2: "https://images.unsplash.com/photo-1599974579688-8dbdd335c77f?w=500&q=80",
        elote: "https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=500&q=80",
        bowlHero: "https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=900&q=80",
        bowl1: "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=500&q=80",
        bowl2: "https://images.unsplash.com/photo-1511690658105-ea6bfc6d5b45?w=500&q=80",
        juice: "https://images.unsplash.com/photo-1622597467836-f3285f2131b8?w=500&q=80",
        dessertHero: "https://images.unsplash.com/photo-1551024601-bec78aea704b?w=900&q=80",
        cookie: "https://images.unsplash.com/photo-1499636136210-6f4ee915583e?w=500&q=80",
        croissant: "https://images.unsplash.com/photo-1555507036-ab1f4038808a?w=500&q=80",
        latte: "https://images.unsplash.com/photo-1461023058943-07fcbe16d735?w=500&q=80",
        promo: "https://images.unsplash.com/photo-1414235077428-338989a2e8c0?w=1000&q=80",
        courier1: "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=200&q=80",
        courier2: "https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=200&q=80",
        courier3: "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=200&q=80"
    )

    static var deliveryPromoImageURL: String { food.promo }

    static let deliveryCategories: [(name: String, icon: String)] = [
        ("All", "square.grid.2x2"),
        ("Burgers", "flame"),
        ("Pizza", "circle.grid.cross"),
        ("Sushi", "fish"),
        ("Tacos", "triangle"),
        ("Healthy", "leaf"),
        ("Dessert", "birthday.cake"),
        ("Coffee", "cup.and.saucer"),
    ]

    static let deliveryRestaurants: [DeliveryRestaurant] = [
        DeliveryRestaurant(
            name: "Smash Bros Burgers", cuisine: "Burgers · American",
            rating: 4.8, reviews: "1,200+", etaMinutes: 20, feeLabel: "Free",
            imageURL: food.burgerHero,
            tags: ["Smash patties", "Milkshakes"], promo: "Free delivery",
            categories: ["Burgers"],
            menu: [
                DeliveryMenuSection(name: "Most ordered", items: [
                    DeliveryMenuItem(name: "Double Smash", detail: "Two patties, cheddar, house sauce, brioche",
                                     price: 8.90, imageURL: food.burger1, popular: true),
                    DeliveryMenuItem(name: "Truffle Smash", detail: "Truffle mayo, crispy onions, swiss",
                                     price: 10.50, imageURL: food.burger2, popular: true),
                ]),
                DeliveryMenuSection(name: "Sides & shakes", items: [
                    DeliveryMenuItem(name: "Loaded Fries", detail: "Cheese sauce, jalapeños, scallions",
                                     price: 4.50, imageURL: food.fries),
                    DeliveryMenuItem(name: "Vanilla Shake", detail: "Madagascar vanilla, whipped cream",
                                     price: 3.90, imageURL: food.shake),
                ]),
            ],
            latitude: 33.5793, longitude: -7.6030),
        DeliveryRestaurant(
            name: "Nonna's Slice House", cuisine: "Pizza · Italian",
            rating: 4.7, reviews: "860+", etaMinutes: 25, feeLabel: "$0.99",
            imageURL: food.pizzaHero,
            tags: ["Wood-fired", "Fresh mozzarella"], promo: "20% off",
            categories: ["Pizza"],
            menu: [
                DeliveryMenuSection(name: "Pizzas", items: [
                    DeliveryMenuItem(name: "Margherita DOP", detail: "San Marzano, fior di latte, basil",
                                     price: 9.80, imageURL: food.pizza1, popular: true),
                    DeliveryMenuItem(name: "Spicy Diavola", detail: "Calabrian salami, hot honey",
                                     price: 12.40, imageURL: food.pizza2),
                    DeliveryMenuItem(name: "Quattro Formaggi", detail: "Gorgonzola, taleggio, parm, mozzarella",
                                     price: 12.90, imageURL: food.pizza3),
                ]),
                DeliveryMenuSection(name: "Dolci", items: [
                    DeliveryMenuItem(name: "Tiramisu", detail: "Espresso-soaked savoiardi, mascarpone",
                                     price: 5.20, imageURL: food.tiramisu),
                ]),
            ],
            latitude: 33.5680, longitude: -7.6120),
        DeliveryRestaurant(
            name: "Kaiten Sushi Lab", cuisine: "Sushi · Japanese",
            rating: 4.9, reviews: "640+", etaMinutes: 30, feeLabel: "$1.49",
            imageURL: food.sushiHero,
            tags: ["Omakase boxes", "Fresh daily"],
            categories: ["Sushi", "Healthy"],
            menu: [
                DeliveryMenuSection(name: "Signature boxes", items: [
                    DeliveryMenuItem(name: "Salmon Lover Box", detail: "12 pcs — nigiri, maki, aburi",
                                     price: 15.90, imageURL: food.sushi1, popular: true),
                    DeliveryMenuItem(name: "Dragon Roll", detail: "Eel, avocado, tobiko",
                                     price: 11.20, imageURL: food.sushi2),
                ]),
                DeliveryMenuSection(name: "Warm", items: [
                    DeliveryMenuItem(name: "Miso Ramen", detail: "Chashu, soft egg, nori",
                                     price: 9.60, imageURL: food.ramen),
                ]),
            ],
            latitude: 33.5880, longitude: -7.6250),
        DeliveryRestaurant(
            name: "El Camión Tacos", cuisine: "Tacos · Mexican",
            rating: 4.6, reviews: "980+", etaMinutes: 15, feeLabel: "Free",
            imageURL: food.tacosHero,
            tags: ["Street style", "Homemade salsas"], promo: "Free delivery",
            categories: ["Tacos"],
            menu: [
                DeliveryMenuSection(name: "Tacos", items: [
                    DeliveryMenuItem(name: "Al Pastor x3", detail: "Trompo pork, pineapple, cilantro",
                                     price: 7.40, imageURL: food.tacos1, popular: true),
                    DeliveryMenuItem(name: "Baja Fish x3", detail: "Crispy fish, chipotle crema, slaw",
                                     price: 8.20, imageURL: food.tacos2),
                ]),
                DeliveryMenuSection(name: "Extras", items: [
                    DeliveryMenuItem(name: "Elote", detail: "Grilled corn, cotija, tajín",
                                     price: 3.80, imageURL: food.elote),
                ]),
            ],
            latitude: 33.5650, longitude: -7.5820),
        DeliveryRestaurant(
            name: "Green Bowl Kitchen", cuisine: "Healthy · Bowls",
            rating: 4.7, reviews: "410+", etaMinutes: 18, feeLabel: "$0.99",
            imageURL: food.bowlHero,
            tags: ["Macro-friendly", "Vegan options"],
            categories: ["Healthy"],
            menu: [
                DeliveryMenuSection(name: "Bowls", items: [
                    DeliveryMenuItem(name: "Teriyaki Chicken Bowl", detail: "Brown rice, edamame, sesame",
                                     price: 10.90, imageURL: food.bowl1, popular: true),
                    DeliveryMenuItem(name: "Falafel Power Bowl", detail: "Quinoa, hummus, pickled onion",
                                     price: 9.80, imageURL: food.bowl2),
                ]),
                DeliveryMenuSection(name: "Cold-pressed", items: [
                    DeliveryMenuItem(name: "Green Detox", detail: "Kale, apple, ginger, lemon",
                                     price: 4.90, imageURL: food.juice),
                ]),
            ],
            latitude: 33.5905, longitude: -7.6060),
        DeliveryRestaurant(
            name: "Sugar Rush Lab", cuisine: "Dessert · Bakery",
            rating: 4.8, reviews: "530+", etaMinutes: 22, feeLabel: "$1.49",
            imageURL: food.dessertHero,
            tags: ["Fresh-baked", "Ice cream"], promo: "Buy 2 get 1",
            categories: ["Dessert", "Coffee"],
            menu: [
                DeliveryMenuSection(name: "Sweet", items: [
                    DeliveryMenuItem(name: "Molten Cookie Skillet", detail: "Warm cookie, vanilla gelato",
                                     price: 6.50, imageURL: food.cookie, popular: true),
                    DeliveryMenuItem(name: "Pistachio Croissant", detail: "Twice-baked, pistachio cream",
                                     price: 4.20, imageURL: food.croissant),
                ]),
                DeliveryMenuSection(name: "Coffee", items: [
                    DeliveryMenuItem(name: "Iced Spanish Latte", detail: "Double shot, condensed milk",
                                     price: 3.60, imageURL: food.latte),
                ]),
            ],
            latitude: 33.5760, longitude: -7.5700),
    ]

    static func sampleCourier() -> DeliveryCourier {
        let couriers = [
            DeliveryCourier(name: "Yassine B.", rating: 4.94, deliveries: 2140,
                            vehicle: "Scooter · Yamaha",
                            avatarURL: food.courier1),
            DeliveryCourier(name: "Sara L.", rating: 4.88, deliveries: 1675,
                            vehicle: "E-bike",
                            avatarURL: food.courier2),
            DeliveryCourier(name: "Mehdi K.", rating: 4.97, deliveries: 3020,
                            vehicle: "Scooter · Honda",
                            avatarURL: food.courier3),
        ]
        return couriers.randomElement() ?? couriers[0]
    }
}
