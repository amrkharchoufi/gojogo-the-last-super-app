import SwiftUI

/// Shared gradients, onboarding chips, and generators.
/// Feed / marketplace / social content starts empty — no mock media.
enum SampleData {

    static let g1 = [Color(hex: "26303F"), Color(hex: "141821")]
    static let g2 = [Color(hex: "3d3546"), Color(hex: "191420")]
    static let g3 = [Color(hex: "2d4038"), Color(hex: "131c17")]
    static let g4 = [Color(hex: "40352c"), Color(hex: "1c1712")]
    static let g5 = [Color(hex: "203040"), Color(hex: "101820")]
    static let gBlue = [Color(hex: "182030"), Color(hex: "0B0E14")]
    static let gViolet = [Color(hex: "20182a"), Color(hex: "100b16")]

    /// No bundled sample photos remain.
    static let allSampleMedia: [String] = []
    /// No bundled sample clips remain.
    static let allSampleClips: [String] = []

    // MARK: Stories

    static let stories: [Story] = [
        Story(name: "You", letter: "J", gradient: g1, isYou: true),
    ]

    // MARK: Feed / Watch / Activity

    static let posts: [Post] = []
    static let notifications: [ActivityItem] = []
    static let videos: [VideoItem] = []
    static let shorts: [Short] = []
    static let defaultComments: [Comment] = []
    static let watchingChat: [ChatMessage] = []

    static func ownSeedPosts(handle: String, name: String, avatarURL: String?,
                             avatarGradient: [Color]) -> [Post] {
        []
    }

    static func seedComments(for posts: [Post]) -> [UUID: [Comment]] {
        [:]
    }

    /// Drop known-dead CDN URLs; no bundled clip remapping.
    static func repairedVideoURL(_ url: String?) -> String? {
        guard let url, !url.isEmpty else { return url }
        if url.contains("gtv-videos-bucket") || url.contains("commondatastorage.googleapis.com")
            || url.contains("w3schools.com") || url.contains("mozilla.net")
            || url.contains("media.w3.org") || url.contains("test-videos.co.uk") {
            return nil
        }
        return url
    }

    // MARK: Profile Home

    static let homeMediaLibrary: [ProfileHomeMedia] = []

    static func randomProfileHome(handle: String, posts: [Post]) -> [ProfileHomeBlock] {
        []
    }

    // MARK: Economy

    static let economyCategories = ["All", "Phones", "Cameras", "Fashion", "Home", "Sports"]

    /// Placeholder until the user lists something — views ignore empty names.
    static let featuredProduct = Product(name: "", price: "", gradient: g1)

    static let products: [Product] = []

    // MARK: Search / TV / Profile grid

    static let people: [PersonSuggestion] = []
    static let searchContent: [TVTile] = []

    static let tvHero = TVShow(
        title: "", subtitle: "", synopsis: "", badge: "", gradient: g1)

    static let tvShows: [TVShow] = []

    static var tvTop10: [TVPoster] { [] }
    static var tvFamily: [TVTile] { [] }
    static var tvDocs: [TVTile] { [] }
    static var tvContinue: [TVShow] { [] }

    static let profileGridURLs: [String] = []

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

    // MARK: Interests (onboarding)

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

    // MARK: GojoTravel

    static let travelDefaultCenter = TravelPlace(
        name: "Current location",
        subtitle: "Near you",
        latitude: 37.7749,
        longitude: -122.4194,
        icon: "location.fill"
    )

