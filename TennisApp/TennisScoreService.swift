import Foundation

// MARK: - Models

struct LiveTournament: Identifiable, Hashable {
    let id: Int
    let name: String
    let category: String  // "ATP", "WTA", "ITF" etc.
}

enum LiveMatchStatus: String {
    case notStarted = "notstarted"
    case live = "inprogress"
    case finished = "finished"
    case interrupted = "interrupted"
    case cancelled = "cancelled"
}

struct LiveMatch: Identifiable {
    let id: Int
    let tournament: LiveTournament
    let round: String
    let player1: String
    let player2: String
    let sets: [(p1: Int, p2: Int)]     // completed + current set scores
    let currentGame: String?           // e.g. "40-30" during live
    let setsWon1: Int
    let setsWon2: Int
    let status: LiveMatchStatus
    let startTime: Date?
    let isServingFirst: Bool?          // true = player1 serving

    var statusText: String {
        switch status {
        case .live: return L.isTurkish ? "🔴 Canlı" : "🔴 Live"
        case .finished: return L.isTurkish ? "✅ Bitti" : "✅ Finished"
        case .notStarted:
            if let time = startTime {
                let fmt = DateFormatter()
                fmt.dateFormat = "HH:mm"
                return fmt.string(from: time)
            }
            return L.isTurkish ? "⏳ Başlamadı" : "⏳ Upcoming"
        case .interrupted: return L.isTurkish ? "⏸ Durduruldu" : "⏸ Interrupted"
        case .cancelled: return L.isTurkish ? "❌ İptal" : "❌ Cancelled"
        }
    }

    var scoreSummary: String {
        sets.map { "\($0.p1)-\($0.p2)" }.joined(separator: "  ")
    }
}

// MARK: - Service

@MainActor
class TennisScoreService: ObservableObject {

    @Published var matchesByTournament: [(tournament: LiveTournament, matches: [LiveMatch])] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    /// Fetch today's tennis events from SofaScore API
    func fetchTodaysMatches() async {
        isLoading = true
        errorMessage = nil

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let today = dateFormatter.string(from: Date())

        let urlString = "https://api.sofascore.com/api/v1/sport/tennis/scheduled-events/\(today)"

        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                errorMessage = "HTTP \(code)"
                isLoading = false
                return
            }

            let parsed = try parseEvents(data)
            matchesByTournament = parsed
            lastUpdated = Date()

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Parse SofaScore Response

    private func parseEvents(_ data: Data) throws -> [(tournament: LiveTournament, matches: [LiveMatch])] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = json["events"] as? [[String: Any]] else {
            return []
        }

        var tournamentMap: [Int: (tournament: LiveTournament, matches: [LiveMatch])] = [:]

        for event in events {
            guard let eventId = event["id"] as? Int else { continue }

            // Tournament info
            let tournamentDict = event["tournament"] as? [String: Any] ?? [:]
            let tournamentId = tournamentDict["uniqueTournament"] as? [String: Any]
            let tId = (tournamentId?["id"] as? Int) ?? (tournamentDict["id"] as? Int) ?? 0
            let tName = (tournamentDict["name"] as? String) ?? "Unknown"
            let categoryDict = tournamentDict["category"] as? [String: Any] ?? [:]
            let catName = (categoryDict["name"] as? String) ?? ""

            let tournament = LiveTournament(id: tId, name: tName, category: catName)

            // Players
            let home = event["homeTeam"] as? [String: Any] ?? [:]
            let away = event["awayTeam"] as? [String: Any] ?? [:]
            let player1 = (home["name"] as? String) ?? "TBD"
            let player2 = (away["name"] as? String) ?? "TBD"

            // Round
            let roundInfo = event["roundInfo"] as? [String: Any]
            let round = (roundInfo?["name"] as? String) ?? ""

            // Status
            let statusDict = event["status"] as? [String: Any] ?? [:]
            let statusType = (statusDict["type"] as? String) ?? "notstarted"
            let matchStatus: LiveMatchStatus
            switch statusType {
            case "inprogress": matchStatus = .live
            case "finished": matchStatus = .finished
            case "cancelled": matchStatus = .cancelled
            default: matchStatus = .notStarted
            }

            // Start time
            var startTime: Date?
            if let ts = event["startTimestamp"] as? TimeInterval {
                startTime = Date(timeIntervalSince1970: ts)
            }

            // Scores
            let homeScore = event["homeScore"] as? [String: Any] ?? [:]
            let awayScore = event["awayScore"] as? [String: Any] ?? [:]

            var sets: [(p1: Int, p2: Int)] = []
            for period in ["period1", "period2", "period3", "period4", "period5"] {
                if let p1 = homeScore[period] as? Int,
                   let p2 = awayScore[period] as? Int {
                    sets.append((p1: p1, p2: p2))
                }
            }

            let setsWon1 = (homeScore["current"] as? Int) ?? 0
            let setsWon2 = (awayScore["current"] as? Int) ?? 0

            // Current game score
            var currentGame: String?
            if let p1Game = homeScore["point"] as? String,
               let p2Game = awayScore["point"] as? String {
                currentGame = "\(p1Game)-\(p2Game)"
            }

            // Serving info (not reliably available)
            let isServingFirst: Bool? = nil

            let match = LiveMatch(
                id: eventId,
                tournament: tournament,
                round: round,
                player1: player1,
                player2: player2,
                sets: sets,
                currentGame: currentGame,
                setsWon1: setsWon1,
                setsWon2: setsWon2,
                status: matchStatus,
                startTime: startTime,
                isServingFirst: isServingFirst
            )

            if var existing = tournamentMap[tId] {
                existing.matches.append(match)
                tournamentMap[tId] = existing
            } else {
                tournamentMap[tId] = (tournament: tournament, matches: [match])
            }
        }

        // Sort: tournaments with live matches first, then by name
        return tournamentMap.values.sorted { a, b in
            let aHasLive = a.matches.contains { $0.status == .live }
            let bHasLive = b.matches.contains { $0.status == .live }
            if aHasLive != bHasLive { return aHasLive }
            return a.tournament.name < b.tournament.name
        }.map { group in
            // Sort matches within tournament: live first, then by time
            let sorted = group.matches.sorted { a, b in
                let order: [LiveMatchStatus] = [.live, .finished, .notStarted, .interrupted, .cancelled]
                let ai = order.firstIndex(of: a.status) ?? 9
                let bi = order.firstIndex(of: b.status) ?? 9
                if ai != bi { return ai < bi }
                return (a.startTime ?? .distantFuture) < (b.startTime ?? .distantFuture)
            }
            return (tournament: group.tournament, matches: sorted)
        }
    }
}
