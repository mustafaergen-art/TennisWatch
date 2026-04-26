import SwiftUI

/// A static view for rendering match summary as an image (for sharing)
struct MatchSummaryCard: View {
    let log: MatchLog

    var body: some View {
        VStack(spacing: 8) {
            Text("🎾 TennisWatch")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.green)

            Text(log.scoreSummary)
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)

            Text("\(log.playerA) vs \(log.playerB)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))

            if !log.sets.isEmpty {
                HStack(spacing: 12) {
                    ForEach(Array(log.sets.enumerated()), id: \.offset) { i, set in
                        VStack(spacing: 2) {
                            Text("Set \(i + 1)")
                                .font(.system(size: 8))
                                .foregroundStyle(.white.opacity(0.5))
                            Text("\(set.a)-\(set.b)")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(set.a > set.b ? .cyan : .orange)
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Text(log.durationText)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
                if !log.locationName.isEmpty {
                    Text("📍 \(log.locationName)")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            if log.totalOuts > 0 {
                Text("🚫 \(log.outsSummary)")
                    .font(.system(size: 10))
                    .foregroundStyle(.red.opacity(0.7))
            }

            Text(log.date.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(16)
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.black)
        )
    }
}

/// Animated dots that cycle: .  ..  ...  ..  .  etc.
struct PulsingDots: View {
    @State private var dotCount = 1
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(.green)
                    .frame(width: 4, height: 4)
                    .opacity(i < dotCount ? 1.0 : 0.2)
            }
        }
        .onReceive(timer) { _ in
            dotCount = dotCount % 3 + 1
        }
    }
}

/// Animated heart icon that pulses
struct PulsingHeart: View {
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 10))
            .foregroundStyle(.red)
            .scaleEffect(scale)
            .animation(
                .easeInOut(duration: 0.6)
                .repeatForever(autoreverses: true),
                value: scale
            )
            .onAppear { scale = 1.25 }
    }
}

struct ContentView: View {
    @StateObject private var scoreManager = ScoreManager()
    @StateObject private var heartRateManager = HeartRateManager()
    @StateObject private var audioListener = AudioListenerManager()
    @State private var showStopConfirm = false
    @State private var isEditingGames = false
    @State private var showPlayerSetup = false
    @State private var showHistory = false

