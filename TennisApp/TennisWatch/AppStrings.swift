import Foundation

/// Simple localization helper — Turkish if device is Turkish, English otherwise
enum L {
    static var isTurkish: Bool {
        Locale.current.language.languageCode?.identifier == "tr"
    }

    // MARK: - Match History View (shared)
    static var myMatches: String { isTurkish ? "Maçlarım" : "My Matches" }
    static var noMatchesYet: String { isTurkish ? "Henüz maç yok" : "No matches yet" }
    static var matchesWillAppear: String {
        isTurkish
            ? "Apple Watch'tan maç bittiğinde\nburaya otomatik gelecek"
            : "Matches will appear here\nautomatically from Apple Watch"
    }
    static func matchCount(_ n: Int) -> String {
        isTurkish ? "\(n) maç" : "\(n) matches"
    }
    static var deleteMatch: String { isTurkish ? "Maçı Sil?" : "Delete Match?" }
    static var delete: String { isTurkish ? "Sil" : "Delete" }
    static var cancel: String { isTurkish ? "İptal" : "Cancel" }
    static var share: String { isTurkish ? "Paylaş" : "Share" }
    static var winner: String { isTurkish ? "Kazanan" : "Winner" }
    static var ongoing: String { isTurkish ? "Devam" : "Ongoing" }
    static var ongoingShort: String { isTurkish ? "Dev:" : "Ong:" }

    // MARK: - Watch ContentView
    static var changeCourtBang: String { isTurkish ? "Kort Değiştir!" : "Change Court!" }
    static var scoreCourtMismatch: String { isTurkish ? "Skor/Kort uyuşmuyor!" : "Score/Court mismatch!" }
    static func recordingName(_ team: String) -> String {
        isTurkish ? "🎤 \(team) ismi..." : "🎤 \(team) name..."
    }
    static var endMatch: String { isTurkish ? "Maçı Bitir" : "End Match" }
    static var pastMatches: String { isTurkish ? "Geçmiş Maçlar" : "Match History" }
    static var saveAndEnd: String { isTurkish ? "Maçı kaydet ve bitir?" : "Save and end match?" }
    static var endAndSave: String { isTurkish ? "Bitir ve Kaydet" : "End & Save" }
    static var matchEnded: String { isTurkish ? "Maç Bitti!" : "Match Ended!" }
    static var newMatch: String { isTurkish ? "Yeni Maç" : "New Match" }
    static var players: String { isTurkish ? "Oyuncular" : "Players" }
    static var teamA: String { isTurkish ? "Takım A" : "Team A" }
    static var teamB: String { isTurkish ? "Takım B" : "Team B" }
    static var recordBoth: String { isTurkish ? "İkisini Kaydet" : "Record Both" }
    static var ok: String { isTurkish ? "Tamam" : "OK" }
    static var close: String { isTurkish ? "Kapat" : "Close" }
    static var matchDetail: String { isTurkish ? "Maç Detayı" : "Match Detail" }
    static var date: String { isTurkish ? "Tarih" : "Date" }
    static var duration: String { isTurkish ? "Süre" : "Duration" }
    static var location: String { isTurkish ? "Konum" : "Location" }
    static var setDetails: String { isTurkish ? "Set Detayları" : "Set Details" }
}
