import SwiftUI

enum SampleData {

    static let g1 = [Color(hex: "26303F"), Color(hex: "141821")]
    static let g2 = [Color(hex: "3d3546"), Color(hex: "191420")]
    static let g3 = [Color(hex: "2d4038"), Color(hex: "131c17")]
    static let g4 = [Color(hex: "40352c"), Color(hex: "1c1712")]
    static let g5 = [Color(hex: "203040"), Color(hex: "101820")]
    static let gBlue = [Color(hex: "182030"), Color(hex: "0B0E14")]
    static let gViolet = [Color(hex: "20182a"), Color(hex: "100b16")]

    // MARK: Stories — several people have multiple frames
    static let stories: [Story] = [
        Story(name: "You", letter: "J", gradient: g1, isYou: true),
        Story(name: "marta", letter: "M", gradient: g2, frames: [
            StoryFrame(imageURL: "https://picsum.photos/seed/story-marta-1/900/1600"),
            StoryFrame(imageURL: "https://picsum.photos/seed/story-marta-2/900/1600"),
            StoryFrame(imageURL: "https://picsum.photos/seed/story-marta-3/900/1600"),
        ]),
        Story(name: "kal.eb", letter: "K", gradient: g3, frames: [
            StoryFrame(imageURL: "https://picsum.photos/seed/story-kaleb-1/900/1600"),
            StoryFrame(imageURL: "https://picsum.photos/seed/story-kaleb-2/900/1600"),
        ]),
        Story(name: "sena", letter: "S", gradient: g4, frames: [
            StoryFrame(imageURL: "https://picsum.photos/seed/story-sena/900/1600", seen: true),
        ]),
        Story(name: "dani", letter: "D", gradient: g5, frames: [
            StoryFrame(imageURL: "https://picsum.photos/seed/story-dani-1/900/1600"),
            StoryFrame(imageURL: "https://picsum.photos/seed/story-dani-2/900/1600"),
            StoryFrame(imageURL: "https://picsum.photos/seed/story-dani-3/900/1600"),
            StoryFrame(imageURL: "https://picsum.photos/seed/story-dani-4/900/1600"),
        ]),
        Story(name: "omar", letter: "O", gradient: gBlue, frames: [
            StoryFrame(imageURL: "https://picsum.photos/seed/story-omar/900/1600"),
        ]),
        Story(name: "lea", letter: "L", gradient: gViolet, frames: [
            StoryFrame(imageURL: "https://picsum.photos/seed/story-lea-1/900/1600"),
            StoryFrame(imageURL: "https://picsum.photos/seed/story-lea-2/900/1600"),
        ]),
        Story(name: "theo", letter: "T", gradient: g3, frames: [
            StoryFrame(imageURL: "https://picsum.photos/seed/story-theo/900/1600", seen: true),
        ]),
        Story(name: "nia", letter: "N", gradient: g2, frames: [
            StoryFrame(imageURL: "https://picsum.photos/seed/story-nia-1/900/1600"),
            StoryFrame(imageURL: "https://picsum.photos/seed/story-nia-2/900/1600"),
        ]),
        Story(name: "rex", letter: "R", gradient: g4, frames: [
            StoryFrame(imageURL: "https://picsum.photos/seed/story-rex/900/1600"),
        ]),
        Story(name: "ava", letter: "A", gradient: g5, frames: [
            StoryFrame(imageURL: "https://picsum.photos/seed/story-ava/900/1600", seen: true),
        ]),
        Story(name: "juin", letter: "J", gradient: gBlue, frames: [
            StoryFrame(imageURL: "https://picsum.photos/seed/story-juin-1/900/1600"),
            StoryFrame(imageURL: "https://picsum.photos/seed/story-juin-2/900/1600"),
            StoryFrame(imageURL: "https://picsum.photos/seed/story-juin-3/900/1600"),
        ]),
    ]

    // MARK: Posts
    static let posts: [Post] = [
        Post(author: "marta.st", meta: "channel · 2h",
             avatarGradient: g2,
             avatarURL: "https://picsum.photos/seed/av-marta/200/200",
             imageURL: "https://picsum.photos/seed/post-marta/1200/900",
             imageAspect: 0.75, text: "Morning light in the field — dog insisted on co-starring.",
             likeCount: 248, commentCount: 3),
        Post(author: "kal.eb", meta: "channel · 4h",
             avatarGradient: g3,
             avatarURL: "https://picsum.photos/seed/av-kaleb/200/200",
             text: "Shipped the first prototype of the drone mapper today. Three months of weekends. Worth it.",
             likeCount: 512, commentCount: 2),
        Post(author: "sena.films", meta: "channel · 6h",
             avatarGradient: g4,
             avatarURL: "https://picsum.photos/seed/av-sena/200/200",
             imageURL: "https://picsum.photos/seed/post-sena/1400/800",
             imageAspect: 0.57,
             text: "Golden hour on the last day of the shoot.",
             showFollow: true, likeCount: 1840, commentCount: 4),
        Post(author: "nia.studio", meta: "channel · 9h",
             avatarGradient: g5,
             avatarURL: "https://picsum.photos/seed/av-nia/200/200",
             imageURL: "https://picsum.photos/seed/post-nia/1200/1200",
             imageAspect: 1.0,
             text: "Clay still drying. Patience is the whole craft.",
             showFollow: true, likeCount: 926, commentCount: 2),
        Post(author: "omar.labs", meta: "channel · 12h",
             avatarGradient: gBlue,
             avatarURL: "https://picsum.photos/seed/av-omar/200/200",
             text: "Night market tip: follow the steam, not the neon.",
             likeCount: 301, commentCount: 1),
    ]