    var body: some View {
        ZStack {
            // MARK: - Main Score View
            ScrollView {
                VStack(spacing: 6) {

                    // MARK: - Top Bar: Tennis logo + time + Set scores
                    HStack(alignment: .center) {
                        // Tap 🎾 to set player names
                        Text("🎾")
                            .font(.system(size: 18))
                            .onTapGesture {
                                showPlayerSetup = true
                            }

                        if heartRateManager.isMonitoring {
                            Text(heartRateManager.formattedTime)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.green.opacity(0.7))
                        }

                        Spacer()

                        // Set scores (small)
                        Text(scoreManager.setScoreText)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 4)

                    // MARK: - Court Side Change Indicator
                    if scoreManager.justChangedSides {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 10))
                                .foregroundStyle(.yellow)
                            Text(L.changeCourtBang)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.yellow)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.yellow.opacity(0.15))
                        )
                    }

                    // MARK: - GPS Side Mismatch Warning
                    if heartRateManager.gpsSideMismatch {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.red)
                            Text(L.scoreCourtMismatch)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.red)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.red.opacity(0.15))
                        )
                    }

                    // MARK: - Player Names (if set)
                    if !scoreManager.playerA.isEmpty || !scoreManager.playerB.isEmpty {
                        HStack {
                            Text(scoreManager.playerA.isEmpty ? "A" : scoreManager.playerA)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.cyan.opacity(0.7))
                                .lineLimit(1)
                            Spacer()
                            Text("vs")
                                .font(.system(size: 8))
                                .foregroundStyle(.white.opacity(0.3))
                            Spacer()
                            Text(scoreManager.playerB.isEmpty ? "B" : scoreManager.playerB)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.orange.opacity(0.7))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                    }

                    // MARK: - Current Game Score (tap A to undo A, tap B to undo B)
                    HStack(spacing: 0) {
                        VStack(spacing: 1) {
                            if !scoreManager.playerA.isEmpty {
                                Text(String(scoreManager.playerA.prefix(4)))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.cyan.opacity(0.6))
                            }
                            Text(scoreManager.currentScoreA)
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .foregroundStyle(.cyan)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            scoreManager.undoA()
                        }

                        Text(":")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(isEditingGames ? .green : .secondary)
                            .contentShape(Rectangle())
                            .frame(width: 30)
                            .onTapGesture(count: 2) {
                                scoreManager.undoLastGame()
                            }
                            .onTapGesture(count: 1) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isEditingGames.toggle()
                                }
                            }

                        VStack(spacing: 1) {
                            if !scoreManager.playerB.isEmpty {
                                Text(String(scoreManager.playerB.prefix(4)))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.orange.opacity(0.6))
                            }
                            Text(scoreManager.currentScoreB)
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .foregroundStyle(.orange)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            scoreManager.undoB()
                        }
                    }

                    // MARK: - Tiebreak indicator
                    if scoreManager.isTiebreak || scoreManager.isMatchTiebreak {
                        Text(scoreManager.isMatchTiebreak ? "🏆 Match TB" : "⚡ Tiebreak")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.yellow)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.yellow.opacity(0.15))
                            )
                    }

                    // MARK: - Games in current set (tap to edit, double-tap to undo game)
                    HStack {
                        Text("Set: \(scoreManager.gamesA) - \(scoreManager.gamesB)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(isEditingGames ? .green : .white.opacity(0.5))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isEditingGames ? .green.opacity(0.15) : .clear)
                            )
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        // Double-tap: undo last game
                        scoreManager.undoLastGame()
                    }
                    .onTapGesture(count: 1) {
                        // Single tap: toggle game editing mode
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditingGames.toggle()
                        }
                    }

                    // MARK: - Listening indicator
                    HStack(spacing: 4) {
                        if scoreManager.isRecordingPlayerName {
                            Circle()
                                .fill(.purple)
                                .frame(width: 6, height: 6)
                            Text(L.recordingName(scoreManager.recordingForTeam))
                                .font(.system(size: 10))
                                .foregroundStyle(.purple)
                        } else if audioListener.isProcessing || scoreManager.isProcessing {
                            Circle()
                                .fill(.yellow)
                                .frame(width: 6, height: 6)
                            Text("Processing...")
                                .font(.system(size: 10))
                                .foregroundStyle(.yellow)
                        } else if audioListener.isDetectingSpeech {
                            Circle()
                                .fill(.red)
                                .frame(width: 6, height: 6)
                            Text("Hearing...")
                                .font(.system(size: 10))
                                .foregroundStyle(.red.opacity(0.8))
                        } else if audioListener.isListening {
                            PulsingDots()
                            Text("Listening")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        } else {
                            Circle()
                                .fill(.gray)
                                .frame(width: 6, height: 6)
                            Text("Mic off")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // MARK: - Debug: last Claude result
                    if !audioListener.lastResult.isEmpty {
                        Text(audioListener.lastResult)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(audioListener.lastError.isEmpty ? .green.opacity(0.6) : .red.opacity(0.6))
                            .lineLimit(2)
                    }

                    // MARK: - Point / Game Buttons
                    HStack(spacing: 6) {
                        Button {
                            if isEditingGames {
                                scoreManager.addGameA()
                            } else {
                                scoreManager.pointForA()
                            }
                        } label: {
                            Text(isEditingGames ? "+G A" : "+A")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .tint(isEditingGames ? .green : .cyan)

                        Button {
                            if isEditingGames {
                                scoreManager.addGameB()
                            } else {
                                scoreManager.pointForB()
                            }
                        } label: {
                            Text(isEditingGames ? "+G B" : "+B")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .tint(isEditingGames ? .green : .orange)
                    }

                    // MARK: - Heart Rate + Calories
                    HStack(spacing: 12) {
                        // Heart rate
                        HStack(spacing: 3) {
                            PulsingHeart()
                            if heartRateManager.heartRate > 0 {
                                Text("\(heartRateManager.heartRate)")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.red)
                            } else {
                                Text("--")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.red.opacity(0.4))
                            }
                        }

                        // Calories
                        HStack(spacing: 3) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                            Text("\(heartRateManager.calories)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.orange)
                            Text("kcal")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.orange.opacity(0.6))
                        }
                    }

                    // MARK: - Location & Status
                    if !heartRateManager.locationName.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: heartRateManager.savedCourtConfirmed ? "location.fill" : "location")
                                .font(.system(size: 8))
                                .foregroundStyle(.blue.opacity(0.7))
                            Text(heartRateManager.locationName)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.blue.opacity(0.7))
                                .lineLimit(1)
                            if !heartRateManager.savedCourtConfirmed {
                                Text("(\(heartRateManager.visitCount)/3)")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                        }
                    }

                    if !heartRateManager.autoStopMessage.isEmpty {
                        Text(heartRateManager.autoStopMessage)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.yellow)
                    }

                    // MARK: - Recent Points (compact)
                    if !scoreManager.pointHistory.isEmpty {
                        Divider()
                            .padding(.vertical, 2)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(Array(scoreManager.pointHistory.suffix(8).enumerated()), id: \.offset) { _, pair in
                                    Text("\(pair.teamA)-\(pair.teamB)")
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.6))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(.white.opacity(0.1))
                                        )
                                }
                            }
                        }

                        // Undo & Clear
                        HStack(spacing: 6) {
                            Button {
                                scoreManager.undoLast()
                            } label: {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: 11))
                            }
                            .tint(.yellow)

                            Button(role: .destructive) {
                                scoreManager.clearAll()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                            }

                            Spacer()

                            // Out counter display
                            if scoreManager.totalOuts > 0 {
                                HStack(spacing: 3) {
                                    Text("🚫")
                                        .font(.system(size: 9))
                                    if scoreManager.outsA > 0 || scoreManager.outsB > 0 {
                                        Text("\(scoreManager.outsA)-\(scoreManager.outsB)")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundStyle(.red.opacity(0.7))
                                    } else {
                                        Text("\(scoreManager.totalOuts)")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundStyle(.red.opacity(0.7))
                                    }
                                }
                            }
                        }
                    }

                    // MARK: - Scroll Down Actions
                    Divider()
                        .padding(.vertical, 4)

                    // L.endMatch button
                    Button {
                        showStopConfirm = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 12))
                            Text(L.endMatch)
                                .font(.system(size: 13, weight: .bold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .tint(.red)

                    // "Geçmiş Maçları Gör" button
                    Button {
                        showHistory = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 12))
                            Text(L.pastMatches)
                                .font(.system(size: 13, weight: .bold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .tint(.white)
                }
                .padding(.horizontal, 2)
            }

            // MARK: - Match Ended Overlay
            if scoreManager.matchEnded {
                matchEndedOverlay
            }

            // MARK: - Player Setup Sheet
            if showPlayerSetup {
                playerSetupOverlay
            }

            // MARK: - Match History Sheet
            if showHistory {
                matchHistoryOverlay
            }
        }
        .onAppear {
            heartRateManager.setup()
            if !heartRateManager.savedCourtConfirmed {
                heartRateManager.start()
            }

            audioListener.onTranscription = { text in
                Task {
                    await scoreManager.processDictatedText(text)
                }
            }
            audioListener.startListening()
        }
        .confirmationDialog("End Match?", isPresented: $showStopConfirm) {
            Button(L.endAndSave, role: .destructive) {
                endAndLogMatch()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(L.saveAndEnd)
        }
        .onChange(of: scoreManager.matchEnded) {
            if scoreManager.matchEnded && scoreManager.lastMatchLog == nil {
                endAndLogMatch()
            }
        }
        .onChange(of: scoreManager.gamesA) {
            heartRateManager.checkSideMismatch(expectedChangeSides: scoreManager.shouldChangeSides)
        }
        .onChange(of: scoreManager.gamesB) {
            heartRateManager.checkSideMismatch(expectedChangeSides: scoreManager.shouldChangeSides)
        }
        .onChange(of: heartRateManager.gpsCourtSide) {
            heartRateManager.checkSideMismatch(expectedChangeSides: scoreManager.shouldChangeSides)
        }
    }

    // MARK: - End Match Logic

    private func endAndLogMatch() {
        scoreManager.endMatch(
            locationName: heartRateManager.locationName,
            duration: heartRateManager.elapsedTime
        )
        heartRateManager.stop()

        // Send match log to iPhone (iPhone renders its own card for sharing)
        if let log = scoreManager.lastMatchLog {
            WatchConnector.shared.sendMatchLog(log)
        }
    }

    // MARK: - Match Ended Overlay

    private var matchEndedOverlay: some View {
        VStack(spacing: 8) {
            Text("🏁")
                .font(.system(size: 28))

            Text(L.matchEnded)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            if let log = scoreManager.lastMatchLog {
                Text(log.scoreSummary)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.green)

                Text("\(log.playerA) vs \(log.playerB)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))

                HStack(spacing: 8) {
                    Text(log.durationText)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.5))
                    if !log.locationName.isEmpty {
                        Text("📍 \(log.locationName)")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }

                if log.totalOuts > 0 {
                    Text("🚫 \(log.outsSummary)")
                        .font(.system(size: 9))
                        .foregroundStyle(.red.opacity(0.6))
                }

                Text(log.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Button {
                scoreManager.dismissMatchEnd()
            } label: {
                Text(L.newMatch)
                    .font(.system(size: 12, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .tint(.green)
            .padding(.top, 4)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.95))
        )
        .padding(8)
    }

    // MARK: - Player Setup Overlay

    private var playerSetupOverlay: some View {
        VStack(spacing: 10) {
            Text(L.players)
                .font(.system(size: 14, weight: .bold, design: .rounded))

            // Player A
            HStack {
                Circle()
                    .fill(.cyan)
                    .frame(width: 8, height: 8)
                Text(scoreManager.playerA.isEmpty ? L.teamA : scoreManager.playerA)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.cyan)
                    .lineLimit(1)
                Spacer()
                Button {
                    showPlayerSetup = false
                    scoreManager.startRecordingName(for: "A")
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 12))
                }
                .tint(.cyan)
            }

            // Player B
            HStack {
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
                Text(scoreManager.playerB.isEmpty ? L.teamB : scoreManager.playerB)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                Spacer()
                Button {
                    showPlayerSetup = false
                    scoreManager.startRecordingName(for: "B")
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 12))
                }
                .tint(.orange)
            }

            Divider()

            HStack(spacing: 8) {
                // Record both: A first, then auto-B
                Button {
                    showPlayerSetup = false
                    scoreManager.startRecordingName(for: "A")
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 10))
                        Text(L.recordBoth)
                            .font(.system(size: 10, weight: .bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 26)
                }
                .tint(.green)

                Button {
                    showPlayerSetup = false
                } label: {
                    Text(L.ok)
                        .font(.system(size: 10, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 26)
                }
                .tint(.white)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.95))
        )
        .padding(8)
    }

    // MARK: - Match History Overlay

    private var matchHistoryOverlay: some View {
        VStack(spacing: 6) {
            HStack {
                Text(L.pastMatches)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Spacer()
                Button {
                    showHistory = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            let logs = MatchHistory.load()
            if logs.isEmpty {
                Text(L.noMatchesYet)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.vertical, 10)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(logs.prefix(10)) { log in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(log.scoreSummary)
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.green)
                                    Spacer()
                                    Text(log.durationText)
                                        .font(.system(size: 8))
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                                HStack {
                                    Text("\(log.playerA) vs \(log.playerB)")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.white.opacity(0.6))
                                    Spacer()
                                    Text(log.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 7))
                                        .foregroundStyle(.white.opacity(0.3))
                                }
                                HStack(spacing: 8) {
                                    if !log.locationName.isEmpty {
                                        Text("📍 \(log.locationName)")
                                            .font(.system(size: 8))
                                            .foregroundStyle(.blue.opacity(0.5))
                                            .lineLimit(1)
                                    }
                                    if log.totalOuts > 0 {
                                        Text("🚫 \(log.outsSummary)")
                                            .font(.system(size: 8))
                                            .foregroundStyle(.red.opacity(0.5))
                                    }
                                }
                            }
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.white.opacity(0.05))
                            )
                        }
                    }
                }
                .frame(maxHeight: 150)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.95))
        )
        .padding(8)
    }
}

#Preview {
    ContentView()
}
