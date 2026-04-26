import Foundation

/// Manages tennis score recording for two teams/players with set tracking.
@MainActor
class ScoreManager: ObservableObject {

    // MARK: - Published State

    /// Current game point score
    @Published var currentScoreA = "0"
    @Published var currentScoreB = "0"

    /// Games won in current set
    @Published var gamesA = 0
    @Published var gamesB = 0

    /// Set scores (e.g., [(6,4), (3,6)])
    @Published var sets: [(a: Int, b: Int)] = []

    /// Point history
    @Published var pointHistory: [(teamA: String, teamB: String)] = []

    @Published var statusMessage = "🎾 Listening..."
    @Published var isProcessing = false

    /// Player names
    @Published var playerA: String = ""
    @Published var playerB: String = ""

    /// Recording player names mode
    @Published var isRecordingPlayerName = false
    @Published var recordingForTeam: String = ""  // "A" or "B"

    /// Match ended flag
    @Published var matchEnded = false
    @Published var lastMatchLog: MatchLog?

    /// Out tracking
    @Published var outsA: Int = 0  // Outs by team A
    @Published var outsB: Int = 0  // Outs by team B
    @Published var totalOuts: Int = 0  // Total outs (when team not specified)

    /// Tiebreak state
    @Published var isTiebreak = false      // Set tiebreak (at 6-6)
    @Published var isMatchTiebreak = false  // Match/super tiebreak (10-point)
    @Published var tiebreakPointsA = 0
    @Published var tiebreakPointsB = 0

    /// Match start time
    var matchStartDate = Date()

    /// All speech transcripts during match
    var matchTranscripts: [String] = []

    // MARK: - Private

    /// Snapshots for undo — saves full state before each point
    private var snapshots: [Snapshot] = []

    private struct Snapshot {
        let scoreA: String
        let scoreB: String
        let gamesA: Int
        let gamesB: Int
        let sets: [(a: Int, b: Int)]
        let pointHistory: [(teamA: String, teamB: String)]
        let scoredByA: Bool  // who scored this point
        let isTiebreak: Bool
        let isMatchTiebreak: Bool
        let tiebreakPointsA: Int
        let tiebreakPointsB: Int
    }

    private func saveSnapshot(scoredByA: Bool) {
        snapshots.append(Snapshot(
            scoreA: currentScoreA,
            scoreB: currentScoreB,
            gamesA: gamesA,
            gamesB: gamesB,
            sets: sets,
            pointHistory: pointHistory,
            scoredByA: scoredByA,
            isTiebreak: isTiebreak,
            isMatchTiebreak: isMatchTiebreak,
            tiebreakPointsA: tiebreakPointsA,
            tiebreakPointsB: tiebreakPointsB
        ))
        // Keep max 30 snapshots
        if snapshots.count > 30 {
            snapshots.removeFirst()
        }
    }

    // MARK: - Set Score Display

    var setScoreText: String {
        if sets.isEmpty {
            if isTiebreak || isMatchTiebreak {
                return "\(gamesA)-\(gamesB) TB"
            }
            return "\(gamesA)-\(gamesB)"
        }
        let setsText = sets.map { "\($0.a)-\($0.b)" }.joined(separator: "  ")
        if isTiebreak || isMatchTiebreak {
            return "\(setsText)  \(gamesA)-\(gamesB) TB"
        }
        return "\(setsText)  \(gamesA)-\(gamesB)"
    }

    // MARK: - Court Side Change Tracking

    /// Total games played in the current set
    var totalGamesInCurrentSet: Int {
        gamesA + gamesB
    }

    /// Total games played across all completed sets
    private var totalGamesAllSets: Int {
        sets.reduce(0) { $0 + $1.a + $1.b }
    }