    /// Posts seeded as the signed-in user (handle remapped in AppState.init).
    static func ownSeedPosts(handle: String, name: String, avatarURL: String?,
                             avatarGradient: [Color]) -> [Post] {
        [
            Post(author: handle, meta: "channel · just now",
                 avatarGradient: avatarGradient, avatarURL: avatarURL,
                 imageURL: "https://picsum.photos/seed/own-post-1-\(handle)/1200/1200",
                 imageAspect: 1.0,
                 text: "First frames on gojogo — more coming.",
                 likeCount: 12, commentCount: 0),
            Post(author: handle, meta: "channel · 1d",
                 avatarGradient: avatarGradient, avatarURL: avatarURL,
                 imageURL: "https://picsum.photos/seed/own-post-2-\(handle)/1200/900",
                 imageAspect: 0.75,
                 text: "Studio light tests. Saving the ones that stay.",
                 likeCount: 48, commentCount: 1),
            Post(author: handle, meta: "channel · 3d",
                 avatarGradient: avatarGradient, avatarURL: avatarURL,
                 text: "Building in public. Notes later.",
                 likeCount: 27, commentCount: 0),
        ]
    }

    // Public sample MP4s — Google gtv-videos-bucket now 403s; use W3C / MDN / sample hosts.
    private static let videoBigBuck = "https://www.w3schools.com/html/mov_bbb.mp4"
    private static let videoElephants = "https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4"
    private static let videoSintel = "https://media.w3.org/2010/05/sintel/trailer.mp4"
    private static let videoTears = "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4"

    /// Remap known-dead CDN URLs (cached sessions may still hold them).
    static func repairedVideoURL(_ url: String?) -> String? {
        guard let url, !url.isEmpty else { return url }
        if url.contains("gtv-videos-bucket") || url.contains("commondatastorage.googleapis.com") {
            if url.localizedCaseInsensitiveContains("Elephant") { return videoElephants }
            if url.localizedCaseInsensitiveContains("Sintel") { return videoSintel }
            if url.localizedCaseInsensitiveContains("Tears") { return videoTears }
            return videoBigBuck
        }
        return url
    }

