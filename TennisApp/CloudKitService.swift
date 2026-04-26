import Foundation
import CloudKit
import CoreLocation

/// Shares match results to CloudKit public database so other TennisWatch users can see them
@MainActor
class CloudKitService: ObservableObject {

    static let shared = CloudKitService()

    @Published var communityMatches: [CommunityMatch] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let container = CKContainer(identifier: "iCloud.com.tennis.app")
    private var publicDB: CKDatabase { container.publicCloudDatabase }

    private let recordType = "TennisMatch"

    // Unique device ID (anonymous, no account needed)
    private var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: "tenniswatch_device_id") {
            return id
        }
        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: "tenniswatch_device_id")
        return newID
    }

    // MARK: - Upload Match

    /// Upload a completed match to CloudKit public database
    func uploadMatch(_ match: MatchLog) {
        let record = CKRecord(recordType: recordType)
        record["playerA"] = match.playerA as CKRecordValue
        record["playerB"] = match.playerB as CKRecordValue
        record["scoreSummary"] = match.scoreSummary as CKRecordValue
        record["setsA"] = match.sets.map { $0.a } as CKRecordValue
        record["setsB"] = match.sets.map { $0.b } as CKRecordValue
        record["duration"] = match.duration as CKRecordValue
        record["locationName"] = match.locationName as CKRecordValue
        record["date"] = match.date as CKRecordValue
        record["deviceID"] = deviceID as CKRecordValue
        record["matchID"] = match.id.uuidString as CKRecordValue
        record["winner"] = match.winner as CKRecordValue
        record["durationText"] = match.durationText as CKRecordValue

        publicDB.save(record) { savedRecord, error in
            if let error = error {
                print("☁️ CloudKit upload error: \(error.localizedDescription)")
            } else {
                print("☁️ CloudKit: Match uploaded successfully")
            }
        }
    }

    // MARK: - Fetch Community Matches

    /// Fetch recent matches from all TennisWatch users (last 24h)
    func fetchCommunityMatches() async {
        isLoading = true
        errorMessage = nil

        // Fetch matches from last 7 days
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let predicate = NSPredicate(format: "date > %@", sevenDaysAgo as NSDate)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]

        do {
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 100)

            var matches: [CommunityMatch] = []

            for (_, result) in results {
                switch result {
                case .success(let record):
                    if let match = parseCommunityMatch(from: record) {
                        matches.append(match)
                    }
                case .failure(let error):
                    print("☁️ CloudKit record error: \(error)")
                }
            }

            // Show ALL matches (shared pool - own + others)
            communityMatches = matches
            print("☁️ CloudKit: Fetched \(communityMatches.count) community matches")

        } catch {
            print("☁️ CloudKit fetch error: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Parse Record

    private func parseCommunityMatch(from record: CKRecord) -> CommunityMatch? {
        guard let playerA = record["playerA"] as? String,
              let playerB = record["playerB"] as? String,
              let scoreSummary = record["scoreSummary"] as? String,
              let date = record["date"] as? Date,
              let deviceID = record["deviceID"] as? String else {
            return nil
        }

        let setsA = record["setsA"] as? [Int] ?? []
        let setsB = record["setsB"] as? [Int] ?? []
        let sets = zip(setsA, setsB).map { (a: $0, b: $1) }

        return CommunityMatch(
            id: record.recordID.recordName,
            playerA: playerA,
            playerB: playerB,
            scoreSummary: scoreSummary,
            sets: sets,
            duration: record["duration"] as? TimeInterval ?? 0,
            durationText: record["durationText"] as? String ?? "",
            locationName: record["locationName"] as? String ?? "",
            date: date,
            winner: record["winner"] as? String ?? "?",
            deviceID: deviceID
        )
    }
}

// MARK: - Community Match Model

struct CommunityMatch: Identifiable {
    let id: String
    let playerA: String
    let playerB: String
    let scoreSummary: String
    let sets: [(a: Int, b: Int)]
    let duration: TimeInterval
    let durationText: String
    let locationName: String
    let date: Date
    let winner: String
    let deviceID: String

    var timeAgo: String {
        let interval = Date().timeIntervalSince(date)
        let minutes = Int(interval) / 60
        if minutes < 60 {
            return L.isTurkish ? "\(minutes)dk önce" : "\(minutes)m ago"
        }
        let hours = minutes / 60
        if hours < 24 {
            return L.isTurkish ? "\(hours)sa önce" : "\(hours)h ago"
        }
        let days = hours / 24
        return L.isTurkish ? "\(days)gün önce" : "\(days)d ago"
    }
}
