import Foundation

/// A completed tennis match record
struct MatchLog: Codable, Identifiable {
    let id: UUID
    let date: Date
    let duration: TimeInterval          // seconds
    let locationName: String
    let playerA: String                  // team A player name(s)
    let playerB: String                  // team B player name(s)
    let sets: [(a: Int, b: Int)]         // completed sets
    let finalGames: (a: Int, b: Int)     // unfinished set games
    let totalPointsA: Int
    let totalPointsB: Int
    let outsA: Int                       // outs by team A
    let outsB: Int                       // outs by team B
    let totalOuts: Int                   // total outs

    // Codable support for tuples
    enum CodingKeys: String, CodingKey {
        case id, date, duration, locationName, playerA, playerB
        case setsA, setsB, finalGamesA, finalGamesB
        case totalPointsA, totalPointsB
        case outsA, outsB, totalOuts
    }

    init(id: UUID = UUID(), date: Date, duration: TimeInterval, locationName: String,
         playerA: String, playerB: String, sets: [(a: Int, b: Int)],
         finalGames: (a: Int, b: Int), totalPointsA: Int, totalPointsB: Int,
         outsA: Int = 0, outsB: Int = 0, totalOuts: Int = 0) {
        self.id = id
        self.date = date
        self.duration = duration
        self.locationName = locationName
        self.playerA = playerA
        self.playerB = playerB
        self.sets = sets
        self.finalGames = finalGames
        self.totalPointsA = totalPointsA
        self.totalPointsB = totalPointsB
        self.outsA = outsA
        self.outsB = outsB
        self.totalOuts = totalOuts
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        duration = try c.decode(TimeInterval.self, forKey: .duration)
        locationName = try c.decode(String.self, forKey: .locationName)
        playerA = try c.decode(String.self, forKey: .playerA)
        playerB = try c.decode(String.self, forKey: .playerB)
        let sA = try c.decode([Int].self, forKey: .setsA)
        let sB = try c.decode([Int].self, forKey: .setsB)
        sets = zip(sA, sB).map { (a: $0, b: $1) }
        let fA = try c.decode(Int.self, forKey: .finalGamesA)
        let fB = try c.decode(Int.self, forKey: .finalGamesB)
        finalGames = (a: fA, b: fB)
        totalPointsA = try c.decode(Int.self, forKey: .totalPointsA)
        totalPointsB = try c.decode(Int.self, forKey: .totalPointsB)
        // Backward compatible: outs may not exist in old data
        outsA = (try? c.decode(Int.self, forKey: .outsA)) ?? 0
        outsB = (try? c.decode(Int.self, forKey: .outsB)) ?? 0
        totalOuts = (try? c.decode(Int.self, forKey: .totalOuts)) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(date, forKey: .date)
        try c.encode(duration, forKey: .duration)
        try c.encode(locationName, forKey: .locationName)
        try c.encode(playerA, forKey: .playerA)
        try c.encode(playerB, forKey: .playerB)
        try c.encode(sets.map { $0.a }, forKey: .setsA)
        try c.encode(sets.map { $0.b }, forKey: .setsB)
        try c.encode(finalGames.a, forKey: .finalGamesA)
        try c.encode(finalGames.b, forKey: .finalGamesB)
        try c.encode(totalPointsA, forKey: .totalPointsA)
        try c.encode(totalPointsB, forKey: .totalPointsB)
        try c.encode(outsA, forKey: .outsA)
        try c.encode(outsB, forKey: .outsB)
        try c.encode(totalOuts, forKey: .totalOuts)
    }

    /// Human-readable score summary like "6-4  3-6  (2-1)"
    var scoreSummary: String {
        var parts = sets.map { "\($0.a)-\($0.b)" }
        if finalGames.a > 0 || finalGames.b > 0 {
            parts.append("(\(finalGames.a)-\(finalGames.b))")
        }
        return parts.joined(separator: "  ")
    }

    /// Winner name or "?" if unclear
    var winner: String {
        let setsWonA = sets.filter { $0.a > $0.b }.count
        let setsWonB = sets.filter { $0.b > $0.a }.count
        if setsWonA > setsWonB { return playerA.isEmpty ? "A" : playerA }
        if setsWonB > setsWonA { return playerB.isEmpty ? "B" : playerB }
        return "?"
    }

    /// Duration formatted as "1h 23m" or "45m"
    var durationText: String {
        let mins = Int(duration) / 60
        if mins >= 60 {
            return "\(mins / 60)h \(mins % 60)m"
        }
        return "\(mins)m"
    }

    /// Out summary text
    var outsSummary: String {
        if totalOuts == 0 { return "" }
        if outsA > 0 || outsB > 0 {
            return "Out: A:\(outsA) B:\(outsB)"
        }
        return "Out: \(totalOuts)"
    }
}

/// Persists match history to UserDefaults
class MatchHistory {
    private static let key = "tennis_match_history"

    static func load() -> [MatchLog] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let logs = try? JSONDecoder().decode([MatchLog].self, from: data) else {
            return []
        }
        return logs.sorted { $0.date > $1.date }
    }

    static func save(_ log: MatchLog) {
        var all = load()
        all.insert(log, at: 0)
        // Keep max 50 matches
        if all.count > 50 { all = Array(all.prefix(50)) }
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func delete(_ id: UUID) {
        var all = load()
        all.removeAll { $0.id == id }
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