    /// Whether players should be on the changed side right now
    /// In tennis, players change ends when the total games in the current set is odd
    /// In tiebreaks, change sides every 6 points
    var shouldChangeSides: Bool {
        if isTiebreak || isMatchTiebreak {
            let totalTBPoints = tiebreakPointsA + tiebreakPointsB
            // In tiebreak: change every 6 points (after 6, 12, 18...)
            let totalGames = totalGamesAllSets + totalGamesInCurrentSet
            let baseSide = totalGames % 2 == 1
            let tbSwaps = totalTBPoints / 6
            return tbSwaps % 2 == 0 ? baseSide : !baseSide
        }
        let totalGames = totalGamesAllSets + totalGamesInCurrentSet
        return totalGames % 2 == 1
    }

    /// Number of court changes so far (total odd-game transitions)
    var courtChangeCount: Int {
        let totalGames = totalGamesAllSets + totalGamesInCurrentSet
        return totalGames / 2 + (totalGames % 2 == 1 ? 1 : 0)
    }

    /// Whether a court change just happened (current set games total is odd and point score is 0-0)
    var justChangedSides: Bool {
        return shouldChangeSides && currentScoreA == "0" && currentScoreB == "0"
    }

    // MARK: - Point Scoring

    func pointForA() {
        handlePoint(scorerIsA: true)
    }

    func pointForB() {
        handlePoint(scorerIsA: false)
    }

    private func handlePoint(scorerIsA: Bool) {
        saveSnapshot(scoredByA: scorerIsA)

        // Tiebreak scoring
        if isTiebreak || isMatchTiebreak {
            handleTiebreakPoint(scorerIsA: scorerIsA)
            return
        }

        let scorerScore = scorerIsA ? currentScoreA : currentScoreB
        let opponentScore = scorerIsA ? currentScoreB : currentScoreA

        var gameWon = false

        switch (scorerScore, opponentScore) {
        case ("0", _):
            if scorerIsA { currentScoreA = "15" } else { currentScoreB = "15" }
        case ("15", _):
            if scorerIsA { currentScoreA = "30" } else { currentScoreB = "30" }
        case ("30", _):
            if scorerIsA { currentScoreA = "40" } else { currentScoreB = "40" }
        case ("40", "40"):
            // Deuce → Advantage
            if scorerIsA { currentScoreA = "AD" } else { currentScoreB = "AD" }
        case ("40", "AD"):
            // Opponent had advantage, back to deuce
            if scorerIsA { currentScoreB = "40" } else { currentScoreA = "40" }
        case ("40", _):
            // 40 vs 0/15/30 → Game won
            gameWon = true
        case ("AD", _):
            // Advantage → Game won
            gameWon = true
        default:
            if scorerIsA { currentScoreA = "15" } else { currentScoreB = "15" }
        }

        // Record point in history (before resetting if game won)
        if !gameWon {
            pointHistory.append((teamA: currentScoreA, teamB: currentScoreB))
        }

        // Handle game won
        if gameWon {
            // Add winning point to history
            pointHistory.append((teamA: scorerIsA ? "W" : currentScoreA,
                                 teamB: scorerIsA ? currentScoreB : "W"))

            // Increment games
            if scorerIsA {
                gamesA += 1
            } else {
                gamesB += 1
            }

            // Check if we should enter tiebreak (6-6)
            if gamesA == 6 && gamesB == 6 {
                isTiebreak = true
                tiebreakPointsA = 0
                tiebreakPointsB = 0
                currentScoreA = "0"
                currentScoreB = "0"
                return
            }

            // Check if set is won
            if isSetWon() {
                sets.append((a: gamesA, b: gamesB))
                gamesA = 0
                gamesB = 0

                // Check if we should enter match tiebreak (e.g., 1 set each → super tiebreak)
                if shouldStartMatchTiebreak() {
                    isMatchTiebreak = true
                    tiebreakPointsA = 0
                    tiebreakPointsB = 0
                    currentScoreA = "0"
                    currentScoreB = "0"
                    return
                }
            }

            // Reset point score for next game
            currentScoreA = "0"
            currentScoreB = "0"
        }
    }

    // MARK: - Tiebreak Scoring

