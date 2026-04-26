import SwiftUI
import UIKit

// MARK: - Today's Matches View

struct TodaysMatchesView: View {
    @StateObject private var service = TennisScoreService()
    @State private var autoRefreshTimer: Timer?

    var body: some View {
        NavigationStack {
            Group {
                if service.isLoading && service.matchesByTournament.isEmpty {
                    loadingView
                } else if let error = service.errorMessage, service.matchesByTournament.isEmpty {
                    errorView(error)
                } else if service.matchesByTournament.isEmpty {
                    emptyView
                } else {
                    matchListView
                }
            }
            .navigationTitle(L.todaysMatches)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        if let updated = service.lastUpdated {
                            Text(updated.formatted(date: .omitted, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            Task { await service.fetchTodaysMatches() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14))
                        }
                        .disabled(service.isLoading)
                    }
                }
            }
        }
        .task {
            await service.fetchTodaysMatches()
        }
        .onAppear { startAutoRefresh() }
        .onDisappear { stopAutoRefresh() }
    }

    // MARK: - Auto Refresh (every 60s)

    private func startAutoRefresh() {
        stopAutoRefresh()
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in
                await service.fetchTodaysMatches()
            }
        }
    }

    private func stopAutoRefresh() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text(L.loadingMatches)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 40))
                .foregroundStyle(.red.opacity(0.5))
            Text(L.couldNotLoad)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(error)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button {
                Task { await service.fetchTodaysMatches() }
            } label: {
                Label(L.tryAgain, systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sportscourt")
                .font(.system(size: 50))
                .foregroundStyle(.green.opacity(0.4))
            Text(L.noMatchesToday)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(L.checkBackLater)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var matchListView: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                ForEach(service.matchesByTournament, id: \.tournament.id) { group in
                    TournamentSection(tournament: group.tournament, matches: group.matches)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .refreshable {
            await service.fetchTodaysMatches()
        }
    }
}

// MARK: - Tournament Section

struct TournamentSection: View {
    let tournament: LiveTournament
    let matches: [LiveMatch]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Tournament header
            HStack(spacing: 8) {
                Text("🎾")
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text(tournament.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                    if !tournament.category.isEmpty {
                        Text(tournament.category)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                Spacer()
                Text("\(matches.count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.green.opacity(0.7)))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(white: 0.15))
            )

            // Matches in this tournament
            ForEach(matches) { match in
                LiveMatchCard(match: match)
            }
        }
    }
}

// MARK: - Live Match Card

struct LiveMatchCard: View {
    let match: LiveMatch

    var body: some View {
        VStack(spacing: 8) {
            // Status + round + share
            HStack {
                Text(match.statusText)
                    .font(.system(size: 12, weight: .semibold))
                if !match.round.isEmpty {
                    Text("·")
                        .foregroundStyle(.white.opacity(0.4))
                    Text(match.round)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                if let game = match.currentGame, match.status == .live {
                    Text(game)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(.yellow.opacity(0.15))
                        )
                }
                // Share button
                Button {
                    shareLiveMatch(match)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13))
                        .foregroundStyle(.blue)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.blue.opacity(0.2)))
                }
            }

            // Player 1 row
            playerRow(
                name: match.player1,
                sets: match.sets.map(\.p1),
                setsWon: match.setsWon1,
                isWinner: match.status == .finished && match.setsWon1 > match.setsWon2,
                color: .cyan
            )

            // Player 2 row
            playerRow(
                name: match.player2,
                sets: match.sets.map(\.p2),
                setsWon: match.setsWon2,
                isWinner: match.status == .finished && match.setsWon2 > match.setsWon1,
                color: .orange
            )

            // Start time for upcoming matches
            if match.status == .notStarted, let time = match.startTime {
                HStack {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                    Text(time.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 12))
                    Spacer()
                }
                .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(match.status == .live ? Color(red: 0.15, green: 0.05, blue: 0.05) : Color.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(match.status == .live ? Color.red.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
    }

    private func playerRow(name: String, sets: [Int], setsWon: Int, isWinner: Bool, color: Color) -> some View {
        HStack(spacing: 8) {
            // Player name
            HStack(spacing: 4) {
                if isWinner {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                }
                Text(name)
                    .font(.system(size: 14, weight: isWinner ? .bold : .regular))
                    .foregroundStyle(isWinner ? color : .white.opacity(0.85))
                    .lineLimit(1)
            }

            Spacer()

            // Set scores
            HStack(spacing: 6) {
                ForEach(Array(sets.enumerated()), id: \.offset) { i, score in
                    Text("\(score)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(setColor(myScore: score, opponentScore: opponentScore(setIndex: i, isPlayer1: color == .cyan)))
                        .frame(width: 20)
                }
            }

            // Sets won
            if match.status != .notStarted {
                Text("\(setsWon)")
                    .font(.system(size: 16, weight: .heavy, design: .monospaced))
                    .foregroundStyle(isWinner ? .green : .white.opacity(0.6))
                    .frame(width: 22)
            }
        }
    }

    private func opponentScore(setIndex: Int, isPlayer1: Bool) -> Int {
        guard setIndex < match.sets.count else { return 0 }
        return isPlayer1 ? match.sets[setIndex].p2 : match.sets[setIndex].p1
    }

    private func setColor(myScore: Int, opponentScore: Int) -> Color {
        if myScore > opponentScore { return .green }
        if myScore < opponentScore { return .red.opacity(0.6) }
        return .white.opacity(0.4)
    }

    private func shareLiveMatch(_ match: LiveMatch) {
        let scoreText = match.sets.map { "\($0.p1)-\($0.p2)" }.joined(separator: ", ")
        var text = "🎾 \(match.player1) vs \(match.player2)"
        if !scoreText.isEmpty {
            text += "\n\(scoreText)"
        }
        if !match.tournament.name.isEmpty {
            text += "\n\(match.tournament.name)"
        }
        if !match.round.isEmpty {
            text += " — \(match.round)"
        }
        text += "\n\(match.statusText)"

        let items: [Any] = [text]
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)

        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = scene.windows.first?.rootViewController {
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            activityVC.popoverPresentationController?.sourceView = topVC.view
            activityVC.popoverPresentationController?.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
            topVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - Preview

#Preview {
    TodaysMatchesView()
}