    // MARK: Long-form videos
    static let videos: [VideoItem] = [
        VideoItem(title: "Why LLMs need tools — a field guide",
                  channel: "signal.lab", meta: "signal.lab · 214K views · 2d",
                  duration: "9:56", thumbGradient: gBlue,
                  thumbURL: "https://picsum.photos/seed/vid-llm/1280/720",
                  videoURL: videoBigBuck, likes: 4200),
        VideoItem(title: "The quiet economics of night markets",
                  channel: "marta.st", meta: "marta.st · 88K views · 5d",
                  duration: "10:53", thumbGradient: gViolet,
                  thumbURL: "https://picsum.photos/seed/vid-markets/1280/720",
                  videoURL: videoElephants, likes: 2100),
        VideoItem(title: "Building a camera from spare parts",
                  channel: "kal.eb", meta: "kal.eb · 41K views · 1w",
                  duration: "14:47", thumbGradient: g3,
                  thumbURL: "https://picsum.photos/seed/vid-camera/1280/720",
                  videoURL: videoSintel, likes: 980),
        VideoItem(title: "Frame rates that feel like film",
                  channel: "sena.films", meta: "sena.films · 62K views · 3d",
                  duration: "12:14", thumbGradient: g4,
                  thumbURL: "https://picsum.photos/seed/vid-film/1280/720",
                  videoURL: videoTears, likes: 1560),
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
              imageURL: "https://picsum.photos/seed/short-marta/900/1600",
              videoURL: videoBigBuck, likeCount: 84_200),
        Short(channel: "kal.eb", subscribers: "channel · 640K",
              caption: "Drone mapper first flight. It actually works.",
              gradient: [Color(hex: "241a2e"), Color(hex: "090711")],
              imageURL: "https://picsum.photos/seed/short-kaleb/900/1600",
              videoURL: videoElephants, likeCount: 31_400),
        Short(channel: "sena.films", subscribers: "channel · 2.4M",
              caption: "Golden hour, no color grade. Straight off the sensor.",
              gradient: [Color(hex: "2a2018"), Color(hex: "0d0906")],
              imageURL: "https://picsum.photos/seed/short-sena/900/1600",
              videoURL: videoSintel, likeCount: 120_800),
    ]

    // MARK: Economy
    static let economyCategories = ["All", "Phones", "Cameras", "Fashion", "Home", "Sports"]

    static let featuredProduct = Product(
        name: "iPhone 13 · 128GB", price: "$275",
        meta: "Battery 91% · verified seller · 2.1 km away",
        gradient: [Color(hex: "1c222e"), Color(hex: "0d1016")],
        imageURL: "https://picsum.photos/seed/prod-iphone/600/600",
        category: "Phones", seller: "mira.tech", condition: "Excellent",
        distance: "2.1 km",
        description: "Unlocked iPhone 13, battery health 91%. Original box + cable. Small scuff on the frame — happy to FaceTime for a walkthrough.")

    static let products: [Product] = [
        Product(name: "Keycaps · PBT set", price: "$24",
                meta: "Like new · 0.8 km",
                gradient: [Color(hex: "242030"), Color(hex: "100e16")],
                imageURL: "https://picsum.photos/seed/prod-keys/400/400",
                category: "Home", seller: "desk.lab", condition: "Like new", distance: "0.8 km"),
        Product(name: "Film cam · Contax", price: "$110",
                meta: "Good · 1.4 km",
                gradient: [Color(hex: "20302a"), Color(hex: "0e1612")],
                imageURL: "https://picsum.photos/seed/prod-cam/400/400",
                category: "Cameras", seller: "sena.films", condition: "Good", distance: "1.4 km",
                description: "Contax T2 body. Light seals replaced. Comes with strap and half a roll of Portra."),
        Product(name: "Chelsea boots", price: "$68",
                meta: "Size 42 · 3.2 km",
                gradient: [Color(hex: "302420"), Color(hex: "160f0d")],
                imageURL: "https://picsum.photos/seed/prod-boots/400/400",
                category: "Fashion", seller: "lea.style", condition: "Good", distance: "3.2 km"),
        Product(name: "Desk lamp", price: "$39",
                meta: "Warm LED · 1.1 km",
                gradient: [Color(hex: "1e2836"), Color(hex: "0d1218")],
                imageURL: "https://picsum.photos/seed/prod-lamp/400/400",
                category: "Home", seller: "kal.eb", condition: "Like new", distance: "1.1 km"),
        Product(name: "Pixel 7a", price: "$220",
                meta: "128GB · unlocked · 4 km",
                gradient: [Color(hex: "1a2430"), Color(hex: "0c1016")],
                imageURL: "https://picsum.photos/seed/prod-pixel/400/400",
                category: "Phones", seller: "omar.gears", condition: "Excellent", distance: "4.0 km"),
        Product(name: "Yoga mat · cork", price: "$32",
                meta: "Barely used · 2.6 km",
                gradient: [Color(hex: "203028"), Color(hex: "0e1612")],
                imageURL: "https://picsum.photos/seed/prod-yoga/400/400",
                category: "Sports", seller: "nia.move", condition: "Like new", distance: "2.6 km"),
        Product(name: "Vintage denim", price: "$45",
                meta: "M · soft wash · 1.9 km",
                gradient: [Color(hex: "242830"), Color(hex: "101418")],
                imageURL: "https://picsum.photos/seed/prod-denim/400/400",
                category: "Fashion", seller: "theo.fit", condition: "Good", distance: "1.9 km"),
        Product(name: "Sony a6400 body", price: "$480",
                meta: "Shutter 12k · 5.1 km",
                gradient: [Color(hex: "2a2030"), Color(hex: "120e18")],
                imageURL: "https://picsum.photos/seed/prod-sony/400/400",
                category: "Cameras", seller: "marta.st", condition: "Excellent", distance: "5.1 km",
                description: "Body only. Two batteries + charger. No dents. Receipt available."),
    ]

    // MARK: Search
    static let people: [PersonSuggestion] = [
        PersonSuggestion(name: "dani", gradient: g1, avatarURL: "https://picsum.photos/seed/p-dani/120/120"),
        PersonSuggestion(name: "omar", gradient: g2, avatarURL: "https://picsum.photos/seed/p-omar/120/120"),
        PersonSuggestion(name: "lea", gradient: g3, avatarURL: "https://picsum.photos/seed/p-lea/120/120"),
        PersonSuggestion(name: "theo", gradient: g4, avatarURL: "https://picsum.photos/seed/p-theo/120/120"),
        PersonSuggestion(name: "nia", gradient: g5, avatarURL: "https://picsum.photos/seed/p-nia/120/120"),
    ]

    static let searchContent: [TVTile] = [
        TVTile(title: "Sunday league", gradient: gBlue,
               imageURL: "https://picsum.photos/seed/search-league/600/400"),
        TVTile(title: "5-a-side near you", gradient: gViolet,
               imageURL: "https://picsum.photos/seed/search-5aside/600/400"),
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
        "https://picsum.photos/seed/pg1/400/400",
        "https://picsum.photos/seed/pg2/400/400",
        "https://picsum.photos/seed/pg3/400/400",
        "https://picsum.photos/seed/pg4/400/400",
        "https://picsum.photos/seed/pg5/400/400",
        "https://picsum.photos/seed/pg6/400/400",
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
}