    private func handleTiebreakPoint(scorerIsA: Bool) {
        if scorerIsA {
            tiebreakPointsA += 1
        } else {
            tiebreakPointsB += 1
        }

        // Update display scores
        currentScoreA = "\(tiebreakPointsA)"
        currentScoreB = "\(tiebreakPointsB)"

        pointHistory.append((teamA: currentScoreA, teamB: currentScoreB))

        // Check if tiebreak is won
        let target = isMatchTiebreak ? 10 : 7
        let leading = max(tiebreakPointsA, tiebreakPointsB)
        let trailing = min(tiebreakPointsA, tiebreakPointsB)

        if leading >= target && leading - trailing >= 2 {
            // Tiebreak won
            pointHistory.append((teamA: scorerIsA ? "W" : currentScoreA,
                                 teamB: scorerIsA ? currentScoreB : "W"))

            if isMatchTiebreak {
                // Match tiebreak won — record as a set (e.g., 1-0 for winner)
                if scorerIsA {
                    gamesA = 1
                } else {
                    gamesB = 1
                }
                sets.append((a: gamesA, b: gamesB))
                gamesA = 0
                gamesB = 0
            } else {
                // Set tiebreak won — set score becomes 7-6
                if scorerIsA {
                    gamesA = 7  // already 6, but we track the tiebreak as a game
                } else {
                    gamesB = 7
                }
                sets.append((a: gamesA, b: gamesB))
                gamesA = 0
                gamesB = 0
            }

            // Reset tiebreak state
            isTiebreak = false
            isMatchTiebreak = false
            tiebreakPointsA = 0
            tiebreakPointsB = 0
            currentScoreA = "0"
            currentScoreB = "0"

            // Check if we should start match tiebreak after this set
            if shouldStartMatchTiebreak() {
                isMatchTiebreak = true
                tiebreakPointsA = 0
                tiebreakPointsB = 0
                currentScoreA = "0"
                currentScoreB = "0"
            }
        }
    }

    /// Check if match tiebreak should start (1 set each in best-of-3)
    private func shouldStartMatchTiebreak() -> Bool {
        let setsWonA = sets.filter { $0.a > $0.b }.count
        let setsWonB = sets.filter { $0.b > $0.a }.count
        // Both have won 1 set — 3rd set is a match tiebreak (super tiebreak)
        return setsWonA == 1 && setsWonB == 1
    }

    private func isSetWon() -> Bool {
        // Standard set: first to 6 games with 2-game lead
        if gamesA >= 6 && gamesA - gamesB >= 2 { return true }
        if gamesB >= 6 && gamesB - gamesA >= 2 { return true }
        // Tiebreak sets are handled separately (7-6 via handleTiebreakPoint)
        if gamesA == 7 && gamesB == 6 { return true }
        if gamesB == 7 && gamesA == 6 { return true }
        return false
    }

    // MARK: - Voice: "Oyun" (Game won by leader)

    /// Called when someone says "oyun" / "game" — awards game to whoever is leading
    func gameForLeader() {
        // In tiebreak, "game" doesn't apply the same way — just skip
        if isTiebreak || isMatchTiebreak { return }

        // Determine who is leading in the current game
        let scoreOrder = ["0": 0, "15": 1, "30": 2, "40": 3, "AD": 4]
        let aVal = scoreOrder[currentScoreA] ?? 0
        let bVal = scoreOrder[currentScoreB] ?? 0

        guard aVal != bVal else { return } // tied (deuce etc.) — can't determine winner

        if aVal > bVal {
            // A is leading — give them enough points to win the game
            while currentScoreA != "0" || (gamesA == 0 && currentScoreB == "0" && pointHistory.isEmpty) {
                // Keep scoring for A until game resets (score goes back to 0-0)
                let prevScoreA = currentScoreA
                handlePoint(scorerIsA: true)
                if currentScoreA == "0" && currentScoreB == "0" && prevScoreA != "0" {
                    break // game was won and reset
                }
                if pointHistory.count > 100 { break } // safety
            }
        } else {
            // B is leading
            while currentScoreB != "0" || (gamesB == 0 && currentScoreA == "0" && pointHistory.isEmpty) {
                let prevScoreB = currentScoreB
                handlePoint(scorerIsA: false)
                if currentScoreA == "0" && currentScoreB == "0" && prevScoreB != "0" {
                    break
                }
                if pointHistory.count > 100 { break }
            }
        }
    }