    static let travelRecentPlaces: [TravelPlace] = []
    static let travelSuggestions: [TravelPlace] = []

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
            avatarURL: nil,
            latitude: pickup.latitude + Double.random(in: -0.012...0.012),
            longitude: pickup.longitude + Double.random(in: -0.012...0.012)
        )
    }

    // MARK: Partner jobs

    private static let partnerCustomers: [String] = [
        "Marta", "Kaleb", "Sena", "Dani", "Omar", "Lea", "Nadia", "Yassine", "Théo",
    ]

    private static let driverPlaces: [(String, String)] = [
        ("Marina Bay", "Corniche"), ("Old Medina", "Bab Marrakech"),
        ("Twin Center", "Maârif"), ("Anfa Place", "Boulevard de la Corniche"),
        ("Gare Casa-Port", "Downtown"), ("Morocco Mall", "Aïn Diab"),
        ("Airport Mohammed V", "Nouaceur"), ("Habous Quarter", "New Medina"),
    ]

    private static let courierRestaurants: [String] = [
        "Café Atlas", "Sushi Corner", "La Sqala", "Pizza Milano",
        "Green Bowl", "Rick's Café", "Burger Yard", "Le Cabestan",
    ]

    private static let courierDropoffs: [(String, String)] = [
        ("Home", "12 Rue Atlas"), ("Office", "Twin Center, Tower A"),
        ("Résidence Al Manar", "Apt 4B"), ("14 Bd Zerktouni", "3rd floor"),
        ("Villa Anfa", "Gate 2"), ("Studio Maârif", "Rue de Paris"),
    ]

    static func samplePartnerJob(role: PartnerRole) -> PartnerJob {
        let name = partnerCustomers.randomElement()!
        let cLat = 33.5731, cLon = -7.5898
        func jitter(_ base: Double, _ spread: Double) -> Double {
            base + Double.random(in: -spread...spread)
        }
        let pLat = jitter(cLat, 0.02), pLon = jitter(cLon, 0.025)
        let dLat = jitter(cLat, 0.02), dLon = jitter(cLon, 0.025)
        let oLat = pLat + Double.random(in: -0.008...0.008)
        let oLon = pLon + Double.random(in: -0.008...0.008)

        switch role {
        case .driver:
            let pickup = driverPlaces.randomElement()!
            var dropoff = driverPlaces.randomElement()!
            while dropoff == pickup { dropoff = driverPlaces.randomElement()! }
            let km = Double.random(in: 2.4...14.5)
            return PartnerJob(
                role: .driver, customerName: name,
                pickupName: pickup.0, pickupSubtitle: pickup.1,
                dropoffName: dropoff.0, dropoffSubtitle: dropoff.1,
                distanceKm: km, minutes: Int((km * 2.4).rounded()) + 3,
                fare: (km * 1.35 + 2.5).rounded() + 0.5,
                customerAvatarURL: nil,
                originLat: oLat, originLon: oLon,
                pickupLat: pLat, pickupLon: pLon,
                dropoffLat: dLat, dropoffLon: dLon)
        case .courier:
            let restaurant = courierRestaurants.randomElement()!
            let drop = courierDropoffs.randomElement()!
            let km = Double.random(in: 0.9...6.2)
            return PartnerJob(
                role: .courier, customerName: name,
                pickupName: restaurant, pickupSubtitle: "Ready in 5 min",
                dropoffName: drop.0, dropoffSubtitle: drop.1,
                distanceKm: km, minutes: Int((km * 2.6).rounded()) + 4,
                fare: (km * 0.9 + 2.2).rounded() + 0.5,
                customerAvatarURL: nil,
                originLat: oLat, originLon: oLon,
                pickupLat: pLat, pickupLon: pLon,
                dropoffLat: dLat, dropoffLon: dLon)
        }
    }

    // MARK: My World

    static let worldContacts: [WorldContact] = []
    static let worldCircles: [WorldCircle] = []
    static let worldConversations: [WorldConversation] = []

    // MARK: Delivery

    static var deliveryPromoImageURL: String? { nil }

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

    static let deliveryRestaurants: [DeliveryRestaurant] = []

    static func sampleCourier() -> DeliveryCourier {
        let couriers = [
            DeliveryCourier(name: "Yassine B.", rating: 4.94, deliveries: 2140,
                            vehicle: "Scooter · Yamaha", avatarURL: nil),
            DeliveryCourier(name: "Sara L.", rating: 4.88, deliveries: 1675,
                            vehicle: "E-bike", avatarURL: nil),
            DeliveryCourier(name: "Mehdi K.", rating: 4.97, deliveries: 3020,
                            vehicle: "Scooter · Honda", avatarURL: nil),
            DeliveryCourier(name: "Amine T.", rating: 4.91, deliveries: 890,
                            vehicle: "On feet", avatarURL: nil),
        ]
        return couriers.randomElement() ?? couriers[0]
    }
}