    // MARK: - Manual Game/Set Editing

    /// Add a game for team A (manual set editing)
    func addGameA() {
        gamesA += 1
        if isSetWon() {
            sets.append((a: gamesA, b: gamesB))
            gamesA = 0
            gamesB = 0
        }
    }

    /// Add a game for team B (manual set editing)
    func addGameB() {
        gamesB += 1
        if isSetWon() {
            sets.append((a: gamesA, b: gamesB))
            gamesA = 0
            gamesB = 0
        }
    }

    /// Remove last game from A (undo game)
    func removeGameA() {
        if gamesA > 0 {
            gamesA -= 1
        }
    }

    /// Remove last game from B (undo game)
    func removeGameB() {
        if gamesB > 0 {
            gamesB -= 1
        }
    }

    /// Undo last game added (either team) — used on double-tap of set display
    func undoLastGame() {
        // If current set has games, remove the most recently added one
        if gamesA > 0 || gamesB > 0 {
            // Use snapshots to figure out who scored last game, or just decrement the higher one
            // Simple heuristic: if last point history entry was "W", that team won a game
            if let lastWin = pointHistory.last {
                if lastWin.teamA == "W" && gamesA > 0 {
                    gamesA -= 1
                } else if lastWin.teamB == "W" && gamesB > 0 {
                    gamesB -= 1
                } else {
                    // Fallback: remove from whichever is higher
                    if gamesA >= gamesB && gamesA > 0 {
                        gamesA -= 1
                    } else if gamesB > 0 {
                        gamesB -= 1
                    }
                }
            } else {
                if gamesA >= gamesB && gamesA > 0 {
                    gamesA -= 1
                } else if gamesB > 0 {
                    gamesB -= 1
                }
            }
        } else if !sets.isEmpty {
            // No games in current set — undo last completed set
            let lastSet = sets.removeLast()
            gamesA = lastSet.a
            gamesB = lastSet.b
            // Remove one game from winner
            if gamesA > gamesB && gamesA > 0 {
                gamesA -= 1
            } else if gamesB > 0 {
                gamesB -= 1
            }
        }
    }

    // MARK: - Match End (Game Over / Maç Bitti)

    /// Ends the match: logs it with date, time, location, players, scores, then resets
    func endMatch(locationName: String, duration: TimeInterval, latitude: Double = 0, longitude: Double = 0) {
        // Count total points per team from history
        var ptsA = 0
        var ptsB = 0
        for p in pointHistory {
            if p.teamA == "W" { ptsA += 1 }
            if p.teamB == "W" { ptsB += 1 }
        }

        let log = MatchLog(
            date: matchStartDate,
            duration: duration,
            locationName: locationName,
            playerA: playerA.isEmpty ? "A" : playerA,
            playerB: playerB.isEmpty ? "B" : playerB,
            sets: sets,
            finalGames: (a: gamesA, b: gamesB),
            totalPointsA: ptsA,
            totalPointsB: ptsB,
            outsA: outsA,
            outsB: outsB,
            totalOuts: totalOuts,
            transcripts: matchTranscripts,
            latitude: latitude,
            longitude: longitude
        )

        MatchHistory.save(log)
        WatchConnector.shared.sendMatchLog(log)
        lastMatchLog = log
        matchEnded = true

        // Reset for next match
        clearAll()
        matchTranscripts = []
        playerA = ""
        playerB = ""
        matchStartDate = Date()
    }

    /// Dismiss the match ended overlay
    func dismissMatchEnd() {
        matchEnded = false
        lastMatchLog = nil
    }

    // MARK: - Player Name Recording

    /// Start recording a player name for the given team
    func startRecordingName(for team: String) {
        recordingForTeam = team
        isRecordingPlayerName = true
    }

    /// Process a voice-recorded player name
    /// After recording A, automatically asks for B
    /// If both "a takımı X b takımı Y" detected, sets both at once
    func setPlayerName(_ name: String) {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()

        // Try to parse both names from a single utterance
        // Patterns: "a takımı X b takımı Y", "a X b Y", "a takım X b takım Y"
        if let both = parseBothNames(from: lower, original: text) {
            playerA = both.a.capitalized
            playerB = both.b.capitalized
            isRecordingPlayerName = false
            recordingForTeam = ""
            return
        }

        let cleaned = text.capitalized
        if recordingForTeam == "A" {
            playerA = cleaned
            // Auto-continue to B
            recordingForTeam = "B"
            // isRecordingPlayerName stays true — next voice input will be B's name
        } else {
            playerB = cleaned
            isRecordingPlayerName = false
            recordingForTeam = ""
        }
    }

    /// Try to extract both player names from a single voice input
    /// e.g. "a takımı Mehmet b takımı Ali" or "a Mehmet b Ali"
    private func parseBothNames(from lower: String, original: String) -> (a: String, b: String)? {
        // Try various separators for A and B
        let aMarkers = ["a takımı ", "a takimi ", "a takım ", "a takim ", "a "]
        let bMarkers = [" b takımı ", " b takimi ", " b takım ", " b takim ", " b "]

        for aM in aMarkers {
            for bM in bMarkers {
                if lower.hasPrefix(aM), let bRange = lower.range(of: bM) {
                    let aName = String(lower[lower.index(lower.startIndex, offsetBy: aM.count)..<bRange.lowerBound])
                        .trimmingCharacters(in: .whitespaces)
                    let bName = String(lower[bRange.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                    if !aName.isEmpty && !bName.isEmpty {
                        return (a: aName, b: bName)
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Set Score Command ("setler 2-0", "set skoru 1-1", etc.)

    /// Parse "setler X-Y", "setler X Y", "set skoru X Y", "sets X Y"
    private func parseSetScoreCommand(_ text: String) -> (a: Int, b: Int)? {
        let t = text.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ":", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Patterns to detect
        let prefixes = ["setler ", "set skoru ", "set skor ", "sets ", "set "]

        for prefix in prefixes {
            guard t.hasPrefix(prefix) else { continue }
            let rest = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            let parts = rest.split(separator: " ").compactMap { Int($0) }
            if parts.count >= 2 && parts[0] >= 0 && parts[0] <= 5 && parts[1] >= 0 && parts[1] <= 5 {
                // Make sure this is a set score, not something like "set a"
                return (a: parts[0], b: parts[1])
            }
        }

        // Also handle Turkish word numbers: "setler iki sıfır", "setler bir bir"
        let wordNums: [(String, Int)] = [
            ("sıfır", 0), ("sifir", 0), ("zero", 0),
            ("bir", 1), ("one", 1),
            ("iki", 2), ("two", 2),
            ("üç", 3), ("uc", 3), ("three", 3),
            ("dört", 4), ("dort", 4), ("four", 4),
            ("beş", 5), ("bes", 5), ("five", 5),
        ]

        for prefix in prefixes {
            guard t.hasPrefix(prefix) else { continue }
            var rest = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)

            var foundNums: [Int] = []
            for (word, val) in wordNums {
                if rest.hasPrefix(word) {
                    foundNums.append(val)
                    rest = String(rest.dropFirst(word.count)).trimmingCharacters(in: .whitespaces)
                }
            }
            if foundNums.count >= 2 {
                return (a: foundNums[0], b: foundNums[1])
            }
        }

        return nil
    }

    /// Apply a set score — e.g., if "setler 2-0", create 2 sets won by A
    private func applySetsScore(aWon: Int, bWon: Int) {
        sets.removeAll()
        // Add sets won by A (use 6-4 as placeholder score)
        for _ in 0..<aWon {
            sets.append((a: 6, b: 4))
        }
        // Add sets won by B (use 4-6 as placeholder score)
        for _ in 0..<bWon {
            sets.append((a: 4, b: 6))
        }
        // Reset current set games
        gamesA = 0
        gamesB = 0
        currentScoreA = "0"
        currentScoreB = "0"
        statusMessage = "🎾 Setler: \(aWon)-\(bWon)"
    }

    // MARK: - Out Tracking

    /// Record an out (general, no team specified)
    func recordOut() {
        totalOuts += 1
    }

    /// Record an out for team A
    func recordOutA() {
        outsA += 1
        totalOuts += 1
    }

    /// Record an out for team B
    func recordOutB() {
        outsB += 1
        totalOuts += 1
    }

    // MARK: - Clear & Undo

    func clearAll() {
        pointHistory.removeAll()
        sets.removeAll()
        gamesA = 0
        gamesB = 0
        currentScoreA = "0"
        currentScoreB = "0"
        outsA = 0
        outsB = 0
        totalOuts = 0
        isTiebreak = false
        isMatchTiebreak = false
        tiebreakPointsA = 0
        tiebreakPointsB = 0
        statusMessage = "🎾 Listening..."
    }

    /// Undo the last point scored by team A
    func undoA() {
        // Find last snapshot where A scored
        if let idx = snapshots.lastIndex(where: { $0.scoredByA }) {
            let snapshot = snapshots[idx]
            snapshots.removeSubrange(idx...)
            restoreSnapshot(snapshot)
        }
    }

    /// Undo the last point scored by team B
    func undoB() {
        // Find last snapshot where B scored
        if let idx = snapshots.lastIndex(where: { !$0.scoredByA }) {
            let snapshot = snapshots[idx]
            snapshots.removeSubrange(idx...)
            restoreSnapshot(snapshot)
        }
    }

    /// General undo (used by undo button)
    func undoLast() {
        guard let snapshot = snapshots.popLast() else { return }
        restoreSnapshot(snapshot)
    }

    private func restoreSnapshot(_ snapshot: Snapshot) {
        currentScoreA = snapshot.scoreA
        currentScoreB = snapshot.scoreB
        gamesA = snapshot.gamesA
        gamesB = snapshot.gamesB
        sets = snapshot.sets
        pointHistory = snapshot.pointHistory
        isTiebreak = snapshot.isTiebreak
        isMatchTiebreak = snapshot.isMatchTiebreak
        tiebreakPointsA = snapshot.tiebreakPointsA
        tiebreakPointsB = snapshot.tiebreakPointsB
    }

    // MARK: - Voice Input (xAI normalized)

    func processDictatedText(_ text: String) async {
        guard !text.isEmpty else { return }

        // Log every transcript
        matchTranscripts.append(text)

        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for player name recording mode
        if isRecordingPlayerName {
            setPlayerName(text)
            return
        }

        // Check for "game over" / "maç bitti" — end match
        if lower.contains("game over") || lower.contains("maç bitti") || lower.contains("mac bitti")
            || lower.contains("match over") || lower.contains("bitti") {
            // This will be handled by ContentView which has access to heartRateManager
            statusMessage = "🏁 Maç bitti!"
            matchEnded = true
            return
        }

        // Check for "tiebreak" / "tie break" / "taybrek" — manually start tiebreak
        if lower == "tiebreak" || lower == "tie break" || lower == "taybrek" || lower == "taybreak" {
            if !isTiebreak && !isMatchTiebreak {
                isTiebreak = true
                tiebreakPointsA = 0
                tiebreakPointsB = 0
                currentScoreA = "0"
                currentScoreB = "0"
                statusMessage = "🎾 Tiebreak!"
            }
            return
        }

        // Check for "super tiebreak" / "match tiebreak" — manually start match tiebreak (10 pts)
        if lower.contains("super tiebreak") || lower.contains("süper taybrek") || lower.contains("match tiebreak")
            || lower.contains("maç taybrek") || lower.contains("mac taybrek") {
            if !isMatchTiebreak {
                isMatchTiebreak = true
                isTiebreak = false
                tiebreakPointsA = 0
                tiebreakPointsB = 0
                currentScoreA = "0"
                currentScoreB = "0"
                statusMessage = "🎾 Match Tiebreak!"
            }
            return
        }

        // Check for "kort değiştir" / "change court" / "change sides" — implies game was won
        if lower.contains("kort değiştir") || lower.contains("kort degistir")
            || lower.contains("change court") || lower.contains("change side")
            || lower.contains("değiş") || lower.contains("degis") {
            gameForLeader()
            return
        }

        // Check for "oyun" or "game" or "50" / "elli" / "fifty" command — award game to leader
        if lower.contains("oyun") || lower.contains("game")
            || lower == "50" || lower == "elli" || lower.contains("elli")
            || lower == "fifty" || lower.contains("fifty") {
            gameForLeader()
            return
        }

        // Check for "out" — record an out call
        // "out a" / "out A" → out for team A, "out b" → out for team B, just "out" → general
        if lower == "out" || lower == "aut" || lower == "dış" || lower == "dis" || lower == "fault" || lower == "foul" {
            recordOut()
            statusMessage = "🚫 Out! (\(totalOuts))"
            return
        }
        if lower == "out a" || lower == "aut a" {
            recordOutA()
            statusMessage = "🚫 Out A! (\(outsA))"
            return
        }
        if lower == "out b" || lower == "aut b" {
            recordOutB()
            statusMessage = "🚫 Out B! (\(outsB))"
            return
        }

        // Check for "setler X-Y" / "setler X Y" / "set skoru X Y" — set the set score directly
        if let setScore = parseSetScoreCommand(lower) {
            applySetsScore(aWon: setScore.a, bWon: setScore.b)
            return
        }

        // Check for "set a" / "set b" — add a game to the specified team
        if lower.contains("set a") || lower.contains("seta") {
            addGameA()
            return
        }
        if lower.contains("set b") || lower.contains("setb") || lower.contains("set bi") {
            addGameB()
            return
        }

        // In tiebreak, voice commands like "a" or "b" for points
        if isTiebreak || isMatchTiebreak {
            if lower == "a" || lower.hasPrefix("point a") || lower.hasPrefix("puan a") {
                pointForA()
                return
            }
            if lower == "b" || lower.hasPrefix("point b") || lower.hasPrefix("puan b") {
                pointForB()
                return
            }
        }

        // Try quick local parse first (no API call needed) — skip in tiebreak mode
        if !isTiebreak && !isMatchTiebreak, let pair = quickParseTurkish(lower) {
            saveSnapshot(scoredByA: true)
            currentScoreA = pair.teamA
            currentScoreB = pair.teamB
            pointHistory.append(pair)
            return
        }

        // Unrecognized utterance: xAI is responsible for normalizing valid score
        // speech upstream. Surface the raw text via statusMessage briefly and
        // return — no remote fallback any more.
        statusMessage = "🎾 \(text)"
    }

    // MARK: - Quick Local Parse (no API call)

    /// Tries to parse common Turkish/English score patterns locally
    private func quickParseTurkish(_ text: String) -> (teamA: String, teamB: String)? {
        let t = text.replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // === Equal score shortcuts ===
        // "15er" "15'er" "on beşer" → 15-15
        if t.contains("15er") || t.contains("on beşer") || t.contains("onbeşer") {
            return ("15", "15")
        }
        // "30ar" "30'ar" "otuzar" → 30-30
        if t.contains("30ar") || t.contains("otuzar") {
            return ("30", "30")
        }
        // "40ar" "kırkar" → 40-40 (deuce)
        if t.contains("40ar") || t.contains("kırkar") {
            return ("40", "40")
        }
        // "deuce" "düs"
        if t == "deuce" || t == "düs" || t.contains("deuce") {
            return ("40", "40")
        }
        // "fifty" / "50" → game won (handled in processDictatedText, but also catch here)
        if t == "50" || t == "elli" || t == "fifty" {
            return nil // let processDictatedText handle as "oyun"
        }
        // "fifteen all" "thirty all" "forty all" — direct word forms
        if t.contains("fifteen all") { return ("15", "15") }
        if t.contains("thirty all") { return ("30", "30") }
        if t.contains("forty all") { return ("40", "40") }

        // "X ol" patterns — Whisper may hear "all" as "ol" in Turkish
        if t == "15 ol" || t == "on beş ol" || t == "onbeş ol" { return ("15", "15") }
        if t == "30 ol" || t == "otuz ol" { return ("30", "30") }
        if t == "40 ol" || t == "kırk ol" || t == "kirk ol" { return ("40", "40") }

        // "X love" → X-0 (e.g. "40 love" = 40-0, "fifteen love" = 15-0)
        if t.contains("love") {
            let beforeLove = t.replacingOccurrences(of: "love", with: "").trimmingCharacters(in: .whitespaces)
            // Replace words with numbers
            var num = beforeLove
            for (word, val) in [("fifteen", "15"), ("thirty", "30"), ("forty", "40")] {
                num = num.replacingOccurrences(of: word, with: val)
            }
            num = num.trimmingCharacters(in: .whitespaces)
            if ["15", "30", "40"].contains(num) {
                return (num, "0")
            }
        }

        // === Advantage ===
        // "avantaj servis" / "advantage server" → AD for A (server)
        if t.contains("avantaj servis") || t.contains("advantage serv") || t.contains("ad servis") {
            return ("AD", "40")
        }
        // "avantaj return" / "avantaj ritern" → AD for B (returner)
        if t.contains("avantaj return") || t.contains("avantaj ritern") || t.contains("advantage return")
            || t.contains("ad return") || t.contains("avantaj röturn") {
            return ("40", "AD")
        }
        // Just "avantaj" or "advantage" alone — give to whoever was last leading
        // Default: A gets advantage (server usually calls it)
        if t.contains("avantaj") || t.contains("advantage") {
            return ("AD", "40")
        }

        // === Word → number mapping ===
        // Order matters: longer strings first so "on beş" matches before "on"
        let replacements: [(String, String)] = [
            ("advantage", "AD"), ("avantaj", "AD"),
            ("fifteen", "15"), ("on beş", "15"), ("onbeş", "15"), ("onbes", "15"),
            ("thirty", "30"), ("otuz", "30"),
            ("forty", "40"), ("kırk", "40"), ("kirk", "40"), ("kök", "40"), ("kurk", "40"),
            ("love", "0"), ("sıfır", "0"), ("sifir", "0"), ("hiç", "0"), ("hic", "0"),
            ("zero", "0"), ("nothing", "0"),
        ]

        var normalized = t
        for (word, num) in replacements {
            normalized = normalized.replacingOccurrences(of: word, with: num)
        }

        // Clean up whitespace
        let parts = normalized.split(separator: " ")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let validScores = Set(["0", "15", "30", "40", "AD"])

        // "eşit" / "esit" / "all" → both sides same
        // e.g. "15 eşit" "30 all" "on beş eşit"
        if parts.count >= 2 {
            let last = parts.last ?? ""
            if last == "eşit" || last == "esit" || last == "all" || last == "ol" {
                let first = parts.first ?? ""
                if validScores.contains(first) {
                    return (first, first)
                }
            }
        }

        // Two valid scores: "15 0", "30 15", "40 30", "AD 40" etc.
        let scores = parts.filter { validScores.contains($0) }
        if scores.count >= 2 {
            return (scores[0], scores[1])
        }

        return nil // couldn't parse locally, fall back to Claude
    }
}
